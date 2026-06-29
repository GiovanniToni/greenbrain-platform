"""Feature Builder V2 for weather-enriched ML parquet datasets.

This module is intentionally pure/pandas-only:
- no database writes
- no uploads
- no training/prediction side effects

Official v2 dataset path:
    features_ml/v2_weather/data_year=YYYY/famiglia_slug=<slug>/part.parquet

Important:
    The partition key is `data_year`, not `year`, to avoid a Hive partition
    conflict with the model feature column named `year`.
"""

from __future__ import annotations

import re
import unicodedata
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np
import pandas as pd


V2_STORAGE_PREFIX = "features_ml/v2_weather"
V2_PARTITION_FIELD = "data_year"
DEFAULT_WARMUP_DAYS = 60

V1_COMPAT_COLUMNS: list[str] = [
    "data",
    "famiglia",
    "fascia_prezzo_iva_inc",
    "qty_venduta",
    "tmin_c",
    "tmax_c",
    "tavg_c",
    "rain_mm",
    "sun_hours",
    "is_holiday",
    "dow",
    "week_num",
    "month_num",
    "year_num",
    "qty_lag_1",
    "qty_lag_2",
    "qty_lag_3",
    "qty_lag_7",
    "qty_lag_10",
    "qty_lag_14",
    "qty_ma_3",
    "qty_ma_7",
    "qty_ma_10",
    "qty_ma_14",
    "qty_ma_28",
]

TRAIN_COMPAT_ALIAS_COLUMNS: list[str] = [
    "week_of_year",
    "month",
    "year",
    "doy",
    "doy_sin",
    "doy_cos",
    "dow_sin",
    "dow_cos",
    "is_weekend",
    "is_month_start",
    "is_month_end",
    "is_pre_holiday",
    "is_post_holiday",
]

CALENDAR_ENRICHED_COLUMNS: list[str] = [
    "is_national_holiday",
    "is_local_holiday",
    "is_local_event",
    "is_commercial_event",
    "is_garden_relevant_event",
    "event_count_total",
    "event_impact_score",
    "max_event_impact_score",
    "is_pre_local_event",
    "is_post_local_event",
    "days_to_next_holiday",
    "days_since_prev_holiday",
    "days_to_next_local_event",
    "days_since_prev_local_event",
    "is_spring_peak",
    "is_summer_peak",
    "is_autumn_peak",
    "is_christmas_season",
    "is_easter_window",
    "is_mother_day_window",
    "is_valentine_window",
    "is_women_day_window",
    "is_saints_window",
]

DEBUG_METADATA_COLUMNS: list[str] = [
    "holiday_name",
    "event_names",
    "event_types",
    "retail_season_code",
    "garden_season_code",
    "weather_source_kind",
    "weather_location_codes",
    "weather_score_version",
]

WEATHER_META_COLUMNS: set[str] = {
    "data",
    "source_kind",
    "location_codes",
    "score_version",
    "created_at",
    "updated_at",
    "weather_source_kind",
    "weather_location_codes",
    "weather_score_version",
}


def slugify(value: str) -> str:
    value = unicodedata.normalize("NFKD", str(value))
    value = value.encode("ascii", "ignore").decode("ascii")
    value = value.lower()
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    return value or "unknown"


def expected_v1_columns() -> list[str]:
    return list(V1_COMPAT_COLUMNS)


def official_v2_relative_path(year: int, famiglia_slug: str) -> Path:
    return Path(V2_STORAGE_PREFIX) / f"{V2_PARTITION_FIELD}={int(year)}" / f"famiglia_slug={famiglia_slug}" / "part.parquet"


def _copy_with_datetime_data(df: pd.DataFrame, *, name: str) -> pd.DataFrame:
    if df is None:
        return pd.DataFrame(columns=["data"])

    out = df.copy()

    # Preserve empty dataframe schemas. This matters for stale families that
    # have known price bands but no fact rows in the selected date window.
    if "data" not in out.columns:
        raise ValueError(f"{name} dataframe is missing required column: data")

    out["data"] = pd.to_datetime(out["data"])
    return out


def _normalize_bool_columns(df: pd.DataFrame) -> pd.DataFrame:
    bool_cols = [
        c for c in df.columns
        if c.startswith("is_") or c.startswith("has_")
    ]
    for col in bool_cols:
        df[col] = df[col].fillna(False).astype(bool)
    return df


def _fill_model_distance_columns(df: pd.DataFrame) -> pd.DataFrame:
    for col in [
        "days_to_next_holiday",
        "days_since_prev_holiday",
        "days_to_next_local_event",
        "days_since_prev_local_event",
    ]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(9999).astype("int64")
    return df


