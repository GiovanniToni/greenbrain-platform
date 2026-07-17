#!/usr/bin/env python3
"""Phase 2M-E2 weather feature-lake builder.

Implementation milestone:
    canonical + derived-long

Outputs:
    weather_location_catalog
    weather_observed_day
    weather_forecast_snapshot
    weather_observed_features_day
    weather_forecast_features_snapshot
    weather_climatology_causal

Lifecycle:
    immutable candidate run
    independent validator subprocess
    atomic promotion after successful validation
"""

from __future__ import annotations

import argparse
import gc
import base64
import gzip
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.dataset as ds
import pyarrow.parquet as pq


CONTRACT_FINGERPRINT = "b9339f7a0bfa44ddb28becb76d853cf0f3a2dc6360dc1a867215646b11f8b4c4"
FEATURE_REGISTRY_FINGERPRINT = "0fc91c8b0b9fc10d275bc254b58b6278aef21b1187741ae0110ef441865478e9"
SCHEMA_REGISTRY_FINGERPRINT = "25e7f17e1708e73a9151863cf1f10b5afa6f7c7f329942992b361d2c0a0e151e"

_FEATURE_REGISTRY_B64 = "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"
_SCHEMA_REGISTRY_B64 = "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"

IMPLEMENTATION_PHASE = "point_in_time"

CANONICAL_OUTPUTS = [
    "weather_location_catalog",
    "weather_observed_day",
    "weather_forecast_snapshot",
]

DERIVED_OUTPUTS = [
    "weather_observed_features_day",
    "weather_forecast_features_snapshot",
    "weather_climatology_causal",
]

MATERIALIZED_OUTPUTS = ['weather_location_catalog', 'weather_observed_day', 'weather_forecast_snapshot', 'weather_observed_features_day', 'weather_forecast_features_snapshot', 'weather_climatology_causal', 'weather_prediction_day_asof']

MIN_PERIODS_BY_WINDOW = {
    3: 2,
    7: 4,
    14: 7,
    28: 14,
}


def _unpack_json(payload: str) -> Any:
    return json.loads(
        gzip.decompress(
            base64.b64decode(payload)
        ).decode("utf-8")
    )


FEATURE_REGISTRY: list[dict[str, str]] = _unpack_json(
    _FEATURE_REGISTRY_B64
)

SCHEMA_REGISTRY: list[dict[str, str]] = _unpack_json(
    _SCHEMA_REGISTRY_B64
)


