#!/usr/bin/env python3
from __future__ import annotations

import argparse
import calendar
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Callable, Iterable

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.dataset as ds
import pyarrow.parquet as pq


PROGRAM_ROLE = "builder"
SUCCESS_DECISION = "CALENDAR_FEATURE_PLAN_OK"

PRE_WINDOW_LIMITS = (
    90,
    60,
    45,
    30,
    21,
    14,
    7,
    3,
    1,
)

POST_WINDOW_LIMITS = (
    1,
    3,
    7,
    14,
    30,
)


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def canonicalize_value(value: Any) -> Any:
    if isinstance(value, date):
        return value.isoformat()

    if isinstance(value, float):
        return value.hex()

    if isinstance(value, list):
        return [
            canonicalize_value(item)
            for item in value
        ]

    if isinstance(value, dict):
        return {
            key: canonicalize_value(item)
            for key, item in sorted(
                value.items()
            )
        }

    return value


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return hashlib.sha256(
        path.read_bytes()
    ).hexdigest()


def schema_fingerprint(
    dataset_name: str,
    grain: list[str],
    sort_order: list[str],
    fields: list[dict[str, Any]],
) -> str:
    payload = {
        "dataset": dataset_name,
        "grain": grain,
        "sort_order": sort_order,
        "fields": fields,
    }

    return sha256_bytes(
        canonical_json(payload).encode(
            "utf-8"
        )
    )


def rows_fingerprint(
    rows: Iterable[dict[str, Any]],
    ordered_columns: list[str],
) -> str:
    hasher = hashlib.sha256()

    for row in rows:
        payload = [
            canonicalize_value(
                row.get(column)
            )
            for column in ordered_columns
        ]

        hasher.update(
            canonical_json(payload).encode(
                "utf-8"
            )
        )
        hasher.update(b"\n")

    return hasher.hexdigest()


def package_fingerprint(
    payload: dict[str, Any],
) -> str:
    copy = dict(payload)
    copy.pop(
        "source_package_fingerprint",
        None,
    )

    return sha256_bytes(
        canonical_json(copy).encode(
            "utf-8"
        )
    )


def read_json(path: Path) -> Any:
    return json.loads(
        path.read_text(encoding="utf-8")
    )