def _add_weather_legacy_aliases(df: pd.DataFrame) -> pd.DataFrame:
    """Populate legacy weather columns from enriched weather store.

    Current policy:
      tmin_c    <- pistoia_tmin_c    fallback area_avg_tmin_c
      tmax_c    <- pistoia_tmax_c    fallback area_avg_tmax_c
      tavg_c    <- pistoia_tavg_c    fallback area_avg_tavg_c
      rain_mm   <- pistoia_rain_mm   fallback area_avg_rain_mm
      sun_hours <- pistoia_sun_hours fallback area_avg_sun_hours
    """
    alias_pairs = {
        "tmin_c": ("pistoia_tmin_c", "area_avg_tmin_c"),
        "tmax_c": ("pistoia_tmax_c", "area_avg_tmax_c"),
        "tavg_c": ("pistoia_tavg_c", "area_avg_tavg_c"),
        "rain_mm": ("pistoia_rain_mm", "area_avg_rain_mm"),
        "sun_hours": ("pistoia_sun_hours", "area_avg_sun_hours"),
    }

    for target, (primary, fallback) in alias_pairs.items():
        if primary in df.columns and fallback in df.columns:
            df[target] = df[primary].combine_first(df[fallback])
        elif primary in df.columns:
            df[target] = df[primary]
        elif fallback in df.columns:
            df[target] = df[fallback]
        else:
            df[target] = np.nan

    return df


def _add_training_aliases(df: pd.DataFrame) -> pd.DataFrame:
    if "week_num" in df.columns:
        df["week_of_year"] = df["week_num"]
    if "month_num" in df.columns:
        df["month"] = df["month_num"]
    if "year_num" in df.columns:
        df["year"] = df["year_num"]
    if "day_of_year" in df.columns:
        df["doy"] = df["day_of_year"]

    # Legacy training compatibility:
    # train_v4_single_family_tweedie.add_holiday_neighborhood expects these
    # columns to exist before it normalizes them. Build them from the known
    # holiday calendar so v2_weather remains compatible with the v4 trainer.
    if "is_holiday" in df.columns and "data" in df.columns:
        dates = pd.to_datetime(df["data"]).dt.normalize()
        holiday_flags = df["is_holiday"].fillna(False).astype(bool)
        holiday_dates = set(dates[holiday_flags].dropna().tolist())

        pre_holiday = (dates + pd.Timedelta(days=1)).isin(holiday_dates)
        post_holiday = (dates - pd.Timedelta(days=1)).isin(holiday_dates)

        if "is_pre_holiday" in df.columns:
            df["is_pre_holiday"] = df["is_pre_holiday"].fillna(pre_holiday).astype(bool)
        else:
            df["is_pre_holiday"] = pre_holiday.astype(bool)

        if "is_post_holiday" in df.columns:
            df["is_post_holiday"] = df["is_post_holiday"].fillna(post_holiday).astype(bool)
        else:
            df["is_post_holiday"] = post_holiday.astype(bool)
    else:
        if "is_pre_holiday" not in df.columns:
            df["is_pre_holiday"] = False
        if "is_post_holiday" not in df.columns:
            df["is_post_holiday"] = False

    return df


def _add_no_leakage_lags(df: pd.DataFrame) -> pd.DataFrame:
    df = df.sort_values(["famiglia", "fascia_prezzo_iva_inc", "data"]).reset_index(drop=True)
    group_keys = [df["famiglia"], df["fascia_prezzo_iva_inc"]]
    grouped_qty = df.groupby(["famiglia", "fascia_prezzo_iva_inc"], sort=False)["qty_venduta"]

    for lag in [1, 2, 3, 7, 10, 14]:
        df[f"qty_lag_{lag}"] = grouped_qty.shift(lag)

    shifted = grouped_qty.shift(1)
    for window in [3, 7, 10, 14, 28]:
        df[f"qty_ma_{window}"] = (
            shifted.groupby(group_keys, sort=False)
            .rolling(window, min_periods=1)
            .mean()
            .reset_index(level=[0, 1], drop=True)
        )

    return df


def _weather_feature_columns(weather: pd.DataFrame, df: pd.DataFrame) -> list[str]:
    cols: list[str] = []
    excluded = set(V1_COMPAT_COLUMNS) | set(TRAIN_COMPAT_ALIAS_COLUMNS) | set(CALENDAR_ENRICHED_COLUMNS)

    for col in weather.columns:
        if col in WEATHER_META_COLUMNS:
            continue
        if col in excluded:
            continue
        if col not in df.columns:
            continue
        if col not in cols:
            cols.append(col)

    return cols


def _ordered_output_columns(
    *,
    df: pd.DataFrame,
    weather_feature_cols: Sequence[str],
    include_debug_metadata: bool,
) -> list[str]:
    blocks: list[Sequence[str]] = [
        V1_COMPAT_COLUMNS,
        TRAIN_COMPAT_ALIAS_COLUMNS,
        CALENDAR_ENRICHED_COLUMNS,
        list(weather_feature_cols),
    ]
    if include_debug_metadata:
        blocks.append(DEBUG_METADATA_COLUMNS)

    ordered: list[str] = []
    for block in blocks:
        for col in block:
            if col in df.columns and col not in ordered:
                ordered.append(col)

    return ordered