def canonical_fingerprint(value: Any) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def default_contract_path() -> Path:
    return (
        Path(__file__).resolve().parent
        / "contracts"
        / "phase2m_e2_weather_contract_v1_2.json"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build the Phase 2M-E2 canonical and derived-long weather outputs."
        )
    )
    parser.add_argument("--source-run", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--training-cutoff", required=True)
    parser.add_argument(
        "--contract",
        type=Path,
        default=default_contract_path(),
    )
    parser.add_argument("--run-id")
    parser.add_argument("--zstd-level", type=int, default=6)
    parser.add_argument(
        "--keep-failed-candidate",
        action="store_true",
    )
    parser.add_argument(
        "--prediction-cutoff-time-utc",
        default="23:59:59",
        help=(
            "UTC cutoff time independently applied to each "
            "prediction date; format HH:MM:SS."
        ),
    )

    return parser.parse_args()



def load_contract(path: Path) -> dict[str, Any]:
    contract = json.loads(path.read_text(encoding="utf-8"))
    unsigned = dict(contract)
    declared = unsigned.pop(
        "final_contract_fingerprint",
        None,
    )
    actual = canonical_fingerprint(unsigned)
    if declared != CONTRACT_FINGERPRINT:
        raise RuntimeError(
            "declared contract fingerprint mismatch: "
            f"{declared} != {CONTRACT_FINGERPRINT}"
        )
    if actual != CONTRACT_FINGERPRINT:
        raise RuntimeError(
            "calculated contract fingerprint mismatch: "
            f"{actual} != {CONTRACT_FINGERPRINT}"
        )
    return contract


def parse_training_cutoff(value: str) -> pd.Timestamp:
    cutoff = pd.Timestamp(value)
    if cutoff.tzinfo is not None:
        cutoff = cutoff.tz_convert(None)
    cutoff = cutoff.normalize()
    if pd.isna(cutoff):
        raise ValueError("invalid training cutoff")
    return cutoff


def read_parquet_tree(path: Path) -> pd.DataFrame:
    files = sorted(path.rglob("*.parquet"))
    if not files:
        raise FileNotFoundError(
            f"no Parquet files under {path}"
        )
    return (
        ds.dataset(
            [str(file) for file in files],
            format="parquet",
        )
        .to_table()
        .to_pandas()
    )


def first_existing(
    columns: Iterable[str],
    candidates: Iterable[str],
) -> str:
    available = set(columns)
    for candidate in candidates:
        if candidate in available:
            return candidate
    raise KeyError(
        "none of the required columns exists: "
        f"candidates={list(candidates)} "
        f"available={sorted(available)}"
    )


def normalize_date(series: pd.Series) -> pd.Series:
    return pd.to_datetime(
        series,
        errors="coerce",
    ).dt.normalize()


def normalize_utc_timestamp(series: pd.Series) -> pd.Series:
    return pd.to_datetime(
        series,
        errors="coerce",
        utc=True,
    )


def normalize_observed(source_run: Path) -> pd.DataFrame:
    frame = read_parquet_tree(
        source_run
        / "raw_extracts"
        / "weather_actuals"
    )
    date_column = first_existing(
        frame.columns,
        ("weather_date", "data", "date"),
    )
    location_column = first_existing(
        frame.columns,
        ("location_id", "source_location_id"),
    )
    frame = frame.rename(
        columns={
            date_column: "data",
            location_column: "source_location_id",
        }
    )
    frame["data"] = normalize_date(frame["data"])
    frame["source_location_id"] = frame[
        "source_location_id"
    ].astype("string")
    frame["weather_profile_id"] = frame[
        "source_location_id"
    ]
    frame[
        "weather_location_set_id"
    ] = "generic_weather_location_set_v1"
    frame["config_version"] = "generic_slots_v1"
    grain = ["data", "source_location_id"]
    frame = (
        frame.sort_values(grain, kind="mergesort")
        .reset_index(drop=True)
    )
    if frame[grain].isna().any().any():
        raise RuntimeError("null observed grain key")
    if frame.duplicated(grain).any():
        raise RuntimeError("duplicate observed grain")
    assert_daily_contiguous(frame)
    return frame


def normalize_forecast(source_run: Path) -> pd.DataFrame:
    frame = read_parquet_tree(
        source_run
        / "raw_extracts"
        / "weather_forecasts"
    )
    run_column = first_existing(
        frame.columns,
        ("forecast_run_date", "run_date"),
    )
    target_column = first_existing(
        frame.columns,
        ("forecast_date", "target_date", "weather_date"),
    )
    location_column = first_existing(
        frame.columns,
        ("location_id", "source_location_id"),
    )
    frame = frame.rename(
        columns={
            run_column: "forecast_run_date",
            target_column: "forecast_date",
            location_column: "source_location_id",
        }
    )
    frame["forecast_run_date"] = normalize_date(
        frame["forecast_run_date"]
    )
    frame["forecast_date"] = normalize_date(
        frame["forecast_date"]
    )
    frame["source_location_id"] = frame[
        "source_location_id"
    ].astype("string")
    frame["forecast_horizon_days"] = (
        frame["forecast_date"]
        - frame["forecast_run_date"]
    ).dt.days.astype("Int64")
    frame["weather_profile_id"] = frame[
        "source_location_id"
    ]
    frame[
        "weather_location_set_id"
    ] = "generic_weather_location_set_v1"
    frame["config_version"] = "generic_slots_v1"
    availability_column = next(
        (
            column
            for column in (
                "fetched_at",
                "created_at",
                "updated_at",
            )
            if column in frame.columns
        ),
        None,
    )
    if availability_column is None:
        raise RuntimeError(
            "forecast availability timestamp unavailable"
        )
    frame["available_at_utc"] = normalize_utc_timestamp(
        frame[availability_column]
    )
    frame["availability_mode"] = "timestamp_evidence"
    grain = [
        "forecast_run_date",
        "forecast_date",
        "source_location_id",
        "forecast_horizon_days",
    ]
    frame = (
        frame.sort_values(
            grain + ["available_at_utc"],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )
    if frame[grain].isna().any().any():
        raise RuntimeError("null forecast grain key")
    if frame.duplicated(grain).any():
        raise RuntimeError("duplicate forecast grain")
    return frame


def assert_daily_contiguous(frame: pd.DataFrame) -> None:
    for location_id, group in frame.groupby(
        "source_location_id",
        sort=False,
    ):
        deltas = (
            group["data"]
            .sort_values(kind="mergesort")
            .diff()
            .dropna()
            .dt.days
        )
        if not deltas.eq(1).all():
            raise RuntimeError(
                "observed dates are not daily contiguous "
                f"for location {location_id}"
            )


def build_location_catalog(
    observed: pd.DataFrame,
    forecast: pd.DataFrame,
) -> pd.DataFrame:
    locations = sorted(
        set(observed["source_location_id"].dropna())
        | set(forecast["source_location_id"].dropna())
    )
    rows: list[dict[str, Any]] = []
    for rank, location_id in enumerate(
        locations,
        start=1,
    ):
        generic_slot = (
            f"loc_{rank:02d}"
            if rank <= 4
            else pd.NA
        )
        rows.append(
            {
                "weather_location_set_id": (
                    "generic_weather_location_set_v1"
                ),
                "config_version": "generic_slots_v1",
                "weather_profile_id": location_id,
                "source_location_id": location_id,
                "generic_location_slot": generic_slot,
                "generic_location_rank": rank,
                "location_role": "unbound",
                "is_primary": False,
                "is_active": True,
                "slot_assignment_method": (
                    "source_location_id_lexicographic_v1"
                ),
                "binding_status": (
                    "generic_slot_bound_role_unresolved"
                    if rank <= 4
                    else "overflow_only"
                ),
            }
        )
    catalog = pd.DataFrame(rows)
    if catalog["source_location_id"].duplicated().any():
        raise RuntimeError("duplicate catalog location")
    if (
        catalog["generic_location_slot"]
        .dropna()
        .duplicated()
        .any()
    ):
        raise RuntimeError("duplicate generic location slot")
    if catalog["is_primary"].any():
        raise RuntimeError("primary location was inferred")
    return (
        catalog.sort_values(
            [
                "generic_location_rank",
                "source_location_id",
            ],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def attach_location_slots(
    frame: pd.DataFrame,
    catalog: pd.DataFrame,
) -> pd.DataFrame:
    slot_columns = catalog[
        [
            "source_location_id",
            "generic_location_slot",
            "generic_location_rank",
        ]
    ]
    result = frame.merge(
        slot_columns,
        on="source_location_id",
        how="left",
        validate="many_to_one",
        sort=False,
    )
    if result["generic_location_rank"].isna().any():
        raise RuntimeError(
            "location slot join produced null rank"
        )
    return result


def registry_rows(
    output: str,
    family: str | None = None,
) -> list[dict[str, str]]:
    rows = [
        row
        for row in FEATURE_REGISTRY
        if row["output"] == output
    ]
    if family is not None:
        rows = [
            row
            for row in rows
            if row["family"] == family
        ]
    return rows


def cast_feature_series(
    series: pd.Series,
    dtype: str,
) -> pd.Series:
    if dtype == "float64":
        return pd.to_numeric(
            series,
            errors="coerce",
        ).astype("float64")
    if dtype == "int16":
        return (
            pd.to_numeric(
                series,
                errors="coerce",
            )
            .round()
            .astype("Int16")
        )
    if dtype == "int8":
        return (
            pd.to_numeric(
                series,
                errors="coerce",
            )
            .round()
            .astype("Int8")
        )
    raise RuntimeError(
        f"unsupported feature dtype {dtype}"
    )


def rolling_numeric(
    frame: pd.DataFrame,
    metric: str,
    window: int,
    operation: str,
    min_periods: int,
) -> pd.Series:
    result = pd.Series(
        np.nan,
        index=frame.index,
        dtype="float64",
    )
    for _, indices in frame.groupby(
        "source_location_id",
        sort=False,
    ).groups.items():
        index = pd.Index(indices)
        values = pd.to_numeric(
            frame.loc[index, metric],
            errors="coerce",
        )
        shifted = values.shift(1)
        roll = shifted.rolling(
            window=window,
            min_periods=min_periods,
        )
        if operation == "mean":
            calculated = roll.mean()
        elif operation == "min":
            calculated = roll.min()
        elif operation == "max":
            calculated = roll.max()
        elif operation == "std":
            calculated = roll.std(ddof=1)
        elif operation == "sum":
            calculated = roll.sum()
        elif operation == "valid_count":
            calculated = roll.count().where(
                roll.count() >= min_periods
            )
        elif operation == "nonzero_count":
            valid_count = roll.count()
            calculated = (
                shifted.notna()
                .mul(shifted.ne(0))
                .astype("float64")
                .rolling(
                    window=window,
                    min_periods=1,
                )
                .sum()
                .where(valid_count >= min_periods)
            )
        else:
            raise RuntimeError(
                f"unsupported rolling operation {operation}"
            )
        result.loc[index] = calculated.to_numpy()
    return result


_CONDITION_RE = re.compile(
    r"^\s*([a-zA-Z0-9_]+)\s*"
    r"(>=|<=|>|<)\s*"
    r"(-?[0-9]+(?:\.[0-9]+)?)\s*$"
)


def evaluate_condition(
    frame: pd.DataFrame,
    condition: str,
) -> pd.Series:
    match = _CONDITION_RE.match(condition)
    if not match:
        raise RuntimeError(
            f"unsupported condition {condition!r}"
        )
    metric, operator, raw_threshold = match.groups()
    if metric not in frame.columns:
        raise KeyError(metric)
    values = pd.to_numeric(
        frame[metric],
        errors="coerce",
    )
    threshold = float(raw_threshold)
    if operator == ">":
        result = values > threshold
    elif operator == ">=":
        result = values >= threshold
    elif operator == "<":
        result = values < threshold
    elif operator == "<=":
        result = values <= threshold
    else:
        raise RuntimeError(operator)
    return result.fillna(False)


def rolling_event_count(
    frame: pd.DataFrame,
    condition: str,
    window: int,
) -> pd.Series:
    qualifying = evaluate_condition(
        frame,
        condition,
    ).astype("int16")
    result = pd.Series(
        0,
        index=frame.index,
        dtype="int64",
    )
    for _, indices in frame.groupby(
        "source_location_id",
        sort=False,
    ).groups.items():
        index = pd.Index(indices)
        shifted = qualifying.loc[index].shift(
            1,
            fill_value=0,
        )
        calculated = (
            shifted.rolling(
                window=window,
                min_periods=1,
            )
            .sum()
            .fillna(0)
        )
        result.loc[index] = calculated.to_numpy()
    return result


def streak_condition(
    frame: pd.DataFrame,
    feature_name: str,
) -> pd.Series:
    if "__dry_day__" in feature_name:
        return (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            <= 0.1
        ).fillna(False)
    if "__rain_day__" in feature_name:
        return (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            > 0.1
        ).fillna(False)
    if "__frost_day__" in feature_name:
        return (
            pd.to_numeric(
                frame["temperature_2m_min_c"],
                errors="coerce",
            )
            <= 0
        ).fillna(False)
    if "__hot_day__" in feature_name:
        return (
            pd.to_numeric(
                frame["temperature_2m_max_c"],
                errors="coerce",
            )
            >= 30
        ).fillna(False)
    if "__strong_wind_day__" in feature_name:
        return (
            pd.to_numeric(
                frame["wind_speed_10m_max_kmh"],
                errors="coerce",
            )
            >= 40
        ).fillna(False)
    raise RuntimeError(
        f"unsupported streak feature {feature_name}"
    )


def consecutive_streak_asof_minus_one(
    frame: pd.DataFrame,
    qualifying: pd.Series,
) -> pd.Series:
    result = pd.Series(
        0,
        index=frame.index,
        dtype="int64",
    )
    for _, indices in frame.groupby(
        "source_location_id",
        sort=False,
    ).groups.items():
        index = pd.Index(indices)
        values = qualifying.loc[index].to_numpy(
            dtype=bool
        )
        current = 0
        streaks = np.zeros(
            len(values),
            dtype=np.int64,
        )
        for position, is_true in enumerate(values):
            if is_true:
                current += 1
            else:
                current = 0
            streaks[position] = current
        shifted = np.concatenate(
            [
                np.array([0], dtype=np.int64),
                streaks[:-1],
            ]
        )
        result.loc[index] = shifted
    return result


def build_observed_features(
    observed: pd.DataFrame,
    catalog: pd.DataFrame,
) -> pd.DataFrame:
    frame = attach_location_slots(
        observed,
        catalog,
    )
    frame = (
        frame.sort_values(
            ["source_location_id", "data"],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )
    assert_daily_contiguous(frame)

    rows = registry_rows(
        "weather_observed_features_day"
    )
    if len(rows) != 521:
        raise RuntimeError(
            f"observed registry count {len(rows)} != 521"
        )

    feature_values: dict[str, pd.Series] = {}
    rolling_cache: dict[
        tuple[str, int, str, int],
        pd.Series,
    ] = {}
    event_cache: dict[
        tuple[str, int],
        pd.Series,
    ] = {}

    for row in rows:
        name = row["feature_name"]
        family = row["family"]
        formula = row["formula"]
        dtype = row["dtype"]

        if family == "lag":
            match = re.fullmatch(
                r"obs_lag_(\d+)d__(.+)",
                name,
            )
            if not match:
                raise RuntimeError(
                    f"invalid lag feature name {name}"
                )
            days = int(match.group(1))
            metric = match.group(2)
            if metric not in frame.columns:
                raise KeyError(metric)
            series = frame.groupby(
                "source_location_id",
                sort=False,
            )[metric].shift(days)

        elif family in {
            "rolling_state",
            "rolling_accumulation",
        }:
            match = re.fullmatch(
                r"obs_roll_(\d+)d__(.+)__"
                r"(mean|min|max|std|sum|valid_count|nonzero_count)",
                name,
            )
            if not match:
                raise RuntimeError(
                    f"invalid rolling feature name {name}"
                )
            window = int(match.group(1))
            metric = match.group(2)
            operation = match.group(3)
            min_periods = MIN_PERIODS_BY_WINDOW[
                window
            ]
            cache_key = (
                metric,
                window,
                operation,
                min_periods,
            )
            if cache_key not in rolling_cache:
                rolling_cache[
                    cache_key
                ] = rolling_numeric(
                    frame=frame,
                    metric=metric,
                    window=window,
                    operation=operation,
                    min_periods=min_periods,
                )
            series = rolling_cache[cache_key]

        elif family == "rolling_event":
            match = re.fullmatch(
                r"count\((.+)\) over previous (\d+) days",
                formula,
            )
            if not match:
                raise RuntimeError(
                    f"invalid rolling-event formula {formula}"
                )
            condition = match.group(1).strip()
            window = int(match.group(2))
            cache_key = (condition, window)
            if cache_key not in event_cache:
                event_cache[
                    cache_key
                ] = rolling_event_count(
                    frame,
                    condition,
                    window,
                )
            series = event_cache[cache_key]

        elif family == "streak":
            qualifying = streak_condition(
                frame,
                name,
            )
            series = (
                consecutive_streak_asof_minus_one(
                    frame,
                    qualifying,
                )
            )

        else:
            raise RuntimeError(
                f"unsupported observed family {family}"
            )

        feature_values[name] = cast_feature_series(
            series,
            dtype,
        )

    feature_frame = pd.DataFrame(
        feature_values,
        index=frame.index,
    )
    output = pd.concat(
        [
            frame,
            feature_frame,
        ],
        axis=1,
    )
    missing = [
        row["feature_name"]
        for row in rows
        if row["feature_name"] not in output.columns
    ]
    if missing:
        raise RuntimeError(
            f"missing observed features: {missing[:20]}"
        )
    return (
        output.sort_values(
            ["data", "source_location_id"],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def safe_ratio(
    numerator: pd.Series,
    denominator: pd.Series,
    positive_only: bool = False,
) -> pd.Series:
    num = pd.to_numeric(
        numerator,
        errors="coerce",
    )
    den = pd.to_numeric(
        denominator,
        errors="coerce",
    )
    allowed = den > 0 if positive_only else den.ne(0)
    return num.div(den.where(allowed))


def forecast_derived_series(
    frame: pd.DataFrame,
    name: str,
) -> pd.Series:
    mapping: dict[str, pd.Series] = {
        "fcst_temperature_range_c": (
            pd.to_numeric(
                frame["temperature_2m_max_c"],
                errors="coerce",
            )
            - pd.to_numeric(
                frame["temperature_2m_min_c"],
                errors="coerce",
            )
        ),
        "fcst_apparent_temperature_range_c": (
            pd.to_numeric(
                frame["apparent_temperature_max_c"],
                errors="coerce",
            )
            - pd.to_numeric(
                frame["apparent_temperature_min_c"],
                errors="coerce",
            )
        ),
        "fcst_apparent_minus_air_temperature_mean_c": (
            pd.to_numeric(
                frame["apparent_temperature_mean_c"],
                errors="coerce",
            )
            - pd.to_numeric(
                frame["temperature_2m_mean_c"],
                errors="coerce",
            )
        ),
        "fcst_daylight_hours": (
            pd.to_numeric(
                frame["daylight_duration_seconds"],
                errors="coerce",
            )
            / 3600.0
        ),
        "fcst_sunshine_hours": (
            pd.to_numeric(
                frame["sunshine_duration_seconds"],
                errors="coerce",
            )
            / 3600.0
        ),
        "fcst_sunshine_fraction": safe_ratio(
            frame["sunshine_duration_seconds"],
            frame["daylight_duration_seconds"],
            positive_only=True,
        ),
        "fcst_precipitation_intensity_mm_per_hour": safe_ratio(
            frame["precipitation_sum_mm"],
            frame["precipitation_hours"],
            positive_only=True,
        ),
        "fcst_rain_share_of_precipitation": safe_ratio(
            frame["rain_sum_mm"],
            frame["precipitation_sum_mm"],
            positive_only=True,
        ),
        "fcst_wind_direction_sin": np.sin(
            np.deg2rad(
                pd.to_numeric(
                    frame[
                        "wind_direction_10m_dominant_deg"
                    ],
                    errors="coerce",
                )
            )
        ),
        "fcst_wind_direction_cos": np.cos(
            np.deg2rad(
                pd.to_numeric(
                    frame[
                        "wind_direction_10m_dominant_deg"
                    ],
                    errors="coerce",
                )
            )
        ),
        "fcst_water_balance_mm": (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            - pd.to_numeric(
                frame[
                    "et0_fao_evapotranspiration_mm"
                ],
                errors="coerce",
            )
        ),
        "fcst_probability_weighted_precipitation_mm": (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            * pd.to_numeric(
                frame[
                    "precipitation_probability_max_pct"
                ],
                errors="coerce",
            )
            / 100.0
        ),
        "fcst_rain_day_flag": (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            > 0.1
        ).astype("int8"),
        "fcst_heavy_rain_day_flag": (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            >= 10.0
        ).astype("int8"),
        "fcst_snow_day_flag": (
            pd.to_numeric(
                frame["snowfall_sum_cm"],
                errors="coerce",
            )
            > 0
        ).astype("int8"),
        "fcst_frost_day_flag": (
            pd.to_numeric(
                frame["temperature_2m_min_c"],
                errors="coerce",
            )
            <= 0
        ).astype("int8"),
        "fcst_hot_day_flag": (
            pd.to_numeric(
                frame["temperature_2m_max_c"],
                errors="coerce",
            )
            >= 30
        ).astype("int8"),
        "fcst_strong_wind_day_flag": (
            pd.to_numeric(
                frame["wind_speed_10m_max_kmh"],
                errors="coerce",
            )
            >= 40
        ).astype("int8"),
    }
    if name not in mapping:
        raise RuntimeError(
            f"unsupported forecast-derived feature {name}"
        )
    return pd.Series(
        mapping[name],
        index=frame.index,
    )


def build_forecast_features(
    forecast: pd.DataFrame,
    catalog: pd.DataFrame,
) -> pd.DataFrame:
    frame = attach_location_slots(
        forecast,
        catalog,
    )
    frame = (
        frame.sort_values(
            [
                "source_location_id",
                "forecast_date",
                "forecast_run_date",
                "available_at_utc",
            ],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )

    rows = registry_rows(
        "weather_forecast_features_snapshot"
    )
    if len(rows) != 35:
        raise RuntimeError(
            f"forecast registry count {len(rows)} != 35"
        )

    revision_metrics = sorted(
        {
            match.group(1)
            for row in rows
            for match in [
                re.fullmatch(
                    r"fcst_revision__(.+)__"
                    r"(?:delta_previous_run|abs_delta_previous_run)",
                    row["feature_name"],
                )
            ]
            if match
        }
    )

    group_keys = [
        "source_location_id",
        "forecast_date",
    ]

    previous_metrics = {
        metric: frame.groupby(
            group_keys,
            sort=False,
        )[metric].shift(1)
        for metric in revision_metrics
    }

    previous_run = frame.groupby(
        group_keys,
        sort=False,
    )["forecast_run_date"].shift(1)

    feature_values: dict[str, pd.Series] = {}

    for row in rows:
        name = row["feature_name"]
        family = row["family"]
        dtype = row["dtype"]

        if family == "forecast_derived":
            series = forecast_derived_series(
                frame,
                name,
            )

        elif family == "forecast_revision":
            if name == (
                "fcst_revision__previous_run_gap_days"
            ):
                series = (
                    frame["forecast_run_date"]
                    - previous_run
                ).dt.days
            else:
                match = re.fullmatch(
                    r"fcst_revision__(.+)__"
                    r"(delta_previous_run|abs_delta_previous_run)",
                    name,
                )
                if not match:
                    raise RuntimeError(
                        f"invalid revision feature {name}"
                    )
                metric = match.group(1)
                operation = match.group(2)
                current = pd.to_numeric(
                    frame[metric],
                    errors="coerce",
                )
                previous = pd.to_numeric(
                    previous_metrics[metric],
                    errors="coerce",
                )
                delta = current - previous
                series = (
                    delta.abs()
                    if operation
                    == "abs_delta_previous_run"
                    else delta
                )
        else:
            raise RuntimeError(
                f"unsupported forecast family {family}"
            )

        feature_values[name] = cast_feature_series(
            pd.Series(
                series,
                index=frame.index,
            ),
            dtype,
        )

    feature_frame = pd.DataFrame(
        feature_values,
        index=frame.index,
    )
    output = pd.concat(
        [
            frame,
            feature_frame,
        ],
        axis=1,
    )
    return (
        output.sort_values(
            [
                "forecast_run_date",
                "forecast_date",
                "source_location_id",
                "forecast_horizon_days",
            ],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def build_climatology(
    observed: pd.DataFrame,
    catalog: pd.DataFrame,
    training_cutoff: pd.Timestamp,
) -> pd.DataFrame:
    rows = registry_rows(
        "weather_climatology_causal"
    )
    if len(rows) != 84:
        raise RuntimeError(
            f"climatology registry count {len(rows)} != 84"
        )

    history = observed[
        observed["data"] < training_cutoff
    ].copy()

    if history.empty:
        raise RuntimeError(
            "no observations before training cutoff"
        )

    history["climatological_day"] = (
        history["data"].dt.strftime("%m-%d")
    )
    history["observation_year"] = (
        history["data"].dt.year.astype("int16")
    )

    locations = (
        catalog[
            [
                "source_location_id",
                "weather_profile_id",
                "weather_location_set_id",
                "config_version",
                "generic_location_slot",
                "generic_location_rank",
            ]
        ]
        .sort_values(
            "generic_location_rank",
            kind="mergesort",
        )
        .reset_index(drop=True)
    )

    calendar = pd.DataFrame(
        {
            "climatological_day": (
                pd.date_range(
                    "2000-01-01",
                    "2000-12-31",
                    freq="D",
                ).strftime("%m-%d")
            )
        }
    )
    calendar["month"] = (
        calendar[
            "climatological_day"
        ]
        .str.slice(0, 2)
        .astype("int8")
    )
    calendar["day_of_month"] = (
        calendar[
            "climatological_day"
        ]
        .str.slice(3, 5)
        .astype("int8")
    )

    locations["_join_key"] = 1
    calendar["_join_key"] = 1
    base = (
        locations.merge(
            calendar,
            on="_join_key",
            how="inner",
            validate="many_to_many",
        )
        .drop(columns="_join_key")
        .sort_values(
            [
                "source_location_id",
                "month",
                "day_of_month",
            ],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )

    base["training_cutoff_date"] = (
        training_cutoff
    )
    base["training_cutoff_version"] = (
        "cutoff_"
        + training_cutoff.strftime("%Y%m%d")
    )

    group_keys = [
        "source_location_id",
        "climatological_day",
    ]

    metrics = sorted(
        {
            re.fullmatch(
                r"clim__(.+)__"
                r"(mean|std|p10|p50|p90|valid_count|year_count)",
                row["feature_name"],
            ).group(1)
            for row in rows
        }
    )

    aggregate_values: dict[
        tuple[str, str],
        pd.Series,
    ] = {}

    for metric in metrics:
        values = pd.to_numeric(
            history[metric],
            errors="coerce",
        )
        metric_frame = history[
            group_keys
        ].copy()
        metric_frame["_value"] = values
        grouped = metric_frame.groupby(
            group_keys,
            sort=True,
            dropna=False,
        )

        simple = grouped["_value"].agg(
            mean="mean",
            std="std",
            valid_count="count",
        )
        quantiles = grouped["_value"].quantile(
            [0.10, 0.50, 0.90]
        ).unstack(level=-1)
        quantiles = quantiles.rename(
            columns={
                0.10: "p10",
                0.50: "p50",
                0.90: "p90",
            }
        )

        year_frame = metric_frame.copy()
        year_frame["_year"] = history[
            "observation_year"
        ].to_numpy()
        year_frame = year_frame[
            year_frame["_value"].notna()
        ]
        year_count = (
            year_frame.groupby(
                group_keys,
                sort=True,
            )["_year"]
            .nunique()
            .rename("year_count")
        )

        aggregate = (
            simple.join(
                quantiles,
                how="outer",
            )
            .join(
                year_count,
                how="outer",
            )
            .reset_index()
        )

        merged = base[
            group_keys
        ].merge(
            aggregate,
            on=group_keys,
            how="left",
            validate="many_to_one",
            sort=False,
        )

        for statistic in (
            "mean",
            "std",
            "p10",
            "p50",
            "p90",
            "valid_count",
            "year_count",
        ):
            series = merged[statistic]
            if statistic in {
                "mean",
                "std",
                "p10",
                "p50",
                "p90",
            }:
                series = series.where(
                    merged["year_count"] >= 3
                )
            aggregate_values[
                (
                    metric,
                    statistic,
                )
            ] = pd.Series(
                series.to_numpy(),
                index=base.index,
            )

    feature_values: dict[str, pd.Series] = {}

    for row in rows:
        name = row["feature_name"]
        match = re.fullmatch(
            r"clim__(.+)__"
            r"(mean|std|p10|p50|p90|valid_count|year_count)",
            name,
        )
        if not match:
            raise RuntimeError(
                f"invalid climatology feature {name}"
            )
        metric = match.group(1)
        statistic = match.group(2)
        feature_values[name] = cast_feature_series(
            aggregate_values[
                (
                    metric,
                    statistic,
                )
            ],
            row["dtype"],
        )

    output = pd.concat(
        [
            base,
            pd.DataFrame(
                feature_values,
                index=base.index,
            ),
        ],
        axis=1,
    )
    return (
        output.sort_values(
            [
                "training_cutoff_date",
                "source_location_id",
                "month",
                "day_of_month",
            ],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def parse_prediction_cutoff_time_utc(
    value: str,
) -> str:
    parts = value.split(":")

    if (
        len(parts) != 3
        or not all(
            part.isdigit()
            for part in parts
        )
    ):
        raise ValueError(
            "prediction cutoff time must use HH:MM:SS UTC"
        )

    hour, minute, second = (
        int(part)
        for part in parts
    )

    if not (
        0 <= hour <= 23
        and 0 <= minute <= 59
        and 0 <= second <= 59
    ):
        raise ValueError(
            "prediction cutoff time is outside HH:MM:SS bounds"
        )

    return (
        f"{hour:02d}:"
        f"{minute:02d}:"
        f"{second:02d}"
    )


def build_prediction_day_asof(
    forecast_features: pd.DataFrame,
    prediction_cutoff_time_utc: str,
) -> pd.DataFrame:
    cutoff_time = (
        parse_prediction_cutoff_time_utc(
            prediction_cutoff_time_utc
        )
    )

    frame = forecast_features.copy()

    required = {
        "forecast_run_date",
        "forecast_date",
        "source_location_id",
        "forecast_horizon_days",
    }

    missing = sorted(
        required
        - set(
            frame.columns
        )
    )

    if missing:
        raise RuntimeError(
            "point-in-time input keys missing: "
            + ", ".join(
                missing
            )
        )

    availability_column = next(
        (
            column
            for column in (
                "available_at_utc",
                "fetched_at",
                "source_fetched_at",
                "created_at",
            )
            if column in frame.columns
        ),
        None,
    )

    if availability_column is None:
        raise RuntimeError(
            "forecast availability timestamp unavailable"
        )

    for column in (
        "forecast_run_date",
        "forecast_date",
    ):
        frame[
            column
        ] = (
            pd.to_datetime(
                frame[
                    column
                ],
                errors="coerce",
            )
            .dt.normalize()
        )

    frame[
        "source_location_id"
    ] = frame[
        "source_location_id"
    ].astype(
        "string"
    )

    frame[
        "_pit_available_at_utc"
    ] = pd.to_datetime(
        frame[
            availability_column
        ],
        errors="coerce",
        utc=True,
    )

    if frame[
        [
            "forecast_run_date",
            "forecast_date",
            "source_location_id",
            "_pit_available_at_utc",
        ]
    ].isna().any().any():
        raise RuntimeError(
            "null point-in-time selection key"
        )

    selection_keys = [
        "forecast_date",
        "source_location_id",
    ]

    selected_parts: list[
        pd.DataFrame
    ] = []

    prediction_dates = sorted(
        frame[
            "forecast_run_date"
        ]
        .drop_duplicates()
        .tolist()
    )

    for prediction_date in (
        prediction_dates
    ):
        prediction_cutoff_utc = (
            pd.Timestamp(
                prediction_date.strftime(
                    "%Y-%m-%d"
                )
                + "T"
                + cutoff_time
                + "Z"
            )
        )

        target_maximum = (
            prediction_date
            + pd.Timedelta(
                days=9
            )
        )

        eligible = frame.loc[
            (
                frame[
                    "_pit_available_at_utc"
                ]
                <= prediction_cutoff_utc
            )
            & (
                frame[
                    "forecast_date"
                ]
                >= prediction_date
            )
            & (
                frame[
                    "forecast_date"
                ]
                <= target_maximum
            )
        ].copy()

        if eligible.empty:
            continue

        eligible[
            "_pit_eligible_snapshot_count"
        ] = (
            eligible.groupby(
                selection_keys,
                sort=False,
                dropna=False,
            )[
                "forecast_run_date"
            ]
            .transform(
                "size"
            )
            .astype(
                "Int16"
            )
        )

        eligible = (
            eligible.sort_values(
                selection_keys
                + [
                    "_pit_available_at_utc",
                    "forecast_run_date",
                    "forecast_horizon_days",
                ],
                kind="mergesort",
            )
        )

        chosen = (
            eligible.groupby(
                selection_keys,
                sort=True,
                dropna=False,
            )
            .tail(
                1
            )
            .copy()
        )

        chosen[
            "prediction_as_of_date"
        ] = prediction_date

        chosen[
            "prediction_cutoff_utc"
        ] = prediction_cutoff_utc

        chosen[
            "prediction_cutoff_time_utc"
        ] = cutoff_time

        chosen[
            "target_date"
        ] = chosen[
            "forecast_date"
        ]

        chosen[
            "selected_forecast_run_date"
        ] = chosen[
            "forecast_run_date"
        ]

        chosen[
            "selected_available_at_utc"
        ] = chosen[
            "_pit_available_at_utc"
        ]

        chosen[
            "selected_source_forecast_horizon_days"
        ] = chosen[
            "forecast_horizon_days"
        ].astype(
            "Int64"
        )

        chosen[
            "selected_forecast_run_age_days"
        ] = (
            prediction_date
            - chosen[
                "forecast_run_date"
            ]
        ).dt.days.astype(
            "Int64"
        )

        chosen[
            "selected_run_age_days"
        ] = chosen[
            "selected_forecast_run_age_days"
        ]

        chosen[
            "forecast_horizon_days"
        ] = (
            chosen[
                "forecast_date"
            ]
            - prediction_date
        ).dt.days.astype(
            "Int64"
        )

        chosen[
            "eligible_snapshot_count"
        ] = chosen[
            "_pit_eligible_snapshot_count"
        ].astype(
            "Int16"
        )

        chosen[
            "selection_rank"
        ] = 1

        chosen[
            "selection_method"
        ] = (
            "latest_available_at_or_before_prediction_cutoff"
        )

        chosen[
            "selection_availability_column"
        ] = availability_column

        chosen[
            "selection_availability_mode"
        ] = "timestamp_evidence"

        selected_parts.append(
            chosen
        )

    if selected_parts:
        result = pd.concat(
            selected_parts,
            ignore_index=True,
            sort=False,
        )

    else:
        result = frame.iloc[
            0:0
        ].copy()

    result = result.drop(
        columns=[
            "_pit_available_at_utc",
            "_pit_eligible_snapshot_count",
        ],
        errors="ignore",
    )

    grain = [
        "prediction_as_of_date",
        "forecast_date",
        "source_location_id",
        "forecast_horizon_days",
    ]

    result = (
        result.sort_values(
            grain,
            kind="mergesort",
        )
        .reset_index(
            drop=True
        )
    )

    if (
        not result.empty
        and result[
            grain
        ].isna().any().any()
    ):
        raise RuntimeError(
            "null weather_prediction_day_asof grain"
        )

    if result.duplicated(
        grain
    ).any():
        raise RuntimeError(
            "duplicate weather_prediction_day_asof grain"
        )

    if not result.empty:
        selected_available = (
            pd.to_datetime(
                result[
                    "selected_available_at_utc"
                ],
                errors="raise",
                utc=True,
            )
        )

        prediction_cutoff = (
            pd.to_datetime(
                result[
                    "prediction_cutoff_utc"
                ],
                errors="raise",
                utc=True,
            )
        )

        if (
            selected_available
            > prediction_cutoff
        ).any():
            raise RuntimeError(
                "point-in-time availability leakage"
            )

        horizons = result[
            "forecast_horizon_days"
        ].astype(
            "Int64"
        )

        if not horizons.between(
            0,
            9,
        ).all():
            raise RuntimeError(
                "prediction horizon outside 0..9"
            )

    return result


def output_sort_columns(
    output: str,
) -> list[str]:
    return {
        "weather_location_catalog": [
            "generic_location_rank",
            "source_location_id",
        ],
        "weather_observed_day": [
            "data",
            "source_location_id",
        ],
        "weather_forecast_snapshot": [
            "forecast_run_date",
            "forecast_date",
            "source_location_id",
            "forecast_horizon_days",
        ],
        "weather_observed_features_day": [
            "data",
            "source_location_id",
        ],
        "weather_forecast_features_snapshot": [
            "forecast_run_date",
            "forecast_date",
            "source_location_id",
            "forecast_horizon_days",
        ],
        "weather_climatology_causal": [
            "source_location_id",
            "month",
            "day_of_month",
        ],
        "weather_prediction_day_asof": [
            "prediction_as_of_date",
            "forecast_date",
            "source_location_id",
            "forecast_horizon_days",
        ],
    }[
        output
    ]



def output_partition_column(
    output: str,
) -> str | None:
    return {
        "weather_location_catalog": None,
        "weather_observed_day": (
            "data"
        ),
        "weather_forecast_snapshot": (
            "forecast_date"
        ),
        "weather_observed_features_day": (
            "data"
        ),
        "weather_forecast_features_snapshot": (
            "forecast_date"
        ),
        "weather_climatology_causal": None,
        "weather_prediction_day_asof": (
            "prediction_as_of_date"
        ),
    }[
        output
    ]



def write_output(
    output: str,
    frame: pd.DataFrame,
    run_dir: Path,
    zstd_level: int,
) -> dict[str, Any]:
    output_dir = run_dir / "outputs" / output
    output_dir.mkdir(
        parents=True,
        exist_ok=False,
    )
    sort_columns = output_sort_columns(output)
    frame = (
        frame.sort_values(
            sort_columns,
            kind="mergesort",
        )
        .reset_index(drop=True)
    )
    partition_column = output_partition_column(
        output
    )
    written_files: list[Path] = []

    if partition_column is None:
        groups = [(None, frame)]
    else:
        years = frame[
            partition_column
        ].dt.year.astype("Int64")
        months = frame[
            partition_column
        ].dt.month.astype("Int64")
        groups = list(
            frame.groupby(
                [years, months],
                sort=True,
                dropna=False,
            )
        )

    for partition_key, partition in groups:
        if partition_column is None:
            destination = (
                output_dir / "part-00000.parquet"
            )
        else:
            year, month = partition_key
            partition_dir = (
                output_dir
                / f"year={int(year):04d}"
                / f"month={int(month):02d}"
            )
            partition_dir.mkdir(
                parents=True,
                exist_ok=True,
            )
            destination = (
                partition_dir
                / "part-00000.parquet"
            )

        table = pa.Table.from_pandas(
            partition,
            preserve_index=False,
        )
        pq.write_table(
            table,
            destination,
            compression="zstd",
            compression_level=zstd_level,
            use_dictionary=True,
            write_statistics=True,
            row_group_size=131072,
        )
        written_files.append(destination)

    full_table = pa.Table.from_pandas(
        frame,
        preserve_index=False,
    )
    file_entries = [
        {
            "path": str(
                file.relative_to(run_dir)
            ),
            "size": file.stat().st_size,
            "sha256": sha256_file(file),
        }
        for file in sorted(written_files)
    ]
    schema_payload = [
        {
            "name": field.name,
            "type": str(field.type),
        }
        for field in full_table.schema
    ]
    return {
        "name": output,
        "row_count": int(len(frame)),
        "column_count": int(len(frame.columns)),
        "sort_columns": sort_columns,
        "partition_date_column": partition_column,
        "schema": schema_payload,
        "schema_fingerprint": canonical_fingerprint(
            schema_payload
        ),
        "content_fingerprint": canonical_fingerprint(
            file_entries
        ),
        "files": file_entries,
    }


def main() -> int:
    args = parse_args()
    load_contract(args.contract)

    if len(FEATURE_REGISTRY) != 640:
        raise RuntimeError(
            "embedded feature registry row count mismatch"
        )
    if len(SCHEMA_REGISTRY) != 10:
        raise RuntimeError(
            "embedded schema registry row count mismatch"
        )

    training_cutoff = parse_training_cutoff(
        args.training_cutoff
    )
    source_run = (
        args.source_run.expanduser().resolve()
    )
    output_root = (
        args.output_root.expanduser().resolve()
    )
    if not source_run.is_dir():
        raise FileNotFoundError(source_run)
    output_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    run_id = (
        args.run_id
        or (
            "gb_phase2m_e2_derived_long_"
            + datetime.now(
                timezone.utc
            ).strftime("%Y%m%d_%H%M%S")
            + f"_{os.getpid()}"
        )
    )
    candidate_dir = (
        output_root / f".candidate_{run_id}"
    )
    final_dir = output_root / run_id

    if candidate_dir.exists():
        raise FileExistsError(candidate_dir)
    if final_dir.exists():
        raise FileExistsError(final_dir)

    candidate_dir.mkdir(parents=True)

    try:
        observed = normalize_observed(source_run)
        forecast = normalize_forecast(source_run)
        catalog = build_location_catalog(
            observed,
            forecast,
        )
        observed_features = (
            build_observed_features(
                observed,
                catalog,
            )
        )
        forecast_features = (
            build_forecast_features(
                forecast,
                catalog,
            )
        )
        climatology = build_climatology(
            observed,
            catalog,
            training_cutoff,
        )

        prediction_asof = build_prediction_day_asof(
            forecast_features=forecast_features,
            prediction_cutoff_time_utc=(
                args.prediction_cutoff_time_utc
            ),
        )

        frames = {
            "weather_location_catalog": catalog,
            "weather_observed_day": observed,
            "weather_forecast_snapshot": forecast,
            "weather_observed_features_day": (
                observed_features
            ),
            "weather_forecast_features_snapshot": (
                forecast_features
            ),
            "weather_climatology_causal": climatology,
            "weather_prediction_day_asof": (
                prediction_asof
            ),
        }

        artifact_manifest = {}

        for output in MATERIALIZED_OUTPUTS:
            artifact = write_output(
                output=output,
                frame=frames[output],
                run_dir=candidate_dir,
                zstd_level=args.zstd_level,
            )
            artifact_manifest[output] = artifact
            print(
                "E2_OUTPUT"
                f"|name={output}"
                f"|rows={artifact['row_count']}"
                f"|columns={artifact['column_count']}"
                f"|content_fp={artifact['content_fingerprint']}"
            )

        feature_counts = {
            output: len(
                registry_rows(output)
            )
            for output in DERIVED_OUTPUTS
        }

        manifest = {
            "module": "phase2m_e2_weather",
            "implementation_phase": (
                IMPLEMENTATION_PHASE
            ),
            "status": "candidate",
            "run_id": run_id,
            "created_at_utc": datetime.now(
                timezone.utc
            ).isoformat(),
            "source_run": str(source_run),
            "contract_path": str(
                args.contract.resolve()
            ),
            "contract_fingerprint": (
                CONTRACT_FINGERPRINT
            ),
            "feature_registry_fingerprint": (
                FEATURE_REGISTRY_FINGERPRINT
            ),
            "schema_registry_fingerprint": (
                SCHEMA_REGISTRY_FINGERPRINT
            ),
            "training_cutoff_date": (
                training_cutoff.strftime(
                    "%Y-%m-%d"
                )
            ),
            "training_cutoff_version": (
                "cutoff_"
                + training_cutoff.strftime(
                    "%Y%m%d"
                )
            ),
            "primary_required": False,
            "generic_wide_required_in_final_e2": True,
            "implemented_output_count": len(
                MATERIALIZED_OUTPUTS
            ),
            "implemented_outputs": (
                MATERIALIZED_OUTPUTS
            ),
            "derived_feature_counts": (
                feature_counts
            ),
            "artifacts": artifact_manifest,
        }
        manifest[
            "prediction_cutoff_time_utc"
        ] = args.prediction_cutoff_time_utc

        manifest[
            "prediction_cutoff_mode"
        ] = (
            "timestamp_evidence_latest_eligible"
        )

        manifest["manifest_fingerprint"] = (
            canonical_fingerprint(manifest)
        )
        manifest_path = (
            candidate_dir / "manifest.json"
        )
        manifest_path.write_text(
            json.dumps(
                manifest,
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )

        # Release materialized parent DataFrames before
        # the independent validator reloads and recomputes
        # the same outputs in a child process.
        del (
            frames,
            observed,
            forecast,
            catalog,
            observed_features,
            forecast_features,
            climatology,
            prediction_asof,
        )
        gc.collect()

        validator = (
            Path(__file__)
            .resolve()
            .with_name(
                "weather_feature_validation.py"
            )
        )
        command = [
            sys.executable,
            str(validator),
            "--run-dir",
            str(candidate_dir),
            "--source-run",
            str(source_run),
            "--contract",
            str(args.contract.resolve()),
            "--prediction-cutoff-time-utc",
            args.prediction_cutoff_time_utc,
            "--expected-phase",
            IMPLEMENTATION_PHASE,
        ]
        validation = subprocess.run(
            command,
            check=False,
            text=True,
            capture_output=True,
        )
        (
            candidate_dir
            / "validator.stdout.log"
        ).write_text(
            validation.stdout,
            encoding="utf-8",
        )
        (
            candidate_dir
            / "validator.stderr.log"
        ).write_text(
            validation.stderr,
            encoding="utf-8",
        )
        print(validation.stdout, end="")
        if validation.returncode != 0:
            raise RuntimeError(
                "independent validator failed "
                f"rc={validation.returncode}: "
                f"{validation.stderr[-5000:]}"
            )

        manifest["status"] = "validated"
        manifest["validated_at_utc"] = (
            datetime.now(
                timezone.utc
            ).isoformat()
        )
        manifest["manifest_fingerprint"] = (
            canonical_fingerprint(
                {
                    key: value
                    for key, value
                    in manifest.items()
                    if key
                    != "manifest_fingerprint"
                }
            )
        )
        manifest_path.write_text(
            json.dumps(
                manifest,
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )

        os.replace(candidate_dir, final_dir)

        print(
            f"E2_POINT_IN_TIME_RUN={final_dir}"
        )
        print(
            "E2_POINT_IN_TIME_BUILD=SUCCESS"
        )
        return 0

    except Exception:
        if (
            candidate_dir.exists()
            and not args.keep_failed_candidate
        ):
            shutil.rmtree(
                candidate_dir,
                ignore_errors=True,
            )
        raise



if __name__ == "__main__":
    raise SystemExit(main())