def write_json_atomic(
    path: Path,
    payload: Any,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    encoded = (
        json.dumps(
            payload,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
            default=str,
        )
        + "\n"
    ).encode("utf-8")

    with tempfile.NamedTemporaryFile(
        mode="wb",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        candidate = Path(handle.name)
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())

    try:
        os.chmod(candidate, 0o644)
        os.replace(candidate, path)
    finally:
        if candidate.exists():
            candidate.unlink()


def normalize_date(value: Any) -> date | None:
    if value is None:
        return None

    if isinstance(value, datetime):
        return value.date()

    if isinstance(value, date):
        return value

    text = str(value).strip()

    if not text:
        return None

    try:
        return date.fromisoformat(
            text[:10]
        )
    except ValueError:
        return None


def normalize_text(value: Any) -> str:
    if value is None:
        return ""

    return " ".join(
        str(value).strip().split()
    )


def date_range(
    start: date,
    end: date,
) -> list[date]:
    output = []
    current = start

    while current <= end:
        output.append(current)
        current += timedelta(days=1)

    return output


def easter_sunday(year: int) -> date:
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3

    h = (
        19 * a
        + b
        - d
        - g
        + 15
    ) % 30

    i = c // 4
    k = c % 4

    l = (
        32
        + 2 * e
        + 2 * i
        - h
        - k
    ) % 7

    m = (
        a
        + 11 * h
        + 22 * l
    ) // 451

    month = (
        h
        + l
        - 7 * m
        + 114
    ) // 31

    day = (
        (
            h
            + l
            - 7 * m
            + 114
        )
        % 31
    ) + 1

    return date(year, month, day)


def nth_weekday_of_month(
    year: int,
    month: int,
    iso_weekday: int,
    nth: int,
) -> date:
    first = date(year, month, 1)

    delta = (
        iso_weekday
        - first.isoweekday()
    ) % 7

    result = first + timedelta(
        days=delta + 7 * (nth - 1)
    )

    if result.month != month:
        raise ValueError(
            "nth weekday falls outside month"
        )

    return result


def weekday_on_or_after(
    year: int,
    month: int,
    day: int,
    iso_weekday: int,
) -> date:
    base = date(year, month, day)

    delta = (
        iso_weekday
        - base.isoweekday()
    ) % 7

    return base + timedelta(days=delta)


def occurrence_for_year(
    event: dict[str, Any],
    year: int,
) -> date:
    rule_type = event["rule_type"]
    params = event["rule_params"]

    if rule_type == "fixed_month_day":
        return date(
            year,
            int(params["month"]),
            int(params["day"]),
        )

    if rule_type == "easter_offset":
        return easter_sunday(year) + timedelta(
            days=int(
                params["offset_days"]
            )
        )

    if rule_type == "nth_weekday_of_month":
        return nth_weekday_of_month(
            year,
            int(params["month"]),
            int(params["iso_weekday"]),
            int(params["nth"]),
        )

    if rule_type == "day_after_nth_weekday":
        base = nth_weekday_of_month(
            year,
            int(params["month"]),
            int(params["iso_weekday"]),
            int(params["nth"]),
        )

        return base + timedelta(
            days=int(
                params["offset_days"]
            )
        )

    if rule_type == "weekday_on_or_after":
        return weekday_on_or_after(
            year,
            int(params["month"]),
            int(params["day"]),
            int(params["iso_weekday"]),
        )

    raise ValueError(
        f"unsupported rule type: {rule_type}"
    )


def event_is_valid(
    event: dict[str, Any],
    occurrence: date,
) -> bool:
    valid_from = (
        date.fromisoformat(
            event["valid_from"]
        )
        if event.get("valid_from")
        else None
    )

    valid_to = (
        date.fromisoformat(
            event["valid_to"]
        )
        if event.get("valid_to")
        else None
    )

    if (
        valid_from is not None
        and occurrence < valid_from
    ):
        return False

    if (
        valid_to is not None
        and occurrence > valid_to
    ):
        return False

    return True


def find_dense_files(
    root: Path,
    grain: str,
) -> list[Path]:
    files = sorted(
        root.rglob("*.parquet")
    )

    if grain == "family_day_dense":
        selected = [
            path
            for path in files
            if (
                "family_day_dense"
                in str(path).lower()
                and "priceband"
                not in str(path).lower()
            )
        ]

        if not selected:
            selected = [
                path
                for path in files
                if (
                    "family_day"
                    in str(path).lower()
                    and "priceband"
                    not in str(path).lower()
                )
            ]

        return selected

    selected = [
        path
        for path in files
        if (
            "family_priceband_day_dense"
            in str(path).lower()
        )
    ]

    if not selected:
        selected = [
            path
            for path in files
            if (
                "family" in str(path).lower()
                and "priceband"
                in str(path).lower()
                and "dense"
                in str(path).lower()
            )
        ]

    return selected


def unique_dates_from_files(
    files: list[Path],
) -> tuple[list[date], int]:
    if not files:
        raise RuntimeError(
            "dense Parquet files not found"
        )

    dataset = ds.dataset(
        [str(path) for path in files],
        format="parquet",
    )

    if "data" not in dataset.schema.names:
        raise RuntimeError(
            "canonical data column absent"
        )

    table = dataset.to_table(
        columns=["data"]
    )

    if table["data"].null_count:
        raise RuntimeError(
            "dense date spine contains nulls"
        )

    dates = sorted(
        {
            normalize_date(value)
            for value in pc.unique(
                table["data"]
            ).to_pylist()
        }
    )

    if None in dates:
        raise RuntimeError(
            "invalid date value in dense spine"
        )

    return dates, table.num_rows


def load_and_validate_packages(
    profile_path: Path,
    contract_path: Path,
) -> tuple[
    dict[str, Any],
    dict[str, Any],
]:
    profile = read_json(profile_path)
    contract = read_json(contract_path)

    actual_profile_fp = package_fingerprint(
        profile
    )

    expected_profile_fp = profile.get(
        "source_package_fingerprint"
    )

    if actual_profile_fp != expected_profile_fp:
        raise RuntimeError(
            "profile package fingerprint mismatch"
        )

    actual_contract_fp = package_fingerprint(
        contract
    )

    expected_contract_fp = contract.get(
        "source_package_fingerprint"
    )

    if actual_contract_fp != expected_contract_fp:
        raise RuntimeError(
            "contract package fingerprint mismatch"
        )

    required_profile_fp = contract[
        "runtime_requirements"
    ][
        "profile_fingerprint_required"
    ]

    if required_profile_fp != expected_profile_fp:
        raise RuntimeError(
            "contract/profile fingerprint linkage mismatch"
        )

    profile_id = profile[
        "calendar_profile_id"
    ]

    contract_profile_id = contract[
        "calendar_profile"
    ][
        "calendar_profile_id"
    ]

    if profile_id != contract_profile_id:
        raise RuntimeError(
            "calendar profile ID mismatch"
        )

    if profile["event_count"] != len(
        profile["events"]
    ):
        raise RuntimeError(
            "profile event count mismatch"
        )

    if profile[
        "raw_alias_policy"
    ][
        "created_at_used_as_known_from"
    ] is not False:
        raise RuntimeError(
            "created_at policy violation"
        )

    if contract[
        "raw_holiday_policy"
    ][
        "canonical"
    ] is not False:
        raise RuntimeError(
            "raw holidays must not be canonical"
        )

    return profile, contract


def load_date_spine(
    b2_run: Path,
) -> tuple[
    list[date],
    dict[str, Any],
]:
    family_files = find_dense_files(
        b2_run,
        "family_day_dense",
    )

    pair_files = find_dense_files(
        b2_run,
        "family_priceband_day_dense",
    )

    family_dates, family_rows = (
        unique_dates_from_files(
            family_files
        )
    )

    pair_dates, pair_rows = (
        unique_dates_from_files(
            pair_files
        )
    )

    if family_dates != pair_dates:
        raise RuntimeError(
            "B2 dense grains have different date spines"
        )

    if not family_dates:
        raise RuntimeError(
            "B2 date spine is empty"
        )

    expected_count = (
        family_dates[-1]
        - family_dates[0]
    ).days + 1

    if len(family_dates) != expected_count:
        raise RuntimeError(
            "B2 date spine is not contiguous"
        )

    return (
        family_dates,
        {
            "family_day_dense": {
                "file_count": len(
                    family_files
                ),
                "row_count": family_rows,
            },
            "family_priceband_day_dense": {
                "file_count": len(
                    pair_files
                ),
                "row_count": pair_rows,
            },
        },
    )


def build_catalog_rows(
    profile: dict[str, Any],
    contract: dict[str, Any],
) -> list[dict[str, Any]]:
    schema = next(
        item["schema"]
        for item in contract["outputs"]
        if item["name"]
        == "calendar_event_catalog"
    )

    columns = [
        field["name"]
        for field in schema
    ]

    rows = []

    for event in sorted(
        profile["events"],
        key=lambda item: item["event_id"],
    ):
        row = dict(event)

        row["rule_params"] = canonical_json(
            row["rule_params"]
        )

        for date_field in (
            "valid_from",
            "valid_to",
        ):
            value = row.get(date_field)

            if isinstance(value, str):
                row[date_field] = (
                    date.fromisoformat(value)
                )

        rows.append(
            {
                column: row.get(column)
                for column in columns
            }
        )

    return rows


def generate_occurrences(
    profile: dict[str, Any],
    contract: dict[str, Any],
    start_date: date,
    end_date: date,
) -> tuple[
    list[dict[str, Any]],
    list[dict[str, Any]],
]:
    schema = next(
        item["schema"]
        for item in contract["outputs"]
        if item["name"]
        == "calendar_event_occurrences"
    )

    columns = [
        field["name"]
        for field in schema
    ]

    profile_id = profile[
        "calendar_profile_id"
    ]

    buffer_start = (
        start_date - timedelta(days=120)
    )

    buffer_end = (
        end_date + timedelta(days=120)
    )

    all_occurrences = []
    active_occurrences = []

    for event in profile["events"]:
        for year in range(
            buffer_start.year,
            buffer_end.year + 1,
        ):
            occurrence_date = (
                occurrence_for_year(
                    event,
                    year,
                )
            )

            if not event_is_valid(
                event,
                occurrence_date,
            ):
                continue

            if not (
                buffer_start
                <= occurrence_date
                <= buffer_end
            ):
                continue

            raw_row = {
                "calendar_profile_id": (
                    profile_id
                ),
                "event_id": (
                    event["event_id"]
                ),
                "occurrence_date": (
                    occurrence_date
                ),
                "occurrence_year": year,
                "event_category": (
                    event["category"]
                ),
                "priority": (
                    event["priority"]
                ),
                "is_national_public_holiday": (
                    event[
                        "is_national_public_holiday"
                    ]
                ),
                "is_local_patron_day": (
                    event[
                        "is_local_patron_day"
                    ]
                ),
                "is_religious_observance": (
                    event[
                        "is_religious_observance"
                    ]
                ),
                "is_family_gifting": (
                    event[
                        "is_family_gifting"
                    ]
                ),
                "is_commercial_retail": (
                    event[
                        "is_commercial_retail"
                    ]
                ),
                "is_environmental_event": (
                    event[
                        "is_environmental_event"
                    ]
                ),
                "is_model_relevant": (
                    event[
                        "is_model_relevant"
                    ]
                ),
                "source_type": (
                    event["source_type"]
                ),
                "source_version": (
                    event["source_version"]
                ),
                "rule_type": (
                    event["rule_type"]
                ),
                "availability_mode": (
                    event[
                        "availability_mode"
                    ]
                ),
                "known_from_date": (
                    event["known_from_date"]
                ),
            }

            row = {
                column: raw_row.get(column)
                for column in columns
            }

            all_occurrences.append(row)

            if event[
                "active_for_profile"
            ]:
                active_occurrences.append(
                    row
                )

    sort_key = lambda row: (
        row["occurrence_date"],
        row["event_id"],
    )

    all_occurrences.sort(
        key=sort_key
    )

    active_occurrences.sort(
        key=sort_key
    )

    keys = [
        (
            row["calendar_profile_id"],
            row["event_id"],
            row["occurrence_date"],
        )
        for row in active_occurrences
    ]

    if len(keys) != len(set(keys)):
        raise RuntimeError(
            "duplicate active occurrence keys"
        )

    return (
        all_occurrences,
        active_occurrences,
    )


def reconcile_raw_holidays(
    raw_holidays: Path,
    profile: dict[str, Any],
) -> dict[str, Any]:
    aliases: dict[str, str] = {}

    for event in profile["events"]:
        for raw_name in event.get(
            "raw_names",
            [],
        ):
            if raw_name in aliases:
                raise RuntimeError(
                    "ambiguous raw holiday alias"
                )

            aliases[raw_name] = (
                event["event_id"]
            )

    events_by_id = {
        event["event_id"]: event
        for event in profile["events"]
    }

    schema_names = pq.ParquetFile(
        raw_holidays
    ).schema_arrow.names

    required = {
        "data",
        "holiday_name",
    }

    if not required.issubset(
        set(schema_names)
    ):
        raise RuntimeError(
            "raw holidays missing required columns"
        )

    raw_rows = pq.read_table(
        raw_holidays,
        columns=[
            "data",
            "holiday_name",
        ],
    ).to_pylist()

    normalized_rows = []

    for row in raw_rows:
        raw_date = normalize_date(
            row.get("data")
        )

        raw_name = normalize_text(
            row.get("holiday_name")
        )

        if (
            raw_date is None
            or not raw_name
        ):
            raise RuntimeError(
                "invalid raw holiday row"
            )

        normalized_rows.append(
            {
                "data": raw_date,
                "holiday_name": raw_name,
            }
        )

    raw_names = {
        row["holiday_name"]
        for row in normalized_rows
    }

    unmapped_names = sorted(
        raw_names - set(aliases)
    )

    if unmapped_names:
        raise RuntimeError(
            "unmapped raw holiday names: "
            + repr(unmapped_names)
        )

    raw_dates = [
        row["data"]
        for row in normalized_rows
    ]

    start_year = min(
        raw_dates
    ).year

    end_year = max(
        raw_dates
    ).year

    raw_by_date: dict[
        date,
        str,
    ] = {}

    mismatches = []

    for row in normalized_rows:
        event_id = aliases[
            row["holiday_name"]
        ]

        event = events_by_id[event_id]

        expected = occurrence_for_year(
            event,
            row["data"].year,
        )

        if (
            not event_is_valid(
                event,
                expected,
            )
            or expected != row["data"]
        ):
            mismatches.append(
                {
                    "raw_name": (
                        row[
                            "holiday_name"
                        ]
                    ),
                    "event_id": event_id,
                    "raw_date": (
                        row["data"].isoformat()
                    ),
                    "expected_date": (
                        expected.isoformat()
                    ),
                }
            )

        raw_by_date[
            row["data"]
        ] = event_id

    if mismatches:
        raise RuntimeError(
            "raw holiday rule mismatch: "
            + repr(mismatches[:10])
        )

    generated: dict[
        date,
        set[str],
    ] = defaultdict(set)

    for event in profile["events"]:
        if not event.get("raw_names"):
            continue

        for year in range(
            start_year,
            end_year + 1,
        ):
            occurrence = occurrence_for_year(
                event,
                year,
            )

            if not event_is_valid(
                event,
                occurrence,
            ):
                continue

            generated[occurrence].add(
                event["event_id"]
            )

    collision_suppressed = []
    unexplained_missing = []

    for occurrence_date, event_ids in sorted(
        generated.items()
    ):
        raw_event_id = raw_by_date.get(
            occurrence_date
        )

        for event_id in sorted(
            event_ids
        ):
            if raw_event_id == event_id:
                continue

            detail = {
                "date": (
                    occurrence_date.isoformat()
                ),
                "missing_event_id": event_id,
                "raw_event_id": raw_event_id,
                "all_generated_event_ids": (
                    sorted(event_ids)
                ),
            }

            if (
                raw_event_id is not None
                and raw_event_id in event_ids
            ):
                collision_suppressed.append(
                    detail
                )
            else:
                unexplained_missing.append(
                    detail
                )

    if unexplained_missing:
        raise RuntimeError(
            "unexplained raw occurrence gaps: "
            + repr(
                unexplained_missing[:10]
            )
        )

    return {
        "raw_row_count": len(
            normalized_rows
        ),
        "raw_alias_count": len(
            aliases
        ),
        "unmapped_raw_name_count": (
            len(unmapped_names)
        ),
        "raw_rule_mismatch_count": (
            len(mismatches)
        ),
        "collision_suppressed_occurrence_count": (
            len(collision_suppressed)
        ),
        "collision_suppressed_occurrences": (
            collision_suppressed
        ),
        "created_at_used_as_known_from": (
            False
        ),
    }


def season_bounds(
    value: date,
) -> tuple[
    str,
    int,
    date,
    date,
]:
    if value.month in (
        12,
        1,
        2,
    ):
        if value.month == 12:
            start = date(
                value.year,
                12,
                1,
            )

            end_year = value.year + 1

            end = date(
                end_year,
                2,
                calendar.monthrange(
                    end_year,
                    2,
                )[1],
            )
        else:
            start = date(
                value.year - 1,
                12,
                1,
            )

            end = date(
                value.year,
                2,
                calendar.monthrange(
                    value.year,
                    2,
                )[1],
            )

        return (
            "winter",
            1,
            start,
            end,
        )

    if value.month in (
        3,
        4,
        5,
    ):
        return (
            "spring",
            2,
            date(value.year, 3, 1),
            date(value.year, 5, 31),
        )

    if value.month in (
        6,
        7,
        8,
    ):
        return (
            "summer",
            3,
            date(value.year, 6, 1),
            date(value.year, 8, 31),
        )

    return (
        "autumn",
        4,
        date(value.year, 9, 1),
        date(value.year, 11, 30),
    )


def build_calendar_day_rows(
    dates: list[date],
    schema: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    columns = [
        field["name"]
        for field in schema
    ]

    rows = []

    for value in dates:
        iso = value.isocalendar()

        leap = calendar.isleap(
            value.year
        )

        days_in_year = (
            366 if leap else 365
        )

        days_in_month = (
            calendar.monthrange(
                value.year,
                value.month,
            )[1]
        )

        month_end = date(
            value.year,
            value.month,
            days_in_month,
        )

        year_end = date(
            value.year,
            12,
            31,
        )

        quarter = (
            (value.month - 1) // 3 + 1
        )

        quarter_start_month = (
            (quarter - 1) * 3 + 1
        )

        quarter_end_month = (
            quarter * 3
        )

        quarter_start = date(
            value.year,
            quarter_start_month,
            1,
        )

        quarter_end = date(
            value.year,
            quarter_end_month,
            calendar.monthrange(
                value.year,
                quarter_end_month,
            )[1],
        )

        day_of_year = (
            value.timetuple().tm_yday
        )

        month_angle = (
            2.0
            * math.pi
            * (value.month - 1)
            / 12.0
        )

        weekday_angle = (
            2.0
            * math.pi
            * (iso.weekday - 1)
            / 7.0
        )

        year_angle = (
            2.0
            * math.pi
            * (day_of_year - 1)
            / float(days_in_year)
        )

        (
            season_name,
            season_index,
            season_start,
            season_end,
        ) = season_bounds(value)

        season_length = (
            season_end
            - season_start
        ).days + 1

        days_since_season_start = (
            value
            - season_start
        ).days

        days_to_season_end = (
            season_end
            - value
        ).days

        season_progress_ratio = (
            days_since_season_start
            / float(season_length - 1)
        )

        year_progress_ratio = (
            (day_of_year - 1)
            / float(days_in_year - 1)
        )

        week_of_month = (
            (value.day - 1) // 7 + 1
        )

        is_weekend = (
            iso.weekday >= 6
        )

        raw_row = {
            "data": value,
            "year": value.year,
            "quarter": quarter,
            "month": value.month,
            "iso_year": iso.year,
            "iso_week": iso.week,
            "day_of_month": value.day,
            "day_of_year": day_of_year,
            "day_of_week": iso.weekday,
            "is_weekend": is_weekend,
            "days_in_month": days_in_month,
            "days_in_year": days_in_year,
            "is_leap_year": leap,
            "days_remaining_in_month": (
                month_end - value
            ).days,
            "days_remaining_in_year": (
                year_end - value
            ).days,
            "is_month_start": (
                value.day == 1
            ),
            "is_month_end": (
                value == month_end
            ),
            "is_quarter_start": (
                value == quarter_start
            ),
            "is_quarter_end": (
                value == quarter_end
            ),
            "is_year_start": (
                value.month == 1
                and value.day == 1
            ),
            "is_year_end": (
                value.month == 12
                and value.day == 31
            ),
            "month_sin": math.sin(
                month_angle
            ),
            "month_cos": math.cos(
                month_angle
            ),
            "day_of_week_sin": (
                math.sin(
                    weekday_angle
                )
            ),
            "day_of_week_cos": (
                math.cos(
                    weekday_angle
                )
            ),
            "day_of_year_sin": (
                math.sin(
                    year_angle
                )
            ),
            "day_of_year_cos": (
                math.cos(
                    year_angle
                )
            ),
            "meteorological_season": (
                season_name
            ),
            "season_index": (
                season_index
            ),
            "days_since_season_start": (
                days_since_season_start
            ),
            "days_to_season_end": (
                days_to_season_end
            ),
            "season_progress_ratio": (
                season_progress_ratio
            ),
            "year_progress_ratio": (
                year_progress_ratio
            ),
            "week_of_month": (
                week_of_month
            ),
            "is_first_week_of_month": (
                week_of_month == 1
            ),
            "is_last_week_of_month": (
                value.day + 7
                > days_in_month
            ),
            "is_first_weekend_of_month": (
                is_weekend
                and value.day <= 7
            ),
            "is_last_weekend_of_month": (
                is_weekend
                and value.day + 7
                > days_in_month
            ),
        }

        row = {
            column: raw_row.get(column)
            for column in columns
        }

        if set(row) != set(columns):
            raise RuntimeError(
                "calendar-day schema mismatch"
            )

        rows.append(row)

    return rows


def choose_event(
    rows: list[dict[str, Any]],
) -> dict[str, Any] | None:
    if not rows:
        return None

    return sorted(
        rows,
        key=lambda row: (
            -row["priority"],
            row["event_id"],
        ),
    )[0]


def nearest_future(
    value: date,
    occurrences: list[
        dict[str, Any]
    ],
    predicate: Callable[
        [dict[str, Any]],
        bool,
    ],
) -> tuple[
    dict[str, Any] | None,
    int | None,
]:
    candidates = [
        row
        for row in occurrences
        if (
            row["occurrence_date"]
            >= value
            and predicate(row)
        )
    ]

    if not candidates:
        return None, None

    candidates.sort(
        key=lambda row: (
            row["occurrence_date"],
            -row["priority"],
            row["event_id"],
        )
    )

    selected = candidates[0]

    return (
        selected,
        (
            selected["occurrence_date"]
            - value
        ).days,
    )


def nearest_previous(
    value: date,
    occurrences: list[
        dict[str, Any]
    ],
    predicate: Callable[
        [dict[str, Any]],
        bool,
    ],
) -> tuple[
    dict[str, Any] | None,
    int | None,
]:
    candidates = [
        row
        for row in occurrences
        if (
            row["occurrence_date"]
            <= value
            and predicate(row)
        )
    ]

    if not candidates:
        return None, None

    candidates.sort(
        key=lambda row: (
            -row[
                "occurrence_date"
            ].toordinal(),
            -row["priority"],
            row["event_id"],
        )
    )

    selected = candidates[0]

    return (
        selected,
        (
            value
            - selected["occurrence_date"]
        ).days,
    )


def pre_bucket(
    distance: int | None,
) -> str:
    if distance is None:
        return "none"

    if distance == 0:
        return "event_day"

    if distance == 1:
        return "1_day"

    if distance <= 3:
        return "2_3_days"

    if distance <= 7:
        return "4_7_days"

    if distance <= 14:
        return "8_14_days"

    if distance <= 21:
        return "15_21_days"

    if distance <= 30:
        return "22_30_days"

    if distance <= 45:
        return "31_45_days"

    if distance <= 60:
        return "46_60_days"

    if distance <= 90:
        return "61_90_days"

    return "none"


def post_bucket(
    distance: int | None,
) -> str:
    if distance is None:
        return "none"

    if distance == 0:
        return "event_day"

    if distance == 1:
        return "1_day"

    if distance <= 3:
        return "2_3_days"

    if distance <= 7:
        return "4_7_days"

    if distance <= 14:
        return "8_14_days"

    if distance <= 30:
        return "15_30_days"

    return "none"


def build_context_rows(
    dates: list[date],
    active_occurrences: list[
        dict[str, Any]
    ],
    profile_id: str,
    schema: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    columns = [
        field["name"]
        for field in schema
    ]

    occurrences_by_date: dict[
        date,
        list[dict[str, Any]],
    ] = defaultdict(list)

    for row in active_occurrences:
        occurrences_by_date[
            row["occurrence_date"]
        ].append(row)

    for rows in occurrences_by_date.values():
        rows.sort(
            key=lambda row: (
                -row["priority"],
                row["event_id"],
            )
        )

    model_occurrences = [
        row
        for row in active_occurrences
        if row["is_model_relevant"]
    ]

    holiday_dates = {
        row["occurrence_date"]
        for row in active_occurrences
        if (
            row[
                "is_national_public_holiday"
            ]
            or row[
                "is_local_patron_day"
            ]
        )
    }

    bridge_dates = set()

    for value in dates:
        if value in holiday_dates:
            continue

        weekday = value.isoweekday()

        is_bridge = (
            (
                weekday == 1
                and value
                + timedelta(days=1)
                in holiday_dates
            )
            or (
                weekday == 5
                and value
                - timedelta(days=1)
                in holiday_dates
            )
        )

        if is_bridge:
            bridge_dates.add(value)

    weekend_dates = {
        value
        for value in dates
        if value.isoweekday() >= 6
    }

    cluster_dates = (
        weekend_dates
        | holiday_dates
        | bridge_dates
    )

    def cluster_length(
        value: date,
    ) -> int:
        if value not in cluster_dates:
            return 0

        start = value
        end = value

        while (
            start - timedelta(days=1)
            in cluster_dates
        ):
            start -= timedelta(days=1)

        while (
            end + timedelta(days=1)
            in cluster_dates
        ):
            end += timedelta(days=1)

        return (
            end - start
        ).days + 1

    rows = []

    for value in dates:
        today_all = (
            occurrences_by_date.get(
                value,
                [],
            )
        )

        today_model = [
            row
            for row in today_all
            if row["is_model_relevant"]
        ]

        primary = choose_event(
            today_model
        )

        next_event, days_to_next = (
            nearest_future(
                value,
                model_occurrences,
                lambda row: True,
            )
        )

        previous_event, days_since = (
            nearest_previous(
                value,
                model_occurrences,
                lambda row: True,
            )
        )

        next_public, days_to_public = (
            nearest_future(
                value,
                model_occurrences,
                lambda row: (
                    row[
                        "is_national_public_holiday"
                    ]
                    or row[
                        "is_local_patron_day"
                    ]
                ),
            )
        )

        next_family, days_to_family = (
            nearest_future(
                value,
                model_occurrences,
                lambda row: row[
                    "is_family_gifting"
                ],
            )
        )

        (
            next_commercial,
            days_to_commercial,
        ) = nearest_future(
            value,
            model_occurrences,
            lambda row: row[
                "is_commercial_retail"
            ],
        )

        (
            next_religious,
            days_to_religious,
        ) = nearest_future(
            value,
            model_occurrences,
            lambda row: row[
                "is_religious_observance"
            ],
        )

        next_local, days_to_local = (
            nearest_future(
                value,
                model_occurrences,
                lambda row: row[
                    "is_local_patron_day"
                ],
            )
        )

        public_today = any(
            row[
                "is_national_public_holiday"
            ]
            for row in today_all
        )

        local_today = any(
            row["is_local_patron_day"]
            for row in today_all
        )

        length = cluster_length(value)

        raw_row: dict[
            str,
            Any,
        ] = {
            "data": value,
            "calendar_profile_id": (
                profile_id
            ),
            "event_count": len(
                today_all
            ),
            "is_any_event_day": bool(
                today_all
            ),
            "is_public_holiday": (
                public_today
            ),
            "is_local_patron_day": (
                local_today
            ),
            "is_calendar_holiday": (
                public_today
                or local_today
            ),
            "is_religious_observance": any(
                row[
                    "is_religious_observance"
                ]
                for row in today_all
            ),
            "is_family_gifting_event": any(
                row["is_family_gifting"]
                for row in today_all
            ),
            "is_commercial_retail_event": any(
                row["is_commercial_retail"]
                for row in today_all
            ),
            "is_environmental_event": any(
                row["is_environmental_event"]
                for row in today_all
            ),
            "primary_event_id": (
                primary["event_id"]
                if primary
                else None
            ),
            "primary_event_category": (
                primary["event_category"]
                if primary
                else None
            ),
            "primary_event_priority": (
                primary["priority"]
                if primary
                else None
            ),
            "next_event_id": (
                next_event["event_id"]
                if next_event
                else None
            ),
            "next_event_category": (
                next_event[
                    "event_category"
                ]
                if next_event
                else None
            ),
            "days_to_next_event": (
                days_to_next
            ),
            "previous_event_id": (
                previous_event["event_id"]
                if previous_event
                else None
            ),
            "previous_event_category": (
                previous_event[
                    "event_category"
                ]
                if previous_event
                else None
            ),
            "days_since_previous_event": (
                days_since
            ),
            "pre_event_window_bucket": (
                pre_bucket(
                    days_to_next
                )
            ),
            "post_event_window_bucket": (
                post_bucket(
                    days_since
                )
            ),
        }

        for limit in PRE_WINDOW_LIMITS:
            raw_row[
                f"is_pre_event_{limit}d"
            ] = (
                days_to_next is not None
                and 1
                <= days_to_next
                <= limit
            )

        raw_row["is_event_day"] = bool(
            today_all
        )

        for limit in POST_WINDOW_LIMITS:
            raw_row[
                f"is_post_event_{limit}d"
            ] = (
                days_since is not None
                and 1
                <= days_since
                <= limit
            )

        category_values = (
            (
                "public_holiday",
                next_public,
                days_to_public,
            ),
            (
                "family_gifting_event",
                next_family,
                days_to_family,
            ),
            (
                "commercial_event",
                next_commercial,
                days_to_commercial,
            ),
            (
                "religious_event",
                next_religious,
                days_to_religious,
            ),
            (
                "local_event",
                next_local,
                days_to_local,
            ),
        )

        for (
            prefix,
            selected,
            distance,
        ) in category_values:
            raw_row[
                f"next_{prefix}_id"
            ] = (
                selected["event_id"]
                if selected
                else None
            )

            raw_row[
                f"days_to_next_{prefix}"
            ] = distance

        raw_row[
            "is_day_before_public_holiday"
        ] = (
            value + timedelta(days=1)
            in holiday_dates
        )

        raw_row[
            "is_day_after_public_holiday"
        ] = (
            value - timedelta(days=1)
            in holiday_dates
        )

        raw_row["is_bridge_day"] = (
            value in bridge_dates
        )

        raw_row["is_long_weekend"] = (
            length >= 3
        )

        raw_row[
            "long_weekend_length"
        ] = (
            length
            if length >= 3
            else 0
        )

        row = {
            column: raw_row.get(column)
            for column in columns
        }

        rows.append(row)

    keys = [
        (
            row["data"],
            row[
                "calendar_profile_id"
            ],
        )
        for row in rows
    ]

    if len(keys) != len(set(keys)):
        raise RuntimeError(
            "duplicate calendar-context keys"
        )

    return rows


def output_contract_map(
    contract: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    outputs = {
        item["name"]: item
        for item in contract["outputs"]
    }

    expected = {
        "calendar_day_features",
        "calendar_event_catalog",
        "calendar_event_occurrences",
        "calendar_context_features",
    }

    if set(outputs) != expected:
        raise RuntimeError(
            "unexpected D2 output set"
        )

    return outputs


def dataset_summary(
    *,
    name: str,
    rows: list[dict[str, Any]],
    contract_output: dict[str, Any],
    sort_order: list[str],
) -> dict[str, Any]:
    schema = contract_output[
        "schema"
    ]

    columns = [
        field["name"]
        for field in schema
    ]

    actual_schema_fp = (
        schema_fingerprint(
            name,
            contract_output["grain"],
            sort_order,
            schema,
        )
    )

    actual_content_fp = (
        rows_fingerprint(
            rows,
            columns,
        )
    )

    return {
        "name": name,
        "row_count": len(rows),
        "column_count": len(schema),
        "schema_fingerprint": (
            actual_schema_fp
        ),
        "content_fingerprint": (
            actual_content_fp
        ),
        "expected_row_count": (
            contract_output["rows"]
        ),
        "expected_column_count": (
            contract_output["columns"]
        ),
        "expected_schema_fingerprint": (
            contract_output[
                "schema_fingerprint"
            ]
        ),
        "expected_content_fingerprint": (
            contract_output[
                "content_fingerprint"
            ]
        ),
        "row_count_match": (
            len(rows)
            == contract_output["rows"]
        ),
        "column_count_match": (
            len(schema)
            == contract_output["columns"]
        ),
        "schema_fingerprint_match": (
            actual_schema_fp
            == contract_output[
                "schema_fingerprint"
            ]
        ),
        "content_fingerprint_match": (
            actual_content_fp
            == contract_output[
                "content_fingerprint"
            ]
        ),
    }


def build_plan(
    *,
    b2_run: Path,
    raw_holidays: Path,
    profile_path: Path,
    contract_path: Path,
    output_run: Path,
) -> dict[str, Any]:
    if output_run.exists():
        raise RuntimeError(
            "plan output path already exists"
        )

    profile, contract = (
        load_and_validate_packages(
            profile_path,
            contract_path,
        )
    )

    outputs = output_contract_map(
        contract
    )

    dates, dense_sources = (
        load_date_spine(
            b2_run
        )
    )

    catalog_rows = (
        build_catalog_rows(
            profile,
            contract,
        )
    )

    (
        _all_occurrences,
        active_occurrences,
    ) = generate_occurrences(
        profile,
        contract,
        dates[0],
        dates[-1],
    )

    reconciliation = (
        reconcile_raw_holidays(
            raw_holidays,
            profile,
        )
    )

    calendar_rows = (
        build_calendar_day_rows(
            dates,
            outputs[
                "calendar_day_features"
            ][
                "schema"
            ],
        )
    )

    context_rows = (
        build_context_rows(
            dates,
            active_occurrences,
            profile[
                "calendar_profile_id"
            ],
            outputs[
                "calendar_context_features"
            ][
                "schema"
            ],
        )
    )

    summaries = {
        "calendar_day_features": (
            dataset_summary(
                name=(
                    "calendar_day_features"
                ),
                rows=calendar_rows,
                contract_output=outputs[
                    "calendar_day_features"
                ],
                sort_order=["data"],
            )
        ),
        "calendar_event_catalog": (
            dataset_summary(
                name=(
                    "calendar_event_catalog"
                ),
                rows=catalog_rows,
                contract_output=outputs[
                    "calendar_event_catalog"
                ],
                sort_order=[
                    "calendar_profile_id",
                    "event_id",
                ],
            )
        ),
        "calendar_event_occurrences": (
            dataset_summary(
                name=(
                    "calendar_event_occurrences"
                ),
                rows=active_occurrences,
                contract_output=outputs[
                    "calendar_event_occurrences"
                ],
                sort_order=[
                    "occurrence_date",
                    "event_id",
                ],
            )
        ),
        "calendar_context_features": (
            dataset_summary(
                name=(
                    "calendar_context_features"
                ),
                rows=context_rows,
                contract_output=outputs[
                    "calendar_context_features"
                ],
                sort_order=[
                    "data",
                    "calendar_profile_id",
                ],
            )
        ),
    }

    issues = []

    for name, summary in summaries.items():
        for gate in (
            "row_count_match",
            "column_count_match",
            "schema_fingerprint_match",
            "content_fingerprint_match",
        ):
            if summary[gate] is not True:
                issues.append(
                    f"{name}: {gate} failed"
                )

    expected_collision_count = (
        contract[
            "raw_holiday_policy"
        ][
            "collision_suppressed_occurrence_count"
        ]
    )

    if (
        reconciliation[
            "collision_suppressed_occurrence_count"
        ]
        != expected_collision_count
    ):
        issues.append(
            "raw collision count mismatch"
        )

    if (
        reconciliation[
            "unmapped_raw_name_count"
        ]
        != 0
    ):
        issues.append(
            "unmapped raw holiday names"
        )

    if (
        reconciliation[
            "raw_rule_mismatch_count"
        ]
        != 0
    ):
        issues.append(
            "raw holiday rule mismatches"
        )

    if (
        reconciliation[
            "created_at_used_as_known_from"
        ]
        is not False
    ):
        issues.append(
            "created_at policy violation"
        )

    if len(dates) != outputs[
        "calendar_day_features"
    ][
        "rows"
    ]:
        issues.append(
            "date-spine row-count mismatch"
        )

    plan = {
        "ok": not issues,
        "mode": "plan",
        "program_role": PROGRAM_ROLE,
        "decision": (
            SUCCESS_DECISION
            if not issues
            else
            "CALENDAR_FEATURE_PLAN_FAILED"
        ),
        "issues": issues,
        "date_spine": {
            "start_date": (
                dates[0].isoformat()
            ),
            "end_date": (
                dates[-1].isoformat()
            ),
            "row_count": len(dates),
            "contiguous": True,
        },
        "dense_sources": dense_sources,
        "calendar_profile_id": (
            profile[
                "calendar_profile_id"
            ]
        ),
        "profile_event_count": (
            profile["event_count"]
        ),
        "active_occurrence_count": (
            len(active_occurrences)
        ),
        "raw_reconciliation": (
            reconciliation
        ),
        "outputs": summaries,
        "fingerprints": {
            "profile_source_package": (
                profile[
                    "source_package_fingerprint"
                ]
            ),
            "contract_source_package": (
                contract[
                    "source_package_fingerprint"
                ]
            ),
            "design_contract": (
                contract[
                    "design_contract_fingerprint"
                ]
            ),
            "profile_file_sha256": (
                sha256_file(
                    profile_path
                )
            ),
            "contract_file_sha256": (
                sha256_file(
                    contract_path
                )
            ),
            "raw_holidays_sha256": (
                sha256_file(
                    raw_holidays
                )
            ),
            "program_file_sha256": (
                sha256_file(
                    Path(__file__)
                )
            ),
        },
        "safety": {
            "output_run_requested": (
                str(output_run)
            ),
            "output_run_created": (
                output_run.exists()
            ),
            "parquet_written": False,
            "database_access": False,
            "supabase_access": False,
            "network_access": False,
        },
    }

    if output_run.exists():
        raise RuntimeError(
            "plan mode created output directory"
        )

    if issues:
        raise RuntimeError(
            "; ".join(issues)
        )

    return plan



MANIFEST_VERSION = "phase2m-d2-calendar-manifest-v1"

MATERIALIZED_OUTPUT_ORDER = (
    "calendar_day_features",
    "calendar_event_catalog",
    "calendar_event_occurrences",
    "calendar_context_features",
)

MATERIALIZED_SORT_ORDERS = {
    "calendar_day_features": (
        "data",
    ),
    "calendar_event_catalog": (
        "calendar_profile_id",
        "event_id",
    ),
    "calendar_event_occurrences": (
        "occurrence_date",
        "event_id",
    ),
    "calendar_context_features": (
        "data",
        "calendar_profile_id",
    ),
}


def contract_arrow_type(
    type_name: str,
) -> pa.DataType:
    mapping = {
        "date32": pa.date32(),
        "string": pa.string(),
        "json_string": pa.string(),
        "int8": pa.int8(),
        "int16": pa.int16(),
        "int32": pa.int32(),
        "int64": pa.int64(),
        "uint8": pa.uint8(),
        "uint16": pa.uint16(),
        "uint32": pa.uint32(),
        "uint64": pa.uint64(),
        "float32": pa.float32(),
        "float64": pa.float64(),
        "bool": pa.bool_(),
        "list<string>": pa.list_(
            pa.string()
        ),
    }

    if type_name not in mapping:
        raise ValueError(
            f"unsupported contract type: {type_name}"
        )

    return mapping[type_name]


def contract_arrow_schema(
    fields: list[dict[str, Any]],
) -> pa.Schema:
    return pa.schema(
        [
            pa.field(
                field["name"],
                contract_arrow_type(
                    field["type"]
                ),
                nullable=field[
                    "nullable"
                ],
            )
            for field in fields
        ]
    )


def safe_output_relative_path(
    value: str,
) -> Path:
    relative = Path(value)

    if (
        not value
        or relative.is_absolute()
        or ".." in relative.parts
        or not value.endswith(
            "part-00000.parquet"
        )
    ):
        raise RuntimeError(
            f"unsafe D2 output path: {value}"
        )

    return relative


def fsync_directory(path: Path) -> None:
    descriptor = os.open(
        path,
        os.O_RDONLY,
    )

    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def write_parquet_atomic(
    path: Path,
    table: pa.Table,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with tempfile.NamedTemporaryFile(
        mode="wb",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        candidate = Path(handle.name)

    try:
        pq.write_table(
            table,
            candidate,
            compression="zstd",
            use_dictionary=True,
            write_statistics=True,
        )

        with candidate.open("rb") as handle:
            os.fsync(handle.fileno())

        os.chmod(candidate, 0o644)
        os.replace(candidate, path)
        fsync_directory(path.parent)
    finally:
        if candidate.exists():
            candidate.unlink()


def physical_rows_are_sorted(
    rows: list[dict[str, Any]],
    columns: tuple[str, ...],
) -> bool:
    keys = [
        tuple(
            row[column]
            for column in columns
        )
        for row in rows
    ]

    return keys == sorted(keys)


def grain_keys_are_unique(
    rows: list[dict[str, Any]],
    grain: list[str],
) -> bool:
    keys = [
        tuple(
            row[column]
            for column in grain
        )
        for row in rows
    ]

    return len(keys) == len(set(keys))


def invoke_independent_validator(
    *,
    validator_path: Path,
    profile_path: Path,
    contract_path: Path,
    raw_holidays_path: Path,
    run_path: Path,
    report_path: Path,
) -> dict[str, Any]:
    command = [
        sys.executable,
        str(validator_path.resolve()),
        "--mode",
        "materialized",
        "--profile-config",
        str(profile_path.resolve()),
        "--contract-config",
        str(contract_path.resolve()),
        "--raw-holidays",
        str(raw_holidays_path.resolve()),
        "--run",
        str(run_path.resolve()),
        "--report",
        str(report_path.resolve()),
    ]

    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )

    report = (
        read_json(report_path)
        if report_path.is_file()
        else None
    )

    result = {
        "command": command,
        "return_code": (
            completed.returncode
        ),
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "report_path": str(
            report_path
        ),
        "report": report,
    }

    if completed.returncode != 0:
        raise RuntimeError(
            "independent validator failed: "
            + completed.stdout
            + completed.stderr
        )

    if (
        not isinstance(report, dict)
        or report.get("ok") is not True
        or report.get("decision")
        != "INDEPENDENT_CALENDAR_MATERIALIZED_VALIDATION_OK"
    ):
        raise RuntimeError(
            "independent validator report is not OK"
        )

    return result


def materialize_calendar_run(
    *,
    b2_run: Path,
    raw_holidays: Path,
    profile_path: Path,
    contract_path: Path,
    validator_path: Path,
    final_run: Path,
    report_path: Path,
    failure_injection: str,
) -> dict[str, Any]:
    allowed_root = Path(
        "/opt/greenbrain-platform/"
        "runtime/ml-datasets/runs"
    ).resolve()

    final_run = final_run.resolve()

    if not final_run.is_absolute():
        raise RuntimeError(
            "final run path must be absolute"
        )

    if final_run.parent != allowed_root:
        raise RuntimeError(
            "final run must be a direct child "
            "of the GreenBrain run root"
        )

    if final_run.exists():
        raise RuntimeError(
            f"final run already exists: {final_run}"
        )

    candidate_run = (
        final_run.parent
        / (
            f".{final_run.name}."
            f"candidate.{os.getpid()}"
        )
    )

    if candidate_run.exists():
        raise RuntimeError(
            f"candidate run already exists: {candidate_run}"
        )

    candidate_validation_report = (
        report_path.with_name(
            report_path.stem
            + ".candidate_validation.json"
        )
    )

    final_validation_report = (
        report_path.with_name(
            report_path.stem
            + ".final_validation.json"
        )
    )

    promoted = False
    completed_successfully = False

    try:
        profile, contract = (
            load_and_validate_packages(
                profile_path,
                contract_path,
            )
        )

        outputs = output_contract_map(
            contract
        )

        dates, dense_sources = (
            load_date_spine(
                b2_run
            )
        )

        catalog_rows = (
            build_catalog_rows(
                profile,
                contract,
            )
        )

        (
            _all_occurrences,
            occurrence_rows,
        ) = generate_occurrences(
            profile,
            contract,
            dates[0],
            dates[-1],
        )

        reconciliation = (
            reconcile_raw_holidays(
                raw_holidays,
                profile,
            )
        )

        calendar_rows = (
            build_calendar_day_rows(
                dates,
                outputs[
                    "calendar_day_features"
                ][
                    "schema"
                ],
            )
        )

        context_rows = (
            build_context_rows(
                dates,
                occurrence_rows,
                profile[
                    "calendar_profile_id"
                ],
                outputs[
                    "calendar_context_features"
                ][
                    "schema"
                ],
            )
        )

        rows_by_name = {
            "calendar_day_features": (
                calendar_rows
            ),
            "calendar_event_catalog": (
                catalog_rows
            ),
            "calendar_event_occurrences": (
                occurrence_rows
            ),
            "calendar_context_features": (
                context_rows
            ),
        }

        candidate_run.mkdir(
            parents=False,
            exist_ok=False,
        )

        output_manifest: dict[
            str,
            dict[str, Any],
        ] = {}

        for index, name in enumerate(
            MATERIALIZED_OUTPUT_ORDER
        ):
            output = outputs[name]
            rows = rows_by_name[name]

            fields = output["schema"]
            columns = [
                field["name"]
                for field in fields
            ]

            if len(rows) != output["rows"]:
                raise RuntimeError(
                    f"{name}: row-count mismatch"
                )

            if len(fields) != output[
                "columns"
            ]:
                raise RuntimeError(
                    f"{name}: column-count mismatch"
                )

            content_fp = rows_fingerprint(
                rows,
                columns,
            )

            if (
                content_fp
                != output[
                    "content_fingerprint"
                ]
            ):
                raise RuntimeError(
                    f"{name}: content-fingerprint mismatch"
                )

            if not physical_rows_are_sorted(
                rows,
                MATERIALIZED_SORT_ORDERS[
                    name
                ],
            ):
                raise RuntimeError(
                    f"{name}: physical sort mismatch"
                )

            if not grain_keys_are_unique(
                rows,
                output["grain"],
            ):
                raise RuntimeError(
                    f"{name}: duplicate grain keys"
                )

            schema = contract_arrow_schema(
                fields
            )

            table = pa.Table.from_pylist(
                rows,
                schema=schema,
            )

            if table.column_names != columns:
                raise RuntimeError(
                    f"{name}: Arrow column order mismatch"
                )

            relative_path = (
                safe_output_relative_path(
                    output["output_path"]
                )
            )

            parquet_path = (
                candidate_run
                / relative_path
            )

            write_parquet_atomic(
                parquet_path,
                table,
            )

            parquet = pq.ParquetFile(
                parquet_path
            )

            compression = {
                parquet.metadata.row_group(
                    row_group_index
                ).column(
                    column_index
                ).compression.upper()
                for row_group_index in range(
                    parquet.metadata.num_row_groups
                )
                for column_index in range(
                    parquet.metadata.row_group(
                        row_group_index
                    ).num_columns
                )
            }

            if compression != {"ZSTD"}:
                raise RuntimeError(
                    f"{name}: non-ZSTD Parquet compression"
                )

            output_manifest[name] = {
                "relative_path": str(
                    relative_path
                ),
                "row_count": (
                    table.num_rows
                ),
                "column_count": (
                    table.num_columns
                ),
                "schema_fingerprint": (
                    output[
                        "schema_fingerprint"
                    ]
                ),
                "content_fingerprint": (
                    content_fp
                ),
                "file_sha256": (
                    sha256_file(
                        parquet_path
                    )
                ),
                "file_bytes": (
                    parquet_path.stat().st_size
                ),
                "compression": "ZSTD",
                "row_group_count": (
                    parquet.metadata.num_row_groups
                ),
            }

            if (
                index == 0
                and failure_injection
                == "after_first_parquet"
            ):
                raise RuntimeError(
                    "injected failure after first Parquet"
                )

        manifest = {
            "manifest_version": (
                MANIFEST_VERSION
            ),
            "status": "complete",
            "run_name": final_run.name,
            "calendar_profile_id": (
                profile[
                    "calendar_profile_id"
                ]
            ),
            "date_spine": {
                "start_date": (
                    dates[0].isoformat()
                ),
                "end_date": (
                    dates[-1].isoformat()
                ),
                "row_count": len(dates),
                "contiguous": True,
            },
            "design_contract_fingerprint": (
                contract[
                    "design_contract_fingerprint"
                ]
            ),
            "profile_source_package_fingerprint": (
                profile[
                    "source_package_fingerprint"
                ]
            ),
            "contract_source_package_fingerprint": (
                contract[
                    "source_package_fingerprint"
                ]
            ),
            "lineage": {
                "b2_run": str(
                    b2_run.resolve()
                ),
                "raw_holidays": str(
                    raw_holidays.resolve()
                ),
                "raw_holidays_sha256": (
                    sha256_file(
                        raw_holidays
                    )
                ),
                "profile_config": str(
                    profile_path.resolve()
                ),
                "profile_config_sha256": (
                    sha256_file(
                        profile_path
                    )
                ),
                "contract_config": str(
                    contract_path.resolve()
                ),
                "contract_config_sha256": (
                    sha256_file(
                        contract_path
                    )
                ),
                "builder_sha256": (
                    sha256_file(
                        Path(__file__)
                    )
                ),
            },
            "dense_sources": (
                dense_sources
            ),
            "raw_reconciliation": (
                reconciliation
            ),
            "outputs": output_manifest,
            "materialization": {
                "parquet_file_count": 4,
                "compression": "ZSTD",
                "candidate_validation": True,
                "atomic_promotion": True,
                "database_write": False,
                "supabase_write": False,
            },
        }

        manifest_path = (
            candidate_run
            / "metadata"
            / "calendar_feature_manifest.json"
        )

        write_json_atomic(
            manifest_path,
            manifest,
        )

        if (
            failure_injection
            == "after_manifest"
        ):
            raise RuntimeError(
                "injected failure after manifest"
            )

        candidate_validation = (
            invoke_independent_validator(
                validator_path=(
                    validator_path
                ),
                profile_path=profile_path,
                contract_path=contract_path,
                raw_holidays_path=(
                    raw_holidays
                ),
                run_path=candidate_run,
                report_path=(
                    candidate_validation_report
                ),
            )
        )

        if (
            failure_injection
            == "after_candidate_validation"
        ):
            raise RuntimeError(
                "injected failure after candidate validation"
            )

        os.replace(
            candidate_run,
            final_run,
        )

        promoted = True
        fsync_directory(
            final_run.parent
        )

        if (
            failure_injection
            == "after_promotion"
        ):
            raise RuntimeError(
                "injected failure after atomic promotion"
            )

        final_validation = (
            invoke_independent_validator(
                validator_path=(
                    validator_path
                ),
                profile_path=profile_path,
                contract_path=contract_path,
                raw_holidays_path=(
                    raw_holidays
                ),
                run_path=final_run,
                report_path=(
                    final_validation_report
                ),
            )
        )

        completed_successfully = True

        return {
            "ok": True,
            "mode": "materialize",
            "decision": (
                "CALENDAR_FEATURE_MATERIALIZATION_OK"
            ),
            "run": {
                "name": final_run.name,
                "path": str(final_run),
                "candidate_path": str(
                    candidate_run
                ),
                "candidate_present_after_promotion": (
                    candidate_run.exists()
                ),
                "final_present": (
                    final_run.is_dir()
                ),
            },
            "calendar_profile_id": (
                profile[
                    "calendar_profile_id"
                ]
            ),
            "date_spine": (
                manifest["date_spine"]
            ),
            "outputs": output_manifest,
            "manifest": {
                "path": str(
                    final_run
                    / "metadata"
                    / "calendar_feature_manifest.json"
                ),
                "sha256": sha256_file(
                    final_run
                    / "metadata"
                    / "calendar_feature_manifest.json"
                ),
            },
            "candidate_validation": (
                candidate_validation
            ),
            "final_validation": (
                final_validation
            ),
            "fingerprints": {
                "design_contract": (
                    contract[
                        "design_contract_fingerprint"
                    ]
                ),
                "profile_source_package": (
                    profile[
                        "source_package_fingerprint"
                    ]
                ),
                "contract_source_package": (
                    contract[
                        "source_package_fingerprint"
                    ]
                ),
            },
            "safety": {
                "source_parquet_modified": (
                    False
                ),
                "database_access": False,
                "supabase_access": False,
                "network_access": False,
                "candidate_cleaned": (
                    not candidate_run.exists()
                ),
                "atomic_promotion": True,
                "parquet_file_count": 4,
            },
        }

    finally:
        if not completed_successfully:
            if candidate_run.exists():
                shutil.rmtree(
                    candidate_run
                )

            if (
                promoted
                and final_run.exists()
            ):
                shutil.rmtree(
                    final_run
                )

            if final_run.parent.exists():
                fsync_directory(
                    final_run.parent
                )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Phase 2M-D2 calendar feature builder."
        )
    )

    parser.add_argument(
        "--b2-run",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--raw-holidays",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--profile-config",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--contract-config",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--output-run",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--report",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--validator",
        type=Path,
    )

    parser.add_argument(
        "--mode",
        choices=(
            "plan",
            "materialize",
        ),
        default="plan",
    )

    parser.add_argument(
        "--failure-injection",
        choices=(
            "none",
            "after_first_parquet",
            "after_manifest",
            "after_candidate_validation",
            "after_promotion",
        ),
        default="none",
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    for path in (
        args.b2_run,
        args.raw_holidays,
        args.profile_config,
        args.contract_config,
    ):
        if not path.exists():
            raise FileNotFoundError(path)

    if args.mode == "plan":
        plan = build_plan(
            b2_run=args.b2_run,
            raw_holidays=(
                args.raw_holidays
            ),
            profile_path=(
                args.profile_config
            ),
            contract_path=(
                args.contract_config
            ),
            output_run=args.output_run,
        )

        write_json_atomic(
            args.report,
            plan,
        )

        print(
            f"PROGRAM_ROLE={PROGRAM_ROLE}"
        )

        print(
            "CALENDAR_PROFILE_ID={}".format(
                plan[
                    "calendar_profile_id"
                ]
            )
        )

        print(
            "DATE_SPINE"
            "|rows={}"
            "|start={}"
            "|end={}"
            "|contiguous={}".format(
                plan[
                    "date_spine"
                ][
                    "row_count"
                ],
                plan[
                    "date_spine"
                ][
                    "start_date"
                ],
                plan[
                    "date_spine"
                ][
                    "end_date"
                ],
                plan[
                    "date_spine"
                ][
                    "contiguous"
                ],
            )
        )

        for name, summary in (
            plan["outputs"].items()
        ):
            print(
                "D2_PLAN_OUTPUT"
                "|name={}"
                "|rows={}"
                "|columns={}"
                "|schema_fp={}"
                "|content_fp={}"
                "|all_gates={}".format(
                    name,
                    summary[
                        "row_count"
                    ],
                    summary[
                        "column_count"
                    ],
                    summary[
                        "schema_fingerprint"
                    ],
                    summary[
                        "content_fingerprint"
                    ],
                    all(
                        summary[gate]
                        for gate in (
                            "row_count_match",
                            "column_count_match",
                            "schema_fingerprint_match",
                            "content_fingerprint_match",
                        )
                    ),
                )
            )

        print(
            "RAW_RECONCILIATION"
            "|rows={}"
            "|aliases={}"
            "|unmapped={}"
            "|rule_mismatches={}"
            "|collision_suppressed={}"
            "|created_at_used_as_known_from={}".format(
                plan[
                    "raw_reconciliation"
                ][
                    "raw_row_count"
                ],
                plan[
                    "raw_reconciliation"
                ][
                    "raw_alias_count"
                ],
                plan[
                    "raw_reconciliation"
                ][
                    "unmapped_raw_name_count"
                ],
                plan[
                    "raw_reconciliation"
                ][
                    "raw_rule_mismatch_count"
                ],
                plan[
                    "raw_reconciliation"
                ][
                    "collision_suppressed_occurrence_count"
                ],
                plan[
                    "raw_reconciliation"
                ][
                    "created_at_used_as_known_from"
                ],
            )
        )

        print("OUTPUT_RUN_CREATED=False")
        print("PARQUET_WRITTEN=False")
        print(
            "DECISION={}".format(
                plan["decision"]
            )
        )

        return 0

    if args.validator is None:
        raise RuntimeError(
            "--validator is required "
            "in materialize mode"
        )

    if not args.validator.is_file():
        raise FileNotFoundError(
            args.validator
        )

    try:
        result = materialize_calendar_run(
            b2_run=args.b2_run,
            raw_holidays=(
                args.raw_holidays
            ),
            profile_path=(
                args.profile_config
            ),
            contract_path=(
                args.contract_config
            ),
            validator_path=(
                args.validator
            ),
            final_run=args.output_run,
            report_path=args.report,
            failure_injection=(
                args.failure_injection
            ),
        )

    except Exception as exc:
        failure = {
            "ok": False,
            "mode": "materialize",
            "decision": (
                "CALENDAR_FEATURE_MATERIALIZATION_FAILED"
            ),
            "error_type": (
                type(exc).__name__
            ),
            "error": str(exc),
            "failure_injection": (
                args.failure_injection
            ),
            "run": {
                "path": str(
                    args.output_run
                ),
                "final_present": (
                    args.output_run.exists()
                ),
            },
            "safety": {
                "source_parquet_modified": (
                    False
                ),
                "database_access": False,
                "supabase_access": False,
                "network_access": False,
            },
        }

        write_json_atomic(
            args.report,
            failure,
        )

        print(
            "MATERIALIZATION_ERROR_TYPE={}".format(
                failure["error_type"]
            )
        )

        print(
            "MATERIALIZATION_ERROR={}".format(
                failure["error"]
            )
        )

        print(
            "FINAL_RUN_PRESENT={}".format(
                failure["run"][
                    "final_present"
                ]
            )
        )

        print(
            "DECISION={}".format(
                failure["decision"]
            )
        )

        return 1

    write_json_atomic(
        args.report,
        result,
    )

    print(
        "PROGRAM_ROLE=builder"
    )

    print(
        "MATERIALIZED_RUN={}".format(
            result["run"]["path"]
        )
    )

    print(
        "CALENDAR_PROFILE_ID={}".format(
            result[
                "calendar_profile_id"
            ]
        )
    )

    for name, summary in (
        result["outputs"].items()
    ):
        print(
            "D2_MATERIALIZED_OUTPUT"
            "|name={}"
            "|rows={}"
            "|columns={}"
            "|bytes={}"
            "|compression={}"
            "|file_sha256={}"
            "|content_fp={}".format(
                name,
                summary["row_count"],
                summary[
                    "column_count"
                ],
                summary["file_bytes"],
                summary["compression"],
                summary["file_sha256"],
                summary[
                    "content_fingerprint"
                ],
            )
        )

    print(
        "CANDIDATE_VALIDATION_OK={}".format(
            result[
                "candidate_validation"
            ][
                "report"
            ][
                "ok"
            ]
        )
    )

    print(
        "FINAL_VALIDATION_OK={}".format(
            result[
                "final_validation"
            ][
                "report"
            ][
                "ok"
            ]
        )
    )

    print(
        "CANDIDATE_CLEANED={}".format(
            result[
                "safety"
            ][
                "candidate_cleaned"
            ]
        )
    )

    print(
        "ATOMIC_PROMOTION={}".format(
            result[
                "safety"
            ][
                "atomic_promotion"
            ]
        )
    )

    print(
        "DECISION={}".format(
            result["decision"]
        )
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
