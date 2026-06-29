import sqlalchemy as sa
from sqlalchemy.engine import URL
# predict_v4_single_family_tweedie.py (SINGLE FAMILY - v4.2 / production V1)
#
# Stessa logica di predict_v4_20families_tweedie.py ma:
# - una sola famiglia (default: phaelenopsis)
# - CLI arg --family / env ONLY_FAMILY
#
# Patch "Punto 1" (production V1):
# - Disabilitabile via env V4_ENABLE_WINDOW_ANCHOR (default: 1 come prima)
# - Aggiunta calibrazione globale sul TOTALE famiglia: V4_FAMILY_TOTAL_BETA (default 1.0)
#   (nel tuo caso: export V4_FAMILY_TOTAL_BETA=0.9185 circa)
# - Nessuna rottura API / output: stessi campi, stessa tabella, stessi nomi colonne
#
# NOTE:
# - NON cambia nulla su fasce / anchoring fascia->totale (resta identico)
# - La beta viene applicata DOPO weekend rebalance + window anchor + warmup




import os
import json
import pickle
from datetime import timedelta
import argparse

import numpy as np
import pandas as pd

# ===== HURDLE GLOBAL CONFIG =====
ENABLE_HURDLE = os.getenv("V4_ENABLE_HURDLE", "0") == "1"
HURDLE_P_FLOOR = float(os.getenv("V4_HURDLE_P_FLOOR", "0.0"))
HURDLE_DEBUG = int(float(os.getenv("V4_HURDLE_DEBUG", "0") or 0))
# damping parameters (configurable)
HURDLE_P_CAP = float(os.getenv("V4_HURDLE_P_CAP", "0.95"))
HURDLE_P_POWER = float(os.getenv("V4_HURDLE_P_POWER", "2.0"))

# =================================

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

from data_access_v1 import load_hist_for_predict_parquet_or_db
from jobs.family_resolver import resolve_family_and_slug
from jobs.seasonality_gate import build_pos_rate_doy, apply_gate



# =========================
# CONFIG
# =========================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, ".env")
if os.path.exists(ENV_PATH):
    load_dotenv(ENV_PATH)


# =========================
# Family beta (global or month)
# =========================
FAMILY_TOTAL_BETA = float(os.getenv("V4_FAMILY_TOTAL_BETA", "1.0"))  # global beta
FAMILY_BETA_MODE = os.getenv("V4_FAMILY_BETA_MODE", "global").strip().lower()  # global|month
FAMILY_BETA_BY_MONTH_RAW = os.getenv("V4_FAMILY_BETA_BY_MONTH", "").strip()
FAMILY_BETA_FALLBACK = float(os.getenv("V4_FAMILY_BETA_FALLBACK", str(FAMILY_TOTAL_BETA)))
# =============================================================================
# Seasonal priors gate (soft) - v1
# Uses priors_cache/priors_v1.parquet (or per_family/priors_<slug>_v1.parquet)
# Toggle: V4_SEASONAL_GATE=1/0
# =============================================================================
_PRIORS_CACHE = {"_global_loaded": False, "_global_df": None, "by_key": {}}

def add_season_features(df, date_col="data"):
    """
    Adds seasonality features:
      - sin/cos day-of-year
      - week of year
      - month
    Safe: if date_col missing -> no-op.
    """
    import numpy as np
    import pandas as pd

    if df is None or len(df) == 0 or (date_col not in df.columns):
        return df

    d = pd.to_datetime(df[date_col])
    doy = d.dt.dayofyear.astype(int).clip(1, 366)
    # 2*pi periodic encoding
    ang = 2.0 * np.pi * (doy / 366.0)
    df = df.copy()
    df["doy_sin"] = np.sin(ang)
    df["doy_cos"] = np.cos(ang)
    df["week_of_year"] = d.dt.isocalendar().week.astype(int)
    df["month"] = d.dt.month.astype(int)
    return df



def load_seasonal_priors(fam: str, slug: str = None, *, base_dir: str = None):
    import os
    import pandas as pd

    if base_dir is None:
        base_dir = os.getenv("PRIORS_CACHE_DIR", os.path.join(BASE_DIR, "priors_cache"))

    fam_l = (fam or "").strip().lower()
    slug_l = (slug or "").strip().lower()

    cache_key = f"slug:{slug_l}" if slug_l else f"fam:{fam_l}"
    if cache_key in _PRIORS_CACHE["by_key"]:
        return _PRIORS_CACHE["by_key"][cache_key]

    # 1) per-family file
    if slug_l:
        pf = os.path.join(base_dir, "per_family", f"priors_{slug_l}_v1.parquet")
        if os.path.exists(pf):
            d = pd.read_parquet(pf)
            _PRIORS_CACHE["by_key"][cache_key] = d
            return d

    # 2) global file filtered by famiglia
    gf = os.path.join(base_dir, "priors_v1.parquet")
    if not _PRIORS_CACHE["_global_loaded"]:
        _PRIORS_CACHE["_global_df"] = pd.read_parquet(gf)
        _PRIORS_CACHE["_global_loaded"] = True

    g = _PRIORS_CACHE["_global_df"]
    d = g[(g["famiglia"].str.lower() == fam_l)].copy()
    _PRIORS_CACHE["by_key"][cache_key] = d
    return d


def compute_season_scale(forecast_dates, priors_df, *,
                         w_doy=0.45, w_week=0.35, w_month=0.20,
                         alpha=1.6, min_scale=0.05, max_scale=2.5, eps=1e-6,
                         conf_k_doy=20.0, conf_k_week=40.0, conf_k_month=80.0,
                         shrink=1.0):
    """
    Seasonal multiplicative scale from priors.

    p_raw per grain -> confidence blend with global using n_days:
      conf = n_days / (n_days + K)
      p = conf*p_raw + (1-conf)*p_global

    p_mix = weighted mean of (p_doy,p_week,p_month)
    raw_scale = (p_mix / p_global) ** alpha
    raw_scale -> shrink: 1 + shrink*(raw_scale - 1)
    final clip: [min_scale, max_scale]
    """
    import numpy as np
    import pandas as pd

    dts = pd.to_datetime(pd.Index(forecast_dates))
    if priors_df is None or getattr(priors_df, "empty", True) or len(dts) == 0:
        return pd.Series(1.0, index=dts)

    df = priors_df.copy()
    if not {"grain","key","pos_rate"}.issubset(df.columns):
        return pd.Series(1.0, index=dts)

    df["grain"] = df["grain"].astype(str)

    def _to_int(x):
        try:
            return int(x)
        except Exception:
            return None

    df["key_int"] = df["key"].map(_to_int)
    df["pos_rate"] = pd.to_numeric(df["pos_rate"], errors="coerce").astype(float)
    if "n_days" in df.columns:
        df["n_days"] = pd.to_numeric(df["n_days"], errors="coerce")
    else:
        df["n_days"] = np.nan

    g = df[df["grain"] == "global"]
    p_global = float(g["pos_rate"].iloc[0]) if len(g) and np.isfinite(g["pos_rate"].iloc[0]) else 0.0
    if p_global <= 0:
        return pd.Series(1.0, index=dts)

    def _maps(grain):
        d = df[(df["grain"] == grain) & df["key_int"].notna() & df["pos_rate"].notna()].copy()
        if len(d) == 0:
            return {}, {}
        pos = {}
        nd = {}
        for k, v, n in zip(d["key_int"].tolist(), d["pos_rate"].tolist(), d["n_days"].tolist()):
            if k is None or not np.isfinite(v):
                continue
            pos[int(k)] = float(v)
            try:
                nd[int(k)] = float(n) if (n is not None and np.isfinite(n)) else 0.0
            except Exception:
                nd[int(k)] = 0.0
        return pos, nd

    pos_doy, nd_doy = _maps("doy")
    pos_week, nd_week = _maps("week")
    pos_month, nd_month = _maps("month")

    doy = dts.dayofyear.astype(int)
    week = dts.isocalendar().week.astype(int)
    month = dts.month.astype(int)

    def _blend(keys, pos_map, nd_map, K):
        p_raw = np.array([pos_map.get(int(k), p_global) for k in keys], dtype=float)
        n = np.array([nd_map.get(int(k), 0.0) for k in keys], dtype=float)
        conf = n / (n + float(K))
        return conf * p_raw + (1.0 - conf) * float(p_global)

    p_doy = _blend(doy, pos_doy, nd_doy, conf_k_doy)
    p_week = _blend(week, pos_week, nd_week, conf_k_week)
    p_month = _blend(month, pos_month, nd_month, conf_k_month)

    w_sum = float(w_doy) + float(w_week) + float(w_month)
    if w_sum <= 0:
        return pd.Series(1.0, index=dts)

    p_mix = (float(w_doy)*p_doy + float(w_week)*p_week + float(w_month)*p_month) / w_sum
    ratio = np.maximum(p_mix, eps) / max(p_global, eps)

    raw = np.power(ratio, float(alpha))
    raw = 1.0 + float(shrink) * (raw - 1.0)
    raw = np.clip(raw, float(min_scale), float(max_scale))

    return pd.Series(raw, index=dts, dtype=float)


