# backtest_v4_family_plus_fasce.py
#
# Backtest "as-of cutoff" per:
#  - family total (model family-level se presente, altrimenti fallback)
#  - fasce (model fascia-level)
#  - ancoraggio fascia->totale famiglia usando shares storiche
#  - strength da DB (weekday_strength + fallback weekday_strength_family)
#
# Output:
#  - backtest_family_plus_fasce_<fam>.csv (righe per cutoff/data/fascia + total)
#  - backtest_family_plus_fasce_<fam>_by_h.csv (metriche per orizzonte, TOTAL)
#  - backtest_family_plus_fasce_<fam>_by_fascia.csv (metriche per fascia)
#
# Env (esempio):
#  ONLY_FAMILY=phaelenopsis
#  V4_HORIZON_DAYS=10
#  BT_DAYS=180
#  BT_STEP=1
#  BT_MIN_HISTORY_DAYS=365
#
# Calibrazione family-total:
#  - Globale (default):
#      V4_FAMILY_TOTAL_BETA=1.0
#  - Per mese (consigliata se bias stagionale):
#      V4_FAMILY_BETA_MODE=month
#      V4_FAMILY_BETA_BY_MONTH='{"1":0.75,"2":0.68,"12":0.42}'
#      V4_FAMILY_BETA_FALLBACK=0.6333   # fallback (tipicamente beta globale)
#    Nota: se V4_FAMILY_BETA_MODE != "month" si usa V4_FAMILY_TOTAL_BETA.
#
# NOTE:
# - richiede bundle già allenato in models_v4/bundle_<slug>_v4.pkl
# - HARD gate in backtest è calcolato "as-of cutoff" per evitare leakage
# - (opzionale ma consigliato) puoi estendere df_true a griglia date×fasce con fill 0
#   per eliminare true_empty se il dataset non contiene righe a zero

import os
import json
import pickle
from datetime import timedelta

import numpy as np
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv
from sklearn.metrics import mean_absolute_error, mean_squared_error

from data_access_v1 import load_family_df_parquet_or_db


# =========================
# CONFIG / ENV
# =========================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, ".env")
if os.path.exists(ENV_PATH):
    load_dotenv(ENV_PATH)

FEATURE_TABLE = "public.greenhouse_forecast_features_dense"

MODELS_DIR = os.path.join(BASE_DIR, "models_v4")
TARGET_COL = "qty_venduta"

HORIZON_DAYS = int(os.getenv("V4_HORIZON_DAYS", "10"))

BT_DAYS = int(os.getenv("BT_DAYS", "100"))
BT_STEP = int(os.getenv("BT_STEP", "1"))
BT_MIN_HISTORY_DAYS = int(os.getenv("BT_MIN_HISTORY_DAYS", "365"))

# Strength tables
STRENGTH_TABLE = "public.greenhouse_weekday_strength"
STRENGTH_FAMILY_TABLE = "public.greenhouse_weekday_strength_family"
STRENGTH_MIN = float(os.getenv("V4_STRENGTH_MIN", "0.6"))
STRENGTH_MAX = float(os.getenv("V4_STRENGTH_MAX", "1.8"))

# Hard gate (full-history) -> in backtest lo calcoliamo "as-of cutoff" per evitare leakage
HARD_ZERO_MIN_POS_DAYS = int(os.getenv("V4_HARD_ZERO_MIN_POS_DAYS", "8"))
HARD_ZERO_MIN_SUM = float(os.getenv("V4_HARD_ZERO_MIN_SUM", "8.0"))
HARD_ZERO_MIN_POS_RATE = float(os.getenv("V4_HARD_ZERO_MIN_POS_RATE", "0.002"))

# Soft gate via pos_rate
SOFT_GATE_POS_RATE_FLOOR = float(os.getenv("V4_SOFT_GATE_POS_RATE_FLOOR", "0.02"))
SOFT_GATE_STRENGTH = float(os.getenv("V4_SOFT_GATE_STRENGTH", "0.85"))

# Blend Tweedie/prior
BLEND_ALPHA_MIN = float(os.getenv("V4_BLEND_ALPHA_MIN", "0.20"))
BLEND_ALPHA_MAX = float(os.getenv("V4_BLEND_ALPHA_MAX", "0.85"))

