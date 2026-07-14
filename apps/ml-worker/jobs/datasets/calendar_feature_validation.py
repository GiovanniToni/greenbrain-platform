#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import tempfile
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

import pyarrow as pa
import pyarrow.parquet as pq


SUPPORTED_PROFILE_ID = "it_toscana_pistoia_retail_v2"

SUPPORTED_DESIGN_CONTRACT_FINGERPRINT = (
    "dc3d57be9e52c636b18128067105ffa48566be24b8e1bc46d967c04436a48af0"
)

MANIFEST_VERSION = "phase2m-d2-calendar-manifest-v1"

EXPECTED_OUTPUTS = {
    "calendar_day_features": {
        "rows": 6398,
        "columns": 38,
        "sort_order": ["data"],
    },
    "calendar_event_catalog": {
        "rows": 46,
        "columns": 28,
        "sort_order": [
            "calendar_profile_id",
            "event_id",
        ],
    },
    "calendar_event_occurrences": {
        "rows": 797,
        "columns": 18,
        "sort_order": [
            "occurrence_date",
            "event_id",
        ],
    },
    "calendar_context_features": {
        "rows": 6398,
        "columns": 52,
        "sort_order": [
            "data",
            "calendar_profile_id",
        ],
    },
}

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


def stable_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def file_digest(path: Path) -> str:
    return hashlib.sha256(
        path.read_bytes()
    ).hexdigest()


def package_digest(payload: dict[str, Any]) -> str:
    copy = dict(payload)

    copy.pop(
        "source_package_fingerprint",
        None,
    )

    return hashlib.sha256(
        stable_json(copy).encode("utf-8")
    ).hexdigest()


def load_document(path: Path) -> Any:
    return json.loads(
        path.read_text(encoding="utf-8")
    )