def apply_soft_seasonal_gate_forecast(df_fam_pred, fam: str, slug: str = None):
    import os
    import pandas as pd

    enabled = str(os.getenv("V4_SEASONAL_GATE", "1")).lower() in ("1","true","yes")
    if not enabled:
        return df_fam_pred

    if df_fam_pred is None or len(df_fam_pred) == 0:
        return df_fam_pred
    if "data" not in df_fam_pred.columns or "qty_forecast" not in df_fam_pred.columns:
        return df_fam_pred

    w_doy = float(os.getenv("V4_GATE_W_DOY", "0.45"))
    w_week = float(os.getenv("V4_GATE_W_WEEK", "0.35"))
    w_month = float(os.getenv("V4_GATE_W_MONTH", "0.20"))
    alpha = float(os.getenv("V4_GATE_ALPHA", "1.6"))
    min_scale = float(os.getenv("V4_GATE_MIN_SCALE", "0.05"))

    max_scale = float(os.getenv("V4_GATE_MAX_SCALE", "2.5"))

    pri = load_seasonal_priors(fam, slug)

    dates = pd.to_datetime(df_fam_pred["data"])
    scale_s = compute_season_scale(dates.unique(), pri,
                                   w_doy=w_doy, w_week=w_week, w_month=w_month,
                                   alpha=alpha, min_scale=min_scale, max_scale=max_scale)
    out = df_fam_pred.copy()
    out["data"] = pd.to_datetime(out["data"])

    before = float(out["qty_forecast"].sum())
    out = out.merge(scale_s.rename("season_scale"), left_on="data", right_index=True, how="left")
    out["season_scale"] = out["season_scale"].fillna(1.0)

    # 1) apply per-date seasonal shape
    out["qty_forecast"] = out["qty_forecast"] * out["season_scale"]
    after_raw = float(out["qty_forecast"].sum())

    # 2) preserve family total (default ON)
    preserve_total = str(os.getenv("V4_GATE_PRESERVE_TOTAL", "1")).lower() in ("1","true","yes")
    if preserve_total and before > 0 and after_raw > 0:
        adj = before / (after_raw + 1e-12)
        out["qty_forecast"] = out["qty_forecast"] * adj
    else:
        adj = 1.0

    after = float(out["qty_forecast"].sum())

    print(
        f"[SEASON-GATE] {fam} ({slug or 'no-slug'}): sum {before:.3f} -> {after:.3f} "
        f"(raw {after_raw:.3f}, adj {adj:.4f}) | "
        f"scale[min/mean/max]={out['season_scale'].min():.3f}/{out['season_scale'].mean():.3f}/{out['season_scale'].max():.3f}",
        flush=True
    )

    out.drop(columns=["season_scale"], inplace=True, errors="ignore")
    return out



def _parse_beta_by_month(raw: str) -> dict[int, float]:
    if not raw:
        return {}
    try:
        obj = json.loads(raw)
        out: dict[int, float] = {}
        for k, v in obj.items():
            out[int(str(k).strip())] = float(v)
        return out
    except Exception:
        return {}

_BETA_BY_MONTH = _parse_beta_by_month(FAMILY_BETA_BY_MONTH_RAW)

def get_beta_for_date(d: pd.Timestamp) -> float:
    if FAMILY_BETA_MODE == "month":
        m = int(pd.Timestamp(d).month)
        return float(_BETA_BY_MONTH.get(m, FAMILY_BETA_FALLBACK))
    return float(FAMILY_TOTAL_BETA)


# ---- DOY seasonality gate ----
ENABLE_DOY_GATE = os.getenv("V4_ENABLE_DOY_GATE", "1") == "1"
DOY_GATE_MODE = os.getenv("V4_DOY_GATE_MODE", "soft")
DOY_SMOOTH = int(os.getenv("V4_DOY_SMOOTH", "15"))
DOY_SOFT_FLOOR = float(os.getenv("V4_DOY_SOFT_FLOOR", "0.01"))
DOY_SOFT_MULT = float(os.getenv("V4_DOY_SOFT_MULT", "0.25"))
DOY_HARD_FLOOR = float(os.getenv("V4_DOY_HARD_FLOOR", "0.003"))


# ---- Hurdle (p_pos * qty_reg) ----
ENABLE_HURDLE = os.getenv("V4_ENABLE_HURDLE", "1") == "1"
HURDLE_P_FLOOR = float(os.getenv("V4_HURDLE_P_FLOOR", "0.00"))  # opzionale: taglia probabilità troppo basse

HORIZON_DAYS = int(os.getenv("V4_HORIZON_DAYS", "10"))
MODELS_DIR = os.getenv("GH_MODELS_DIR", os.path.join(BASE_DIR, "models_v4"))

FEATURE_TABLE = "public.greenhouse_forecast_features_dense"
HOLIDAYS_TABLE = "public.greenhouse_holidays"
WEATHER_TABLE = "public.greenhouse_weather_daily"
FORECAST_TABLE = "public.greenhouse_forecast_results_v2"

STRENGTH_TABLE = "public.greenhouse_weekday_strength"
STRENGTH_FAMILY_TABLE = "public.greenhouse_weekday_strength_family"
STRENGTH_MIN = float(os.getenv("V4_STRENGTH_MIN", "0.6"))
STRENGTH_MAX = float(os.getenv("V4_STRENGTH_MAX", "1.8"))

HARD_ZERO_MIN_POS_DAYS = int(os.getenv("V4_HARD_ZERO_MIN_POS_DAYS", "8"))
HARD_ZERO_MIN_SUM = float(os.getenv("V4_HARD_ZERO_MIN_SUM", "8.0"))
HARD_ZERO_MIN_POS_RATE = float(os.getenv("V4_HARD_ZERO_MIN_POS_RATE", "0.002"))

SOFT_GATE_POS_RATE_FLOOR = float(os.getenv("V4_SOFT_GATE_POS_RATE_FLOOR", "0.02"))
SOFT_GATE_STRENGTH = float(os.getenv("V4_SOFT_GATE_STRENGTH", "0.85"))

BLEND_ALPHA_MIN = float(os.getenv("V4_BLEND_ALPHA_MIN", "0.20"))
BLEND_ALPHA_MAX = float(os.getenv("V4_BLEND_ALPHA_MAX", "0.85"))

USE_FAMILY_LEVEL = os.getenv("V4_USE_FAMILY_LEVEL", "1") == "1"


ENABLE_WEEKEND_REBALANCE = os.getenv("V4_ENABLE_WEEKEND_REBALANCE", "1") == "1"
WEEKEND_REBALANCE_STRENGTH = float(os.getenv("V4_WEEKEND_REBALANCE_STRENGTH", "0.70"))
MIN_REBALANCE_TOTAL = float(os.getenv("V4_MIN_REBALANCE_TOTAL", "5.0"))

ENABLE_WINDOW_ANCHOR = os.getenv("V4_ENABLE_WINDOW_ANCHOR", "1") == "1"
WINDOW_ANCHOR_LAMBDA = float(os.getenv("V4_WINDOW_ANCHOR_LAMBDA", "0.30"))
WINDOW_ANCHOR_MIN_YEARS = int(os.getenv("V4_WINDOW_ANCHOR_MIN_YEARS", "8"))
WINDOW_ANCHOR_MIN_FC_TOTAL = float(os.getenv("V4_WINDOW_ANCHOR_MIN_FC_TOTAL", "3.0"))
WINDOW_ANCHOR_DYNAMIC = os.getenv("V4_WINDOW_ANCHOR_DYNAMIC", "1") == "1"
WINDOW_ANCHOR_LAMBDA_MAX = float(os.getenv("V4_WINDOW_ANCHOR_LAMBDA_MAX", "0.85"))
WINDOW_ANCHOR_GAP_FULL = float(os.getenv("V4_WINDOW_ANCHOR_GAP_FULL", "0.50"))