def build_family_year_v2_weather_frame(
    *,
    facts: pd.DataFrame,
    calendar: pd.DataFrame,
    weather: pd.DataFrame,
    famiglia: str,
    year: int,
    fasce: Iterable[str] | None = None,
    target_from: str | pd.Timestamp | None = None,
    target_to: str | pd.Timestamp | None = None,
    warmup_days: int = DEFAULT_WARMUP_DAYS,
    include_debug_metadata: bool = True,
) -> pd.DataFrame:
    """Build a single-family/year v2 weather dataframe.

    `facts` must contain:
      data, famiglia, fascia_prezzo_iva_inc, qty_venduta

    `calendar` should come from:
      public.greenhouse_calendar_features_daily

    `weather` should come from:
      public.greenhouse_weather_ml_features_daily
    """
    if not famiglia:
        raise ValueError("famiglia is required")

    year = int(year)
    target_from_ts = pd.to_datetime(target_from or f"{year}-01-01")
    target_to_ts = pd.to_datetime(target_to or f"{year}-12-31")
    warmup_start_ts = target_from_ts - pd.Timedelta(days=int(warmup_days))

    facts = _copy_with_datetime_data(facts, name="facts")
    calendar = _copy_with_datetime_data(calendar, name="calendar")
    weather = _copy_with_datetime_data(weather, name="weather")

    required_fact_cols = {"data", "famiglia", "fascia_prezzo_iva_inc", "qty_venduta"}
    missing_fact_cols = sorted(required_fact_cols - set(facts.columns))
    if missing_fact_cols:
        raise ValueError(f"facts dataframe is missing required columns: {missing_fact_cols}")

    facts = facts.copy()
    facts["famiglia"] = facts["famiglia"].astype(str)
    facts["fascia_prezzo_iva_inc"] = facts["fascia_prezzo_iva_inc"].astype(str)
    facts["qty_venduta"] = pd.to_numeric(facts["qty_venduta"], errors="coerce").fillna(0.0)

    if fasce is None:
        fasce_list = sorted(facts.loc[facts["famiglia"] == famiglia, "fascia_prezzo_iva_inc"].dropna().astype(str).unique().tolist())
    else:
        fasce_list = sorted({str(x) for x in fasce if x is not None})

    if not fasce_list:
        raise ValueError(f"no fasce found for famiglia={famiglia!r}")

    dates = pd.date_range(warmup_start_ts, target_to_ts, freq="D")
    grid = pd.MultiIndex.from_product(
        [[famiglia], fasce_list, dates],
        names=["famiglia", "fascia_prezzo_iva_inc", "data"],
    ).to_frame(index=False)

    df = grid.merge(
        facts[["data", "famiglia", "fascia_prezzo_iva_inc", "qty_venduta"]],
        on=["data", "famiglia", "fascia_prezzo_iva_inc"],
        how="left",
    )
    df["qty_venduta"] = df["qty_venduta"].fillna(0.0)

    df = df.merge(calendar, on="data", how="left", suffixes=("", "_calendar"))

    weather_for_merge = weather.rename(columns={
        "source_kind": "weather_source_kind",
        "location_codes": "weather_location_codes",
        "score_version": "weather_score_version",
    })
    df = df.merge(weather_for_merge, on="data", how="left", suffixes=("", "_weather"))

    df = _add_weather_legacy_aliases(df)
    df = _add_training_aliases(df)
    df = _normalize_bool_columns(df)
    df = _fill_model_distance_columns(df)
    df = _add_no_leakage_lags(df)

    df = df[(df["data"] >= target_from_ts) & (df["data"] <= target_to_ts)].copy()

    weather_feature_cols = _weather_feature_columns(weather_for_merge, df)
    ordered_cols = _ordered_output_columns(
        df=df,
        weather_feature_cols=weather_feature_cols,
        include_debug_metadata=include_debug_metadata,
    )

    out = df[ordered_cols].copy()

    for col in out.columns:
        if col == "data":
            continue
        if col in {"famiglia", "fascia_prezzo_iva_inc"} or col in DEBUG_METADATA_COLUMNS:
            out[col] = out[col].astype("string")
        elif out[col].dtype == "object":
            out[col] = pd.to_numeric(out[col], errors="ignore")

    return out


def write_family_year_v2_weather_parquet(
    frame: pd.DataFrame,
    *,
    output_root: str | Path,
    year: int,
    famiglia_slug: str,
) -> Path:
    output_root = Path(output_root)
    out_file = output_root / f"{V2_PARTITION_FIELD}={int(year)}" / f"famiglia_slug={famiglia_slug}" / "part.parquet"
    out_file.parent.mkdir(parents=True, exist_ok=True)
    frame.to_parquet(out_file, index=False)
    return out_file
