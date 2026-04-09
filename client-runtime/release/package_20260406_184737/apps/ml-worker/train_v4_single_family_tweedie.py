# train_v4_single_family_tweedie.py  (SINGLE FAMILY - v4.2)
#
# Stessa logica di train_v4_20families_tweedie.py ma:
# - una sola famiglia (default: phaelenopsis)
# - CLI arg --family / env ONLY_FAMILY
# - salva un solo bundle

import os
import pickle
import warnings
from datetime import timedelta
import argparse

import sqlalchemy as sa
from sqlalchemy.engine import URL

import numpy as np
import pandas as pd
import lightgbm as lgb
from lightgbm import LGBMClassifier
from sklearn.isotonic import IsotonicRegression
from sklearn.metrics import log_loss, brier_score_loss
from sklearn.metrics import mean_absolute_error, mean_squared_error
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

from data_access_v1 import load_family_df_parquet_or_db
from jobs.family_resolver import resolve_family_and_slug


warnings.filterwarnings("ignore", message="Mean of empty slice")

# =========================
# CONFIG
# =========================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, ".env")
if os.path.exists(ENV_PATH):
    load_dotenv(ENV_PATH)

VALID_DAYS = int(os.getenv("V4_VALID_DAYS", "30"))
MIN_TRAIN_ROWS = int(os.getenv("V4_MIN_TRAIN_ROWS", "500"))

POWER_GRID = os.getenv("V4_TWEEDIE_POWER_GRID", "1.1,1.2,1.3,1.4,1.5,1.6,1.7").split(",")
POWER_GRID = [float(x.strip()) for x in POWER_GRID if x.strip()]

MODELS_DIR = os.getenv("GH_MODELS_DIR", os.path.join(BASE_DIR, "models_v4"))
os.makedirs(MODELS_DIR, exist_ok=True)

FEATURE_TABLE = "public.greenhouse_forecast_features_dense"
TARGET_COL = "qty_venduta"

MIN_DATE = os.getenv("V4_MIN_DATE", "2009-01-01")
TRAIN_FAMILY_LEVEL = os.getenv("V4_TRAIN_FAMILY_LEVEL", "1") == "1"

# training speed/stability
LGBM_LEARNING_RATE = float(os.getenv("V4_LGBM_LR", "0.03"))
LGBM_MAX_ESTIMATORS = int(os.getenv("V4_LGBM_ESTIMATORS", "6000"))
LGBM_EARLY_STOP = int(os.getenv("V4_LGBM_EARLY_STOP", "200"))
LGBM_NUM_LEAVES = int(os.getenv("V4_LGBM_NUM_LEAVES", "63"))


# =========================
# DB
# =========================

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
    ang = 2.0 * np.pi * (doy / 366.0)
    df = df.copy()
    df["doy_sin"] = np.sin(ang)
    df["doy_cos"] = np.cos(ang)
    df["week_of_year"] = d.dt.isocalendar().week.astype(int)
    df["month"] = d.dt.month.astype(int)
    return df


def get_engine():
    import os
    from jobs.common import load_env; load_env()

    need = ["PG_HOST","PG_PORT","PG_DB","PG_USER","PG_PASSWORD"]
    missing = [k for k in need if not os.getenv(k)]
    if missing:
        raise RuntimeError(f"Variabili PG_* mancanti nel .env: {missing}")

    sslmode = os.getenv("PG_SSLMODE", "require")

    url = URL.create(
        drivername="postgresql+psycopg",
        username=os.getenv("PG_USER"),
        password=os.getenv("PG_PASSWORD"),
        host=os.getenv("PG_HOST"),
        port=int(os.getenv("PG_PORT","5432")),
        database=os.getenv("PG_DB","postgres"),
        query={"sslmode": sslmode},
    )
    return sa.create_engine(url, pool_pre_ping=True)


# =========================
# HELPERS
# =========================
def safe_slug(s: str) -> str:
    s = (s or "").strip().lower()
    s = s.replace("€", "eur").replace(" ", "-")
    return s

def bundle_path_for_family(famiglia_slug: str) -> str:
    s = (famiglia_slug or "").strip().lower()
    return os.path.join(MODELS_DIR, f"bundle_{s}_v4.pkl")

