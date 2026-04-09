# backtest_v4_family_total.py
# Backtest SOLO family total (no fasce) per 1 famiglia, usando bundle v4 (family_level)
# - rolling cutoff giornaliero
# - forecast autoregressivo per HORIZON giorni
# - meteo/holiday presi dallo storico (feature_table) per le date forecast

import os
import pickle
from datetime import timedelta

import numpy as np
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv
from sklearn.metrics import mean_absolute_error, mean_squared_error


# =========================
# CONFIG
# =========================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, ".env")
if os.path.exists(ENV_PATH):
    load_dotenv(ENV_PATH)

MODELS_DIR = os.path.join(BASE_DIR, "models_v4")
FEATURE_TABLE = "public.greenhouse_forecast_features_dense"

ONLY_FAMILY = os.getenv("ONLY_FAMILY", "phaelenopsis").strip().lower()

HORIZON_DAYS = int(os.getenv("V4_HORIZON_DAYS", "10"))

# Backtest window (quanti giorni indietro fare i cutoff)
BT_DAYS = int(os.getenv("BT_DAYS", "180"))

# In quanti giorni fare step (1 = ogni giorno)
BT_STEP = int(os.getenv("BT_STEP", "1"))

# Min history needed before we start a cutoff (safety)
MIN_HISTORY_DAYS = int(os.getenv("BT_MIN_HISTORY_DAYS", "365"))

# Profilo blend (stesse logiche del predict)
BLEND_ALPHA_MIN = float(os.getenv("V4_BLEND_ALPHA_MIN", "0.20"))
BLEND_ALPHA_MAX = float(os.getenv("V4_BLEND_ALPHA_MAX", "0.85"))


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


# =========================
# Utils
# =========================
def safe_slug(s: str) -> str:
    s = (s or "").strip().lower()
    s = s.replace("€", "eur").replace(" ", "_")
    return s

def bundle_path(famiglia: str) -> str:
    return os.path.join(MODELS_DIR, f"bundle_{safe_slug(famiglia)}_v4.pkl")

def median_fallback(medians: dict, col: str, default: float = 0.0) -> float:
    v = medians.get(col, default)
    try:
        v = float(v)
        if np.isnan(v):
            return float(default)
        return v
    except Exception:
        return float(default)

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

def pick_prior(dmrow, dwrow, doyrow, mrow, wrow):
    # stessa gerarchia usata in predict
    if dmrow.get("dm_n", 0) >= 20 and not pd.isna(dmrow.get("dm_avg", np.nan)):
        return float(dmrow["dm_avg"]), float(dmrow.get("dm_pos_rate", 0.0) or 0.0)
    if dwrow.get("dw_n", 0) >= 20 and not pd.isna(dwrow.get("dw_avg", np.nan)):
        return float(dwrow["dw_avg"]), float(dwrow.get("dw_pos_rate", 0.0) or 0.0)
    if doyrow.get("doy_n", 0) >= 10 and not pd.isna(doyrow.get("doy_avg", np.nan)):
        return float(doyrow["doy_avg"]), float(doyrow.get("doy_pos_rate", 0.0) or 0.0)
    if mrow.get("m_n", 0) >= 30 and not pd.isna(mrow.get("m_avg", np.nan)):
        return float(mrow["m_avg"]), float(mrow.get("m_pos_rate", 0.0) or 0.0)
    if wrow.get("w_n", 0) >= 30 and not pd.isna(wrow.get("w_avg", np.nan)):
        return float(wrow["w_avg"]), float(wrow.get("w_pos_rate", 0.0) or 0.0)
    return None, 0.0

def compute_alpha(pos_rate: float, ds: int) -> float:
    pr = max(0.0, min(1.0, float(pos_rate)))
    alpha = 0.35 + 0.50 * pr  # 0.35..0.85
    if ds >= 60:
        alpha *= 0.7
    if ds >= 180:
        alpha *= 0.4
    return max(BLEND_ALPHA_MIN, min(BLEND_ALPHA_MAX, alpha))