USE_FAMILY_LEVEL = os.getenv("V4_USE_FAMILY_LEVEL", "1") == "1"

# ---- Calibrazione family total
FAMILY_TOTAL_BETA = float(os.getenv("V4_FAMILY_TOTAL_BETA", "1.0"))  # default global beta
FAMILY_BETA_MODE = os.getenv("V4_FAMILY_BETA_MODE", "global").strip().lower()  # global|month
FAMILY_BETA_BY_MONTH_RAW = os.getenv("V4_FAMILY_BETA_BY_MONTH", "").strip()
FAMILY_BETA_FALLBACK = float(os.getenv("V4_FAMILY_BETA_FALLBACK", str(FAMILY_TOTAL_BETA)))


# Weekend rebalance
ENABLE_WEEKEND_REBALANCE = os.getenv("V4_ENABLE_WEEKEND_REBALANCE", "1") == "1"
WEEKEND_REBALANCE_STRENGTH = float(os.getenv("V4_WEEKEND_REBALANCE_STRENGTH", "0.70"))
MIN_REBALANCE_TOTAL = float(os.getenv("V4_MIN_REBALANCE_TOTAL", "5.0"))

# Window anchor
ENABLE_WINDOW_ANCHOR = os.getenv("V4_ENABLE_WINDOW_ANCHOR", "1") == "1"
WINDOW_ANCHOR_LAMBDA = float(os.getenv("V4_WINDOW_ANCHOR_LAMBDA", "0.30"))
WINDOW_ANCHOR_MIN_YEARS = int(os.getenv("V4_WINDOW_ANCHOR_MIN_YEARS", "8"))
WINDOW_ANCHOR_MIN_FC_TOTAL = float(os.getenv("V4_WINDOW_ANCHOR_MIN_FC_TOTAL", "3.0"))
WINDOW_ANCHOR_DYNAMIC = os.getenv("V4_WINDOW_ANCHOR_DYNAMIC", "1") == "1"
WINDOW_ANCHOR_LAMBDA_MAX = float(os.getenv("V4_WINDOW_ANCHOR_LAMBDA_MAX", "0.85"))
WINDOW_ANCHOR_GAP_FULL = float(os.getenv("V4_WINDOW_ANCHOR_GAP_FULL", "0.50"))

# Micro-cap post-anchor
ENABLE_MICRO_CAP = os.getenv("V4_ENABLE_MICRO_CAP", "1") == "1"
MICRO_CAP_EXPECTED_MAX = float(os.getenv("V4_MICRO_CAP_EXPECTED_MAX", "3.0"))
MICRO_CAP_MULT = float(os.getenv("V4_MICRO_CAP_MULT", "2.0"))
MICRO_CAP_ABS_MAX = float(os.getenv("V4_MICRO_CAP_ABS_MAX", "3.0"))

# Pre-season warm-up
ENABLE_PRESEASON_WARMUP = os.getenv("V4_ENABLE_PRESEASON_WARMUP", "1") == "1"
PRESEASON_DAYS = int(os.getenv("V4_PRESEASON_DAYS", "30"))
PRESEASON_FLOOR_FRAC = float(os.getenv("V4_PRESEASON_FLOOR_FRAC", "0.05"))
PRESEASON_MIN_YEARS = int(os.getenv("V4_PRESEASON_MIN_YEARS", "6"))


# =========================
# Beta helpers (family total)
# =========================
def _parse_beta_by_month(raw: str) -> dict[int, float]:
    if not raw:
        return {}
    try:
        obj = json.loads(raw)
        out: dict[int, float] = {}
        for k, v in obj.items():
            try:
                kk = int(k)
            except Exception:
                kk = int(str(k).strip())
            out[kk] = float(v)
        return out
    except Exception:
        return {}


_BETA_BY_MONTH = _parse_beta_by_month(FAMILY_BETA_BY_MONTH_RAW)


def get_beta_for_date(d: pd.Timestamp) -> float:
    """
    Restituisce il beta da applicare al family-total per la data d.
    - Se FAMILY_BETA_MODE == "month": usa dict per mese con fallback
    - Altrimenti: usa FAMILY_TOTAL_BETA
    """
    if FAMILY_BETA_MODE == "month":
        m = int(pd.Timestamp(d).month)
        return float(_BETA_BY_MONTH.get(m, FAMILY_BETA_FALLBACK))
    return float(FAMILY_TOTAL_BETA)