ENABLE_MICRO_CAP = os.getenv("V4_ENABLE_MICRO_CAP", "1") == "1"
MICRO_CAP_EXPECTED_MAX = float(os.getenv("V4_MICRO_CAP_EXPECTED_MAX", "3.0"))
MICRO_CAP_MULT = float(os.getenv("V4_MICRO_CAP_MULT", "2.0"))
MICRO_CAP_ABS_MAX = float(os.getenv("V4_MICRO_CAP_ABS_MAX", "3.0"))

ENABLE_PRESEASON_WARMUP = os.getenv("V4_ENABLE_PRESEASON_WARMUP", "1") == "1"
PRESEASON_DAYS = int(os.getenv("V4_PRESEASON_DAYS", "30"))
PRESEASON_FLOOR_FRAC = float(os.getenv("V4_PRESEASON_FLOOR_FRAC", "0.05"))
PRESEASON_MIN_YEARS = int(os.getenv("V4_PRESEASON_MIN_YEARS", "6"))


# =========================
# DB
# =========================
def get_engine():
    """
    Crea engine Postgres usando PG_* dal .env (robusto anche con password con caratteri speciali).
    """
    from dotenv import load_dotenv
    from jobs.common import load_env; load_env()

    import os
    host = os.getenv("PG_HOST")
    port = int(os.getenv("PG_PORT", "5432"))
    db = os.getenv("PG_DB", "postgres")
    user = os.getenv("PG_USER")
    pw = os.getenv("PG_PASSWORD")
    ssl = os.getenv("PG_SSLMODE", "require")

    if not all([host, user, pw, db]):
        raise RuntimeError("Variabili PG_* mancanti nel .env")

    url = URL.create(
        drivername="postgresql+psycopg",
        username=user,
        password=pw,
        host=host,
        port=port,
        database=db,
        query={"sslmode": ssl},
    )

    return sa.create_engine(url, pool_pre_ping=True)


def safe_slug(s: str) -> str:
    s = (s or "").strip().lower()
    s = s.replace("€", "eur").replace(" ", "_")
    return s


def bundle_path(famiglia_slug: str) -> str:
    s = (famiglia_slug or "").strip().lower()
    return os.path.join(MODELS_DIR, f"bundle_{s}_v4.pkl")


# =========================
# Small utils
# =========================
def calendar_feats(d: pd.Timestamp, dow_pg: int):
    doy = int(d.dayofyear)
    doy_sin = float(np.sin(2 * np.pi * doy / 365.0))
    doy_cos = float(np.cos(2 * np.pi * doy / 365.0))
    dow_sin = float(np.sin(2 * np.pi * dow_pg / 7.0))
    dow_cos = float(np.cos(2 * np.pi * dow_pg / 7.0))
    is_weekend = int(dow_pg in [0, 6])
    is_month_start = int(d.day <= 3)
    is_month_end = int(d.day >= 28)
    return doy, doy_sin, doy_cos, dow_sin, dow_cos, is_weekend, is_month_start, is_month_end


def compute_lags_ma(series_values: list[float]) -> dict:
    def lag(k: int):
        return series_values[-k] if len(series_values) >= k else np.nan

    def ma(k: int):
        if len(series_values) >= k:
            return float(np.mean(series_values[-k:]))
        return np.nan

    return {
        "qty_lag_1": lag(1),
        "qty_lag_2": lag(2),
        "qty_lag_3": lag(3),
        "qty_lag_7": lag(7),
        "qty_lag_10": lag(10),
        "qty_lag_14": lag(14),
        "qty_ma_3": ma(3),
        "qty_ma_7": ma(7),
        "qty_ma_10": ma(10),
        "qty_ma_14": ma(14),
        "qty_ma_28": ma(28),
    }


def df_to_dict(df: pd.DataFrame, keys: list[str]) -> dict:
    out = {}
    if df is None or df.empty:
        return out
    for r in df.to_dict(orient="records"):
        k = tuple(r[c] for c in keys)
        out[k] = r
    return out


def delete_family_window(conn, famiglia: str, start_date, end_date):
    """
    Cancella solo i record della stessa famiglia e solo nella finestra forecast.
    start_date/end_date: stringhe 'YYYY-MM-DD' o date.
    """
    conn.execute(
        text(f"""
            DELETE FROM {FORECAST_TABLE}
            WHERE LOWER(famiglia)=LOWER(:famiglia)
              AND data BETWEEN :start_d AND :end_d;
        """),
        {"famiglia": famiglia, "start_d": start_date, "end_d": end_date},
    )


def upsert_forecast(conn, df_out: pd.DataFrame) -> int:
    """
    UPSERT (insert/update) per evitare TRUNCATE e supportare run multi-famiglia.
    Richiede UNIQUE(data, famiglia, fascia_prezzo_iva_inc) su Supabase.
    """
    if df_out.empty:
        return 0

    insert_sql = text(f"""
        INSERT INTO {FORECAST_TABLE}
            (data, famiglia, fascia_prezzo_iva_inc, qty_forecast, created_at)
        VALUES
            (:data, :famiglia, :fascia, :qty, now())
        ON CONFLICT (data, famiglia, fascia_prezzo_iva_inc)
        DO UPDATE SET
            qty_forecast = EXCLUDED.qty_forecast,
            created_at = now();
    """)

    rows = []
    for r in df_out.itertuples(index=False):
        rows.append({
            "data": (r.data.date().isoformat() if hasattr(r.data, "date") else str(r.data)),
            "famiglia": str(r.famiglia),
            "fascia": str(r.fascia_prezzo_iva_inc),
            "qty": float(r.qty_forecast),
        })

    # batch per evitare payload enormi
    B = 2000
    for i in range(0, len(rows), B):
        conn.execute(insert_sql, rows[i:i+B])

    return len(rows)


def load_strength_getter(engine, famiglia: str):
    q_s = text(
        f"""
        SELECT fascia_prezzo_iva_inc, week_of_year, dow, strength
        FROM {STRENGTH_TABLE}
        WHERE LOWER(famiglia) = LOWER(:famiglia);
    """
    )
    s_fascia = pd.read_sql(q_s, engine, params={"famiglia": famiglia})

    q_sf = text(
        f"""
        SELECT week_of_year, dow, strength
        FROM {STRENGTH_FAMILY_TABLE}
        WHERE LOWER(famiglia) = LOWER(:famiglia);
    """
    )
    s_family = pd.read_sql(q_sf, engine, params={"famiglia": famiglia})

    strength_fascia = {
        (str(r.fascia_prezzo_iva_inc), int(r.week_of_year), int(r.dow)): float(r.strength)
        for r in s_fascia.itertuples(index=False)
    }
    strength_family = {(int(r.week_of_year), int(r.dow)): float(r.strength) for r in s_family.itertuples(index=False)}

    def get_strength(fascia: str, week_of_year: int, dow: int) -> float:
        v = strength_fascia.get((str(fascia), int(week_of_year), int(dow)))
        if v is not None:
            return float(v)
        v2 = strength_family.get((int(week_of_year), int(dow)))
        if v2 is not None:
            return float(v2)
        return 1.0

    return get_strength


def median_fallback(medians: dict, col: str, default: float = 0.0) -> float:
    v = medians.get(col, default)
    try:
        v = float(v)
        if np.isnan(v):
            return float(default)
        return v
    except Exception:
        return float(default)


def zero_feats_from_queue(q: list[float]):
    zs = 0
    for v in reversed(q):
        if v > 0:
            break
        zs += 1
    zs = int(min(zs, 365))

    ds = 9999
    for i in range(1, min(len(q), 366) + 1):
        if q[-i] > 0:
            ds = i - 1
            break
    ds = int(min(ds, 365))
    return zs, ds