# =========================
# Load daily agg (storico)
# =========================
def load_family_daily_agg(engine, famiglia: str) -> pd.DataFrame:
    q = text(f"""
        SELECT
          data::date as data,
          lower(trim(famiglia)) as famiglia,
          SUM(qty_venduta)::numeric as qty_venduta,
          AVG(tmin_c) as tmin_c,
          AVG(tmax_c) as tmax_c,
          AVG(tavg_c) as tavg_c,
          AVG(rain_mm) as rain_mm,
          AVG(sun_hours) as sun_hours,
          MAX(is_holiday::int) as is_holiday,
          MAX(dow) as dow
        FROM {FEATURE_TABLE}
        WHERE lower(trim(famiglia)) = lower(:famiglia)
        GROUP BY 1,2
        ORDER BY 1;
    """)
    df = pd.read_sql(q, engine, params={"famiglia": famiglia})
    if df.empty:
        return df
    df["data"] = pd.to_datetime(df["data"])
    df["qty_venduta"] = pd.to_numeric(df["qty_venduta"], errors="coerce").fillna(0).clip(lower=0)
    for c in ["tmin_c","tmax_c","tavg_c","rain_mm","sun_hours"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df["is_holiday"] = pd.to_numeric(df["is_holiday"], errors="coerce").fillna(0).astype(int)
    df["dow"] = pd.to_numeric(df["dow"], errors="coerce").fillna(0).astype(int)
    return df


# =========================
# Forecast per 1 cutoff
# =========================
def forecast_from_cutoff(daily_df: pd.DataFrame, bundle: dict, cutoff_date: pd.Timestamp) -> pd.DataFrame:
    family_level = bundle.get("family_level")
    if family_level is None:
        raise RuntimeError("bundle non contiene family_level (set V4_TRAIN_FAMILY_LEVEL=1 e ri-traina)")

    fam_cols = family_level["feature_cols"]
    fam_medians = family_level["medians"]
    fam_reg = family_level["regressor"]
    fam_prof = family_level["profiles_full"]

    fam_dm = df_to_dict(fam_prof["dm"], ["__grp__", "dow", "month"])
    fam_dw = df_to_dict(fam_prof["dw"], ["__grp__", "dow", "week_of_year"])
    fam_doy = df_to_dict(fam_prof["doy"], ["__grp__", "doy"])
    fam_m = df_to_dict(fam_prof["m"], ["__grp__", "month"])
    fam_w = df_to_dict(fam_prof["w"], ["__grp__", "week_of_year"])

    # history <= cutoff
    hist = daily_df[daily_df["data"] <= cutoff_date].copy()
    if len(hist) < MIN_HISTORY_DAYS:
        return pd.DataFrame()

    # queue iniziale = storico reale fino al cutoff
    fam_queue = [float(x) for x in hist["qty_venduta"].tolist()]

    start_date = (cutoff_date + timedelta(days=1)).normalize()
    end_date = (start_date + timedelta(days=HORIZON_DAYS - 1)).normalize()
    dates = pd.date_range(start=start_date, end=end_date, freq="D")

    # pre/post holiday calcolati su is_holiday storico (daily_df)
    # per comodità: mappa per data
    daily_map = daily_df.set_index("data")

    out_rows = []

    for d in dates:
        if d not in daily_map.index:
            # se manca una data (buchi), skip quel giorno
            continue

        row_exo = daily_map.loc[d]

        week_of_year = int(d.isocalendar().week)
        month_num = int(d.month)
        year_num = int(d.year)
        dow_pg = int((d.weekday() + 1) % 7)  # 0=dom..6=sab

        doy, doy_sin, doy_cos, dow_sin, dow_cos, is_weekend, is_month_start, is_month_end = calendar_feats(d, dow_pg)

        is_holiday = int(row_exo["is_holiday"]) if not pd.isna(row_exo["is_holiday"]) else 0
        # pre/post usando daily_map (storico)
        next_d = d + timedelta(days=1)
        prev_d = d - timedelta(days=1)
        next_is_holiday = int(daily_map.loc[next_d]["is_holiday"]) if next_d in daily_map.index else 0
        prev_is_holiday = int(daily_map.loc[prev_d]["is_holiday"]) if prev_d in daily_map.index else 0
        is_pre_holiday = int(next_is_holiday)
        is_post_holiday = int(prev_is_holiday)

        tmin_c = row_exo.get("tmin_c", np.nan)
        tmax_c = row_exo.get("tmax_c", np.nan)
        tavg_c = row_exo.get("tavg_c", np.nan)
        rain_mm = row_exo.get("rain_mm", np.nan)
        sun_hours = row_exo.get("sun_hours", np.nan)

        fam_lm = compute_lags_ma(fam_queue)
        fam_zs, fam_ds = zero_feats_from_queue(fam_queue)

        fdm = fam_dm.get(("ALL", dow_pg, month_num), {})
        fdw = fam_dw.get(("ALL", dow_pg, week_of_year), {})
        fdoy = fam_doy.get(("ALL", doy), {})
        fm = fam_m.get(("ALL", month_num), {})
        fw = fam_w.get(("ALL", week_of_year), {})

        prior_mean, prior_pos_rate = pick_prior(fdm, fdw, fdoy, fm, fw)
        alpha = compute_alpha(prior_pos_rate, fam_ds)

        Xfam = pd.DataFrame([{
            "dow": dow_pg, "week_of_year": week_of_year, "month": month_num, "year": year_num,
            "doy_sin": doy_sin, "doy_cos": doy_cos, "dow_sin": dow_sin, "dow_cos": dow_cos,
            "is_weekend": is_weekend, "is_month_start": is_month_start, "is_month_end": is_month_end,
            "is_holiday": int(is_holiday),
            "is_pre_holiday": int(is_pre_holiday),
            "is_post_holiday": int(is_post_holiday),
            "tmin_c": tmin_c, "tmax_c": tmax_c, "tavg_c": tavg_c, "rain_mm": rain_mm, "sun_hours": sun_hours,
            **fam_lm,
            "is_zero_lag1": int((fam_lm["qty_lag_1"] if not np.isnan(fam_lm["qty_lag_1"]) else 0.0) <= 0.0),
            "is_zero_ma7": int((fam_lm["qty_ma_7"] if not np.isnan(fam_lm["qty_ma_7"]) else 0.0) <= 0.0),
            "zero_streak": fam_zs,
            "days_since_last_sale": fam_ds,
            # profiles
            "dm_avg": fdm.get("dm_avg", np.nan), "dm_p50": fdm.get("dm_p50", np.nan),
            "dm_n": fdm.get("dm_n", 0), "dm_pos_rate": fdm.get("dm_pos_rate", np.nan),
            "dw_avg": fdw.get("dw_avg", np.nan), "dw_p50": fdw.get("dw_p50", np.nan),
            "dw_n": fdw.get("dw_n", 0), "dw_pos_rate": fdw.get("dw_pos_rate", np.nan),
            "doy_avg": fdoy.get("doy_avg", np.nan), "doy_p50": fdoy.get("doy_p50", np.nan),
            "doy_n": fdoy.get("doy_n", 0), "doy_pos_rate": fdoy.get("doy_pos_rate", np.nan),
            "m_avg": fm.get("m_avg", np.nan), "m_p50": fm.get("m_p50", np.nan),
            "m_n": fm.get("m_n", 0), "m_pos_rate": fm.get("m_pos_rate", np.nan),
            "w_avg": fw.get("w_avg", np.nan), "w_p50": fw.get("w_p50", np.nan),
            "w_n": fw.get("w_n", 0), "w_pos_rate": fw.get("w_pos_rate", np.nan),
            "prior_mean": prior_mean if prior_mean is not None else np.nan,
            "prior_pos_rate": prior_pos_rate,
            "prior_n": 0,
        }])

        # fill medians
        for c in Xfam.columns:
            Xfam[c] = pd.to_numeric(Xfam[c], errors="coerce").fillna(median_fallback(fam_medians, c, 0.0))

        Xfam = Xfam[fam_cols]
        base = float(np.clip(fam_reg.predict(Xfam)[0], 0, None))
        if prior_mean is None:
            pred = base
        else:
            pred = alpha * base + (1 - alpha) * float(prior_mean)
        pred = max(0.0, float(pred))

        # autoregressive update
        fam_queue.append(pred)

        # actual available (storico)
        y_true = float(row_exo["qty_venduta"]) if not pd.isna(row_exo["qty_venduta"]) else np.nan

        out_rows.append({
            "cutoff_date": cutoff_date.date().isoformat(),
            "date": d.date().isoformat(),
            "h": int((d - start_date).days) + 1,
            "y_true": y_true,
            "y_pred": pred,
        })

    return pd.DataFrame(out_rows)


# =========================
# MAIN
# =========================
def main():
    famiglia = ONLY_FAMILY
    bp = bundle_path(famiglia)
    if not os.path.exists(bp):
        raise RuntimeError(f"Bundle non trovato: {bp} (prima fai train e genera bundle)")

    with open(bp, "rb") as f:
        bundle = pickle.load(f)

    engine = get_engine()
    daily = load_family_daily_agg(engine, famiglia)
    engine.dispose()

    if daily.empty:
        raise RuntimeError("Storico daily vuoto per la famiglia.")

    daily = daily.sort_values("data").reset_index(drop=True)

    max_date = daily["data"].max().normalize()
    start_cutoff = (max_date - timedelta(days=BT_DAYS)).normalize()

    cutoffs = pd.date_range(start=start_cutoff, end=(max_date - timedelta(days=HORIZON_DAYS)), freq=f"{BT_STEP}D")

    all_bt = []
    for i, c in enumerate(cutoffs, 1):
        df_one = forecast_from_cutoff(daily, bundle, c)
        if df_one is not None and not df_one.empty:
            all_bt.append(df_one)

        if i % 10 == 0:
            print(f"[BT] progress {i}/{len(cutoffs)} cutoff={c.date().isoformat()}")

    bt = pd.concat(all_bt, ignore_index=True) if all_bt else pd.DataFrame()
    if bt.empty:
        print("Backtest vuoto (forse pochi dati o MIN_HISTORY troppo alto).")
        return

    # metriche globali (su tutte le righe)
    y_true = bt["y_true"].astype(float).values
    y_pred = bt["y_pred"].astype(float).values

    mae = mean_absolute_error(y_true, y_pred)
    rmse = mean_squared_error(y_true, y_pred) ** 0.5

    # metriche per orizzonte h
    by_h = bt.groupby("h").apply(
        lambda g: pd.Series({
            "n": int(len(g)),
            "mae": float(mean_absolute_error(g["y_true"], g["y_pred"])),
            "rmse": float(mean_squared_error(g["y_true"], g["y_pred"]) ** 0.5),
            "true_sum": float(g["y_true"].sum()),
            "pred_sum": float(g["y_pred"].sum()),
        })
    ).reset_index()

    # salva risultati
    out_csv = os.path.join(BASE_DIR, f"backtest_family_total_{safe_slug(famiglia)}.csv")
    out_h_csv = os.path.join(BASE_DIR, f"backtest_family_total_{safe_slug(famiglia)}_by_h.csv")
    bt.to_csv(out_csv, index=False)
    by_h.to_csv(out_h_csv, index=False)

    print("\n==============================")
    print(f"BACKTEST family total | famiglia={famiglia}")
    print(f"cutoffs={len(cutoffs)}  rows={len(bt)}  horizon={HORIZON_DAYS}  days={BT_DAYS}")
    print(f"MAE={mae:.4f}  RMSE={rmse:.4f}")
    print(f"Saved:\n - {out_csv}\n - {out_h_csv}")
    print("==============================\n")

    # preview by_h
    print(by_h.head(10).to_string(index=False))


if __name__ == "__main__":
    main()