def save_document(
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


def contract_schema_digest(
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

    return hashlib.sha256(
        stable_json(payload).encode("utf-8")
    ).hexdigest()


def coerce_date(value: Any) -> date | None:
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
        return date.fromisoformat(text[:10])
    except ValueError:
        return None


def clean_label(value: Any) -> str:
    if value is None:
        return ""

    return " ".join(
        str(value).strip().split()
    )


def canonical_cell(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()

    if isinstance(value, date):
        return value.isoformat()

    if isinstance(value, float):
        return value.hex()

    if isinstance(value, list):
        return [
            canonical_cell(item)
            for item in value
        ]

    if isinstance(value, dict):
        return {
            key: canonical_cell(item)
            for key, item in sorted(
                value.items()
            )
        }

    return value


def logical_rows_digest(
    rows: list[dict[str, Any]],
    columns: list[str],
) -> str:
    hasher = hashlib.sha256()

    for row in rows:
        payload = [
            canonical_cell(
                row.get(column)
            )
            for column in columns
        ]

        hasher.update(
            stable_json(payload).encode(
                "utf-8"
            )
        )

        hasher.update(b"\n")

    return hasher.hexdigest()


def parse_contract_type(type_name: str) -> pa.DataType:
    mapping = {
        "date32": pa.date32(),
        "string": pa.string(),
        "json_string": pa.string(),
        "int8": pa.int8(),
        "int16": pa.int16(),
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


def inspect_source_packages(
    profile_path: Path,
    contract_path: Path,
) -> tuple[
    dict[str, Any],
    dict[str, Any],
    dict[str, Any],
    list[str],
]:
    profile = load_document(
        profile_path
    )

    contract = load_document(
        contract_path
    )

    issues: list[str] = []

    actual_profile_fp = package_digest(
        profile
    )

    declared_profile_fp = profile.get(
        "source_package_fingerprint"
    )

    if actual_profile_fp != declared_profile_fp:
        issues.append(
            "profile package fingerprint mismatch"
        )

    actual_contract_fp = package_digest(
        contract
    )

    declared_contract_fp = contract.get(
        "source_package_fingerprint"
    )

    if actual_contract_fp != declared_contract_fp:
        issues.append(
            "contract package fingerprint mismatch"
        )

    if (
        profile.get("calendar_profile_id")
        != SUPPORTED_PROFILE_ID
    ):
        issues.append(
            "unsupported calendar profile ID"
        )

    if (
        contract.get(
            "calendar_profile",
            {},
        ).get(
            "calendar_profile_id"
        )
        != SUPPORTED_PROFILE_ID
    ):
        issues.append(
            "contract calendar profile mismatch"
        )

    if (
        contract.get(
            "design_contract_fingerprint"
        )
        != SUPPORTED_DESIGN_CONTRACT_FINGERPRINT
    ):
        issues.append(
            "unsupported design contract fingerprint"
        )

    required_profile_fp = contract.get(
        "runtime_requirements",
        {},
    ).get(
        "profile_fingerprint_required"
    )

    if required_profile_fp != declared_profile_fp:
        issues.append(
            "contract/profile package linkage mismatch"
        )

    events = profile.get(
        "events",
        [],
    )

    event_ids = [
        event.get("event_id")
        for event in events
    ]

    if profile.get("event_count") != 46:
        issues.append(
            "profile event count must be 46"
        )

    if len(events) != 46:
        issues.append(
            "event-list count must be 46"
        )

    if len(event_ids) != len(set(event_ids)):
        issues.append(
            "duplicate event IDs"
        )

    active_count = sum(
        1
        for event in events
        if event.get(
            "active_for_profile"
        )
        is True
    )

    model_relevant_active_count = sum(
        1
        for event in events
        if (
            event.get(
                "active_for_profile"
            )
            is True
            and event.get(
                "is_model_relevant"
            )
            is True
        )
    )

    if active_count != 45:
        issues.append(
            "active event count must be 45"
        )

    if model_relevant_active_count != 36:
        issues.append(
            "active model-relevant event count must be 36"
        )

    aliases: dict[str, str] = {}

    for event in events:
        if (
            event.get(
                "availability_mode"
            )
            != "deterministic"
        ):
            issues.append(
                "non-deterministic event: "
                + str(event.get("event_id"))
            )

        if event.get(
            "known_from_date"
        ) is not None:
            issues.append(
                "known_from_date must be null: "
                + str(event.get("event_id"))
            )

        for raw_name in event.get(
            "raw_names",
            [],
        ):
            if raw_name in aliases:
                issues.append(
                    "duplicate raw alias: "
                    + raw_name
                )

            aliases[raw_name] = event[
                "event_id"
            ]

    if len(aliases) != 16:
        issues.append(
            "raw alias count must be 16"
        )

    catalog = {
        event["event_id"]: event
        for event in events
        if event.get("event_id")
    }

    required_semantics = {
        "pistoia_st_james_patron_day": True,
        "florence_st_john_patron_day": False,
    }

    for event_id, expected_active in (
        required_semantics.items()
    ):
        event = catalog.get(event_id)

        if event is None:
            issues.append(
                f"required event missing: {event_id}"
            )
            continue

        if (
            event.get(
                "active_for_profile"
            )
            is not expected_active
        ):
            issues.append(
                f"invalid profile activation: {event_id}"
            )

    saint_francis = catalog.get(
        "saint_francis_of_assisi_day"
    )

    if saint_francis is None:
        issues.append(
            "San Francesco event missing"
        )
    elif (
        saint_francis.get("valid_from")
        != "2026-01-01"
    ):
        issues.append(
            "San Francesco valid_from mismatch"
        )

    outputs = {
        output["name"]: output
        for output in contract.get(
            "outputs",
            [],
        )
    }

    if set(outputs) != set(EXPECTED_OUTPUTS):
        issues.append(
            "unexpected output dataset set"
        )

    for name, expected in (
        EXPECTED_OUTPUTS.items()
    ):
        output = outputs.get(name)

        if output is None:
            continue

        if output.get("rows") != expected[
            "rows"
        ]:
            issues.append(
                f"{name}: expected row count mismatch"
            )

        if output.get("columns") != expected[
            "columns"
        ]:
            issues.append(
                f"{name}: expected column count mismatch"
            )

        fields = output.get(
            "schema",
            [],
        )

        if len(fields) != expected["columns"]:
            issues.append(
                f"{name}: schema field count mismatch"
            )

        actual_schema_fp = (
            contract_schema_digest(
                name,
                output.get("grain", []),
                expected["sort_order"],
                fields,
            )
        )

        if (
            actual_schema_fp
            != output.get(
                "schema_fingerprint"
            )
        ):
            issues.append(
                f"{name}: schema fingerprint mismatch"
            )

        relative_path = output.get(
            "output_path",
            ""
        )

        if (
            not relative_path
            or Path(relative_path).is_absolute()
            or ".." in Path(
                relative_path
            ).parts
        ):
            issues.append(
                f"{name}: unsafe output path"
            )

    materialization = contract.get(
        "materialization",
        {},
    )

    if (
        materialization.get(
            "expected_file_count"
        )
        != 4
    ):
        issues.append(
            "expected materialized file count must be 4"
        )

    if (
        str(
            materialization.get(
                "compression"
            )
        ).lower()
        != "zstd"
    ):
        issues.append(
            "compression must be ZSTD"
        )

    if materialization.get(
        "parquet_only"
    ) is not True:
        issues.append(
            "D2 must remain Parquet-only"
        )

    if materialization.get(
        "candidate_validation"
    ) is not True:
        issues.append(
            "candidate validation must be enabled"
        )

    if materialization.get(
        "final_independent_validation"
    ) is not True:
        issues.append(
            "independent final validation must be enabled"
        )

    if contract.get(
        "implementation",
        {},
    ).get(
        "build_global_modified"
    ) is not False:
        issues.append(
            "build_global modification is prohibited"
        )

    summary = {
        "calendar_profile_id": (
            profile.get(
                "calendar_profile_id"
            )
        ),
        "profile_event_count": len(
            events
        ),
        "active_event_count": (
            active_count
        ),
        "active_model_relevant_event_count": (
            model_relevant_active_count
        ),
        "raw_alias_count": len(
            aliases
        ),
        "output_count": len(
            outputs
        ),
        "profile_package_fingerprint": (
            declared_profile_fp
        ),
        "contract_package_fingerprint": (
            declared_contract_fp
        ),
        "design_contract_fingerprint": (
            contract.get(
                "design_contract_fingerprint"
            )
        ),
        "profile_sha256": file_digest(
            profile_path
        ),
        "contract_sha256": file_digest(
            contract_path
        ),
    }

    return (
        profile,
        contract,
        summary,
        issues,
    )


def inspect_raw_holiday_source(
    raw_holidays: Path,
    profile: dict[str, Any],
) -> tuple[
    dict[str, Any],
    list[str],
]:
    issues: list[str] = []

    parquet = pq.ParquetFile(
        raw_holidays
    )

    schema_names = set(
        parquet.schema_arrow.names
    )

    required = {
        "data",
        "holiday_name",
    }

    if not required.issubset(
        schema_names
    ):
        issues.append(
            "raw holidays missing required columns"
        )

        return (
            {
                "path": str(raw_holidays),
                "sha256": file_digest(
                    raw_holidays
                ),
            },
            issues,
        )

    rows = pq.read_table(
        raw_holidays,
        columns=[
            "data",
            "holiday_name",
        ],
    ).to_pylist()

    normalized = []

    for row in rows:
        event_date = coerce_date(
            row.get("data")
        )

        event_name = clean_label(
            row.get("holiday_name")
        )

        if event_date is None:
            issues.append(
                "raw holiday with invalid date"
            )
            continue

        if not event_name:
            issues.append(
                "raw holiday with empty name"
            )
            continue

        normalized.append(
            (
                event_date,
                event_name,
            )
        )

    dates = [
        item[0]
        for item in normalized
    ]

    names = {
        item[1]
        for item in normalized
    }

    aliases = {
        raw_name
        for event in profile.get(
            "events",
            [],
        )
        for raw_name in event.get(
            "raw_names",
            [],
        )
    }

    unmapped = sorted(
        names - aliases
    )

    if len(rows) != 286:
        issues.append(
            "raw holiday row count must be 286"
        )

    if len(set(dates)) != 286:
        issues.append(
            "raw holiday dates must be unique"
        )

    if len(names) != 16:
        issues.append(
            "raw holiday name count must be 16"
        )

    if unmapped:
        issues.append(
            "unmapped raw holiday names: "
            + repr(unmapped)
        )

    summary = {
        "path": str(raw_holidays),
        "sha256": file_digest(
            raw_holidays
        ),
        "row_count": len(rows),
        "valid_row_count": len(
            normalized
        ),
        "unique_date_count": len(
            set(dates)
        ),
        "distinct_name_count": len(
            names
        ),
        "unmapped_name_count": len(
            unmapped
        ),
        "unmapped_names": unmapped,
        "created_at_used_as_known_from": (
            False
        ),
    }

    return summary, issues


def read_materialized_output(
    run_path: Path,
    output: dict[str, Any],
    sort_order: list[str],
) -> tuple[
    dict[str, Any],
    list[dict[str, Any]],
    list[str],
]:
    name = output["name"]

    issues: list[str] = []

    relative_path = Path(
        output["output_path"]
    )

    parquet_path = (
        run_path / relative_path
    )

    if not parquet_path.is_file():
        issues.append(
            f"{name}: Parquet file missing"
        )

        return (
            {
                "name": name,
                "path": str(
                    parquet_path
                ),
            },
            [],
            issues,
        )

    parquet = pq.ParquetFile(
        parquet_path
    )

    table = parquet.read()

    expected_fields = output[
        "schema"
    ]

    expected_names = [
        field["name"]
        for field in expected_fields
    ]

    if table.column_names != expected_names:
        issues.append(
            f"{name}: column order mismatch"
        )

    for field_definition in expected_fields:
        field_name = field_definition[
            "name"
        ]

        if field_name not in table.schema.names:
            issues.append(
                f"{name}: missing field {field_name}"
            )
            continue

        actual_field = table.schema.field(
            field_name
        )

        expected_type = parse_contract_type(
            field_definition["type"]
        )

        if not actual_field.type.equals(
            expected_type
        ):
            issues.append(
                f"{name}: type mismatch for {field_name}"
            )

        if (
            actual_field.nullable
            != field_definition[
                "nullable"
            ]
        ):
            issues.append(
                f"{name}: nullability mismatch for {field_name}"
            )

    rows = table.to_pylist()

    if table.num_rows != output["rows"]:
        issues.append(
            f"{name}: row count mismatch"
        )

    if table.num_columns != output[
        "columns"
    ]:
        issues.append(
            f"{name}: column count mismatch"
        )

    content_fp = logical_rows_digest(
        rows,
        expected_names,
    )

    if (
        content_fp
        != output[
            "content_fingerprint"
        ]
    ):
        issues.append(
            f"{name}: content fingerprint mismatch"
        )

    keys = [
        tuple(
            row.get(column)
            for column in sort_order
        )
        for row in rows
    ]

    if keys != sorted(keys):
        issues.append(
            f"{name}: deterministic sort mismatch"
        )

    grain = output["grain"]

    unique_keys = [
        tuple(
            row.get(column)
            for column in grain
        )
        for row in rows
    ]

    if len(unique_keys) != len(
        set(unique_keys)
    ):
        issues.append(
            f"{name}: duplicate grain keys"
        )

    compression_values = set()

    for row_group_index in range(
        parquet.metadata.num_row_groups
    ):
        row_group = parquet.metadata.row_group(
            row_group_index
        )

        for column_index in range(
            row_group.num_columns
        ):
            compression_values.add(
                row_group.column(
                    column_index
                ).compression.upper()
            )

    if compression_values != {"ZSTD"}:
        issues.append(
            f"{name}: compression is not exclusively ZSTD"
        )

    summary = {
        "name": name,
        "path": str(parquet_path),
        "file_sha256": file_digest(
            parquet_path
        ),
        "file_bytes": (
            parquet_path.stat().st_size
        ),
        "row_count": table.num_rows,
        "column_count": table.num_columns,
        "schema_fingerprint": (
            output[
                "schema_fingerprint"
            ]
        ),
        "content_fingerprint": (
            content_fp
        ),
        "compression": sorted(
            compression_values
        ),
        "row_group_count": (
            parquet.metadata.num_row_groups
        ),
        "sorted": keys == sorted(keys),
        "unique_grain_keys": (
            len(unique_keys)
            == len(set(unique_keys))
        ),
    }

    return summary, rows, issues


def expected_pre_bucket(
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


def expected_post_bucket(
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


def validate_calendar_day_semantics(
    rows: list[dict[str, Any]],
) -> list[str]:
    issues: list[str] = []

    dates = [
        coerce_date(row.get("data"))
        for row in rows
    ]

    if any(value is None for value in dates):
        issues.append(
            "calendar-day contains invalid dates"
        )

        return issues

    clean_dates = [
        value
        for value in dates
        if value is not None
    ]

    expected_count = (
        clean_dates[-1]
        - clean_dates[0]
    ).days + 1

    if len(clean_dates) != expected_count:
        issues.append(
            "calendar-day date spine is not contiguous"
        )

    for row, value in zip(
        rows,
        clean_dates,
    ):
        if row["year"] != value.year:
            issues.append(
                f"calendar year mismatch: {value}"
            )
            break

        if row["month"] != value.month:
            issues.append(
                f"calendar month mismatch: {value}"
            )
            break

        if (
            row["day_of_week"]
            != value.isoweekday()
        ):
            issues.append(
                f"calendar weekday mismatch: {value}"
            )
            break

        if (
            row["is_weekend"]
            != (
                value.isoweekday()
                >= 6
            )
        ):
            issues.append(
                f"calendar weekend mismatch: {value}"
            )
            break

        if (
            row["is_month_start"]
            != (value.day == 1)
        ):
            issues.append(
                f"month-start mismatch: {value}"
            )
            break

        if not math.isclose(
            (
                row["month_sin"] ** 2
                + row["month_cos"] ** 2
            ),
            1.0,
            rel_tol=0.0,
            abs_tol=1e-12,
        ):
            issues.append(
                f"month cycle mismatch: {value}"
            )
            break

        expected_season = (
            "winter"
            if value.month in {
                12,
                1,
                2,
            }
            else "spring"
            if value.month in {
                3,
                4,
                5,
            }
            else "summer"
            if value.month in {
                6,
                7,
                8,
            }
            else "autumn"
        )

        if (
            row[
                "meteorological_season"
            ]
            != expected_season
        ):
            issues.append(
                f"season mismatch: {value}"
            )
            break

    return issues


def validate_catalog_semantics(
    rows: list[dict[str, Any]],
) -> list[str]:
    issues: list[str] = []

    event_ids = [
        row["event_id"]
        for row in rows
    ]

    if len(event_ids) != len(set(event_ids)):
        issues.append(
            "catalog contains duplicate event IDs"
        )

    if {
        row["calendar_profile_id"]
        for row in rows
    } != {SUPPORTED_PROFILE_ID}:
        issues.append(
            "catalog profile ID mismatch"
        )

    active_count = sum(
        1
        for row in rows
        if row["active_for_profile"]
    )

    if active_count != 45:
        issues.append(
            "materialized active event count mismatch"
        )

    for row in rows:
        if (
            row["availability_mode"]
            != "deterministic"
        ):
            issues.append(
                "materialized non-deterministic event"
            )
            break

        if row["known_from_date"] is not None:
            issues.append(
                "materialized known_from_date must be null"
            )
            break

    return issues


def validate_occurrence_semantics(
    rows: list[dict[str, Any]],
    catalog_rows: list[dict[str, Any]],
) -> list[str]:
    issues: list[str] = []

    catalog = {
        row["event_id"]: row
        for row in catalog_rows
    }

    for row in rows:
        event_id = row["event_id"]

        if event_id not in catalog:
            issues.append(
                f"occurrence references unknown event: {event_id}"
            )
            break

        event = catalog[event_id]

        if event[
            "active_for_profile"
        ] is not True:
            issues.append(
                f"inactive event was materialized: {event_id}"
            )
            break

        if (
            row["calendar_profile_id"]
            != SUPPORTED_PROFILE_ID
        ):
            issues.append(
                "occurrence profile ID mismatch"
            )
            break

        if row["known_from_date"] is not None:
            issues.append(
                "occurrence known_from_date must be null"
            )
            break

        occurrence_date = coerce_date(
            row["occurrence_date"]
        )

        if occurrence_date is None:
            issues.append(
                "occurrence contains invalid date"
            )
            break

        if row[
            "occurrence_year"
        ] != occurrence_date.year:
            issues.append(
                f"occurrence year mismatch: {event_id}"
            )
            break

    return issues


def validate_context_semantics(
    rows: list[dict[str, Any]],
    calendar_rows: list[dict[str, Any]],
    occurrence_rows: list[dict[str, Any]],
    catalog_rows: list[dict[str, Any]],
) -> list[str]:
    issues: list[str] = []

    calendar_dates = [
        coerce_date(row["data"])
        for row in calendar_rows
    ]

    context_dates = [
        coerce_date(row["data"])
        for row in rows
    ]

    if context_dates != calendar_dates:
        issues.append(
            "context and calendar date spines differ"
        )

        return issues

    catalog = {
        row["event_id"]: row
        for row in catalog_rows
    }

    occurrences_by_date: dict[
        date,
        list[dict[str, Any]],
    ] = defaultdict(list)

    for occurrence in occurrence_rows:
        occurrence_date = coerce_date(
            occurrence[
                "occurrence_date"
            ]
        )

        if occurrence_date is not None:
            occurrences_by_date[
                occurrence_date
            ].append(occurrence)

    holiday_dates = {
        occurrence_date
        for occurrence_date, items
        in occurrences_by_date.items()
        if any(
            item[
                "is_national_public_holiday"
            ]
            or item[
                "is_local_patron_day"
            ]
            for item in items
        )
    }

    for row, value in zip(
        rows,
        context_dates,
    ):
        if value is None:
            issues.append(
                "context contains invalid date"
            )
            break

        today = occurrences_by_date.get(
            value,
            [],
        )

        public_today = any(
            item[
                "is_national_public_holiday"
            ]
            for item in today
        )

        local_today = any(
            item[
                "is_local_patron_day"
            ]
            for item in today
        )

        if row["event_count"] != len(today):
            issues.append(
                f"context event_count mismatch: {value}"
            )
            break

        if (
            row["is_any_event_day"]
            != bool(today)
        ):
            issues.append(
                f"context event-day mismatch: {value}"
            )
            break

        if (
            row["is_event_day"]
            != bool(today)
        ):
            issues.append(
                f"context is_event_day mismatch: {value}"
            )
            break

        if (
            row["is_public_holiday"]
            != public_today
        ):
            issues.append(
                f"public-holiday mismatch: {value}"
            )
            break

        if (
            row["is_local_patron_day"]
            != local_today
        ):
            issues.append(
                f"local-patron mismatch: {value}"
            )
            break

        if (
            row["is_calendar_holiday"]
            != (
                public_today
                or local_today
            )
        ):
            issues.append(
                f"calendar-holiday mismatch: {value}"
            )
            break

        if (
            row[
                "pre_event_window_bucket"
            ]
            != expected_pre_bucket(
                row[
                    "days_to_next_event"
                ]
            )
        ):
            issues.append(
                f"pre-event bucket mismatch: {value}"
            )
            break

        if (
            row[
                "post_event_window_bucket"
            ]
            != expected_post_bucket(
                row[
                    "days_since_previous_event"
                ]
            )
        ):
            issues.append(
                f"post-event bucket mismatch: {value}"
            )
            break

        distance = row[
            "days_to_next_event"
        ]

        for limit in PRE_WINDOW_LIMITS:
            expected_flag = (
                distance is not None
                and 1
                <= distance
                <= limit
            )

            if (
                row[
                    f"is_pre_event_{limit}d"
                ]
                != expected_flag
            ):
                issues.append(
                    f"pre-event flag mismatch: {value}, {limit}"
                )
                return issues

        distance_since = row[
            "days_since_previous_event"
        ]

        for limit in POST_WINDOW_LIMITS:
            expected_flag = (
                distance_since is not None
                and 1
                <= distance_since
                <= limit
            )

            if (
                row[
                    f"is_post_event_{limit}d"
                ]
                != expected_flag
            ):
                issues.append(
                    f"post-event flag mismatch: {value}, {limit}"
                )
                return issues

        if (
            row[
                "is_day_before_public_holiday"
            ]
            != (
                value + timedelta(days=1)
                in holiday_dates
            )
        ):
            issues.append(
                f"day-before-holiday mismatch: {value}"
            )
            break

        if (
            row[
                "is_day_after_public_holiday"
            ]
            != (
                value - timedelta(days=1)
                in holiday_dates
            )
        ):
            issues.append(
                f"day-after-holiday mismatch: {value}"
            )
            break

        primary_event_id = row.get(
            "primary_event_id"
        )

        if primary_event_id is not None:
            today_ids = {
                item["event_id"]
                for item in today
                if item[
                    "is_model_relevant"
                ]
            }

            if primary_event_id not in today_ids:
                issues.append(
                    f"primary event absent from occurrence bridge: {value}"
                )
                break

            if primary_event_id not in catalog:
                issues.append(
                    f"primary event absent from catalog: {value}"
                )
                break

    return issues


def validate_manifest(
    run_path: Path,
    profile: dict[str, Any],
    contract: dict[str, Any],
    output_summaries: dict[
        str,
        dict[str, Any],
    ],
) -> tuple[
    dict[str, Any],
    list[str],
]:
    issues: list[str] = []

    manifest_path = (
        run_path
        / "metadata"
        / "calendar_feature_manifest.json"
    )

    if not manifest_path.is_file():
        return (
            {
                "path": str(
                    manifest_path
                ),
                "exists": False,
            },
            [
                "calendar feature manifest missing"
            ],
        )

    manifest = load_document(
        manifest_path
    )

    if (
        manifest.get("manifest_version")
        != MANIFEST_VERSION
    ):
        issues.append(
            "manifest version mismatch"
        )

    if manifest.get("status") != "complete":
        issues.append(
            "manifest status is not complete"
        )

    if (
        manifest.get(
            "calendar_profile_id"
        )
        != SUPPORTED_PROFILE_ID
    ):
        issues.append(
            "manifest profile ID mismatch"
        )

    if (
        manifest.get(
            "design_contract_fingerprint"
        )
        != SUPPORTED_DESIGN_CONTRACT_FINGERPRINT
    ):
        issues.append(
            "manifest design-contract fingerprint mismatch"
        )

    if (
        manifest.get(
            "profile_source_package_fingerprint"
        )
        != profile[
            "source_package_fingerprint"
        ]
    ):
        issues.append(
            "manifest profile-package fingerprint mismatch"
        )

    if (
        manifest.get(
            "contract_source_package_fingerprint"
        )
        != contract[
            "source_package_fingerprint"
        ]
    ):
        issues.append(
            "manifest contract-package fingerprint mismatch"
        )

    manifest_outputs = manifest.get(
        "outputs",
        {}
    )

    if set(manifest_outputs) != set(
        output_summaries
    ):
        issues.append(
            "manifest output set mismatch"
        )
    else:
        for name, summary in (
            output_summaries.items()
        ):
            recorded = manifest_outputs[
                name
            ]

            for key in (
                "row_count",
                "column_count",
                "schema_fingerprint",
                "content_fingerprint",
                "file_sha256",
            ):
                if recorded.get(key) != summary.get(
                    key
                ):
                    issues.append(
                        f"manifest mismatch: {name}.{key}"
                    )

    summary = {
        "path": str(manifest_path),
        "exists": True,
        "sha256": file_digest(
            manifest_path
        ),
        "manifest_version": (
            manifest.get(
                "manifest_version"
            )
        ),
        "status": manifest.get(
            "status"
        ),
    }

    return summary, issues


def validate_materialized_run(
    run_path: Path,
    profile: dict[str, Any],
    contract: dict[str, Any],
) -> tuple[
    dict[str, Any],
    list[str],
]:
    issues: list[str] = []

    if not run_path.is_dir():
        return (
            {
                "run_path": str(run_path),
                "exists": False,
            },
            [
                "materialized run directory missing"
            ],
        )

    outputs = {
        output["name"]: output
        for output in contract["outputs"]
    }

    rows_by_name: dict[
        str,
        list[dict[str, Any]],
    ] = {}

    output_summaries = {}

    for name, expected in (
        EXPECTED_OUTPUTS.items()
    ):
        summary, rows, output_issues = (
            read_materialized_output(
                run_path,
                outputs[name],
                expected["sort_order"],
            )
        )

        output_summaries[name] = (
            summary
        )

        rows_by_name[name] = rows

        issues.extend(output_issues)

    actual_parquets = sorted(
        path
        for path in run_path.rglob(
            "*.parquet"
        )
        if not any(
            part.startswith(".")
            for part in path.relative_to(
                run_path
            ).parts
        )
    )

    if len(actual_parquets) != 4:
        issues.append(
            "materialized run must contain exactly four Parquet files"
        )

    if not issues:
        issues.extend(
            validate_calendar_day_semantics(
                rows_by_name[
                    "calendar_day_features"
                ]
            )
        )

        issues.extend(
            validate_catalog_semantics(
                rows_by_name[
                    "calendar_event_catalog"
                ]
            )
        )

        issues.extend(
            validate_occurrence_semantics(
                rows_by_name[
                    "calendar_event_occurrences"
                ],
                rows_by_name[
                    "calendar_event_catalog"
                ],
            )
        )

        issues.extend(
            validate_context_semantics(
                rows_by_name[
                    "calendar_context_features"
                ],
                rows_by_name[
                    "calendar_day_features"
                ],
                rows_by_name[
                    "calendar_event_occurrences"
                ],
                rows_by_name[
                    "calendar_event_catalog"
                ],
            )
        )

    manifest_summary, manifest_issues = (
        validate_manifest(
            run_path,
            profile,
            contract,
            output_summaries,
        )
    )

    issues.extend(manifest_issues)

    summary = {
        "run_path": str(run_path),
        "exists": True,
        "parquet_file_count": len(
            actual_parquets
        ),
        "outputs": output_summaries,
        "manifest": manifest_summary,
    }

    return summary, issues


def parse_cli() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Independent Phase 2M-D2 "
            "contract and materialized-output validator."
        )
    )

    parser.add_argument(
        "--mode",
        choices=(
            "contract",
            "materialized",
        ),
        required=True,
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
        "--raw-holidays",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--run",
        type=Path,
    )

    parser.add_argument(
        "--report",
        required=True,
        type=Path,
    )

    return parser.parse_args()


def entrypoint() -> int:
    args = parse_cli()

    required_paths = (
        args.profile_config,
        args.contract_config,
        args.raw_holidays,
    )

    for path in required_paths:
        if not path.is_file():
            raise FileNotFoundError(path)

    (
        profile,
        contract,
        package_summary,
        package_issues,
    ) = inspect_source_packages(
        args.profile_config,
        args.contract_config,
    )

    (
        raw_summary,
        raw_issues,
    ) = inspect_raw_holiday_source(
        args.raw_holidays,
        profile,
    )

    issues = (
        list(package_issues)
        + list(raw_issues)
    )

    materialized_summary = None

    if args.mode == "materialized":
        if args.run is None:
            issues.append(
                "--run is required in materialized mode"
            )
        elif not issues:
            (
                materialized_summary,
                materialized_issues,
            ) = validate_materialized_run(
                args.run,
                profile,
                contract,
            )

            issues.extend(
                materialized_issues
            )

    decision = (
        "INDEPENDENT_CALENDAR_CONTRACT_VALIDATION_OK"
        if (
            args.mode == "contract"
            and not issues
        )
        else
        "INDEPENDENT_CALENDAR_MATERIALIZED_VALIDATION_OK"
        if (
            args.mode == "materialized"
            and not issues
        )
        else
        "INDEPENDENT_CALENDAR_VALIDATION_FAILED"
    )

    report = {
        "ok": not issues,
        "mode": args.mode,
        "validator_architecture": (
            "independent_contract_and_materialized_output_reader"
        ),
        "decision": decision,
        "issues": issues,
        "source_packages": (
            package_summary
        ),
        "raw_holidays": raw_summary,
        "materialized": (
            materialized_summary
        ),
        "safety": {
            "builder_imported": False,
            "generation_pipeline_called": False,
            "parquet_written": False,
            "run_created": False,
            "database_access": False,
            "supabase_access": False,
            "network_access": False,
        },
    }

    save_document(
        args.report,
        report,
    )

    print(
        "VALIDATOR_ARCHITECTURE="
        "independent_contract_and_materialized_output_reader"
    )

    print(
        "VALIDATION_MODE={}".format(
            args.mode
        )
    )

    print(
        "SOURCE_PACKAGE_VALIDATION_OK={}".format(
            not package_issues
        )
    )

    print(
        "RAW_HOLIDAY_VALIDATION_OK={}".format(
            not raw_issues
        )
    )

    print(
        "PROFILE_EVENT_COUNT={}".format(
            package_summary[
                "profile_event_count"
            ]
        )
    )

    print(
        "ACTIVE_EVENT_COUNT={}".format(
            package_summary[
                "active_event_count"
            ]
        )
    )

    print(
        "RAW_ALIAS_COUNT={}".format(
            package_summary[
                "raw_alias_count"
            ]
        )
    )

    print(
        "OUTPUT_CONTRACT_COUNT={}".format(
            package_summary[
                "output_count"
            ]
        )
    )

    print(
        "PARQUET_WRITTEN=False"
    )

    print(
        "RUN_CREATED=False"
    )

    for issue in issues:
        print(
            f"VALIDATION_ISSUE={issue}"
        )

    print(
        f"DECISION={decision}"
    )

    return 0 if not issues else 1


if __name__ == "__main__":
    raise SystemExit(entrypoint())