# =========================
# Prior logic
# =========================
def pick_prior(dmrow, dwrow, doyrow, mrow, wrow):
    if dmrow.get("dm_n", 0) >= 20 and not pd.isna(dmrow.get("dm_avg", np.nan)):
        return float(dmrow["dm_avg"]), float(dmrow.get("dm_pos_rate", 0.0) or 0.0), int(dmrow.get("dm_n", 0))
    if dwrow.get("dw_n", 0) >= 20 and not pd.isna(dwrow.get("dw_avg", np.nan)):
        return float(dwrow["dw_avg"]), float(dwrow.get("dw_pos_rate", 0.0) or 0.0), int(dwrow.get("dw_n", 0))
    if doyrow.get("doy_n", 0) >= 10 and not pd.isna(doyrow.get("doy_avg", np.nan)):
        return float(doyrow["doy_avg"]), float(doyrow.get("doy_pos_rate", 0.0) or 0.0), int(doyrow.get("doy_n", 0))
    if mrow.get("m_n", 0) >= 30 and not pd.isna(mrow.get("m_avg", np.nan)):
        return float(mrow["m_avg"]), float(mrow.get("m_pos_rate", 0.0) or 0.0), int(mrow.get("m_n", 0))
    if wrow.get("w_n", 0) >= 30 and not pd.isna(wrow.get("w_avg", np.nan)):
        return float(wrow["w_avg"]), float(wrow.get("w_pos_rate", 0.0) or 0.0), int(wrow.get("w_n", 0))
    return None, 0.0, 0


def compute_alpha(pos_rate: float, ds: int) -> float:
    pr = float(pos_rate)
    pr = max(0.0, min(1.0, pr))
    alpha = 0.35 + 0.50 * pr
    if ds >= 60:
        alpha *= 0.7
    if ds >= 180:
        alpha *= 0.4
    return max(BLEND_ALPHA_MIN, min(BLEND_ALPHA_MAX, alpha))


def soft_gate_multiplier(prior_pos_rate: float) -> float:
    pr = max(0.0, min(1.0, float(prior_pos_rate)))
    floor = max(1e-6, float(SOFT_GATE_POS_RATE_FLOOR))
    if pr >= floor:
        return 1.0
    x = pr / floor
    k = max(0.01, 1.0 - float(SOFT_GATE_STRENGTH))
    return float(x ** (1.0 / k))


# =========================
# Shares family -> fascia
# =========================
def build_share_tables_from_hist(hist: pd.DataFrame) -> dict:
    h = hist.copy()
    h["data"] = pd.to_datetime(h["data"])
    h["dow"] = ((h["data"].dt.weekday + 1) % 7).astype(int)
    h["month"] = h["data"].dt.month.astype(int)
    h["doy"] = h["data"].dt.dayofyear.astype(int)

    day_tot = h.groupby("data")["qty_venduta"].sum().rename("day_total").reset_index()
    h = h.merge(day_tot, on="data", how="left")
    h["share"] = np.where(h["day_total"] > 0, h["qty_venduta"] / h["day_total"], np.nan)

    dm = h.groupby(["dow", "month", "fascia_prezzo_iva_inc"])["share"].mean().reset_index()
    doy = h.groupby(["doy", "fascia_prezzo_iva_inc"])["share"].mean().reset_index()
    m = h.groupby(["month", "fascia_prezzo_iva_inc"])["share"].mean().reset_index()

    return {
        "dm": df_to_dict(dm, ["dow", "month", "fascia_prezzo_iva_inc"]),
        "doy": df_to_dict(doy, ["doy", "fascia_prezzo_iva_inc"]),
        "m": df_to_dict(m, ["month", "fascia_prezzo_iva_inc"]),
    }


def pick_share(share_tbl: dict, dow: int, month: int, doy: int, fascia: str):
    v = share_tbl["dm"].get((dow, month, fascia))
    if v is not None and not pd.isna(v.get("share", np.nan)):
        return float(v["share"])
    v = share_tbl["doy"].get((doy, fascia))
    if v is not None and not pd.isna(v.get("share", np.nan)):
        return float(v["share"])
    v = share_tbl["m"].get((month, fascia))
    if v is not None and not pd.isna(v.get("share", np.nan)):
        return float(v["share"])
    return None


# =========================
# Weekend + anchor helpers
# =========================
def compute_hist_weekend_share(hist_day_total: pd.DataFrame, months: list[int]) -> float:
    h = hist_day_total.copy()
    h["data"] = pd.to_datetime(h["data"])
    h["month"] = h["data"].dt.month.astype(int)
    h = h[h["month"].isin(months)].copy()
    if h.empty:
        return 0.0
    h["dow_pg"] = ((h["data"].dt.weekday + 1) % 7).astype(int)
    wk = h[h["dow_pg"].isin([0, 6])]["qty_total"].sum()
    tot = h["qty_total"].sum()
    return float(wk / tot) if tot > 0 else 0.0


def rebalance_weekend(df_family_day: pd.DataFrame, target_weekend_share: float, strength: float) -> pd.DataFrame:
    df = df_family_day.copy()
    if df.empty:
        return df
    if df["qty_total_pred"].sum() < MIN_REBALANCE_TOTAL:
        return df

    df["dow_pg"] = ((pd.to_datetime(df["data"]).dt.weekday + 1) % 7).astype(int)
    is_wk = df["dow_pg"].isin([0, 6])

    total = float(df["qty_total_pred"].sum())
    wk_sum = float(df.loc[is_wk, "qty_total_pred"].sum())
    wd_sum = float(df.loc[~is_wk, "qty_total_pred"].sum())

    if total <= 0 or wk_sum <= 0 or wd_sum <= 0:
        return df

    cur_share = wk_sum / total
    target = max(0.0, min(1.0, float(target_weekend_share)))
    lam = max(0.0, min(1.0, float(strength)))

    desired_share = (1 - lam) * cur_share + lam * target
    desired_wk = desired_share * total
    desired_wd = total - desired_wk

    f_wk = desired_wk / wk_sum if wk_sum > 0 else 1.0
    f_wd = desired_wd / wd_sum if wd_sum > 0 else 1.0

    df.loc[is_wk, "qty_total_pred"] = df.loc[is_wk, "qty_total_pred"] * f_wk
    df.loc[~is_wk, "qty_total_pred"] = df.loc[~is_wk, "qty_total_pred"] * f_wd
    df["qty_total_pred"] = df["qty_total_pred"].clip(lower=0.0)
    return df[["data", "qty_total_pred"]]


def compute_hist_expected_total_for_window(hist_day_total: pd.DataFrame, forecast_dates: pd.DatetimeIndex):
    if hist_day_total is None or hist_day_total.empty or forecast_dates is None or len(forecast_dates) == 0:
        return 0.0, 0

    h = hist_day_total.copy()
    h["data"] = pd.to_datetime(h["data"])
    h["year"] = h["data"].dt.year.astype(int)
    h["month"] = h["data"].dt.month.astype(int)
    h["day"] = h["data"].dt.day.astype(int)

    md_set = set((int(d.month), int(d.day)) for d in forecast_dates)
    md_df = pd.DataFrame(list(md_set), columns=["month", "day"])
    hh = h.merge(md_df, on=["month", "day"], how="inner")
    if hh.empty:
        return 0.0, 0

    by_year = hh.groupby("year")["qty_total"].sum()
    by_year = by_year[by_year > 0]
    n_years = int(by_year.shape[0])
    avg_total = float(by_year.mean()) if n_years > 0 else 0.0
    return avg_total, n_years


def compute_dynamic_lambda(base_lam: float, n_years: int, fc_total: float, expected_total: float) -> float:
    base = max(0.0, min(1.0, float(base_lam)))
    years_factor = (float(n_years) - 5.0) / 10.0
    years_factor = max(0.0, min(1.0, years_factor))
    denom = max(1.0, float(expected_total))
    gap = abs(float(expected_total) - float(fc_total)) / denom
    gap_full = max(0.05, float(WINDOW_ANCHOR_GAP_FULL))
    gap_factor = max(0.0, min(1.0, gap / gap_full))
    lam_max = max(base, min(1.0, float(WINDOW_ANCHOR_LAMBDA_MAX)))
    lam = base + (lam_max - base) * years_factor * gap_factor
    return max(0.0, min(lam_max, lam))


def compute_days_to_season(d: pd.Timestamp, season_p50_doy):
    if season_p50_doy is None or np.isnan(season_p50_doy):
        return None
    doy = int(d.dayofyear)
    target = int(round(float(season_p50_doy)))
    return target - doy