# =========================
# DB
# =========================
def get_engine():
    host = os.getenv("PG_HOST")
    port = os.getenv("PG_PORT", "5432")
    db = os.getenv("PG_DB")
    user = os.getenv("PG_USER")
    pwd = os.getenv("PG_PASSWORD")
    if not all([host, db, user, pwd]):
        raise RuntimeError("Variabili PG_* mancanti nel .env")
    return create_engine(
        f"postgresql+psycopg2://{user}:{pwd}@{host}:{port}/{db}?sslmode=require",
        pool_pre_ping=True,
    )


def safe_slug(s: str) -> str:
    s = (s or "").strip().lower()
    s = s.replace("€", "eur").replace(" ", "_")
    return s


def bundle_path(famiglia: str) -> str:
    return os.path.join(MODELS_DIR, f"bundle_{safe_slug(famiglia)}_v4.pkl")


# =========================
# Utils
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


def df_to_dict(df: pd.DataFrame, keys: list[str]) -> dict:
    out = {}
    if df is None or df.empty:
        return out
    for r in df.to_dict(orient="records"):
        k = tuple(r[c] for c in keys)
        out[k] = r
    return out


def median_fallback(medians: dict, col: str, default: float = 0.0) -> float:
    v = medians.get(col, default)
    try:
        v = float(v)
        if np.isnan(v):
            return float(default)
        return v
    except Exception:
        return float(default)


def evaluate(y_true, y_pred):
    mae = float(mean_absolute_error(y_true, y_pred))
    rmse = float(mean_squared_error(y_true, y_pred) ** 0.5)
    return mae, rmse


# =========================
# Prior logic (same as predict)
# =========================
def pick_prior(dmrow, dwrow, doyrow, mrow, wrow) -> tuple[float | None, float, int]:
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
# Shares family->fascia (as-of cutoff)
# =========================
def build_share_tables_from_hist(hist: pd.DataFrame) -> dict:
    h = hist.copy()
    h["data"] = pd.to_datetime(h["data"])
    h["dow"] = ((h["data"].dt.weekday + 1) % 7).astype(int)  # 0=dom..6=sab
    h["month"] = h["data"].dt.month.astype(int)
    h["doy"] = h["data"].dt.dayofyear.astype(int)

    day_tot = h.groupby("data")[TARGET_COL].sum().rename("day_total").reset_index()
    h = h.merge(day_tot, on="data", how="left")
    h["share"] = np.where(h["day_total"] > 0, h[TARGET_COL] / h["day_total"], np.nan)

    dm = h.groupby(["dow", "month", "fascia_prezzo_iva_inc"])["share"].mean().reset_index()
    doy = h.groupby(["doy", "fascia_prezzo_iva_inc"])["share"].mean().reset_index()
    m = h.groupby(["month", "fascia_prezzo_iva_inc"])["share"].mean().reset_index()

    return {
        "dm": df_to_dict(dm, ["dow", "month", "fascia_prezzo_iva_inc"]),
        "doy": df_to_dict(doy, ["doy", "fascia_prezzo_iva_inc"]),
        "m": df_to_dict(m, ["month", "fascia_prezzo_iva_inc"]),
    }


def pick_share(share_tbl: dict, dow: int, month: int, doy: int, fascia: str) -> float | None:
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
# Weekend rebalance + window anchor (same as predict)
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


def compute_hist_expected_total_for_window(hist_day_total: pd.DataFrame, forecast_dates: pd.DatetimeIndex) -> tuple[float, int]:
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


def compute_days_to_season(d: pd.Timestamp, season_p50_doy: float | None) -> int | None:
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

    return out


# =========================
# Strength getter (DB)
# =========================
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


# =========================
# Data load (parquet-first) + prep
# =========================
def load_family_all(engine, famiglia: str) -> pd.DataFrame:
    df = load_family_df_parquet_or_db(engine, famiglia=famiglia, min_date="2009-01-01", feature_table=FEATURE_TABLE)
    if df is None:
        df = pd.DataFrame()
    if df.empty:
        return df

    df["data"] = pd.to_datetime(df["data"])
    df[TARGET_COL] = pd.to_numeric(df[TARGET_COL], errors="coerce").fillna(0).clip(lower=0.0)
    df["famiglia"] = df["famiglia"].astype(str)
    df["fascia_prezzo_iva_inc"] = df["fascia_prezzo_iva_inc"].astype(str)
    df["dow"] = pd.to_numeric(df["dow"], errors="coerce").fillna(0).astype(int)  # 0=dom..6=sab
    return df.sort_values(["data", "fascia_prezzo_iva_inc"])