def evaluate(y_true, y_pred, label="valid"):
    mae = mean_absolute_error(y_true, y_pred)
    rmse = mean_squared_error(y_true, y_pred) ** 0.5
    print(f"{label} MAE : {mae:.4f}")
    print(f"{label} RMSE: {rmse:.4f}")
    return mae, rmse

def safe_fillna_by_median(train_df: pd.DataFrame, valid_df: pd.DataFrame, cols):
    train_df = train_df.copy()
    valid_df = valid_df.copy()
    medians = {}
    for c in cols:
        med = pd.to_numeric(train_df[c], errors="coerce").median()
        medians[c] = float(med) if pd.notna(med) else 0.0
        train_df[c] = pd.to_numeric(train_df[c], errors="coerce").fillna(medians[c])
        valid_df[c] = pd.to_numeric(valid_df[c], errors="coerce").fillna(medians[c])
    return train_df, valid_df, medians

# =========================
# FEATURE ENGINEERING
# =========================
def add_calendar(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["data"] = pd.to_datetime(df["data"])
    df["doy"] = df["data"].dt.dayofyear.astype(int)
    df["week_of_year"] = df["data"].dt.isocalendar().week.astype(int)
    df["year"] = df["data"].dt.year.astype(int)
    df["month"] = df["data"].dt.month.astype(int)

    df["doy_sin"] = np.sin(2 * np.pi * df["doy"] / 365.0)
    df["doy_cos"] = np.cos(2 * np.pi * df["doy"] / 365.0)
    df["dow_sin"] = np.sin(2 * np.pi * df["dow"] / 7.0)
    df["dow_cos"] = np.cos(2 * np.pi * df["dow"] / 7.0)

    df["is_weekend"] = df["dow"].isin([0, 6]).astype(int)  # 0=dom,6=sab
    df["is_month_start"] = (df["data"].dt.day <= 3).astype(int)
    df["is_month_end"] = (df["data"].dt.day >= 28).astype(int)
    return df

def add_holiday_neighborhood(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    tmp = df[["data", "is_holiday"]].drop_duplicates("data").sort_values("data")
    tmp["is_holiday"] = tmp["is_holiday"].astype(int)
    tmp["is_pre_holiday"] = tmp["is_holiday"].shift(-1).fillna(0).astype(int)
    tmp["is_post_holiday"] = tmp["is_holiday"].shift(1).fillna(0).astype(int)
    df = df.merge(tmp[["data", "is_pre_holiday", "is_post_holiday"]], on="data", how="left")
    df["is_pre_holiday"] = df["is_pre_holiday"].fillna(0).astype(int)
    df["is_post_holiday"] = df["is_post_holiday"].fillna(0).astype(int)
    return df

def add_zero_inflation_features_by_group(df: pd.DataFrame, group_cols: list[str]) -> pd.DataFrame:
    df = df.sort_values(group_cols + ["data"]).copy()
    df["is_zero_lag1"] = (df["qty_lag_1"].fillna(0) <= 0).astype(int)
    df["is_zero_ma7"] = (df["qty_ma_7"].fillna(0) <= 0).astype(int)

    zero_streak = []
    days_since = []

    if group_cols:
        groups = df.groupby(group_cols, sort=False)
    else:
        groups = [(None, df)]

    for _, g in groups:
        zs = 0
        last_sale_date = None
        for r in g.itertuples(index=False):
            qty = getattr(r, TARGET_COL)
            d = getattr(r, "data")
            if qty > 0:
                zs = 0
                last_sale_date = d
            else:
                zs += 1
            zero_streak.append(zs)
            if last_sale_date is None:
                days_since.append(9999)
            else:
                days_since.append(int((d - last_sale_date).days))

    df["zero_streak"] = pd.Series(zero_streak, index=df.index).clip(0, 365)
    df["days_since_last_sale"] = pd.Series(days_since, index=df.index).clip(0, 365)
    return df

def build_profiles_full(train_df: pd.DataFrame, group_key: str) -> dict:
    t = train_df.copy()

    if group_key == "ALL":
        t["__grp__"] = "ALL"
        gcol = "__grp__"
    else:
        gcol = group_key

    def agg_block(g, prefix: str, add_p50: bool = True):
        base = g.agg(
            **{
                f"{prefix}_avg": "mean",
                f"{prefix}_n": "count",
                f"{prefix}_pos_rate": lambda s: float((np.array(s.values) > 0).mean()) if len(s.values) else 0.0,
            }
        )
        if add_p50:
            p50 = g.apply(lambda s: float(np.nanmedian(s.values)) if len(s.values) else np.nan)
            p50.name = f"{prefix}_p50"
            out = base.join(p50)
        else:
            out = base
        return out.reset_index()

    dm = agg_block(t.groupby([gcol, "dow", "month"])[TARGET_COL], "dm", add_p50=True)
    dw = agg_block(t.groupby([gcol, "dow", "week_of_year"])[TARGET_COL], "dw", add_p50=True)
    doy = agg_block(t.groupby([gcol, "doy"])[TARGET_COL], "doy", add_p50=True)
    m = agg_block(t.groupby([gcol, "month"])[TARGET_COL], "m", add_p50=True)
    w = agg_block(t.groupby([gcol, "week_of_year"])[TARGET_COL], "w", add_p50=True)
    return {"dm": dm, "dw": dw, "doy": doy, "m": m, "w": w, "group_key": group_key}

def merge_profiles_full(df: pd.DataFrame, prof: dict) -> pd.DataFrame:
    df = df.copy()
    if prof["group_key"] == "ALL":
        df["__grp__"] = "ALL"
        gcol = "__grp__"
    else:
        gcol = prof["group_key"]

    df = df.merge(prof["dm"], on=[gcol, "dow", "month"], how="left")
    df = df.merge(prof["dw"], on=[gcol, "dow", "week_of_year"], how="left")
    df = df.merge(prof["doy"], on=[gcol, "doy"], how="left")
    df = df.merge(prof["m"], on=[gcol, "month"], how="left")
    df = df.merge(prof["w"], on=[gcol, "week_of_year"], how="left")
    return df

def add_profile_priors(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()

    def pick_prior_row(r):
        if pd.notna(r.get("dm_avg", np.nan)) and r.get("dm_n", 0) >= 20:
            return r["dm_avg"], r.get("dm_pos_rate", np.nan), r.get("dm_n", 0)
        if pd.notna(r.get("dw_avg", np.nan)) and r.get("dw_n", 0) >= 20:
            return r["dw_avg"], r.get("dw_pos_rate", np.nan), r.get("dw_n", 0)
        if pd.notna(r.get("doy_avg", np.nan)) and r.get("doy_n", 0) >= 10:
            return r["doy_avg"], r.get("doy_pos_rate", np.nan), r.get("doy_n", 0)
        if pd.notna(r.get("m_avg", np.nan)) and r.get("m_n", 0) >= 30:
            return r["m_avg"], r.get("m_pos_rate", np.nan), r.get("m_n", 0)
        if pd.notna(r.get("w_avg", np.nan)) and r.get("w_n", 0) >= 30:
            return r["w_avg"], r.get("w_pos_rate", np.nan), r.get("w_n", 0)
        return np.nan, np.nan, 0

    pri = df.apply(pick_prior_row, axis=1, result_type="expand")
    df["prior_mean"] = pri[0]
    df["prior_pos_rate"] = pri[1]
    df["prior_n"] = pri[2]
    return df

def compute_season_start_stats(df_daily: pd.DataFrame, qty_col: str = "qty_venduta", min_pos_qty: float = 0.001) -> dict:
    d = df_daily.copy()
    d["data"] = pd.to_datetime(d["data"])
    d["year"] = d["data"].dt.year.astype(int)
    d["doy"] = d["data"].dt.dayofyear.astype(int)
    d[qty_col] = pd.to_numeric(d[qty_col], errors="coerce").fillna(0).clip(lower=0)

    pos = d[d[qty_col] > float(min_pos_qty)].copy()
    if pos.empty:
        return {"season_start_p25": None, "season_start_p50": None, "season_start_p75": None, "n_years_season": 0}

    first_by_year = pos.groupby("year")["doy"].min()
    vals = first_by_year.values.astype(float)
    if len(vals) == 0:
        return {"season_start_p25": None, "season_start_p50": None, "season_start_p75": None, "n_years_season": 0}

    return {
        "season_start_p25": float(np.percentile(vals, 25)),
        "season_start_p50": float(np.percentile(vals, 50)),
        "season_start_p75": float(np.percentile(vals, 75)),
        "n_years_season": int(len(vals)),
    }

# =========================
# LOAD DATA
# =========================
def load_family_df(engine, famiglia: str, famiglia_slug: str | None = None) -> pd.DataFrame:
    return load_family_df_parquet_or_db(
        engine,
        famiglia=famiglia,
        famiglia_slug=famiglia_slug,
        min_date=MIN_DATE,
        feature_table=FEATURE_TABLE,
    )

def train_one_family_fascia(engine, famiglia: str, famiglia_slug: str | None = None) -> dict | None:
    print("\n==============================")
    print(f"🚀 TRAIN V4.2 Tweedie | fascia-level | famiglia: {famiglia}")
    print("==============================")

    df = load_family_df(engine, famiglia)
    if df.empty:
        print("⚠️ Nessuna riga: skip.")
        return None

    df["data"] = pd.to_datetime(df["data"])
    df[TARGET_COL] = pd.to_numeric(df[TARGET_COL], errors="coerce").fillna(0).clip(lower=0)

    df = add_calendar(df)
    df = add_holiday_neighborhood(df)
    df = add_zero_inflation_features_by_group(df, ["fascia_prezzo_iva_inc"])

    max_date = df["data"].max()
    cutoff_valid = max_date - timedelta(days=VALID_DAYS)
    train_df = df[df["data"] < cutoff_valid].copy()
    valid_df = df[df["data"] >= cutoff_valid].copy()

    print(f"✅ Righe tot: {len(df)}  train: {len(train_df)}  valid: {len(valid_df)}")
    print(f"   range: {df['data'].min().date()} → {df['data'].max().date()}")

    if len(train_df) < MIN_TRAIN_ROWS:
        print("⚠️ Troppo poco training: skip.")
        return None

    prof = build_profiles_full(train_df, "fascia_prezzo_iva_inc")
    train_df = merge_profiles_full(train_df, prof)
    valid_df = merge_profiles_full(valid_df, prof)
    train_df = add_profile_priors(train_df)
    valid_df = add_profile_priors(valid_df)

    fasce = sorted(train_df["fascia_prezzo_iva_inc"].dropna().unique().tolist())
    if not fasce:
        print("⚠️ Nessuna fascia nel train: skip.")
        return None

    fascia_map = {v: i for i, v in enumerate(fasce)}
    train_df["fascia_enc"] = train_df["fascia_prezzo_iva_inc"].map(fascia_map).fillna(-1).astype(int)
    valid_df["fascia_enc"] = valid_df["fascia_prezzo_iva_inc"].map(fascia_map).fillna(-1).astype(int)

    feature_cols = [
        "fascia_enc",
        "dow", "week_of_year", "month", "year",
        "doy_sin", "doy_cos", "dow_sin", "dow_cos",
        "is_weekend", "is_month_start", "is_month_end",
        "is_holiday", "is_pre_holiday", "is_post_holiday",
        "tmin_c", "tmax_c", "tavg_c", "rain_mm", "sun_hours",
        "qty_lag_1", "qty_lag_2", "qty_lag_3", "qty_lag_7", "qty_lag_10", "qty_lag_14",
        "qty_ma_3", "qty_ma_7", "qty_ma_10", "qty_ma_14", "qty_ma_28",
        "is_zero_lag1", "is_zero_ma7", "zero_streak", "days_since_last_sale",
        "dm_avg", "dm_p50", "dm_n", "dm_pos_rate",
        "dw_avg", "dw_p50", "dw_n", "dw_pos_rate",
        "doy_avg", "doy_p50", "doy_n", "doy_pos_rate",
        "m_avg", "m_p50", "m_n", "m_pos_rate",
        "w_avg", "w_p50", "w_n", "w_pos_rate",
        "prior_mean", "prior_pos_rate", "prior_n",
    ]


    # --- M1: ensure seasonality columns in feature_cols ---

    for _c in ("doy_sin","doy_cos","week_of_year","month"):

        if _c not in feature_cols:

            feature_cols.append(_c)

    numeric_cols = [c for c in feature_cols if c != "fascia_enc"]
    train_df, valid_df, medians = safe_fillna_by_median(train_df, valid_df, numeric_cols)

    # --- season features for TRAIN (M1) ---

    try:

        train_df = add_season_features(train_df, 'data')

        valid_df = add_season_features(valid_df, 'data')

    except Exception:

        pass


    X_train = train_df[feature_cols]
    y_train = train_df[TARGET_COL].values
    X_valid = valid_df[feature_cols]
    y_valid = valid_df[TARGET_COL].values

    hist_stats = df.groupby("fascia_prezzo_iva_inc").agg(
        sum_all=("qty_venduta", "sum"),
        pos_days_all=("qty_venduta", lambda s: int((s > 0).sum())),
        n_days_all=("qty_venduta", "count"),
    ).reset_index()
    hist_stats["pos_rate_all"] = np.where(hist_stats["n_days_all"] > 0,
                                          hist_stats["pos_days_all"] / hist_stats["n_days_all"], 0.0)

    best = None
    best_rmse = 1e18
    best_mae = None

    for pwr in POWER_GRID:
        print(f"\n🔎 Tweedie power={pwr}")
        model = lgb.LGBMRegressor(
            objective="tweedie",
            tweedie_variance_power=pwr,
            learning_rate=LGBM_LEARNING_RATE,
            n_estimators=LGBM_MAX_ESTIMATORS,
            num_leaves=LGBM_NUM_LEAVES,
            subsample=0.8,
            colsample_bytree=0.8,
            min_child_samples=25,
            reg_lambda=1.0,
            random_state=42,
            n_jobs=1,
            force_row_wise=True,
        )

        model.fit(
            X_train, y_train,
            eval_set=[(X_valid, y_valid)],
            eval_metric="rmse",
            callbacks=[lgb.early_stopping(stopping_rounds=LGBM_EARLY_STOP, verbose=False)],
        )

        y_hat = np.clip(model.predict(X_valid), 0, None)
        mae, rmse = evaluate(y_valid, y_hat, label=f"valid (power={pwr})")
        if rmse < best_rmse:
            best_rmse = rmse
            best_mae = mae
            best = (pwr, model)

    best_power, best_model = best
    # =========================
    # HURDLE: classifier p(y>0)
    # =========================
    y_train_bin = (train_df[TARGET_COL].values > 0).astype(int)
    y_valid_bin = (valid_df[TARGET_COL].values > 0).astype(int)

    clf_pos = LGBMClassifier(
        objective="binary",
        learning_rate=0.05,
        n_estimators=3000,
        num_leaves=63,
        subsample=0.8,
        colsample_bytree=0.8,
        min_child_samples=25,
        reg_lambda=1.0,
        random_state=42,
        n_jobs=1,
        force_row_wise=True,
    )

    clf_pos.fit(
        X_train, y_train_bin,
        eval_set=[(X_valid, y_valid_bin)],
        eval_metric="binary_logloss",
        callbacks=[lgb.early_stopping(stopping_rounds=LGBM_EARLY_STOP, verbose=False)],
    )

    # --- HURDLE calibration on VALID (isotonic) ---
    try:
        p_valid_raw = clf_pos.predict_proba(X_valid)[:, 1]
        yv = y_valid_bin.astype(int)

        # raw metrics
        ll_raw = log_loss(yv, p_valid_raw, labels=[0,1])
        br_raw = brier_score_loss(yv, p_valid_raw)

        iso = IsotonicRegression(out_of_bounds="clip")
        iso.fit(p_valid_raw, yv)
        p_valid_cal = iso.predict(p_valid_raw)

        ll_cal = log_loss(yv, p_valid_cal, labels=[0,1])
        br_cal = brier_score_loss(yv, p_valid_cal)

        print(f"📏 HURDLE valid calib | logloss raw={ll_raw:.5f} cal={ll_cal:.5f} | brier raw={br_raw:.5f} cal={br_cal:.5f}", flush=True)
    except Exception as e:
        iso = None
        p_valid_raw = None
        print(f"⚠️ calib failed: {e}", flush=True)

    print(f"\n🏆 BEST power={best_power}  RMSE={best_rmse:.4f}  MAE={best_mae:.4f}")

    return {
"feature_cols": feature_cols,
        "medians": medians,
        "fascia_map": fascia_map,
        "profiles_full": prof,
        "hist_stats_full": hist_stats,
        "tweedie_power": float(best_power),
        "regressor": best_model,
        
        'clf_pos': clf_pos,
        'clf_pos_cal': iso,
        'pos_valid_y': (yv.tolist() if 'yv' in locals() and yv is not None else None),
        'pos_valid_p_raw': (p_valid_raw.tolist() if 'p_valid_raw' in locals() and p_valid_raw is not None else None),
        'clf_pos_cal': iso,
        'pos_valid_y': (yv.tolist() if 'yv' in locals() and yv is not None else None),
        'pos_valid_p_raw': (p_valid_raw.tolist() if 'p_valid_raw' in locals() and p_valid_raw is not None else None),"valid_days": VALID_DAYS,
        "model_version": "v4_2_tweedie_fascia_fullhistory_gatingready",
        "trained_at": pd.Timestamp.utcnow().isoformat(),
        "train_max_date": df["data"].max().date().isoformat(),
        "valid_rmse_best": float(best_rmse),
        "valid_mae_best": float(best_mae),
    }
# =========================
# FAMILY LEVEL TRAIN (same as your v4.2)
# =========================
def load_family_daily_agg(engine, famiglia: str) -> pd.DataFrame:
    q = text(f"""
        SELECT
          data,
          LOWER(famiglia) as famiglia,
          SUM(qty_venduta)::numeric as qty_venduta,
          AVG(tmin_c) as tmin_c,
          AVG(tmax_c) as tmax_c,
          AVG(tavg_c) as tavg_c,
          AVG(rain_mm) as rain_mm,
          AVG(sun_hours) as sun_hours,
          MAX(is_holiday::int) as is_holiday,
          MAX(dow) as dow
        FROM {FEATURE_TABLE}
        WHERE LOWER(famiglia)=LOWER(:famiglia)
          AND data >= :min_date
        GROUP BY 1,2
        ORDER BY 1;
    """)
    return pd.read_sql(q, engine, params={"famiglia": famiglia, "min_date": MIN_DATE})

def add_lags_ma_to_daily(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["data"] = pd.to_datetime(df["data"])
    df = df.sort_values("data")
    y = pd.to_numeric(df["qty_venduta"], errors="coerce").fillna(0.0).clip(lower=0)

    # lags
    df["qty_lag_1"]  = y.shift(1)
    df["qty_lag_2"]  = y.shift(2)
    df["qty_lag_3"]  = y.shift(3)
    df["qty_lag_7"]  = y.shift(7)
    df["qty_lag_10"] = y.shift(10)
    df["qty_lag_14"] = y.shift(14)

    # moving averages
    df["qty_ma_3"]  = y.rolling(3,  min_periods=1).mean()
    df["qty_ma_7"]  = y.rolling(7,  min_periods=1).mean()
    df["qty_ma_10"] = y.rolling(10, min_periods=1).mean()
    df["qty_ma_14"] = y.rolling(14, min_periods=1).mean()
    df["qty_ma_28"] = y.rolling(28, min_periods=1).mean()

    return df


def train_one_family_daily(engine, famiglia: str, famiglia_slug: str | None = None) -> dict | None:
    print("\n==============================")
    print(f"🚀 TRAIN V4.2 Tweedie | family-level | famiglia: {famiglia}")
    print("==============================")

    df = load_family_daily_agg(engine, famiglia)
    if df.empty:
        print("⚠️ Nessuna riga: skip.")
        return None

    df["data"] = pd.to_datetime(df["data"])
    df[TARGET_COL] = pd.to_numeric(df[TARGET_COL], errors="coerce").fillna(0).clip(lower=0)
    season_stats = compute_season_start_stats(df, qty_col=TARGET_COL, min_pos_qty=0.001)

    df = add_lags_ma_to_daily(df)
    df = add_calendar(df)
    df = add_holiday_neighborhood(df)
    df = add_zero_inflation_features_by_group(df, [])

    max_date = df["data"].max()
    cutoff_valid = max_date - timedelta(days=VALID_DAYS)
    train_df = df[df["data"] < cutoff_valid].copy()
    valid_df = df[df["data"] >= cutoff_valid].copy()

    print(f"✅ Righe tot: {len(df)}  train: {len(train_df)}  valid: {len(valid_df)}")
    print(f"   range: {df['data'].min().date()} → {df['data'].max().date()}")

    if len(train_df) < MIN_TRAIN_ROWS:
        print("⚠️ Troppo poco training: skip.")
        return None

    prof = build_profiles_full(train_df, "ALL")
    train_df = merge_profiles_full(train_df, prof)
    valid_df = merge_profiles_full(valid_df, prof)
    train_df = add_profile_priors(train_df)
    valid_df = add_profile_priors(valid_df)

    feature_cols = [
        "dow", "week_of_year", "month", "year",
        "doy_sin", "doy_cos", "dow_sin", "dow_cos",
        "is_weekend", "is_month_start", "is_month_end",
        "is_holiday", "is_pre_holiday", "is_post_holiday",
        "tmin_c", "tmax_c", "tavg_c", "rain_mm", "sun_hours",
        "qty_lag_1", "qty_lag_2", "qty_lag_3", "qty_lag_7", "qty_lag_10", "qty_lag_14",
        "qty_ma_3", "qty_ma_7", "qty_ma_10", "qty_ma_14", "qty_ma_28",
        "is_zero_lag1", "is_zero_ma7", "zero_streak", "days_since_last_sale",
        "dm_avg", "dm_p50", "dm_n", "dm_pos_rate",
        "dw_avg", "dw_p50", "dw_n", "dw_pos_rate",
        "doy_avg", "doy_p50", "doy_n", "doy_pos_rate",
        "m_avg", "m_p50", "m_n", "m_pos_rate",
        "w_avg", "w_p50", "w_n", "w_pos_rate",
        "prior_mean", "prior_pos_rate", "prior_n",
    ]

    train_df, valid_df, medians = safe_fillna_by_median(train_df, valid_df, feature_cols)

    # --- season features for TRAIN (M1) ---

    try:

        train_df = add_season_features(train_df, 'data')

        valid_df = add_season_features(valid_df, 'data')

    except Exception:

        pass


    X_train = train_df[feature_cols]
    y_train = train_df[TARGET_COL].values
    X_valid = valid_df[feature_cols]
    y_valid = valid_df[TARGET_COL].values

    full_stats = {
        "sum_all": float(df[TARGET_COL].sum()),
        "pos_days_all": int((df[TARGET_COL] > 0).sum()),
        "n_days_all": int(len(df)),
        "pos_rate_all": float((df[TARGET_COL] > 0).mean()) if len(df) else 0.0,
    }

    best = None
    best_rmse = 1e18
    best_mae = None

    for pwr in POWER_GRID:
        print(f"\n🔎 Tweedie power={pwr}")
        model = lgb.LGBMRegressor(
            objective="tweedie",
            tweedie_variance_power=pwr,
            learning_rate=LGBM_LEARNING_RATE,
            n_estimators=LGBM_MAX_ESTIMATORS,
            num_leaves=LGBM_NUM_LEAVES,
            subsample=0.8,
            colsample_bytree=0.8,
            min_child_samples=25,
            reg_lambda=1.0,
            random_state=42,
            n_jobs=1,
            force_row_wise=True,
        )

        model.fit(
            X_train, y_train,
            eval_set=[(X_valid, y_valid)],
            eval_metric="rmse",
            callbacks=[lgb.early_stopping(stopping_rounds=LGBM_EARLY_STOP, verbose=False)],
        )

        y_hat = np.clip(model.predict(X_valid), 0, None)
        mae, rmse = evaluate(y_valid, y_hat, label=f"valid (power={pwr})")
        if rmse < best_rmse:
            best_rmse = rmse
            best_mae = mae
            best = (pwr, model)

    best_power, best_model = best
    # =========================

    # HURDLE (family-level): classifier p(y>0)
    # =========================
    y_train_bin = (train_df[TARGET_COL].values > 0).astype(int)
    y_valid_bin = (valid_df[TARGET_COL].values > 0).astype(int)

    clf_pos = LGBMClassifier(
        objective="binary",
        learning_rate=0.05,
        n_estimators=3000,
        num_leaves=63,
        subsample=0.8,
        colsample_bytree=0.8,
        min_child_samples=25,
        reg_lambda=1.0,
        random_state=42,
        n_jobs=1,
        force_row_wise=True,
    )

    clf_pos.fit(
        X_train, y_train_bin,
        eval_set=[(X_valid, y_valid_bin)],
        eval_metric="binary_logloss",
        callbacks=[lgb.early_stopping(stopping_rounds=LGBM_EARLY_STOP, verbose=False)],
    )

    # --- HURDLE calibration on VALID (isotonic) ---
    try:
        p_valid_raw = clf_pos.predict_proba(X_valid)[:, 1]
        yv = y_valid_bin.astype(int)

        # raw metrics
        ll_raw = log_loss(yv, p_valid_raw, labels=[0,1])
        br_raw = brier_score_loss(yv, p_valid_raw)

        iso = IsotonicRegression(out_of_bounds="clip")
        iso.fit(p_valid_raw, yv)
        p_valid_cal = iso.predict(p_valid_raw)

        ll_cal = log_loss(yv, p_valid_cal, labels=[0,1])
        br_cal = brier_score_loss(yv, p_valid_cal)

        print(f"📏 HURDLE valid calib | logloss raw={ll_raw:.5f} cal={ll_cal:.5f} | brier raw={br_raw:.5f} cal={br_cal:.5f}", flush=True)
    except Exception as e:
        iso = None
        p_valid_raw = None
        print(f"⚠️ calib failed: {e}", flush=True)



    return {
        "feature_cols": feature_cols,
        "medians": medians,
        "profiles_full": prof,
        "hist_stats_full": full_stats,
        "tweedie_power": float(best_power),
        "regressor": best_model,
        "valid_days": VALID_DAYS,
        "model_version": "v4_2_tweedie_family_fullhistory_gatingready",
        "trained_at": pd.Timestamp.utcnow().isoformat(),
        "train_max_date": df["data"].max().date().isoformat(),
        "valid_rmse_best": float(best_rmse),
        "valid_mae_best": float(best_mae),
        "season_stats": season_stats,
        'clf_pos': clf_pos,
        'clf_pos_cal': iso,
        'pos_valid_y': (yv.tolist() if 'yv' in locals() and yv is not None else None),
        'pos_valid_p_raw': (p_valid_raw.tolist() if 'p_valid_raw' in locals() and p_valid_raw is not None else None),
        'clf_pos_cal': iso,
        'pos_valid_y': (yv.tolist() if 'yv' in locals() and yv is not None else None),
        'pos_valid_p_raw': (p_valid_raw.tolist() if 'p_valid_raw' in locals() and p_valid_raw is not None else None),

    }

# =========================
# MAIN
# =========================
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--family", default=os.getenv("ONLY_FAMILY", "phaelenopsis"))
    args = parser.parse_args()

    fam = (args.family or "").strip()
    if not fam:
        raise RuntimeError("Famiglia vuota")

    engine = get_engine()

    fam_name, fam_slug = resolve_family_and_slug(engine, fam)
    print(f"RESOLVED family input='{fam}' -> famiglia='{fam_name}' slug='{fam_slug}'", flush=True)
    fam = fam_name


    fascia_bundle = train_one_family_fascia(engine, fam, famiglia_slug=fam_slug)
    if fascia_bundle is None:
        print("⚠️ fascia-level skipped (no data / too little training) for %s" % fam)

    family_bundle = None
    if TRAIN_FAMILY_LEVEL:
        try:
            family_bundle = train_one_family_daily(engine, fam, famiglia_slug=fam_slug)
        except Exception as e:
            print(f"⚠️ family-level failed for {fam}: {e}")
            family_bundle = None

    bundle = {"famiglia": fam, "famiglia_slug": fam_slug, "fascia_level": fascia_bundle, "family_level": family_bundle}

    out_path = bundle_path_for_family(fam_slug)
    with open(out_path, "wb") as f:
                pickle.dump(bundle, f)

    engine.dispose()
    print("\n==============================")
    print(f"✅ DONE. Salvato bundle -> {out_path}")
    print("==============================")

if __name__ == "__main__":
    main()