def apply_microcap_and_warmup(
    df_fam_pred: pd.DataFrame,
    dates: pd.DatetimeIndex,
    expected_total: float,
    n_years: int,
    season_stats: dict | None,
) -> pd.DataFrame:
    out = df_fam_pred.copy()
    if out.empty:
        return out

    fc_total = float(out["qty_total_pred"].sum())

    if ENABLE_MICRO_CAP and expected_total > 0 and expected_total <= MICRO_CAP_EXPECTED_MAX:
        cap = max(MICRO_CAP_ABS_MAX, float(expected_total) * MICRO_CAP_MULT)
        if fc_total > cap:
            scale = cap / fc_total
            out["qty_total_pred"] = (out["qty_total_pred"] * scale).clip(lower=0.0)
            fc_total = float(out["qty_total_pred"].sum())
            print(f"[MICRO-CAP] cap={cap:.3f} scale={scale:.3f}")

    if ENABLE_PRESEASON_WARMUP and expected_total > 0 and n_years >= PRESEASON_MIN_YEARS and season_stats:
        season_p50 = season_stats.get("season_start_p50")
        if season_p50 is not None:
            dts_list = []
            for d in dates:
                dts = compute_days_to_season(pd.Timestamp(d), season_p50)
                if dts is not None:
                    dts_list.append(dts)
            if dts_list:
                min_dts = int(min(dts_list))
                if 0 <= min_dts <= PRESEASON_DAYS:
                    floor_total = float(expected_total) * float(PRESEASON_FLOOR_FRAC)
                    if fc_total < floor_total:
                        if fc_total > 0:
                            scale = floor_total / fc_total
                            out["qty_total_pred"] = (out["qty_total_pred"] * scale).clip(lower=0.0)
                        else:
                            out["qty_total_pred"] = float(floor_total) / float(len(out))
                        print(f"[WARMUP] min_dts={min_dts} floor_total={floor_total:.3f}")
    return out


# =========================
# PREDICT ONE FAMILY
# =========================

def ensure_model_feature_frame(df: pd.DataFrame, feature_cols, medians, *, context: str = "") -> pd.DataFrame:
    """Return df with exactly the model feature columns.

    Inference must obey the bundle feature contract. Some prediction paths build
    future feature rows manually and may not include weather/calendar columns
    that were present during training. Missing columns are filled from the
    medians stored in the bundle, falling back to 0.0.
    """
    out = df.copy()
    missing = [c for c in feature_cols if c not in out.columns]
    for c in missing:
        out[c] = median_fallback(medians, c, 0.0)

    for c in feature_cols:
        out[c] = pd.to_numeric(out[c], errors="coerce").fillna(median_fallback(medians, c, 0.0))

    if missing and os.getenv("V4_FEATURE_CONTRACT_DEBUG", "0") == "1":
        print(
            f"[FEATURE-CONTRACT] {context}: added_missing_cols={len(missing)} "
            f"sample={missing[:12]}",
            flush=True,
        )

    return out[list(feature_cols)]