# =========================
# Predictor core "as-of cutoff"
# =========================
def predict_asof_cutoff(
    engine,
    famiglia: str,
    bundle: dict,
    df_all: pd.DataFrame,
    cutoff: pd.Timestamp,
    get_strength,
) -> pd.DataFrame:
    fascia_level = bundle.get("fascia_level")
    family_level = bundle.get("family_level")

    if fascia_level is None:
        raise RuntimeError("bundle missing fascia_level")

    season_stats = family_level.get("season_stats") if family_level is not None else None

    # fasce objects
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

    # family-level objects
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

    # storico disponibile "as-of cutoff"
    hist = df_all[df_all["data"] <= cutoff].copy()
    if hist.empty:
        return pd.DataFrame()

    # finestra forecast
    start_date = (pd.Timestamp(cutoff).date() + timedelta(days=1))
    end_date = (pd.Timestamp(start_date) + timedelta(days=HORIZON_DAYS - 1)).date()
    dates = pd.date_range(start=start_date, end=end_date, freq="D")

    # fasce viste fino a cutoff
    fasce = sorted(hist["fascia_prezzo_iva_inc"].dropna().unique().tolist())
    if not fasce:
        return pd.DataFrame()

    # shares as-of cutoff
    share_tbl = build_share_tables_from_hist(hist)

    # hist day total as-of cutoff (per weekend share + expected total window)
    hist_day_total = hist.groupby("data")[TARGET_COL].sum().rename("qty_total").reset_index()
    hist_day_total["data"] = pd.to_datetime(hist_day_total["data"])

    # queues per fascia e famiglia (as-of cutoff)
    queues = {
        fascia: [float(x) for x in hist.loc[hist["fascia_prezzo_iva_inc"] == fascia, TARGET_COL].tolist()]
        for fascia in fasce
    }
    fam_queue = [float(x) for x in hist.groupby("data")[TARGET_COL].sum().tolist()]

    # hard-gate stats per fascia (as-of cutoff)
    stats_asof = (
        hist.groupby("fascia_prezzo_iva_inc")
        .agg(
            sum_all=(TARGET_COL, "sum"),
            pos_days_all=(TARGET_COL, lambda s: int((s > 0).sum())),
            n_days_all=(TARGET_COL, "count"),
        )
        .reset_index()
    )
    stats_asof["pos_rate_all"] = np.where(
        stats_asof["n_days_all"] > 0, stats_asof["pos_days_all"] / stats_asof["n_days_all"], 0.0
    )

    stat_d_asof = {
        str(r.fascia_prezzo_iva_inc): {
            "sum_all": float(r.sum_all),
            "pos_days_all": int(r.pos_days_all),
            "n_days_all": int(r.n_days_all),
            "pos_rate_all": float(r.pos_rate_all),
        }
        for r in stats_asof.itertuples(index=False)
    }

    # lookup exog dal df_all (una riga per giorno)
    df_day = df_all[df_all["data"].isin(dates)].sort_values(["data"]).drop_duplicates(["data"]).copy()
    df_day = df_day.set_index("data")

    # ========== 1) family total prediction (autoregressivo)
    fam_day_pred = []
    for d in dates:
        week_of_year = int(d.isocalendar().week)
        month_num = int(d.month)
        year_num = int(d.year)
        dow_pg = int((d.weekday() + 1) % 7)

        doy, doy_sin, doy_cos, dow_sin, dow_cos, is_weekend, is_month_start, is_month_end = calendar_feats(d, dow_pg)

        if d in df_day.index:
            r = df_day.loc[d]
            is_holiday = int(bool(r.get("is_holiday", 0)))
            tmin_c = r.get("tmin_c", np.nan)
            tmax_c = r.get("tmax_c", np.nan)
            tavg_c = r.get("tavg_c", np.nan)
            rain_mm = r.get("rain_mm", np.nan)
            sun_hours = r.get("sun_hours", np.nan)
        else:
            is_holiday = 0
            tmin_c = tmax_c = tavg_c = rain_mm = sun_hours = np.nan

        next_d = d + pd.Timedelta(days=1)
        prev_d = d - pd.Timedelta(days=1)
        next_is_holiday = int(bool(df_day.loc[next_d].get("is_holiday", 0))) if next_d in df_day.index else 0
        prev_is_holiday = int(bool(df_day.loc[prev_d].get("is_holiday", 0))) if prev_d in df_day.index else 0
        is_pre_holiday = next_is_holiday
        is_post_holiday = prev_is_holiday

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
                        # profiles
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

            for c in Xfam.columns:
                Xfam[c] = pd.to_numeric(Xfam[c], errors="coerce").fillna(median_fallback(fam_medians, c, 0.0))

            Xfam = Xfam[fam_cols]
            base = float(np.clip(fam_reg.predict(Xfam)[0], 0, None))

            fam_total = base if prior_mean is None else (alpha * base + (1 - alpha) * float(prior_mean))
            fam_total = max(0.0, float(fam_total))
        else:
            m_mean = float(hist_day_total.loc[hist_day_total["data"].dt.month == month_num, "qty_total"].mean())
            fam_total = 0.0 if np.isnan(m_mean) else max(0.0, m_mean)

        fam_day_pred.append({"data": d, "qty_total_pred": fam_total})
        fam_queue.append(float(fam_total))

    df_fam_pred = pd.DataFrame(fam_day_pred)

    # weekend rebalance
    if ENABLE_WEEKEND_REBALANCE:
        months_in_window = sorted(set(int(x.month) for x in dates))
        target_wk_share = compute_hist_weekend_share(hist_day_total, months_in_window)
        df_fam_pred = rebalance_weekend(df_fam_pred, target_wk_share, WEEKEND_REBALANCE_STRENGTH)

    # window anchor
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

        df_fam_pred = apply_microcap_and_warmup(
            df_fam_pred=df_fam_pred,
            dates=dates,
            expected_total=expected_total,
            n_years=n_years,
            season_stats=season_stats,
        )

    # ---- Apply beta AFTER all post-processing (recommended)
    if FAMILY_BETA_MODE in ("month", "global"):
        df_fam_pred["beta"] = pd.to_datetime(df_fam_pred["data"]).apply(get_beta_for_date).astype(float)
        df_fam_pred["qty_total_pred"] = (df_fam_pred["qty_total_pred"] * df_fam_pred["beta"]).clip(lower=0.0)
        df_fam_pred = df_fam_pred.drop(columns=["beta"])


    # ---- Final post-calibration scalar (after weekend+anchor+wampup)
    FAMILY_POST_SCALAR = float(os.getenv("V4_FAMILY_POST_SCALAR", "1.0"))
    if FAMILY_POST_SCALAR != 1.0:
        df_fam_pred["qty_total_pred"] = (df_fam_pred["qty_total_pred"] * FAMILY_POST_SCALAR).clip(lower=0.0)

    # ========== 2) fascia prediction + anchor to family total
    rows = []
    for d in dates:
        week_of_year = int(d.isocalendar().week)
        month_num = int(d.month)
        year_num = int(d.year)
        dow_pg = int((d.weekday() + 1) % 7)
        doy, doy_sin, doy_cos, dow_sin, dow_cos, is_weekend, is_month_start, is_month_end = calendar_feats(d, dow_pg)

        if d in df_day.index:
            r = df_day.loc[d]
            is_holiday = int(bool(r.get("is_holiday", 0)))
            tmin_c = r.get("tmin_c", np.nan)
            tmax_c = r.get("tmax_c", np.nan)
            tavg_c = r.get("tavg_c", np.nan)
            rain_mm = r.get("rain_mm", np.nan)
            sun_hours = r.get("sun_hours", np.nan)
        else:
            is_holiday = 0
            tmin_c = tmax_c = tavg_c = rain_mm = sun_hours = np.nan

        next_d = d + pd.Timedelta(days=1)
        prev_d = d - pd.Timedelta(days=1)
        next_is_holiday = int(bool(df_day.loc[next_d].get("is_holiday", 0))) if next_d in df_day.index else 0
        prev_is_holiday = int(bool(df_day.loc[prev_d].get("is_holiday", 0))) if prev_d in df_day.index else 0
        is_pre_holiday = next_is_holiday
        is_post_holiday = prev_is_holiday

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
            # HARD gate (as-of cutoff)
            st = stat_d_asof.get(str(fascia), None)
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
                        # profiles
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

            X = Xrow[f_cols]
            base = float(np.clip(f_reg.predict(X)[0], 0, None)) * wk_strength
            blended = base if prior_mean is None else (alpha * base + (1 - alpha) * float(prior_mean))
            blended = max(0.0, float(blended))
            blended *= soft_gate_multiplier(prior_pos_rate)

            tmp_preds.append((fascia, blended))

        # anchor to family total
        anchored = []
        for fascia, pred in tmp_preds:
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
            rows.append(
                {
                    "data": d,
                    "famiglia": famiglia,
                    "fascia_prezzo_iva_inc": fascia,
                    "qty_forecast": float(qty2),
                }
            )
            queues[fascia].append(float(qty2))

    return pd.DataFrame(rows)


