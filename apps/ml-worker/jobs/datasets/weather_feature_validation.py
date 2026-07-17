#!/usr/bin/env python3
"""Independent validator for Phase 2M-E2 canonical + derived-long outputs."""

from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import json
import re
from pathlib import Path
from typing import Any, Iterable

import numpy as np
import pandas as pd
import pyarrow.dataset as ds
import pyarrow.parquet as pq
import gc


CONTRACT_FINGERPRINT = "b9339f7a0bfa44ddb28becb76d853cf0f3a2dc6360dc1a867215646b11f8b4c4"
FEATURE_REGISTRY_FINGERPRINT = "0fc91c8b0b9fc10d275bc254b58b6278aef21b1187741ae0110ef441865478e9"
SCHEMA_REGISTRY_FINGERPRINT = "25e7f17e1708e73a9151863cf1f10b5afa6f7c7f329942992b361d2c0a0e151e"

_FEATURE_REGISTRY_B64 = "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"
_SCHEMA_REGISTRY_B64 = "H4sIAAAAAAAC/+2Z7Y6juBKGbyXqvz3SwWAMrLRXMjNCZbuceAdwlo/09K7m3k8RCKEDJpmP3iOtzmikFvaLXS6X6ymTj38/7Wuw1dNvTy8I7QHrvHAKWuuqvME2t/pZucrYfX7CuqHW54vsWDtjCyTF04cn17XHrl0bhP5A4fakadQBS8iNrfZYH2tb9fpIMw4ihjhFGQoUghmRhDLgAEqy1ISKRxELgywznKkgZVmmeJxIiFBIwPg67h+N61fx96cn5YqurJpPT7/tPn7yLevT04ddL52vbd7W1YN6Zu7QvVz/0N64rlZ4nebSPjXUrsCbpqZw46i2oQFtCfXr7VtQfRmatG2OBbzmFZSXcUjSdnoatdrPHltb4l+uGp+wwNMwYDmN1kJFBn8p89a9nZyWdrIa67dPeek0FuNiaTw1DIftwek1zw0OGXpOUFidm9qV8+fWTYsHGu1E4s/98zkif3T71vbn87enbx+uka4pJh+MYycbrE+ocw2vvhjOhEBUMotEGCcpV6GIDUsDxbNA6ETGkqOCcwAHoLVgAco0DSRGiosoNnwthucu6M3dWFvf8QVfyYeVzgtbIezR++ZPuXErzLdj5mwkhUpt1flc0grheIQaqzZvsTwixUxXY17C11z1ArLddfJyYNa1CNXjYruqVYXrdK7cqTe1H++o2qWK9r6w+0Ob6ym2kXymm0FKUSD4qMSX/OioIQ9Lr4HYBrkBl9OJPLqWDnhztOO4ZbmUH2tU9mjbQXEg/zf3RE1Xrg7VB5W/E/t8csL80JVW2/b1vAbakFWfrKu9LlyXW4+6Obi6fQGS16DtbE1/5GW4Iq/ci4GiOGvUytIaZwsKRUp5fSwEfcJL1GhuGdF/zyvzCHr71sq2Nl1V22Y4GsXQ3VDAV/upuz9zG70HOrv3Q2xu07hBK8bcqjw238rWT8klFyincWHPi6W0o2098oAFZa4dDQR0CDTu1/X7rmmbs7a3/0t5WJm01zVHpNzr1X3rhX92BJP2dUx5Q5KhlTQNOZdM7i7gnlI5nMAWMNvpc0Y70iF3QFMeIIzFmy6DLeVnerFdoMQ4Wjg0bV53FTGixeep5fy0TKNXAQW5JUL3aGnW2DMJmwqOdCRaL4BSA1Q0KQw5D4IUUikiFRiJmdQyFoQhkxoBgWH0LzA8hkhEScbDSMtIyugegBaLHLzzZqXb1Fhd8za7Hp/UM/j/sfePYe/9iUaelSBtf9D9THo3CHpd9MtB9a9lSHfKKaHj136yfythpkT0OGEmJcEl71r1pnUM97NPbrhDoa7t4A9ocmd8tNm80xg871qzdbkJmQkU8IDR9YYrhVECAQuECATEQcRjk6JOExAIqFQSgNRhYFQiuDYqjoxZY8s473RD7B0+tu1q3FOZVr/uBrN/3zR68NYcVat++bHL0wNDvRtWij6KZnfPy8RD06AlS2ekm8QHcp+rX+cx+L+oWaZtule8pCbUhmfcCA2SLsbCZEaFAAGwKJWJNEkSawrBOMYkCjBIgixEyFJtMsnCNP1VAea3fBll71sQ1fCSz4qGj9tFw91C4V5x4C8I7hQBD5DfS/sHCe+n+oLkD9D7AWKvUnqFzEsa3yGwH7sbqPXjdYnUJUYfYucWMLcgeZNT2v7vGYdd64zZ+Fr8rApbQusKt7fkuJE9i0RyVb3mCroGCl8CESbgEkTKeaiEZEQqFgsVpiFLUkhMmkWSQ6YwJiyhBmZUloDOZKIxEmkif1UCWVq8TBweN23niqXDtsG1Oclt5ztAbdXeR8qXuxg6X6vuMmg2OEloAme81U2cUsCEqBkPdCIgo/uz4TriTIo4oCInloGSUkIYZUmcKsmAK20QRZKqWGcbsTNW3cOXctS7C012l/5d/zl8iqbvKmW+AzRLly2vpT3RFI2W3+PMlmqWsrZk9kblJ8/Qf4c/g+gBCg1CL4vWur1EWhPPMTT0L+g0Nt9n1CB8gFSjcI1XY9eSWlPHDbuu7RsEG0R+jq33L0LDz7Shf0m2oX3Jt7H9EcrNpB7WzRRrxFv88AXD7yu3p3XMrNNt7pICck/ZePnK6P+Mdb1Yvqn5fffN64fDydqGwrRrfup2uXmV3Bd0VgrynUZfruVZJqnOVyoL6eaoMWZKhARmYnUkw0CkdAOQPNGM7pAMBOdMSUNKKRQwmYp7Xyk9+XLYtuHFuitGmCtyUX5iu8sCdmPe3OHXIxGVGvqMtLv8otnn78K1zY76dsOJAKoAYL+n/E3TkGe/H3CP0ey6ycSxR/xsMhUbgSFLRUhuDrnKdBhLE4DiYDSLlFGKJXECiZKK7lQQaCqGUhnRZZ7uYT/oZw+XvPzxbsllkH9mS1qo9+jdkGdPLbW2UcPbZEeLX9tHNiqTGYRAsR5nmoMKBRdUk2aGNjDMmIwYMGQKkCdMIR0TLqh0gIChFkZq0D+xUbNV+7dprVycCsD1PZyOU7/u3fN1L8fnWY086/3P9BpUroTCjpv3+b+8+w+PniIAAA=="

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate Phase 2M-E2 canonical and derived-long outputs."
        )
    )
    parser.add_argument(
        "--run-dir",
        required=True,
        type=Path,
    )
    parser.add_argument(
        "--source-run",
        required=True,
        type=Path,
    )
    parser.add_argument(
        "--contract",
        required=True,
        type=Path,
    )
    parser.add_argument(
        "--expected-phase",
        default="point_in_time",
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
    contract = json.loads(
        path.read_text(encoding="utf-8")
    )
    unsigned = dict(contract)
    declared = unsigned.pop(
        "final_contract_fingerprint",
        None,
    )
    actual = canonical_fingerprint(unsigned)
    if declared != CONTRACT_FINGERPRINT:
        raise AssertionError(
            "declared contract fingerprint mismatch"
        )
    if actual != CONTRACT_FINGERPRINT:
        raise AssertionError(
            "calculated contract fingerprint mismatch"
        )
    return contract


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
    raise KeyError(list(candidates))


def assert_unique(
    frame: pd.DataFrame,
    keys: list[str],
    label: str,
) -> None:
    if frame[keys].isna().any().any():
        raise AssertionError(
            f"{label} contains null grain keys"
        )
    if frame.duplicated(keys).any():
        raise AssertionError(
            f"{label} contains duplicate grain"
        )


def compare_series(
    expected: pd.Series,
    actual: pd.Series,
    label: str,
) -> None:
    if pd.api.types.is_bool_dtype(expected.dtype):
        left = expected.astype("boolean")
        right = actual.astype("boolean")
        if not left.equals(right):
            raise AssertionError(
                f"{label} boolean values differ"
            )
        return

    left = pd.to_numeric(
        expected,
        errors="coerce",
    ).to_numpy(
        dtype=float,
        na_value=np.nan,
    )
    right = pd.to_numeric(
        actual,
        errors="coerce",
    ).to_numpy(
        dtype=float,
        na_value=np.nan,
    )
    if not np.allclose(
        left,
        right,
        equal_nan=True,
        rtol=1e-9,
        atol=1e-9,
    ):
        mismatch = np.flatnonzero(
            ~np.isclose(
                left,
                right,
                equal_nan=True,
                rtol=1e-9,
                atol=1e-9,
            )
        )
        first = (
            int(mismatch[0])
            if len(mismatch)
            else -1
        )
        raise AssertionError(
            f"{label} numeric values differ "
            f"at position {first}"
        )


def validate_zstd(output_dir: Path) -> None:
    parquet_files = sorted(
        output_dir.rglob("*.parquet")
    )
    if not parquet_files:
        raise AssertionError(
            f"no files in {output_dir}"
        )
    for parquet_file in parquet_files:
        metadata = pq.read_metadata(parquet_file)
        for row_group_index in range(
            metadata.num_row_groups
        ):
            row_group = metadata.row_group(
                row_group_index
            )
            for column_index in range(
                row_group.num_columns
            ):
                column = row_group.column(
                    column_index
                )
                if str(
                    column.compression
                ).upper() != "ZSTD":
                    raise AssertionError(
                        "non-ZSTD Parquet column: "
                        f"{parquet_file} "
                        f"{column.path_in_schema}"
                    )


def normalize_raw_observed(
    source_run: Path,
) -> pd.DataFrame:
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
    frame["data"] = pd.to_datetime(
        frame["data"],
        errors="coerce",
    ).dt.normalize()
    frame["source_location_id"] = frame[
        "source_location_id"
    ].astype("string")
    return (
        frame.sort_values(
            ["data", "source_location_id"],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def normalize_raw_forecast(
    source_run: Path,
) -> pd.DataFrame:
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
    frame["forecast_run_date"] = pd.to_datetime(
        frame["forecast_run_date"],
        errors="coerce",
    ).dt.normalize()
    frame["forecast_date"] = pd.to_datetime(
        frame["forecast_date"],
        errors="coerce",
    ).dt.normalize()
    frame["source_location_id"] = frame[
        "source_location_id"
    ].astype("string")
    return (
        frame.sort_values(
            [
                "forecast_run_date",
                "forecast_date",
                "source_location_id",
            ],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def validate_observed_reproduction(
    source_run: Path,
    observed: pd.DataFrame,
) -> None:
    raw = normalize_raw_observed(source_run)
    normalized = (
        observed.sort_values(
            ["data", "source_location_id"],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )
    if len(raw) != len(normalized):
        raise AssertionError(
            "observed row count differs from source"
        )
    if not raw[
        ["data", "source_location_id"]
    ].equals(
        normalized[
            ["data", "source_location_id"]
        ]
    ):
        raise AssertionError(
            "observed grain differs from source"
        )
    for column in raw.columns:
        if (
            column in normalized.columns
            and pd.api.types.is_numeric_dtype(
                raw[column]
            )
        ):
            compare_series(
                raw[column],
                normalized[column],
                "observed reproduction " + column,
            )


def validate_forecast_reproduction(
    source_run: Path,
    forecast: pd.DataFrame,
) -> None:
    raw = normalize_raw_forecast(source_run)
    normalized = (
        forecast.sort_values(
            [
                "forecast_run_date",
                "forecast_date",
                "source_location_id",
            ],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )
    if len(raw) != len(normalized):
        raise AssertionError(
            "forecast row count differs from source"
        )
    if not raw[
        [
            "forecast_run_date",
            "forecast_date",
            "source_location_id",
        ]
    ].equals(
        normalized[
            [
                "forecast_run_date",
                "forecast_date",
                "source_location_id",
            ]
        ]
    ):
        raise AssertionError(
            "forecast grain differs from source"
        )
    for column in raw.columns:
        if (
            column in normalized.columns
            and pd.api.types.is_numeric_dtype(
                raw[column]
            )
        ):
            compare_series(
                raw[column],
                normalized[column],
                "forecast reproduction " + column,
            )
    expected_horizon = (
        normalized["forecast_date"]
        - normalized["forecast_run_date"]
    ).dt.days.astype("Int64")
    if not expected_horizon.equals(
        normalized[
            "forecast_horizon_days"
        ].astype("Int64")
    ):
        raise AssertionError(
            "forecast horizon arithmetic differs"
        )


def validate_catalog(
    catalog: pd.DataFrame,
    observed: pd.DataFrame,
    forecast: pd.DataFrame,
) -> None:
    expected_locations = sorted(
        set(observed["source_location_id"].dropna())
        | set(forecast["source_location_id"].dropna())
    )
    actual_locations = (
        catalog["source_location_id"]
        .astype("string")
        .tolist()
    )
    if actual_locations != expected_locations:
        raise AssertionError(
            "location catalog universe differs"
        )
    if catalog["source_location_id"].duplicated().any():
        raise AssertionError(
            "duplicate location catalog row"
        )
    if (
        catalog["generic_location_slot"]
        .dropna()
        .duplicated()
        .any()
    ):
        raise AssertionError(
            "duplicate generic location slot"
        )
    if catalog["is_primary"].fillna(False).any():
        raise AssertionError(
            "primary location was inferred"
        )
    expected_slots = [
        (
            f"loc_{rank:02d}"
            if rank <= 4
            else pd.NA
        )
        for rank in range(
            1,
            len(expected_locations) + 1,
        )
    ]
    actual_slots = catalog[
        "generic_location_slot"
    ].tolist()
    for expected, actual in zip(
        expected_slots,
        actual_slots,
    ):
        if pd.isna(expected):
            if not pd.isna(actual):
                raise AssertionError(
                    "overflow location received a slot"
                )
        elif expected != actual:
            raise AssertionError(
                "generic slot assignment differs"
            )


def assert_daily_contiguous(
    frame: pd.DataFrame,
) -> None:
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
            raise AssertionError(
                "non-daily observed history for "
                f"{location_id}"
            )


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
    raise AssertionError(
        f"unsupported feature dtype {dtype}"
    )


def attach_slots(
    frame: pd.DataFrame,
    catalog: pd.DataFrame,
) -> pd.DataFrame:
    return frame.merge(
        catalog[
            [
                "source_location_id",
                "generic_location_slot",
                "generic_location_rank",
            ]
        ],
        on="source_location_id",
        how="left",
        validate="many_to_one",
        sort=False,
    )


def shadow_rolling_numeric(
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
    for _, group in frame.groupby(
        "source_location_id",
        sort=False,
    ):
        index = group.index
        values = pd.to_numeric(
            group[metric],
            errors="coerce",
        )
        shifted = values.shift(1)
        roller = shifted.rolling(
            window=window,
            min_periods=min_periods,
        )
        if operation == "mean":
            value = roller.mean()
        elif operation == "min":
            value = roller.min()
        elif operation == "max":
            value = roller.max()
        elif operation == "std":
            value = roller.std(ddof=1)
        elif operation == "sum":
            value = roller.sum()
        elif operation == "valid_count":
            count = roller.count()
            value = count.where(
                count >= min_periods
            )
        elif operation == "nonzero_count":
            count = roller.count()
            value = (
                (
                    shifted.notna()
                    & shifted.ne(0)
                )
                .astype("float64")
                .rolling(
                    window=window,
                    min_periods=1,
                )
                .sum()
                .where(count >= min_periods)
            )
        else:
            raise AssertionError(operation)
        result.loc[index] = value.to_numpy()
    return result


_CONDITION_RE = re.compile(
    r"^\s*([a-zA-Z0-9_]+)\s*"
    r"(>=|<=|>|<)\s*"
    r"(-?[0-9]+(?:\.[0-9]+)?)\s*$"
)


def shadow_condition(
    frame: pd.DataFrame,
    text: str,
) -> pd.Series:
    match = _CONDITION_RE.match(text)
    if not match:
        raise AssertionError(
            f"unsupported condition {text}"
        )
    metric, operator, threshold_text = (
        match.groups()
    )
    values = pd.to_numeric(
        frame[metric],
        errors="coerce",
    )
    threshold = float(threshold_text)
    if operator == ">":
        result = values > threshold
    elif operator == ">=":
        result = values >= threshold
    elif operator == "<":
        result = values < threshold
    elif operator == "<=":
        result = values <= threshold
    else:
        raise AssertionError(operator)
    return result.fillna(False)


def shadow_event_count(
    frame: pd.DataFrame,
    condition: str,
    window: int,
) -> pd.Series:
    flags = shadow_condition(
        frame,
        condition,
    ).astype("int16")
    result = pd.Series(
        0,
        index=frame.index,
        dtype="int64",
    )
    for _, group in frame.groupby(
        "source_location_id",
        sort=False,
    ):
        index = group.index
        shifted = flags.loc[index].shift(
            1,
            fill_value=0,
        )
        value = (
            shifted.rolling(
                window,
                min_periods=1,
            )
            .sum()
            .fillna(0)
        )
        result.loc[index] = value.to_numpy()
    return result


def shadow_streak_flag(
    frame: pd.DataFrame,
    name: str,
) -> pd.Series:
    if "__dry_day__" in name:
        return (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            <= 0.1
        ).fillna(False)
    if "__rain_day__" in name:
        return (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            > 0.1
        ).fillna(False)
    if "__frost_day__" in name:
        return (
            pd.to_numeric(
                frame["temperature_2m_min_c"],
                errors="coerce",
            )
            <= 0
        ).fillna(False)
    if "__hot_day__" in name:
        return (
            pd.to_numeric(
                frame["temperature_2m_max_c"],
                errors="coerce",
            )
            >= 30
        ).fillna(False)
    if "__strong_wind_day__" in name:
        return (
            pd.to_numeric(
                frame["wind_speed_10m_max_kmh"],
                errors="coerce",
            )
            >= 40
        ).fillna(False)
    raise AssertionError(name)


def shadow_streak(
    frame: pd.DataFrame,
    flags: pd.Series,
) -> pd.Series:
    result = pd.Series(
        0,
        index=frame.index,
        dtype="int64",
    )
    for _, group in frame.groupby(
        "source_location_id",
        sort=False,
    ):
        index = group.index
        values = flags.loc[index].to_numpy(
            dtype=bool
        )
        current = 0
        ended = np.zeros(
            len(values),
            dtype=np.int64,
        )
        for position, value in enumerate(values):
            current = current + 1 if value else 0
            ended[position] = current
        shifted = np.concatenate(
            [
                np.array([0], dtype=np.int64),
                ended[:-1],
            ]
        )
        result.loc[index] = shifted
    return result


def recompute_observed_features(
    observed: pd.DataFrame,
    catalog: pd.DataFrame,
) -> pd.DataFrame:
    frame = attach_slots(
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

    values: dict[str, pd.Series] = {}

    for row in registry_rows(
        "weather_observed_features_day"
    ):
        name = row["feature_name"]
        family = row["family"]
        formula = row["formula"]

        if family == "lag":
            match = re.fullmatch(
                r"obs_lag_(\d+)d__(.+)",
                name,
            )
            if not match:
                raise AssertionError(name)
            days = int(match.group(1))
            metric = match.group(2)
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
                raise AssertionError(name)
            window = int(match.group(1))
            metric = match.group(2)
            operation = match.group(3)
            series = shadow_rolling_numeric(
                frame,
                metric,
                window,
                operation,
                MIN_PERIODS_BY_WINDOW[
                    window
                ],
            )

        elif family == "rolling_event":
            match = re.fullmatch(
                r"count\((.+)\) over previous (\d+) days",
                formula,
            )
            if not match:
                raise AssertionError(formula)
            series = shadow_event_count(
                frame,
                match.group(1).strip(),
                int(match.group(2)),
            )

        elif family == "streak":
            series = shadow_streak(
                frame,
                shadow_streak_flag(
                    frame,
                    name,
                ),
            )

        else:
            raise AssertionError(family)

        values[name] = cast_feature_series(
            series,
            row["dtype"],
        )

    return pd.DataFrame(
        values,
        index=frame.index,
    )


def shadow_safe_ratio(
    numerator: pd.Series,
    denominator: pd.Series,
) -> pd.Series:
    num = pd.to_numeric(
        numerator,
        errors="coerce",
    )
    den = pd.to_numeric(
        denominator,
        errors="coerce",
    )
    return num.div(
        den.where(den > 0)
    )


def shadow_forecast_derived(
    frame: pd.DataFrame,
    name: str,
) -> pd.Series:
    if name == "fcst_temperature_range_c":
        return (
            pd.to_numeric(
                frame["temperature_2m_max_c"],
                errors="coerce",
            )
            - pd.to_numeric(
                frame["temperature_2m_min_c"],
                errors="coerce",
            )
        )
    if name == "fcst_apparent_temperature_range_c":
        return (
            pd.to_numeric(
                frame["apparent_temperature_max_c"],
                errors="coerce",
            )
            - pd.to_numeric(
                frame["apparent_temperature_min_c"],
                errors="coerce",
            )
        )
    if name == (
        "fcst_apparent_minus_air_temperature_mean_c"
    ):
        return (
            pd.to_numeric(
                frame["apparent_temperature_mean_c"],
                errors="coerce",
            )
            - pd.to_numeric(
                frame["temperature_2m_mean_c"],
                errors="coerce",
            )
        )
    if name == "fcst_daylight_hours":
        return pd.to_numeric(
            frame["daylight_duration_seconds"],
            errors="coerce",
        ) / 3600.0
    if name == "fcst_sunshine_hours":
        return pd.to_numeric(
            frame["sunshine_duration_seconds"],
            errors="coerce",
        ) / 3600.0
    if name == "fcst_sunshine_fraction":
        return shadow_safe_ratio(
            frame["sunshine_duration_seconds"],
            frame["daylight_duration_seconds"],
        )
    if name == (
        "fcst_precipitation_intensity_mm_per_hour"
    ):
        return shadow_safe_ratio(
            frame["precipitation_sum_mm"],
            frame["precipitation_hours"],
        )
    if name == "fcst_rain_share_of_precipitation":
        return shadow_safe_ratio(
            frame["rain_sum_mm"],
            frame["precipitation_sum_mm"],
        )
    if name == "fcst_wind_direction_sin":
        return np.sin(
            np.deg2rad(
                pd.to_numeric(
                    frame[
                        "wind_direction_10m_dominant_deg"
                    ],
                    errors="coerce",
                )
            )
        )
    if name == "fcst_wind_direction_cos":
        return np.cos(
            np.deg2rad(
                pd.to_numeric(
                    frame[
                        "wind_direction_10m_dominant_deg"
                    ],
                    errors="coerce",
                )
            )
        )
    if name == "fcst_water_balance_mm":
        return (
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
        )
    if name == (
        "fcst_probability_weighted_precipitation_mm"
    ):
        return (
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
        )
    if name == "fcst_rain_day_flag":
        return (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            > 0.1
        ).astype("int8")
    if name == "fcst_heavy_rain_day_flag":
        return (
            pd.to_numeric(
                frame["precipitation_sum_mm"],
                errors="coerce",
            )
            >= 10.0
        ).astype("int8")
    if name == "fcst_snow_day_flag":
        return (
            pd.to_numeric(
                frame["snowfall_sum_cm"],
                errors="coerce",
            )
            > 0
        ).astype("int8")
    if name == "fcst_frost_day_flag":
        return (
            pd.to_numeric(
                frame["temperature_2m_min_c"],
                errors="coerce",
            )
            <= 0
        ).astype("int8")
    if name == "fcst_hot_day_flag":
        return (
            pd.to_numeric(
                frame["temperature_2m_max_c"],
                errors="coerce",
            )
            >= 30
        ).astype("int8")
    if name == "fcst_strong_wind_day_flag":
        return (
            pd.to_numeric(
                frame["wind_speed_10m_max_kmh"],
                errors="coerce",
            )
            >= 40
        ).astype("int8")
    raise AssertionError(name)


def recompute_forecast_features(
    forecast: pd.DataFrame,
    catalog: pd.DataFrame,
) -> pd.DataFrame:
    frame = attach_slots(
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
    metrics = sorted(
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
    keys = [
        "source_location_id",
        "forecast_date",
    ]
    previous = {
        metric: frame.groupby(
            keys,
            sort=False,
        )[metric].shift(1)
        for metric in metrics
    }
    previous_run = frame.groupby(
        keys,
        sort=False,
    )["forecast_run_date"].shift(1)
    values: dict[str, pd.Series] = {}

    for row in rows:
        name = row["feature_name"]
        if row["family"] == "forecast_derived":
            series = shadow_forecast_derived(
                frame,
                name,
            )
        elif name == (
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
                raise AssertionError(name)
            metric = match.group(1)
            delta = (
                pd.to_numeric(
                    frame[metric],
                    errors="coerce",
                )
                - pd.to_numeric(
                    previous[metric],
                    errors="coerce",
                )
            )
            series = (
                delta.abs()
                if match.group(2)
                == "abs_delta_previous_run"
                else delta
            )
        values[name] = cast_feature_series(
            pd.Series(
                series,
                index=frame.index,
            ),
            row["dtype"],
        )
    return pd.DataFrame(
        values,
        index=frame.index,
    )


def recompute_climatology(
    observed: pd.DataFrame,
    catalog: pd.DataFrame,
    cutoff: pd.Timestamp,
) -> pd.DataFrame:
    rows = registry_rows(
        "weather_climatology_causal"
    )
    history = observed[
        observed["data"] < cutoff
    ].copy()
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
        .str[:2]
        .astype("int8")
    )
    calendar["day_of_month"] = (
        calendar[
            "climatological_day"
        ]
        .str[3:5]
        .astype("int8")
    )
    locations["_cross"] = 1
    calendar["_cross"] = 1
    base = (
        locations.merge(
            calendar,
            on="_cross",
            how="inner",
        )
        .drop(columns="_cross")
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
    base["training_cutoff_date"] = cutoff
    base["training_cutoff_version"] = (
        "cutoff_" + cutoff.strftime("%Y%m%d")
    )

    group_keys = [
        "source_location_id",
        "climatological_day",
    ]
    values: dict[str, pd.Series] = {}

    for row in rows:
        name = row["feature_name"]
        match = re.fullmatch(
            r"clim__(.+)__"
            r"(mean|std|p10|p50|p90|valid_count|year_count)",
            name,
        )
        if not match:
            raise AssertionError(name)
        metric = match.group(1)
        statistic = match.group(2)

        metric_frame = history[
            group_keys
        ].copy()
        metric_frame["_value"] = pd.to_numeric(
            history[metric],
            errors="coerce",
        )
        metric_frame["_year"] = history[
            "observation_year"
        ].to_numpy()

        grouped = metric_frame.groupby(
            group_keys,
            sort=True,
        )
        if statistic == "mean":
            aggregate = grouped[
                "_value"
            ].mean().rename("_expected")
        elif statistic == "std":
            aggregate = grouped[
                "_value"
            ].std(ddof=1).rename("_expected")
        elif statistic == "p10":
            aggregate = grouped[
                "_value"
            ].quantile(0.10).rename("_expected")
        elif statistic == "p50":
            aggregate = grouped[
                "_value"
            ].quantile(0.50).rename("_expected")
        elif statistic == "p90":
            aggregate = grouped[
                "_value"
            ].quantile(0.90).rename("_expected")
        elif statistic == "valid_count":
            aggregate = grouped[
                "_value"
            ].count().rename("_expected")
        elif statistic == "year_count":
            aggregate = (
                metric_frame[
                    metric_frame["_value"].notna()
                ]
                .groupby(
                    group_keys,
                    sort=True,
                )["_year"]
                .nunique()
                .rename("_expected")
            )
        else:
            raise AssertionError(statistic)

        year_count = (
            metric_frame[
                metric_frame["_value"].notna()
            ]
            .groupby(
                group_keys,
                sort=True,
            )["_year"]
            .nunique()
            .rename("_years")
        )

        merged = (
            base[group_keys]
            .merge(
                aggregate.reset_index(),
                on=group_keys,
                how="left",
                validate="many_to_one",
            )
            .merge(
                year_count.reset_index(),
                on=group_keys,
                how="left",
                validate="many_to_one",
            )
        )
        series = merged["_expected"]
        if statistic in {
            "mean",
            "std",
            "p10",
            "p50",
            "p90",
        }:
            series = series.where(
                merged["_years"] >= 3
            )
        values[name] = cast_feature_series(
            pd.Series(
                series.to_numpy(),
                index=base.index,
            ),
            row["dtype"],
        )

    return pd.concat(
        [
            base,
            pd.DataFrame(
                values,
                index=base.index,
            ),
        ],
        axis=1,
    ).sort_values(
        [
            "training_cutoff_date",
            "source_location_id",
            "month",
            "day_of_month",
        ],
        kind="mergesort",
    ).reset_index(drop=True)


def validate_feature_columns(
    output: str,
    frame: pd.DataFrame,
    expected_count: int,
) -> list[str]:
    names = [
        row["feature_name"]
        for row in registry_rows(output)
    ]
    if len(names) != expected_count:
        raise AssertionError(
            f"{output} registry count mismatch"
        )
    missing = [
        name
        for name in names
        if name not in frame.columns
    ]
    if missing:
        raise AssertionError(
            f"{output} missing features {missing[:20]}"
        )
    if len(names) != len(set(names)):
        raise AssertionError(
            f"{output} duplicate registered names"
        )
    return names


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


def recompute_prediction_day_asof(
    forecast_features: pd.DataFrame,
    prediction_cutoff_time_utc: str,
) -> pd.DataFrame:
    cutoff_time = (
        parse_prediction_cutoff_time_utc(
            prediction_cutoff_time_utc
        )
    )

    source = forecast_features.copy()

    availability_column = next(
        (
            column
            for column in (
                "available_at_utc",
                "fetched_at",
                "source_fetched_at",
                "created_at",
            )
            if column in source.columns
        ),
        None,
    )

    if availability_column is None:
        raise AssertionError(
            "forecast availability timestamp unavailable"
        )

    for column in (
        "forecast_run_date",
        "forecast_date",
    ):
        source[
            column
        ] = (
            pd.to_datetime(
                source[
                    column
                ],
                errors="raise",
            )
            .dt.normalize()
        )

    source[
        "source_location_id"
    ] = source[
        "source_location_id"
    ].astype(
        "string"
    )

    source[
        "_validator_available_at_utc"
    ] = pd.to_datetime(
        source[
            availability_column
        ],
        errors="raise",
        utc=True,
    )

    group_columns = [
        "forecast_date",
        "source_location_id",
    ]

    selected_parts: list[
        pd.DataFrame
    ] = []

    prediction_dates = sorted(
        source[
            "forecast_run_date"
        ]
        .drop_duplicates()
        .tolist()
    )

    for prediction_date in (
        prediction_dates
    ):
        cutoff = pd.Timestamp(
            prediction_date.strftime(
                "%Y-%m-%d"
            )
            + "T"
            + cutoff_time
            + "Z"
        )

        eligible = source.loc[
            (
                source[
                    "_validator_available_at_utc"
                ]
                <= cutoff
            )
            & (
                source[
                    "forecast_date"
                ]
                >= prediction_date
            )
            & (
                source[
                    "forecast_date"
                ]
                <= (
                    prediction_date
                    + pd.Timedelta(
                        days=9
                    )
                )
            )
        ].copy()

        if eligible.empty:
            continue

        eligible[
            "_validator_eligible_count"
        ] = (
            eligible.groupby(
                group_columns,
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

        eligible = eligible.sort_values(
            group_columns
            + [
                "_validator_available_at_utc",
                "forecast_run_date",
                "forecast_horizon_days",
            ],
            kind="mergesort",
        )

        chosen = (
            eligible.groupby(
                group_columns,
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
        ] = cutoff

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
            "_validator_available_at_utc"
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
            "_validator_eligible_count"
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
        result = source.iloc[
            0:0
        ].copy()

    result = result.drop(
        columns=[
            "_validator_available_at_utc",
            "_validator_eligible_count",
        ],
        errors="ignore",
    )

    grain = [
        "prediction_as_of_date",
        "forecast_date",
        "source_location_id",
        "forecast_horizon_days",
    ]

    return (
        result.sort_values(
            grain,
            kind="mergesort",
        )
        .reset_index(
            drop=True
        )
    )


def compare_point_in_time_series(
    expected: pd.Series,
    actual: pd.Series,
    column: str,
) -> None:
    lowered = column.lower()

    datetime_like = (
        "date" in lowered
        or "_utc" in lowered
        or "fetched_at" in lowered
        or "available_at" in lowered
    )

    if datetime_like:
        use_utc = (
            "_utc" in lowered
            or "fetched_at" in lowered
            or "available_at" in lowered
        )

        expected_values = pd.to_datetime(
            expected,
            errors="coerce",
            utc=use_utc,
        )

        actual_values = pd.to_datetime(
            actual,
            errors="coerce",
            utc=use_utc,
        )

        effective_use_utc = (
            use_utc
            or isinstance(
                expected_values.dtype,
                pd.DatetimeTZDtype,
            )
            or isinstance(
                actual_values.dtype,
                pd.DatetimeTZDtype,
            )
        )

        if effective_use_utc:
            expected_values = pd.Series(
                pd.to_datetime(
                    expected_values,
                    errors="coerce",
                    utc=True,
                )
            ).astype(
                "datetime64[ns, UTC]"
            )

            actual_values = pd.Series(
                pd.to_datetime(
                    actual_values,
                    errors="coerce",
                    utc=True,
                )
            ).astype(
                "datetime64[ns, UTC]"
            )

        else:
            expected_values = pd.Series(
                expected_values
            ).astype(
                "datetime64[ns]"
            )

            actual_values = pd.Series(
                actual_values
            ).astype(
                "datetime64[ns]"
            )

        if not expected_values.equals(
            actual_values
        ):
            raise AssertionError(
                "point-in-time datetime differs: "
                + column
            )

        return

    if (
        pd.api.types.is_numeric_dtype(
            expected
        )
        or pd.api.types.is_numeric_dtype(
            actual
        )
    ):
        expected_values = pd.to_numeric(
            expected,
            errors="coerce",
        ).to_numpy(
            dtype=float,
            na_value=np.nan,
        )

        actual_values = pd.to_numeric(
            actual,
            errors="coerce",
        ).to_numpy(
            dtype=float,
            na_value=np.nan,
        )

        if not np.allclose(
            expected_values,
            actual_values,
            equal_nan=True,
            rtol=1e-9,
            atol=1e-9,
        ):
            raise AssertionError(
                "point-in-time numeric differs: "
                + column
            )

        return

    expected_values = (
        expected.astype(
            "string"
        )
        .fillna(
            "<NA>"
        )
        .tolist()
    )

    actual_values = (
        actual.astype(
            "string"
        )
        .fillna(
            "<NA>"
        )
        .tolist()
    )

    if expected_values != actual_values:
        raise AssertionError(
            "point-in-time values differ: "
            + column
        )


def validate_prediction_day_asof(
    expected: pd.DataFrame,
    actual: pd.DataFrame,
    prediction_cutoff_time_utc: str,
) -> None:
    cutoff_time = (
        parse_prediction_cutoff_time_utc(
            prediction_cutoff_time_utc
        )
    )

    grain = [
        "prediction_as_of_date",
        "forecast_date",
        "source_location_id",
        "forecast_horizon_days",
    ]

    missing_columns = sorted(
        set(
            expected.columns
        )
        - set(
            actual.columns
        )
    )

    if missing_columns:
        raise AssertionError(
            "weather_prediction_day_asof missing columns: "
            + ", ".join(
                missing_columns[
                    :30
                ]
            )
        )

    expected_sorted = (
        expected.sort_values(
            grain,
            kind="mergesort",
        )
        .reset_index(
            drop=True
        )
    )

    actual_sorted = (
        actual.sort_values(
            grain,
            kind="mergesort",
        )
        .reset_index(
            drop=True
        )
    )

    if len(
        expected_sorted
    ) != len(
        actual_sorted
    ):
        raise AssertionError(
            "weather_prediction_day_asof row count differs"
        )

    if actual_sorted.duplicated(
        grain
    ).any():
        raise AssertionError(
            "duplicate weather_prediction_day_asof grain"
        )

    for column in (
        expected_sorted.columns
    ):
        compare_point_in_time_series(
            expected_sorted[
                column
            ],
            actual_sorted[
                column
            ],
            column,
        )

    selected_available = pd.to_datetime(
        actual_sorted[
            "selected_available_at_utc"
        ],
        errors="raise",
        utc=True,
    )

    prediction_cutoff = pd.to_datetime(
        actual_sorted[
            "prediction_cutoff_utc"
        ],
        errors="raise",
        utc=True,
    )

    if (
        selected_available
        > prediction_cutoff
    ).any():
        raise AssertionError(
            "point-in-time availability leakage"
        )

    actual_cutoff_values = set(
        actual_sorted[
            "prediction_cutoff_time_utc"
        ]
        .astype(
            "string"
        )
        .dropna()
    )

    if actual_cutoff_values != {
        cutoff_time
    }:
        raise AssertionError(
            "prediction cutoff metadata differs"
        )

    horizons = actual_sorted[
        "forecast_horizon_days"
    ].astype(
        "Int64"
    )

    if not horizons.between(
        0,
        9,
    ).all():
        raise AssertionError(
            "point-in-time horizon outside 0..9"
        )


class SequentialOutputMapping:
    """Read one materialized output on each access without caching."""

    def __init__(
        self,
        output_names,
        loader,
    ):
        self._output_names = tuple(
            output_names
        )
        self._output_name_set = set(
            self._output_names
        )
        self._loader = loader

    def __getitem__(
        self,
        key,
    ):
        if key not in self._output_name_set:
            raise KeyError(key)

        return self._loader(key)

    def __iter__(self):
        return iter(
            self._output_names
        )

    def __len__(self):
        return len(
            self._output_names
        )

    def keys(self):
        return self._output_names

    def values(self):
        for key in self._output_names:
            yield self._loader(key)

    def items(self):
        for key in self._output_names:
            yield key, self._loader(key)

    def get(
        self,
        key,
        default=None,
    ):
        if key not in self._output_name_set:
            return default

        return self._loader(key)


def main() -> int:
    args = parse_args()
    load_contract(args.contract)
    if len(FEATURE_REGISTRY) != 640:
        raise AssertionError('embedded feature registry mismatch')
    if len(SCHEMA_REGISTRY) != 10:
        raise AssertionError('embedded schema registry mismatch')
    run_dir = args.run_dir.expanduser().resolve()
    source_run = args.source_run.expanduser().resolve()
    manifest = json.loads((run_dir / 'manifest.json').read_text(encoding='utf-8'))
    if manifest['implementation_phase'] != args.expected_phase:
        raise AssertionError('unexpected implementation phase')
    if manifest['contract_fingerprint'] != CONTRACT_FINGERPRINT:
        raise AssertionError('manifest contract mismatch')
    if manifest['feature_registry_fingerprint'] != FEATURE_REGISTRY_FINGERPRINT:
        raise AssertionError('manifest feature registry mismatch')
    if manifest['schema_registry_fingerprint'] != SCHEMA_REGISTRY_FINGERPRINT:
        raise AssertionError('manifest schema registry mismatch')
    if manifest['implemented_outputs'] != MATERIALIZED_OUTPUTS:
        raise AssertionError('materialized output list mismatch')
    outputs = SequentialOutputMapping(output_names=MATERIALIZED_OUTPUTS, loader=lambda output: read_parquet_tree(run_dir / 'outputs' / output))
    observed = outputs['weather_observed_day']
    observed_features = outputs['weather_observed_features_day']
    for frame in (observed, observed_features):
        frame['data'] = pd.to_datetime(frame['data'], errors='raise').dt.normalize()
    forecast = outputs['weather_forecast_snapshot']
    forecast_features = outputs['weather_forecast_features_snapshot']
    for frame in (forecast, forecast_features):
        frame['forecast_run_date'] = pd.to_datetime(frame['forecast_run_date'], errors='raise').dt.normalize()
        frame['forecast_date'] = pd.to_datetime(frame['forecast_date'], errors='raise').dt.normalize()
        frame['available_at_utc'] = pd.to_datetime(frame['available_at_utc'], errors='raise', utc=True)
    climatology = outputs['weather_climatology_causal']
    climatology['training_cutoff_date'] = pd.to_datetime(climatology['training_cutoff_date'], errors='raise').dt.normalize()
    assert_unique(observed, ['data', 'source_location_id'], 'weather_observed_day')
    assert_unique(forecast, ['forecast_run_date', 'forecast_date', 'source_location_id', 'forecast_horizon_days'], 'weather_forecast_snapshot')
    assert_unique(observed_features, ['data', 'source_location_id'], 'weather_observed_features_day')
    assert_unique(forecast_features, ['forecast_run_date', 'forecast_date', 'source_location_id', 'forecast_horizon_days'], 'weather_forecast_features_snapshot')
    assert_unique(climatology, ['training_cutoff_date', 'source_location_id', 'climatological_day'], 'weather_climatology_causal')
    validate_observed_reproduction(source_run, observed)
    validate_forecast_reproduction(source_run, forecast)
    catalog = outputs['weather_location_catalog']
    validate_catalog(catalog, observed, forecast)
    observed_names = validate_feature_columns('weather_observed_features_day', observed_features, 521)
    forecast_names = validate_feature_columns('weather_forecast_features_snapshot', forecast_features, 35)
    climatology_names = validate_feature_columns('weather_climatology_causal', climatology, 84)
    if len(observed_features) != len(observed):
        raise AssertionError('observed feature row count mismatch')
    if len(forecast_features) != len(forecast):
        raise AssertionError('forecast feature row count mismatch')
    expected_observed = recompute_observed_features(observed, catalog)
    actual_observed = observed_features.sort_values(['source_location_id', 'data'], kind='mergesort').reset_index(drop=True)
    del observed_features
    gc.collect()
    for name in observed_names:
        compare_series(expected_observed[name], actual_observed[name], 'observed feature ' + name)
    del expected_observed
    gc.collect()
    expected_forecast = recompute_forecast_features(forecast, catalog)
    del forecast
    gc.collect()
    actual_forecast = forecast_features.sort_values(['source_location_id', 'forecast_date', 'forecast_run_date', 'available_at_utc'], kind='mergesort').reset_index(drop=True)
    del forecast_features
    gc.collect()
    for name in forecast_names:
        compare_series(expected_forecast[name], actual_forecast[name], 'forecast feature ' + name)
    del expected_forecast
    gc.collect()
    cutoff = pd.Timestamp(manifest['training_cutoff_date']).normalize()
    expected_climatology = recompute_climatology(observed, catalog, cutoff)
    del catalog, observed
    gc.collect()
    actual_climatology = climatology.sort_values(['training_cutoff_date', 'source_location_id', 'month', 'day_of_month'], kind='mergesort').reset_index(drop=True)
    del climatology
    gc.collect()
    if len(actual_climatology) != len(expected_climatology):
        raise AssertionError('climatology row count mismatch')
    for name in climatology_names:
        compare_series(expected_climatology[name], actual_climatology[name], 'climatology feature ' + name)
    del expected_climatology
    gc.collect()
    for output in MATERIALIZED_OUTPUTS:
        validate_zstd(run_dir / 'outputs' / output)
        artifact = manifest['artifacts'][output]
        if artifact['row_count'] != len(outputs[output]):
            raise AssertionError(f'{output} manifest row count mismatch')
        if not artifact['schema_fingerprint']:
            raise AssertionError(f'{output} schema fingerprint missing')
        if not artifact['content_fingerprint']:
            raise AssertionError(f'{output} content fingerprint missing')
    expected_prediction_asof = recompute_prediction_day_asof(forecast_features=outputs['weather_forecast_features_snapshot'], prediction_cutoff_time_utc=args.prediction_cutoff_time_utc)
    validate_prediction_day_asof(expected=expected_prediction_asof, actual=outputs['weather_prediction_day_asof'], prediction_cutoff_time_utc=args.prediction_cutoff_time_utc)
    del expected_prediction_asof
    gc.collect()
    report = {'ok': True, 'decision': 'PHASE2M_E2_POINT_IN_TIME_VALIDATION_OK', 'implementation_phase': args.expected_phase, 'contract_fingerprint': CONTRACT_FINGERPRINT, 'feature_registry_fingerprint': FEATURE_REGISTRY_FINGERPRINT, 'schema_registry_fingerprint': SCHEMA_REGISTRY_FINGERPRINT, 'training_cutoff_date': manifest['training_cutoff_date'], 'primary_required': False, 'generic_wide_required_in_final_e2': True, 'feature_counts': {'weather_observed_features_day': 521, 'weather_forecast_features_snapshot': 35, 'weather_climatology_causal': 84}, 'output_rows': {output: int(len(frame)) for (output, frame) in outputs.items()}, 'full_feature_recomputation': True, 'causal_window_validation': True, 'forecast_revision_validation': True, 'climatology_cutoff_validation': True}
    (run_dir / 'validation_report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print('E2_POINT_IN_TIME_VALIDATION_DECISION=PHASE2M_E2_POINT_IN_TIME_VALIDATION_OK')
    print('E2_POINT_IN_TIME_FULL_RECOMPUTATION=SUCCESS')
    print('E2_POINT_IN_TIME_INDEPENDENT_VALIDATION=SUCCESS')
    return 0




if __name__ == "__main__":
    raise SystemExit(main())