def predict_one_family(engine, famiglia: str) -> pd.DataFrame:
    fam_input = (famiglia or "").strip().lower()
    fam_name, fam_slug = resolve_family_and_slug(engine, fam_input)
    print(f"RESOLVED family input='{fam_input}' -> famiglia='{fam_name}' slug='{fam_slug}'", flush=True)
    _gate_slug = fam_slug

    famiglia = fam_name
    bp = bundle_path(fam_slug)
    if not os.path.exists(bp):
        print(f"[SKIP] bundle mancante: {bp}")
        return pd.DataFrame()

    with open(bp, "rb") as f:
        bundle = pickle.load(f)

    # --- HURDLE loaders ---
    clf_pos_fascia = None
    clf_pos_family = None
    # optional: isotonic calibrator saved at train-time
    clf_pos_family_cal = None
    try:
        _src = None
        if 'family_level' in locals() and isinstance(family_level, dict):
            _src = family_level
        elif 'family_bundle' in locals() and isinstance(family_bundle, dict):
            _src = family_bundle
        if isinstance(_src, dict):
            clf_pos_family_cal = _src.get('clf_pos_cal')
    except Exception:
        clf_pos_family_cal = None

    try:
        clf_pos_fascia = (bundle.get('fascia_level') or {}).get('clf_pos')
    except Exception:
        clf_pos_fascia = None
    try:
        clf_pos_family = (bundle.get('family_level') or {}).get('clf_pos')
    except Exception:
        clf_pos_family = None
    # --- HURDLE loaders ---
    clf_pos_fascia = None
    clf_pos_family = None
    try:
        clf_pos_fascia = (bundle.get('fascia_level') or {}).get('clf_pos')
    except Exception:
        clf_pos_fascia = None
    try:
        clf_pos_family = (bundle.get('family_level') or {}).get('clf_pos')
    except Exception:
        clf_pos_family = None

    fascia_level = bundle.get("fascia_level")
    family_level = bundle.get("family_level")

    season_stats = family_level.get("season_stats") if family_level else None

    if fascia_level is None:
        print(f"[SKIP] fascia_level missing: {famiglia}")
        return pd.DataFrame()

    f_cols = fascia_level["feature_cols"]
    f_medians = fascia_level["medians"]
    fascia_map = fascia_level["fascia_map"]
    f_reg = fascia_level["regressor"]

    prof = fascia_level["profiles_full"]
    dm_d = df_to_dict(prof["dm"], ["fascia_prezzo_iva_inc", "dow", "month"])
    dw_d = df_to_dict(prof["dw"], ["fascia_prezzo_iva_inc", "dow", "week_of_year"])
    doy_d = df_to_dict(prof["doy"], ["fascia_prezzo_iva_inc", "doy"])
    m_d = df_to_dict(prof["m"], ["fascia_prezzo_iva_inc", "month"])
    w_d = df_to_dict(prof["w"], ["fascia_prezzo_iva_inc", "week_of_year"])

    # HARD gate stats (full-history, già nel bundle)
    hist_stats_full = fascia_level.get("hist_stats_full")
    stat_d = {}
    if hist_stats_full is not None and not hist_stats_full.empty:
        for r in hist_stats_full.itertuples(index=False):
            stat_d[str(r.fascia_prezzo_iva_inc)] = {
                "sum_all": float(r.sum_all),
                "pos_days_all": int(r.pos_days_all),
                "n_days_all": int(r.n_days_all),
                "pos_rate_all": float(r.pos_rate_all),
            }

    use_family = USE_FAMILY_LEVEL and (family_level is not None)
    if use_family:
        fam_cols = family_level["feature_cols"]
        fam_medians = family_level["medians"]
        fam_reg = family_level["regressor"]
        fam_prof = family_level["profiles_full"]
        fam_dm = df_to_dict(fam_prof["dm"], ["__grp__", "dow", "month"])
        fam_dw = df_to_dict(fam_prof["dw"], ["__grp__", "dow", "week_of_year"])
        fam_doy = df_to_dict(fam_prof["doy"], ["__grp__", "doy"])
        fam_m = df_to_dict(fam_prof["m"], ["__grp__", "month"])
        fam_w = df_to_dict(fam_prof["w"], ["__grp__", "week_of_year"])
    else:
        fam_cols = fam_medians = fam_reg = None
        fam_dm = fam_dw = fam_doy = fam_m = fam_w = None

    # strength getter
    get_strength = load_strength_getter(engine, famiglia)

    # storico completo (parquet-first)
    hist = load_hist_for_predict_parquet_or_db(engine, famiglia=famiglia, famiglia_slug=fam_slug, feature_table=FEATURE_TABLE)
    if hist.empty:
        print(f"[SKIP] storico vuoto: {famiglia}")
        return pd.DataFrame()

    hist["data"] = pd.to_datetime(hist["data"])
    hist["qty_venduta"] = pd.to_numeric(hist["qty_venduta"], errors="coerce").fillna(0).clip(lower=0)

    max_hist_date = hist["data"].max().date()
    start_date = max_hist_date + timedelta(days=1)
    end_date = start_date + timedelta(days=HORIZON_DAYS - 1)

    fasce = sorted(hist["fascia_prezzo_iva_inc"].dropna().unique().tolist())
    if not fasce:
        print(f"[SKIP] nessuna fascia: {famiglia}")
        return pd.DataFrame()

    share_tbl = build_share_tables_from_hist(hist)
    hist_day_total = hist.groupby("data")["qty_venduta"].sum().rename("qty_total").reset_index()
    hist_day_total["data"] = pd.to_datetime(hist_day_total["data"])

    # holidays/weather in forecast window
    q_h = text(
        f"""
        SELECT data, is_holiday
        FROM {HOLIDAYS_TABLE}
        WHERE data BETWEEN :start_d AND :end_d
        ORDER BY data;
    """
    )
    h = pd.read_sql(q_h, engine, params={"start_d": start_date.isoformat(), "end_d": end_date.isoformat()})
    h["data"] = pd.to_datetime(h["data"])

    q_w = text(
        f"""
        SELECT data, tmin_c, tmax_c, tavg_c, rain_mm, sun_hours
        FROM {WEATHER_TABLE}
        WHERE data BETWEEN :start_d AND :end_d
        ORDER BY data;
    """
    )
    w = pd.read_sql(q_w, engine, params={"start_d": start_date.isoformat(), "end_d": end_date.isoformat()})
    w["data"] = pd.to_datetime(w["data"])

    # queues autoregressive
    queues = {
        fascia: [float(x) for x in hist.loc[hist["fascia_prezzo_iva_inc"] == fascia, "qty_venduta"].tolist()]
        for fascia in fasce
    }
    fam_queue = [float(x) for x in hist.groupby("data")["qty_venduta"].sum().tolist()]

    dates = pd.date_range(start=start_date, end=end_date, freq="D")
    fam_day_pred = []

    # =========================
    # 1) Predict family totals (autoregressivo)
    # =========================
    for d in dates:
        week_of_year = int(d.isocalendar().week)
        month_num = int(d.month)
        year_num = int(d.year)
        dow_pg = int((d.weekday() + 1) % 7)

        doy, doy_sin, doy_cos, dow_sin, dow_cos, is_weekend, is_month_start, is_month_end = calendar_feats(d, dow_pg)

        hh = h.loc[h["data"] == d]
        is_holiday = bool(hh.iloc[0]["is_holiday"]) if not hh.empty else False
        next_is_holiday = (
            bool(h.loc[h["data"] == (d + timedelta(days=1)), "is_holiday"].iloc[0])
            if not h.loc[h["data"] == (d + timedelta(days=1))].empty
            else False
        )
        prev_is_holiday = (
            bool(h.loc[h["data"] == (d - timedelta(days=1)), "is_holiday"].iloc[0])
            if not h.loc[h["data"] == (d - timedelta(days=1))].empty
            else False
        )
        is_pre_holiday = int(next_is_holiday)
        is_post_holiday = int(prev_is_holiday)

        ww = w.loc[w["data"] == d]
        if not ww.empty:
            tmin_c = ww.iloc[0]["tmin_c"]
            tmax_c = ww.iloc[0]["tmax_c"]
            tavg_c = ww.iloc[0]["tavg_c"]
            rain_mm = ww.iloc[0]["rain_mm"]
            sun_hours = ww.iloc[0]["sun_hours"]
        else:
            tmin_c = tmax_c = tavg_c = rain_mm = sun_hours = np.nan

        if use_family:
            fam_lm = compute_lags_ma(fam_queue)
            fam_zs, fam_ds = zero_feats_from_queue(fam_queue)

            fdm = fam_dm.get(("ALL", dow_pg, month_num), {})
            fdw = fam_dw.get(("ALL", dow_pg, week_of_year), {})
            fdoy = fam_doy.get(("ALL", doy), {})
            fm = fam_m.get(("ALL", month_num), {})
            fw = fam_w.get(("ALL", week_of_year), {})

            prior_mean, prior_pos_rate, _ = pick_prior(fdm, fdw, fdoy, fm, fw)
            alpha = compute_alpha(prior_pos_rate, fam_ds)

            # --- season features for PREDICT (family) ---

            try:

                # try to add seasonality features on the df used for Xfam

                df_feat = add_season_features(df_feat, 'data')

            except Exception as _e:

                pass


            Xfam = pd.DataFrame(
                [
                    {
                        "dow": dow_pg,
                        "week_of_year": week_of_year,
                        "month": month_num,
                        "year": year_num,
                        "doy_sin": doy_sin,
                        "doy_cos": doy_cos,
                        "dow_sin": dow_sin,
                        "dow_cos": dow_cos,
                        "is_weekend": is_weekend,
                        "is_month_start": is_month_start,
                        "is_month_end": is_month_end,
                        "is_holiday": int(is_holiday),
                        "is_pre_holiday": int(is_pre_holiday),
                        "is_post_holiday": int(is_post_holiday),
                        "tmin_c": tmin_c,
                        "tmax_c": tmax_c,
                        "tavg_c": tavg_c,
                        "rain_mm": rain_mm,
                        "sun_hours": sun_hours,
                        **fam_lm,
                        "is_zero_lag1": int(
                            (fam_lm["qty_lag_1"] if not np.isnan(fam_lm["qty_lag_1"]) else 0.0) <= 0.0
                        ),
                        "is_zero_ma7": int(
                            (fam_lm["qty_ma_7"] if not np.isnan(fam_lm["qty_ma_7"]) else 0.0) <= 0.0
                        ),
                        "zero_streak": fam_zs,
                        "days_since_last_sale": fam_ds,
                        "dm_avg": fdm.get("dm_avg", np.nan),
                        "dm_p50": fdm.get("dm_p50", np.nan),
                        "dm_n": fdm.get("dm_n", 0),
                        "dm_pos_rate": fdm.get("dm_pos_rate", np.nan),
                        "dw_avg": fdw.get("dw_avg", np.nan),
                        "dw_p50": fdw.get("dw_p50", np.nan),
                        "dw_n": fdw.get("dw_n", 0),
                        "dw_pos_rate": fdw.get("dw_pos_rate", np.nan),
                        "doy_avg": fdoy.get("doy_avg", np.nan),
                        "doy_p50": fdoy.get("doy_p50", np.nan),
                        "doy_n": fdoy.get("doy_n", 0),
                        "doy_pos_rate": fdoy.get("doy_pos_rate", np.nan),
                        "m_avg": fm.get("m_avg", np.nan),
                        "m_p50": fm.get("m_p50", np.nan),
                        "m_n": fm.get("m_n", 0),
                        "m_pos_rate": fm.get("m_pos_rate", np.nan),
                        "w_avg": fw.get("w_avg", np.nan),
                        "w_p50": fw.get("w_p50", np.nan),
                        "w_n": fw.get("w_n", 0),
                        "w_pos_rate": fw.get("w_pos_rate", np.nan),
                        "prior_mean": prior_mean if prior_mean is not None else np.nan,
                        "prior_pos_rate": prior_pos_rate,
                        "prior_n": 0,
                    }
                ]
            )

            Xfam = ensure_model_feature_frame(
                Xfam,
                fam_cols,
                fam_medians,
                context=f"family_level:{famiglia}",
            )
            if HURDLE_DEBUG:
                try:
                    print(f"[HURDLE-XFAM] Xfam shape={Xfam.shape}")
                    print(f"[HURDLE-XFAM] first cols={list(Xfam.columns)[:20]}")
                except Exception as e:
                    print(f"[HURDLE-XFAM] print failed: {e}")

            # --- HURDLE day-level prob (apply AFTER anchor) ---
            p_pos_day = 1.0
            if ENABLE_HURDLE and (clf_pos_family is not None):
                try:
                    p_pos_day = float(np.clip(clf_pos_family.predict_proba(Xfam)[0, 1], 0, 1))
                    # apply optional calibration (train-time isotonic)
                    if clf_pos_family_cal is not None:
                        try:
                            # isotonic has .predict; fallback if different object
                            p_pos_day = float(clf_pos_family_cal.predict([float(p_pos_day)])[0])
                        except Exception:
                            pass

                    if HURDLE_P_FLOOR > 0 and p_pos_day < HURDLE_P_FLOOR:
                        p_pos_day = 0.0

                except Exception as e:
                    if HURDLE_DEBUG:
                        print(f"[HURDLE-ERR] p_pos_day predict_proba failed: {e}")
                    p_pos_day = 1.0

            # --- anti-overconfidence (cap + damping) ---
            p_pos_day = min(float(p_pos_day), HURDLE_P_CAP)
            p_pos_day = float(p_pos_day) ** HURDLE_P_POWER
            p_pos_day = float(max(0.0, min(1.0, p_pos_day)))
            base_reg = float(np.clip(fam_reg.predict(Xfam)[0], 0, None))
            if ENABLE_HURDLE and (clf_pos_family is not None):
                p_pos = float(np.clip(clf_pos_family.predict_proba(Xfam)[0, 1], 0, 1))
                if HURDLE_P_FLOOR > 0 and p_pos < HURDLE_P_FLOOR:
                    p_pos = 0.0
                # base hurdle disabled: apply hurdle only on FAMILY TOTALS via p_pos_day
                base = base_reg
                if HURDLE_DEBUG:
                    print(f"[HURDLE] fam_day p_pos(raw)={p_pos:.3f} base_reg={base_reg:.3f} NOTE=totals_only")
            else:
                base = base_reg
            fam_total = base if prior_mean is None else (alpha * base + (1 - alpha) * float(prior_mean))
            fam_total = max(0.0, float(fam_total))
        else:
            fam_total = float(hist_day_total.loc[hist_day_total["data"].dt.month == month_num, "qty_total"].mean())
            fam_total = 0.0 if np.isnan(fam_total) else max(0.0, fam_total)


        p_pos_day = 1.0  # fallback default to avoid unbound on sparse families
        fam_day_pred.append({"data": d, "qty_total_pred": fam_total, "p_pos_day": float(p_pos_day)})
        fam_queue.append(float(fam_total))

    df_fam_pred = pd.DataFrame(fam_day_pred)
    # keep p_pos_day across transforms (rebalance/anchor may drop extra cols)
    df_p_pos = df_fam_pred[['data','p_pos_day']].copy() if 'p_pos_day' in df_fam_pred.columns else None

    # =========================
    # 1b) Weekend rebalance (opzionale)
    # =========================
    if ENABLE_WEEKEND_REBALANCE:
        months_in_window = sorted(set(int(x.month) for x in dates))
        target_wk_share = compute_hist_weekend_share(hist_day_total, months_in_window)
        df_fam_pred = rebalance_weekend(df_fam_pred, target_wk_share, WEEKEND_REBALANCE_STRENGTH)

        # re-attach p_pos_day after weekend rebalance
        if df_p_pos is not None:
            df_fam_pred = df_fam_pred.merge(df_p_pos, on='data', how='left')

    # =========================
    # 1c) Window anchor (opzionale, default come prima via env)
    # =========================
    if ENABLE_WINDOW_ANCHOR:
        expected_total, n_years = compute_hist_expected_total_for_window(hist_day_total, dates)
        fc_total = float(df_fam_pred["qty_total_pred"].sum())
        lam0 = max(0.0, min(1.0, float(WINDOW_ANCHOR_LAMBDA)))
        lam = compute_dynamic_lambda(lam0, n_years, fc_total, expected_total) if WINDOW_ANCHOR_DYNAMIC else lam0

        if n_years >= WINDOW_ANCHOR_MIN_YEARS and expected_total > 0 and fc_total >= WINDOW_ANCHOR_MIN_FC_TOTAL:
            desired_total = (1.0 - lam) * fc_total + lam * float(expected_total)
            scale = desired_total / fc_total if fc_total > 0 else 1.0
            scale = max(0.5, min(2.0, scale))
            df_fam_pred["qty_total_pred"] = (df_fam_pred["qty_total_pred"] * scale).clip(lower=0.0)


            print(
                f"[ANCHOR] {famiglia}: fc_total={fc_total:.3f} expected={expected_total:.3f} years={n_years} lam={lam:.3f} scale={scale:.3f}"
            )
        else:
            print(f"[ANCHOR-SKIP] {famiglia}: fc_total={fc_total:.3f} expected={expected_total:.3f} years={n_years}")

        df_fam_pred = apply_microcap_and_warmup(df_fam_pred, dates, expected_total, n_years, season_stats)
    # =========================
    # 1d) Apply family beta AFTER all post-processing (recommended)
    # =========================
    df_fam_pred["beta"] = pd.to_datetime(df_fam_pred["data"]).apply(get_beta_for_date).astype(float)
    df_fam_pred["qty_total_pred"] = (df_fam_pred["qty_total_pred"] * df_fam_pred["beta"]).clip(lower=0.0)
    df_fam_pred = df_fam_pred.drop(columns=["beta"])



    # =========================
    # 2) Predict fasce anchored to family total (identico)
    # =========================
    # ===== HURDLE TOTALS ALWAYS (anchor ON/OFF) =====
    if ENABLE_HURDLE and ('p_pos_day' in df_fam_pred.columns) and ('_hurdle_totals_applied' not in df_fam_pred.columns):
        _p0 = df_fam_pred['p_pos_day'].astype(float).fillna(1.0).clip(0.0, 1.0)
        if HURDLE_P_FLOOR > 0:
            _p = _p0.where(_p0 >= HURDLE_P_FLOOR, 0.0)
        else:
            _p = _p0
        if HURDLE_DEBUG:
            print(f"[HURDLE-TOTAL-DBG] p_pos_day damped min={_p0.min():.4f} max={_p0.max():.4f} mean={_p0.mean():.4f} <floor={(_p0 < HURDLE_P_FLOOR).sum()}/{len(_p0)}")
            print(f"[HURDLE-TOTAL-DBG] sum_before={df_fam_pred['qty_total_pred'].sum():.3f}")
        df_fam_pred['qty_total_pred'] = (df_fam_pred['qty_total_pred'].astype(float) * _p).clip(lower=0.0)
        df_fam_pred['_hurdle_totals_applied'] = 1
        if HURDLE_DEBUG:
            print(f"[HURDLE-TOTAL-DBG] sum_after={df_fam_pred['qty_total_pred'].sum():.3f}")
    
    # mappa finale: usa SEMPRE questi totali nel loop fasce
    fam_total_by_date = dict(zip(df_fam_pred['data'], df_fam_pred['qty_total_pred']))

    all_rows = []

    for d in dates:
        week_of_year = int(d.isocalendar().week)
        month_num = int(d.month)
        year_num = int(d.year)
        dow_pg = int((d.weekday() + 1) % 7)
        doy, doy_sin, doy_cos, dow_sin, dow_cos, is_weekend, is_month_start, is_month_end = calendar_feats(d, dow_pg)

        hh = h.loc[h["data"] == d]
        is_holiday = bool(hh.iloc[0]["is_holiday"]) if not hh.empty else False
        next_is_holiday = (
            bool(h.loc[h["data"] == (d + timedelta(days=1)), "is_holiday"].iloc[0])
            if not h.loc[h["data"] == (d + timedelta(days=1))].empty
            else False
        )
        prev_is_holiday = (
            bool(h.loc[h["data"] == (d - timedelta(days=1)), "is_holiday"].iloc[0])
            if not h.loc[h["data"] == (d - timedelta(days=1))].empty
            else False
        )
        is_pre_holiday = int(next_is_holiday)
        is_post_holiday = int(prev_is_holiday)

        ww = w.loc[w["data"] == d]
        if not ww.empty:
            tmin_c = ww.iloc[0]["tmin_c"]
            tmax_c = ww.iloc[0]["tmax_c"]
            tavg_c = ww.iloc[0]["tavg_c"]
            rain_mm = ww.iloc[0]["rain_mm"]
            sun_hours = ww.iloc[0]["sun_hours"]
        else:
            tmin_c = tmax_c = tavg_c = rain_mm = sun_hours = np.nan

        fam_total = float(df_fam_pred.loc[df_fam_pred["data"] == d, "qty_total_pred"].iloc[0])

        # shares per fascia
        shares = {}
        for fascia in fasce:
            s = pick_share(share_tbl, dow_pg, month_num, doy, fascia)
            if s is not None and s > 0:
                shares[fascia] = float(s)
        if not shares:
            shares = {f: 1.0 for f in fasce}
        tot_s = sum(shares.values())
        shares = {k: (v / tot_s if tot_s > 0 else 1.0 / len(shares)) for k, v in shares.items()}

        tmp_preds = []
        for fascia in fasce:
            # HARD gate
            st = stat_d.get(str(fascia), None)
            if st is not None:
                if (
                    (st["pos_days_all"] < HARD_ZERO_MIN_POS_DAYS)
                    or (st["sum_all"] < HARD_ZERO_MIN_SUM)
                    or (st["pos_rate_all"] < HARD_ZERO_MIN_POS_RATE)
                ):
                    tmp_preds.append((fascia, 0.0))
                    continue

            wk_strength = get_strength(fascia, week_of_year, dow_pg)
            wk_strength = max(STRENGTH_MIN, min(STRENGTH_MAX, float(wk_strength)))

            lm = compute_lags_ma(queues[fascia])
            zs, ds = zero_feats_from_queue(queues[fascia])

            dmrow = dm_d.get((fascia, dow_pg, month_num), {})
            dwrow = dw_d.get((fascia, dow_pg, week_of_year), {})
            doyrow = doy_d.get((fascia, doy), {})
            mrow = m_d.get((fascia, month_num), {})
            wrow = w_d.get((fascia, week_of_year), {})

            prior_mean, prior_pos_rate, prior_n = pick_prior(dmrow, dwrow, doyrow, mrow, wrow)
            alpha = compute_alpha(prior_pos_rate, ds)

            fascia_enc = int(fascia_map.get(fascia, -1))

            Xrow = pd.DataFrame(
                [
                    {
                        "fascia_enc": fascia_enc,
                        "dow": dow_pg,
                        "week_of_year": week_of_year,
                        "month": month_num,
                        "year": year_num,
                        "doy_sin": doy_sin,
                        "doy_cos": doy_cos,
                        "dow_sin": dow_sin,
                        "dow_cos": dow_cos,
                        "is_weekend": is_weekend,
                        "is_month_start": is_month_start,
                        "is_month_end": is_month_end,
                        "is_holiday": int(is_holiday),
                        "is_pre_holiday": int(is_pre_holiday),
                        "is_post_holiday": int(is_post_holiday),
                        "tmin_c": tmin_c,
                        "tmax_c": tmax_c,
                        "tavg_c": tavg_c,
                        "rain_mm": rain_mm,
                        "sun_hours": sun_hours,
                        **lm,
                        "is_zero_lag1": int((lm["qty_lag_1"] if not np.isnan(lm["qty_lag_1"]) else 0.0) <= 0.0),
                        "is_zero_ma7": int((lm["qty_ma_7"] if not np.isnan(lm["qty_ma_7"]) else 0.0) <= 0.0),
                        "zero_streak": zs,
                        "days_since_last_sale": ds,
                        "dm_avg": dmrow.get("dm_avg", np.nan),
                        "dm_p50": dmrow.get("dm_p50", np.nan),
                        "dm_n": dmrow.get("dm_n", 0),
                        "dm_pos_rate": dmrow.get("dm_pos_rate", np.nan),
                        "dw_avg": dwrow.get("dw_avg", np.nan),
                        "dw_p50": dwrow.get("dw_p50", np.nan),
                        "dw_n": dwrow.get("dw_n", 0),
                        "dw_pos_rate": dwrow.get("dw_pos_rate", np.nan),
                        "doy_avg": doyrow.get("doy_avg", np.nan),
                        "doy_p50": doyrow.get("doy_p50", np.nan),
                        "doy_n": doyrow.get("doy_n", 0),
                        "doy_pos_rate": doyrow.get("doy_pos_rate", np.nan),
                        "m_avg": mrow.get("m_avg", np.nan),
                        "m_p50": mrow.get("m_p50", np.nan),
                        "m_n": mrow.get("m_n", 0),
                        "m_pos_rate": mrow.get("m_pos_rate", np.nan),
                        "w_avg": wrow.get("w_avg", np.nan),
                        "w_p50": wrow.get("w_p50", np.nan),
                        "w_n": wrow.get("w_n", 0),
                        "w_pos_rate": wrow.get("w_pos_rate", np.nan),
                        "prior_mean": prior_mean if prior_mean is not None else np.nan,
                        "prior_pos_rate": prior_pos_rate,
                        "prior_n": prior_n,
                    }
                ]
            )

            for c in Xrow.columns:
                if c == "fascia_enc":
                    continue
                Xrow[c] = pd.to_numeric(Xrow[c], errors="coerce").fillna(median_fallback(f_medians, c, 0.0))

            # --- season features for PREDICT (fasce) ---

            try:

                df_feat = add_season_features(df_feat, 'data')

            except Exception as _e:

                pass


            X = ensure_model_feature_frame(
                    Xrow,
                    f_cols,
                    f_medians,
                    context=f"fascia_level:{famiglia}",
                )
            base_reg = float(np.clip(f_reg.predict(X)[0], 0, None)) * wk_strength
            if ENABLE_HURDLE and (clf_pos_family is not None):
                p_pos = float(np.clip(clf_pos_fascia.predict_proba(X)[0, 1], 0, 1))
                if HURDLE_P_FLOOR > 0 and p_pos < HURDLE_P_FLOOR:
                    p_pos = 0.0
                # base hurdle disabled: apply hurdle only on FAMILY TOTALS via p_pos_day
                base = base_reg
                if HURDLE_DEBUG >= 2:
                    print(f"[HURDLE] fascia p_pos(raw)={p_pos:.3f} base_reg={base_reg:.3f} NOTE=totals_only")
            else:
                base = base_reg
            blended = base if prior_mean is None else (alpha * base + (1 - alpha) * float(prior_mean))
            blended = max(0.0, float(blended))
            blended *= soft_gate_multiplier(prior_pos_rate)

            tmp_preds.append((fascia, blended))

        anchored = []
        for fascia, pred in tmp_preds:
            # usa il totale famiglia POST-hurdle/anchor per questa data
            try:
                fam_total = float(fam_total_by_date.get(d, fam_total))
            except Exception:
                pass

            target = float(fam_total) * float(shares.get(fascia, 0.0))

            dmrow = dm_d.get((fascia, dow_pg, month_num), {})
            dwrow = dw_d.get((fascia, dow_pg, week_of_year), {})
            doyrow = doy_d.get((fascia, doy), {})
            mrow = m_d.get((fascia, month_num), {})
            wrow = w_d.get((fascia, week_of_year), {})
            _, prior_pos_rate, _ = pick_prior(dmrow, dwrow, doyrow, mrow, wrow)

            rel = max(0.10, min(0.90, 0.20 + 0.70 * float(prior_pos_rate)))
            qty = rel * float(pred) + (1 - rel) * float(target)
            anchored.append((fascia, max(0.0, qty)))

        s_day = sum(v for _, v in anchored)
        scale = (fam_total / s_day) if (s_day > 0 and fam_total > 0) else 0.0

        for fascia, qty in anchored:
            qty2 = float(qty) * scale if scale > 0 else 0.0
            qty2 = max(0.0, qty2)
            all_rows.append(
                {
                    "data": d,
                    "famiglia": famiglia,
                    "fascia_prezzo_iva_inc": fascia,
                    "qty_forecast": round(qty2, 3),
                }
            )
            queues[fascia].append(float(qty2))

    df_out = pd.DataFrame(all_rows)


    # ===== DOY SEASONALITY GATE (post-process) =====
    if ENABLE_DOY_GATE and not df_out.empty:
        gate_tbl = build_pos_rate_doy(hist, smooth_window=DOY_SMOOTH)
        for i, r in df_out.iterrows():
            d = pd.to_datetime(r["data"])
            doy = int(d.dayofyear)
            fascia = str(r["fascia_prezzo_iva_inc"])

            pos_rate = gate_tbl["by_fascia"].get(
                (fascia, doy),
                gate_tbl["by_family"].get(doy, 0.0)
            )

            df_out.at[i, "qty_forecast"] = apply_gate(
                r["qty_forecast"],
                pos_rate,
                mode=DOY_GATE_MODE,
                soft_floor=DOY_SOFT_FLOOR,
                soft_mult=DOY_SOFT_MULT,
                hard_floor=DOY_HARD_FLOOR
            )
    # ================================================
    print(f"[OK] {famiglia}: built={len(df_out)} rows ({start_date}→{end_date})")

    # --- seasonal gate (soft) on FINAL output ---
    try:
        _slug = locals().get('_gate_slug', None)
        df_out = apply_soft_seasonal_gate_forecast(df_out, famiglia, _slug)
    except Exception as e:
        print('[SEASON-GATE] %s: error %s' % (famiglia, e), flush=True)

    return df_out



# =========================
# MAIN
# =========================
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--family", default=os.getenv("ONLY_FAMILY", "phaelenopsis"))
    parser.add_argument("--write_db", default=os.getenv("WRITE_DB", "1"))  # 1/0
    args = parser.parse_args()

    fam = (args.family or "").strip()
    if not fam:
        raise RuntimeError("Famiglia vuota")

    engine = get_engine()
    df = predict_one_family(engine, fam)
    if str(args.write_db).lower() in ("1", "true", "yes"):
        with engine.begin() as conn:
            # finestra forecast basata sui dati prodotti
            if not df.empty:
                start_d = df["data"].min().date().isoformat() if hasattr(df["data"].min(), "date") else str(df["data"].min())
                end_d = df["data"].max().date().isoformat() if hasattr(df["data"].max(), "date") else str(df["data"].max())
                fam_name = str(df["famiglia"].iloc[0])
                delete_family_window(conn, fam_name, start_d, end_d)

            written = upsert_forecast(conn, df)

        print("DONE. total_rows_written=", written)
    else:
        print("DONE. write_db=0 (non scrivo su DB)")
        print(df.head(20))

    engine.dispose()
if __name__ == "__main__":
    main()