# =========================
# MAIN BACKTEST
# =========================
def main():
    fam = os.getenv("ONLY_FAMILY")
    if not fam:
        raise RuntimeError("Imposta ONLY_FAMILY (es. export ONLY_FAMILY=phaelenopsis)")

    bp = bundle_path(fam)
    if not os.path.exists(bp):
        raise RuntimeError(f"Bundle mancante: {bp}")

    with open(bp, "rb") as f:
        bundle = pickle.load(f)

    engine = get_engine()
    get_strength = load_strength_getter(engine, fam)  # caricato una volta (veloce)

    df_all = load_family_all(engine, fam)
    if df_all.empty:
        raise RuntimeError("Dataset vuoto per famiglia")

    max_date = df_all["data"].max().normalize()
    min_date = df_all["data"].min().normalize()

    start_cut = (max_date - pd.Timedelta(days=BT_DAYS)).normalize()
    end_cut = (max_date - pd.Timedelta(days=HORIZON_DAYS)).normalize()

    cutoffs = pd.date_range(start=start_cut, end=end_cut, freq=f"{BT_STEP}D")
    cutoffs = [c for c in cutoffs if (c - min_date).days >= BT_MIN_HISTORY_DAYS]

    if not cutoffs:
        raise RuntimeError("Nessun cutoff valido (controlla BT_* e storico disponibile)")

    rows = []

    # ---- SKIP counters (debug)
    sk_pred_empty = 0
    sk_true_empty = 0
    sk_merge_empty = 0

    total_steps = len(cutoffs)
    for i, cutoff in enumerate(cutoffs, start=1):
        if i % 10 == 0:
            print(f"[BT] progress {i}/{total_steps} cutoff={cutoff.date()}")

        df_pred = predict_asof_cutoff(engine, fam, bundle, df_all, cutoff, get_strength)
        if df_pred.empty:
            sk_pred_empty += 1
            continue

        start_date = (cutoff + pd.Timedelta(days=1)).normalize()
        end_date = (start_date + pd.Timedelta(days=HORIZON_DAYS - 1)).normalize()

        df_true = df_all[(df_all["data"] >= start_date) & (df_all["data"] <= end_date)].copy()
        if df_true.empty:
            sk_true_empty += 1
            continue

        m = df_pred.merge(
            df_true[["data", "fascia_prezzo_iva_inc", TARGET_COL]],
            on=["data", "fascia_prezzo_iva_inc"],
            how="left",
        )
        m[TARGET_COL] = pd.to_numeric(m[TARGET_COL], errors="coerce").fillna(0.0).clip(lower=0.0)

        if m.empty:
            sk_merge_empty += 1
            continue

        m["cutoff"] = cutoff.normalize()
        m["h"] = (pd.to_datetime(m["data"]).dt.normalize() - cutoff.normalize()).dt.days.astype(int)

        # righe fascia
        for r in m.itertuples(index=False):
            rows.append(
                {
                    "cutoff": r.cutoff.date().isoformat(),
                    "data": pd.Timestamp(r.data).date().isoformat(),
                    "h": int(r.h),
                    "famiglia": fam,
                    "fascia_prezzo_iva_inc": str(r.fascia_prezzo_iva_inc),
                    "y_true": float(getattr(r, TARGET_COL)),
                    "y_pred": float(r.qty_forecast),
                    "kind": "fascia",
                }
            )

        # righe TOTAL (somma fasce vs somma true)
        by_day_pred = m.groupby("data")["qty_forecast"].sum().rename("y_pred_total").reset_index()
        by_day_true = df_true.groupby("data")[TARGET_COL].sum().rename("y_true_total").reset_index()
        mt = by_day_pred.merge(by_day_true, on="data", how="left").fillna(0.0)
        mt["cutoff"] = cutoff.normalize()
        mt["h"] = (pd.to_datetime(mt["data"]).dt.normalize() - cutoff.normalize()).dt.days.astype(int)

        for r in mt.itertuples(index=False):
            rows.append(
                {
                    "cutoff": r.cutoff.date().isoformat(),
                    "data": pd.Timestamp(r.data).date().isoformat(),
                    "h": int(r.h),
                    "famiglia": fam,
                    "fascia_prezzo_iva_inc": "__TOTAL__",
                    "y_true": float(r.y_true_total),
                    "y_pred": float(r.y_pred_total),
                    "kind": "total",
                }
            )

    engine.dispose()

    bt = pd.DataFrame(rows)
    if bt.empty:
        raise RuntimeError("Backtest vuoto: nessuna riga prodotta")

    bt_tot = bt[bt["kind"] == "total"].copy()
    bt_f = bt[bt["kind"] == "fascia"].copy()

    mae_t, rmse_t = evaluate(bt_tot["y_true"].values, bt_tot["y_pred"].values)
    mae_f, rmse_f = evaluate(bt_f["y_true"].values, bt_f["y_pred"].values)

    # by_h (TOTAL)
    def _group_metrics(g: pd.DataFrame) -> pd.Series:
        return pd.Series(
            {
                "n": int(len(g)),
                "mae": float(mean_absolute_error(g["y_true"], g["y_pred"])),
                "rmse": float(mean_squared_error(g["y_true"], g["y_pred"]) ** 0.5),
                "true_sum": float(g["y_true"].sum()),
                "pred_sum": float(g["y_pred"].sum()),
            }
        )

    by_h = (
        bt_tot.groupby("h")
        .apply(_group_metrics, include_groups=False)
        .reset_index()
        .sort_values("h")
        .reset_index(drop=True)
    )

    # by_fascia (FASCE)
    by_fascia = (
        bt_f.groupby("fascia_prezzo_iva_inc")
        .apply(_group_metrics, include_groups=False)
        .reset_index()
        .sort_values(["rmse", "mae"], ascending=[True, True])
        .reset_index(drop=True)
    )

    out_main = os.path.join(BASE_DIR, f"backtest_family_plus_fasce_{safe_slug(fam)}.csv")
    out_by_h = os.path.join(BASE_DIR, f"backtest_family_plus_fasce_{safe_slug(fam)}_by_h.csv")
    out_by_f = os.path.join(BASE_DIR, f"backtest_family_plus_fasce_{safe_slug(fam)}_by_fascia.csv")

    bt.to_csv(out_main, index=False)
    by_h.to_csv(out_by_h, index=False)
    by_fascia.to_csv(out_by_f, index=False)

    cutoffs_n = bt_tot["cutoff"].nunique()

    # info calibrazione attiva
    if FAMILY_BETA_MODE == "month":
        beta_info = f"month (fallback={FAMILY_BETA_FALLBACK:.4f}, months={sorted(_BETA_BY_MONTH.keys())})"
    else:
        beta_info = f"global ({FAMILY_TOTAL_BETA:.4f})"

    print("\n==============================")
    print(f"BACKTEST family+fasce | famiglia={fam}")
    print(f"cutoffs={cutoffs_n}  horizon={HORIZON_DAYS}  days={BT_DAYS}")
    print(f"[TOTAL]  MAE={mae_t:.4f}  RMSE={rmse_t:.4f}")
    print(f"[FASCE]  MAE={mae_f:.4f}  RMSE={rmse_f:.4f}")
    print(f"Family beta mode = {beta_info}")
    print(f"SKIPS: pred_empty={sk_pred_empty}  true_empty={sk_true_empty}  merge_empty={sk_merge_empty}")
    print("Saved:")
    print(f" - {out_main}")
    print(f" - {out_by_h}")
    print(f" - {out_by_f}")
    print("==============================\n")

    print(by_h.to_string(index=False))


if __name__ == "__main__":
    main()