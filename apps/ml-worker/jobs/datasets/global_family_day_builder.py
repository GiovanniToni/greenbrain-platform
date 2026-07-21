#!/usr/bin/env python3
"""Build the Phase 2M-G2 dense global family-day feature lake.

The builder is contract-driven and deliberately keeps orchestration outside
build_global.py until Phase 2M-I2 has completed.

Execution architecture:
- B2 supplies the immutable data+famiglia row spine.
- C2 and D2 are small dimensions loaded once.
- F2 is streamed in lockstep with B2 by year/month partition.
- E2 is pivoted at date grain for one target month at a time.
- Output is written in bounded Arrow batches to an isolated candidate run.
- Independent validation is mandatory before atomic promotion.
"""

from __future__ import annotations

import ctypes
import gc

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date, datetime, time as datetime_time, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable, Iterator, Mapping, Sequence

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.dataset as ds
import pyarrow.parquet as pq


DEFAULT_CONTRACT = (
    Path(__file__).resolve().parent
    / "contracts"
    / "phase2m_g2_family_day_contract_v1.json"
)

DEFAULT_RUNS_ROOT = Path(
    "/opt/greenbrain-platform/runtime/ml-datasets/runs"
)

DEFAULT_VALIDATOR = (
    Path(__file__).resolve().parent
    / "global_family_day_validation.py"
)

PHASE_ARGUMENTS = {
    "B2": "b2_run",
    "C2": "c2_run",
    "D2": "d2_run",
    "E2": "e2_run",
    "F2": "f2_run",
}

KEY_COLUMNS = (
    "data",
    "famiglia",
)

PARTITION_COLUMNS = (
    "year",
    "month",
)

FORBIDDEN_DATABASE_MODULE_PREFIXES = (
    "psycopg",
    "psycopg2",
    "sqlalchemy",
    "supabase",
    "asyncpg",
)

YEAR_MONTH_PATTERN = re.compile(
    r"(?<!\d)(20\d{2})[-_]?([01]\d)(?!\d)"
)


class G2BuilderError(RuntimeError):
    """Raised when a blocking contract or build invariant fails."""


@dataclass(frozen=True)
class ResolvedInput:
    logical_input: str
    phase: str
    run_id: str
    run_root: Path
    logical_dataset: str
    dataset_root: Path
    source_grain: str
    join_keys: str
    join_type: str
    reference_row_count: int
    file_count: int
    footer_row_count: int
    total_size_bytes: int
    schema: pa.Schema
    schema_fingerprint: str
    compression_values: tuple[str, ...]


@dataclass(frozen=True)
class PartitionInfo:
    year: int
    month: int
    files: tuple[Path, ...]
    row_count: int
    size_bytes: int
    row_group_count: int


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def canonical_fingerprint(value: Any) -> str:
    return hashlib.sha256(
        canonical_json_bytes(value)
    ).hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()

    with path.open("rb") as handle:
        for chunk in iter(
            lambda: handle.read(1024 * 1024),
            b"",
        ):
            digest.update(chunk)

    return digest.hexdigest()



def current_process_rss_bytes(
) -> int | None:
    try:
        lines = Path(
            "/proc/self/status"
        ).read_text(
            encoding="utf-8",
            errors="replace",
        ).splitlines()
    except OSError:
        return None

    for line in lines:
        if not line.startswith(
            "VmRSS:"
        ):
            continue

        parts = line.split()

        if len(parts) < 2:
            return None

        try:
            value = int(
                parts[1]
            )
        except ValueError:
            return None

        if (
            len(parts) >= 3
            and parts[2].lower()
            == "kb"
        ):
            value *= 1024

        return value

    return None


def release_process_memory(
) -> dict[str, Any]:
    rss_before = (
        current_process_rss_bytes()
    )

    pool = pa.default_memory_pool()

    arrow_bytes_before = int(
        pool.bytes_allocated()
    )

    gc_collected_first = int(
        gc.collect()
    )

    release_unused = getattr(
        pool,
        "release_unused",
        None,
    )

    if not callable(
        release_unused
    ):
        raise G2BuilderError(
            "PyArrow memory pool does not expose "
            "release_unused()"
        )

    release_unused()

    malloc_trim_available = False
    malloc_trim_result: bool | None = None
    malloc_trim_error: str | None = None

    try:
        libc = ctypes.CDLL(None)

        malloc_trim = getattr(
            libc,
            "malloc_trim",
            None,
        )

        if malloc_trim is not None:
            malloc_trim_available = True
            malloc_trim.argtypes = [
                ctypes.c_size_t
            ]
            malloc_trim.restype = (
                ctypes.c_int
            )

            malloc_trim_result = bool(
                malloc_trim(0)
            )
    except Exception as exc:
        malloc_trim_error = (
            f"{type(exc).__name__}: {exc}"
        )

    gc_collected_second = int(
        gc.collect()
    )

    release_unused()

    arrow_bytes_after = int(
        pool.bytes_allocated()
    )

    rss_after = (
        current_process_rss_bytes()
    )

    return {
        "rss_before_bytes": (
            rss_before
        ),
        "rss_after_bytes": (
            rss_after
        ),
        "rss_released_bytes": (
            (
                rss_before - rss_after
            )
            if (
                rss_before is not None
                and rss_after is not None
            )
            else None
        ),
        "arrow_bytes_before": (
            arrow_bytes_before
        ),
        "arrow_bytes_after": (
            arrow_bytes_after
        ),
        "arrow_bytes_released": (
            arrow_bytes_before
            - arrow_bytes_after
        ),
        "arrow_release_unused_called": (
            True
        ),
        "gc_collected_first": (
            gc_collected_first
        ),
        "gc_collected_second": (
            gc_collected_second
        ),
        "malloc_trim_available": (
            malloc_trim_available
        ),
        "malloc_trim_result": (
            malloc_trim_result
        ),
        "malloc_trim_error": (
            malloc_trim_error
        ),
    }


def utc_timestamp() -> str:
    return datetime.now(
        timezone.utc
    ).replace(
        microsecond=0
    ).isoformat().replace(
        "+00:00",
        "Z",
    )


def generated_run_id() -> str:
    timestamp = datetime.now(
        timezone.utc
    ).strftime("%Y%m%d_%H%M%S")

    return (
        "gb_phase2m_g2_family_day_"
        f"{timestamp}_"
        f"{uuid.uuid4().hex[:12]}"
    )


def write_json_atomic(
    path: Path,
    payload: Any,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    serialized = (
        json.dumps(
            payload,
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        temporary_path = Path(
            handle.name
        )

        handle.write(serialized)
        handle.flush()
        os.fsync(handle.fileno())

    try:
        os.chmod(
            temporary_path,
            0o644,
        )

        os.replace(
            temporary_path,
            path,
        )
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def parquet_files(root: Path) -> list[Path]:
    if root.is_file():
        return [root]

    return sorted(
        root.rglob("*.parquet")
    )


def physical_schema(root: Path) -> pa.Schema:
    files = parquet_files(root)

    if not files:
        raise G2BuilderError(
            f"Parquet dataset is empty: {root}"
        )

    schemas = [
        pq.ParquetFile(
            path
        ).schema_arrow.remove_metadata()
        for path in files
    ]

    unique = {
        schema.to_string()
        for schema in schemas
    }

    if len(unique) != 1:
        raise G2BuilderError(
            f"Inconsistent physical schemas: {root}"
        )

    return schemas[0]


def arrow_schema_fingerprint(
    schema: pa.Schema,
) -> str:
    normalized = (
        schema
        .remove_metadata()
        .to_string(
            show_field_metadata=False
        )
    )

    return hashlib.sha256(
        normalized.encode("utf-8")
    ).hexdigest()


def parquet_footer_inventory(
    root: Path,
) -> tuple[
    int,
    int,
    int,
    tuple[str, ...],
]:
    files = parquet_files(root)

    if not files:
        raise G2BuilderError(
            f"No Parquet files found: {root}"
        )

    total_rows = 0
    total_bytes = 0
    compression_values: set[str] = set()

    for path in files:
        parquet = pq.ParquetFile(path)
        metadata = parquet.metadata

        total_rows += metadata.num_rows
        total_bytes += path.stat().st_size

        for row_group_index in range(
            metadata.num_row_groups
        ):
            row_group = metadata.row_group(
                row_group_index
            )

            for column_index in range(
                row_group.num_columns
            ):
                compression_values.add(
                    str(
                        row_group.column(
                            column_index
                        ).compression
                    ).upper()
                )

    return (
        len(files),
        total_rows,
        total_bytes,
        tuple(
            sorted(
                compression_values
            )
        ),
    )


def extract_partition_key(
    path: Path,
    dataset_root: Path,
) -> tuple[int, int] | None:
    relative = path.relative_to(
        dataset_root
    )

    year_value: int | None = None
    month_value: int | None = None

    for part in relative.parts:
        if part.startswith("year="):
            year_value = int(
                part.split("=", 1)[1]
            )

        elif part.startswith("month="):
            month_value = int(
                part.split("=", 1)[1]
            )

    if (
        year_value is not None
        and month_value is not None
    ):
        return (
            year_value,
            month_value,
        )

    match = YEAR_MONTH_PATTERN.search(
        path.name
    )

    if match:
        return (
            int(match.group(1)),
            int(match.group(2)),
        )

    return None


def partition_inventory(
    dataset_root: Path,
) -> dict[
    tuple[int, int],
    PartitionInfo,
]:
    grouped: dict[
        tuple[int, int],
        list[Path],
    ] = defaultdict(list)

    for path in parquet_files(
        dataset_root
    ):
        key = extract_partition_key(
            path,
            dataset_root,
        )

        if key is None:
            raise G2BuilderError(
                "Unable to derive year/month "
                f"partition from {path}"
            )

        grouped[key].append(path)

    result = {}

    for (
        year_value,
        month_value,
    ), files in sorted(
        grouped.items()
    ):
        row_count = 0
        size_bytes = 0
        row_group_count = 0

        for path in sorted(files):
            parquet = pq.ParquetFile(
                path
            )

            row_count += (
                parquet.metadata.num_rows
            )
            row_group_count += (
                parquet.metadata.num_row_groups
            )
            size_bytes += (
                path.stat().st_size
            )

        result[
            (
                year_value,
                month_value,
            )
        ] = PartitionInfo(
            year=year_value,
            month=month_value,
            files=tuple(
                sorted(files)
            ),
            row_count=row_count,
            size_bytes=size_bytes,
            row_group_count=(
                row_group_count
            ),
        )

    return result


def load_contract(
    path: Path,
) -> dict[str, Any]:
    if not path.is_file():
        raise G2BuilderError(
            f"Contract not found: {path}"
        )

    contract = json.loads(
        path.read_text(
            encoding="utf-8"
        )
    )

    payload = dict(contract)

    try:
        stored_fingerprint = payload.pop(
            "contract_fingerprint"
        )
    except KeyError as exc:
        raise G2BuilderError(
            "Contract fingerprint is missing"
        ) from exc

    calculated_fingerprint = (
        canonical_fingerprint(payload)
    )

    if (
        stored_fingerprint
        != calculated_fingerprint
    ):
        raise G2BuilderError(
            "Contract fingerprint mismatch"
        )

    if contract.get(
        "contract_status"
    ) != "frozen":
        raise G2BuilderError(
            "Contract is not frozen"
        )

    if contract.get("phase") != "2M-G2":
        raise G2BuilderError(
            "Unexpected contract phase"
        )

    output = contract.get(
        "output",
        {},
    )

    schema_descriptor = output.get(
        "schema"
    )

    if not isinstance(
        schema_descriptor,
        list,
    ):
        raise G2BuilderError(
            "Contract output schema is missing"
        )

    schema_fingerprint = (
        canonical_fingerprint(
            schema_descriptor
        )
    )

    if schema_fingerprint != output.get(
        "schema_fingerprint"
    ):
        raise G2BuilderError(
            "Output schema fingerprint mismatch"
        )

    if len(schema_descriptor) != output.get(
        "column_count"
    ):
        raise G2BuilderError(
            "Output schema column count mismatch"
        )

    lineage = contract.get(
        "column_lineage"
    )

    if not isinstance(lineage, list):
        raise G2BuilderError(
            "Executable column lineage is missing"
        )

    if len(lineage) != len(
        schema_descriptor
    ):
        raise G2BuilderError(
            "Column lineage count mismatch"
        )

    expected_ordinals = list(
        range(
            1,
            len(lineage) + 1,
        )
    )

    if [
        row.get("ordinal")
        for row in lineage
    ] != expected_ordinals:
        raise G2BuilderError(
            "Column lineage ordinals are invalid"
        )

    schema_names = [
        row.get("name")
        for row in schema_descriptor
    ]

    lineage_names = [
        row.get("output_column")
        for row in lineage
    ]

    if schema_names != lineage_names:
        raise G2BuilderError(
            "Lineage/output schema order mismatch"
        )

    if len(schema_names) != len(
        set(schema_names)
    ):
        raise G2BuilderError(
            "Output column names are not unique"
        )

    mapping_policy = contract.get(
        "execution_mapping_policy",
        {},
    )

    mapping_fingerprint = (
        canonical_fingerprint(
            lineage
        )
    )

    if mapping_fingerprint != (
        mapping_policy.get(
            "column_lineage_fingerprint"
        )
    ):
        raise G2BuilderError(
            "Column lineage fingerprint mismatch"
        )

    if mapping_policy.get(
        "heuristic_source_resolution_allowed"
    ) is not False:
        raise G2BuilderError(
            "Heuristic source resolution "
            "must be forbidden"
        )

    weather_policy = contract.get(
        "weather_policy",
        {},
    )

    if weather_policy.get(
        "target_date_policy"
    ) != "EVENT_DAY_SAME_DATE":
        raise G2BuilderError(
            "Weather target-date policy must be "
            "EVENT_DAY_SAME_DATE"
        )

    if weather_policy.get(
        "same_day_actual_eligibility"
    ) != "RETROSPECTIVE_ONLY":
        raise G2BuilderError(
            "Same-day actual weather must be "
            "RETROSPECTIVE_ONLY"
        )

    if weather_policy.get(
        "explicit_lag_eligibility"
    ) != "PREDICTION_ELIGIBLE":
        raise G2BuilderError(
            "Explicit weather lags must be "
            "PREDICTION_ELIGIBLE"
        )

    if weather_policy.get(
        "shifted_rolling_eligibility"
    ) != "PREDICTION_ELIGIBLE":
        raise G2BuilderError(
            "Shifted weather rolling features "
            "must be PREDICTION_ELIGIBLE"
        )

    if weather_policy.get(
        "forecast_columns_in_base_g2"
    ) is not False:
        raise G2BuilderError(
            "Forecast columns must be excluded "
            "from base G2"
        )

    if weather_policy.get(
        "forecast_overlay_dataset"
    ) != "weather_prediction_day_asof":
        raise G2BuilderError(
            "Forecast overlay dataset must be "
            "weather_prediction_day_asof"
        )


    if weather_policy.get(
        "coverage_policy"
    ) != (
        "ALLOW_NULL_ONLY_AFTER_"
        "OBSERVED_WEATHER_MAX_DATE"
    ):
        raise G2BuilderError(
            "Weather coverage policy must allow "
            "nulls only after the observed "
            "weather maximum date"
        )

    if weather_policy.get(
        "internal_gap_policy"
    ) != "FORBID":
        raise G2BuilderError(
            "Internal weather gaps must be "
            "forbidden"
        )

    if weather_policy.get(
        "pre_observation_gap_policy"
    ) != "FORBID":
        raise G2BuilderError(
            "Pre-observation weather gaps must "
            "be forbidden"
        )

    if weather_policy.get(
        "trailing_gap_fill"
    ) != "NULL":
        raise G2BuilderError(
            "Trailing weather gaps must use "
            "null values"
        )

    if weather_policy.get(
        "previous_day_relabeling"
    ) != "FORBID":
        raise G2BuilderError(
            "Previous-day weather relabeling "
            "must be forbidden"
        )

    if weather_policy.get(
        "missingness_scope"
    ) != "WEATHER_COLUMNS_ONLY":
        raise G2BuilderError(
            "Trailing missingness must be "
            "limited to weather columns"
        )

    if contract.get(
        "materialization_policy",
        {},
    ).get(
        "database_write"
    ) is not False:
        raise G2BuilderError(
            "Database output must be forbidden"
        )

    return contract


def resolve_run_ids(
    contract: Mapping[str, Any],
    args: argparse.Namespace,
) -> dict[str, str]:
    fixture_ids = (
        contract.get(
            "reference_fixture",
            {},
        ).get(
            "run_ids",
            {},
        )
    )

    result = {}

    for phase, argument_name in (
        PHASE_ARGUMENTS.items()
    ):
        explicit_value = getattr(
            args,
            argument_name,
        )

        run_id = (
            explicit_value
            or fixture_ids.get(phase)
        )

        if not run_id:
            raise G2BuilderError(
                f"Run ID is required for {phase}"
            )

        if "/" in run_id or "\\" in run_id:
            raise G2BuilderError(
                f"Invalid run ID for {phase}: "
                f"{run_id}"
            )

        result[phase] = run_id

    return result


def resolve_inputs(
    contract: Mapping[str, Any],
    runs_root: Path,
    run_ids: Mapping[str, str],
) -> dict[str, ResolvedInput]:
    required_inputs = contract.get(
        "required_inputs"
    )

    if not isinstance(
        required_inputs,
        list,
    ):
        raise G2BuilderError(
            "Contract required_inputs is invalid"
        )

    resolved: dict[
        str,
        ResolvedInput,
    ] = {}

    seen_datasets: set[str] = set()

    for item in required_inputs:
        logical_input = str(
            item["logical_input"]
        )
        phase = str(item["phase"])
        logical_dataset = str(
            item["dataset"]
        )

        if phase not in run_ids:
            raise G2BuilderError(
                f"No run ID resolved for {phase}"
            )

        if logical_dataset in seen_datasets:
            raise G2BuilderError(
                "Duplicate logical dataset in "
                f"contract: {logical_dataset}"
            )

        seen_datasets.add(
            logical_dataset
        )

        run_id = run_ids[phase]
        run_root = (
            runs_root / run_id
        ).resolve()

        if not run_root.is_dir():
            raise G2BuilderError(
                f"Run root not found: {run_root}"
            )

        dataset_root = (
            run_root / logical_dataset
        ).resolve()

        try:
            dataset_root.relative_to(
                run_root
            )
        except ValueError as exc:
            raise G2BuilderError(
                "Resolved dataset escapes run root"
            ) from exc

        if not dataset_root.exists():
            raise G2BuilderError(
                "Exact contract dataset path "
                f"not found: {dataset_root}"
            )

        schema = physical_schema(
            dataset_root
        )

        (
            file_count,
            footer_row_count,
            total_size_bytes,
            compression_values,
        ) = parquet_footer_inventory(
            dataset_root
        )

        reference_row_count = int(
            item["reference_row_count"]
        )

        if (
            footer_row_count
            != reference_row_count
        ):
            raise G2BuilderError(
                "Reference row-count mismatch "
                f"for {logical_input}: "
                f"{footer_row_count} != "
                f"{reference_row_count}"
            )

        resolved_input = ResolvedInput(
            logical_input=logical_input,
            phase=phase,
            run_id=run_id,
            run_root=run_root,
            logical_dataset=(
                logical_dataset
            ),
            dataset_root=dataset_root,
            source_grain=str(
                item["source_grain"]
            ),
            join_keys=str(
                item["join_keys"]
            ),
            join_type=str(
                item["join_type"]
            ),
            reference_row_count=(
                reference_row_count
            ),
            file_count=file_count,
            footer_row_count=(
                footer_row_count
            ),
            total_size_bytes=(
                total_size_bytes
            ),
            schema=schema,
            schema_fingerprint=(
                arrow_schema_fingerprint(
                    schema
                )
            ),
            compression_values=(
                compression_values
            ),
        )

        if logical_input in resolved:
            raise G2BuilderError(
                "Duplicate logical input: "
                f"{logical_input}"
            )

        resolved[
            logical_input
        ] = resolved_input

    if len(resolved) != len(
        required_inputs
    ):
        raise G2BuilderError(
            "Not all required inputs resolved"
        )

    return resolved


def source_by_dataset(
    resolved_inputs: Mapping[
        str,
        ResolvedInput,
    ],
) -> dict[str, ResolvedInput]:
    result = {}

    for resolved in (
        resolved_inputs.values()
    ):
        dataset = (
            resolved.logical_dataset
        )

        if dataset in result:
            raise G2BuilderError(
                "Dataset appears more than once: "
                f"{dataset}"
            )

        result[dataset] = resolved

    return result


def validate_lineage_against_sources(
    contract: Mapping[str, Any],
    resolved_inputs: Mapping[
        str,
        ResolvedInput,
    ],
) -> pa.Schema:
    datasets = source_by_dataset(
        resolved_inputs
    )

    schema_descriptor = contract[
        "output"
    ]["schema"]

    fields = []

    for descriptor, lineage in zip(
        schema_descriptor,
        contract["column_lineage"],
    ):
        dataset_name = lineage[
            "source_dataset"
        ]

        resolved = datasets.get(
            dataset_name
        )

        if resolved is None:
            raise G2BuilderError(
                "Lineage dataset is unresolved: "
                f"{dataset_name}"
            )

        source_column = lineage[
            "source_column"
        ]

        index = resolved.schema.get_field_index(
            source_column
        )

        if index < 0:
            raise G2BuilderError(
                "Lineage source column not found: "
                f"{dataset_name}.{source_column}"
            )

        source_field = resolved.schema.field(
            index
        )

        expected_type = descriptor[
            "type"
        ]

        if str(source_field.type) != (
            expected_type
        ):
            raise G2BuilderError(
                "Lineage type mismatch for "
                f"{lineage['output_column']}: "
                f"{source_field.type} != "
                f"{expected_type}"
            )

        fields.append(
            pa.field(
                descriptor["name"],
                source_field.type,
                nullable=bool(
                    descriptor["nullable"]
                ),
            )
        )

    metadata = {
        b"greenbrain_contract_name": (
            str(
                contract[
                    "contract_name"
                ]
            ).encode("utf-8")
        ),
        b"greenbrain_contract_version": (
            str(
                contract["version"]
            ).encode("utf-8")
        ),
        b"greenbrain_contract_fingerprint": (
            str(
                contract[
                    "contract_fingerprint"
                ]
            ).encode("utf-8")
        ),
        b"greenbrain_output_schema_fingerprint": (
            str(
                contract["output"][
                    "schema_fingerprint"
                ]
            ).encode("utf-8")
        ),
    }

    return pa.schema(
        fields,
        metadata=metadata,
    )


def lineage_by_dataset(
    contract: Mapping[str, Any],
) -> dict[
    str,
    list[dict[str, Any]],
]:
    result: dict[
        str,
        list[dict[str, Any]],
    ] = defaultdict(list)

    for row in contract[
        "column_lineage"
    ]:
        result[
            row["source_dataset"]
        ].append(row)

    return {
        dataset: sorted(
            rows,
            key=lambda row: int(
                row["ordinal"]
            ),
        )
        for dataset, rows in result.items()
    }


def required_columns_for_dataset(
    dataset_name: str,
    lineage_rows: Sequence[
        Mapping[str, Any]
    ],
    key_columns: Sequence[str],
) -> list[str]:
    result: list[str] = []

    for column in key_columns:
        if column not in result:
            result.append(column)

    for row in lineage_rows:
        source_column = str(
            row["source_column"]
        )

        if source_column not in result:
            result.append(
                source_column
            )

    return result


def input_manifest(
    resolved_inputs: Mapping[
        str,
        ResolvedInput,
    ],
) -> list[dict[str, Any]]:
    return [
        {
            "logical_input": (
                resolved.logical_input
            ),
            "phase": resolved.phase,
            "run_id": resolved.run_id,
            "run_root": str(
                resolved.run_root
            ),
            "logical_dataset": (
                resolved.logical_dataset
            ),
            "dataset_root": str(
                resolved.dataset_root
            ),
            "source_grain": (
                resolved.source_grain
            ),
            "join_keys": (
                resolved.join_keys
            ),
            "join_type": (
                resolved.join_type
            ),
            "reference_row_count": (
                resolved.reference_row_count
            ),
            "file_count": (
                resolved.file_count
            ),
            "footer_row_count": (
                resolved.footer_row_count
            ),
            "total_size_bytes": (
                resolved.total_size_bytes
            ),
            "schema_fingerprint": (
                resolved.schema_fingerprint
            ),
            "compression_values": list(
                resolved.compression_values
            ),
        }
        for resolved in sorted(
            resolved_inputs.values(),
            key=lambda item: (
                item.phase,
                item.logical_dataset,
            ),
        )
    ]


def normalized_type_family(
    type_name: str,
) -> str:
    value = type_name.lower().strip()

    if (
        "string" in value
        or "binary" in value
    ):
        return "variable_width"

    if "bool" in value:
        return "boolean"

    if (
        "timestamp" in value
        or "date64" in value
        or "duration" in value
    ):
        return "width_8"

    if "date32" in value:
        return "width_4"

    if (
        "float64" in value
        or "double" in value
        or "int64" in value
        or "uint64" in value
    ):
        return "width_8"

    if (
        "float32" in value
        or "int32" in value
        or "uint32" in value
    ):
        return "width_4"

    if (
        "int16" in value
        or "uint16" in value
    ):
        return "width_2"

    if (
        "int8" in value
        or "uint8" in value
    ):
        return "width_1"

    if (
        "decimal128" in value
        or "fixed_size_binary[16]"
        in value
    ):
        return "width_16"

    return "unknown"


def estimated_bytes_per_value(
    type_name: str,
) -> int:
    family = normalized_type_family(
        type_name
    )

    return {
        "boolean": 1,
        "width_1": 1,
        "width_2": 2,
        "width_4": 4,
        "width_8": 8,
        "width_16": 16,
        "variable_width": 28,
        "unknown": 16,
    }[family]


def capacity_estimate(
    contract: Mapping[str, Any],
    output_root: Path,
) -> dict[str, Any]:
    schema = contract[
        "output"
    ]["schema"]

    nullable_count = sum(
        bool(row["nullable"])
        for row in schema
    )

    bytes_per_row = sum(
        estimated_bytes_per_value(
            str(row["type"])
        )
        for row in schema
    ) + (
        nullable_count + 7
    ) // 8

    rows = int(
        contract["output"][
            "reference_row_count"
        ]
    )

    uncompressed_bytes = (
        rows * bytes_per_row
    )

    estimated_compressed_bytes = int(
        uncompressed_bytes * 0.25
    )

    required_free_bytes = max(
        20 * 1024**3,
        int(
            estimated_compressed_bytes
            * 1.50
        ),
    )

    probe = output_root

    while not probe.exists():
        parent = probe.parent

        if parent == probe:
            raise G2BuilderError(
                "Unable to resolve existing "
                f"filesystem for {output_root}"
            )

        probe = parent

    free_bytes = shutil.disk_usage(
        probe
    ).free

    return {
        "estimated_bytes_per_row": (
            bytes_per_row
        ),
        "reference_rows": rows,
        "estimated_uncompressed_bytes": (
            uncompressed_bytes
        ),
        "estimated_compressed_bytes": (
            estimated_compressed_bytes
        ),
        "required_free_bytes": (
            required_free_bytes
        ),
        "free_bytes": free_bytes,
        "free_space_sufficient": (
            free_bytes
            >= required_free_bytes
        ),
        "filesystem_probe": str(probe),
    }


def validate_partition_alignment(
    contract: Mapping[str, Any],
    resolved_inputs: Mapping[
        str,
        ResolvedInput,
    ],
) -> tuple[
    dict[
        tuple[int, int],
        PartitionInfo,
    ],
    dict[
        tuple[int, int],
        PartitionInfo,
    ],
]:
    try:
        b2 = resolved_inputs[
            "family_day_dense_grid"
        ]
        f2 = resolved_inputs[
            "dense_sales_family_features"
        ]
    except KeyError as exc:
        raise G2BuilderError(
            "B2/F2 logical inputs are missing"
        ) from exc

    b2_partitions = partition_inventory(
        b2.dataset_root
    )

    f2_partitions = partition_inventory(
        f2.dataset_root
    )

    if set(b2_partitions) != set(
        f2_partitions
    ):
        raise G2BuilderError(
            "B2/F2 partition sets differ"
        )

    expected_partition_count = int(
        contract["output"][
            "reference_monthly_partition_count"
        ]
    )

    if len(b2_partitions) != (
        expected_partition_count
    ):
        raise G2BuilderError(
            "Unexpected B2/F2 partition count: "
            f"{len(b2_partitions)} != "
            f"{expected_partition_count}"
        )

    total_b2_rows = 0
    total_f2_rows = 0

    for key in sorted(b2_partitions):
        b2_partition = b2_partitions[key]
        f2_partition = f2_partitions[key]

        if (
            b2_partition.row_count
            != f2_partition.row_count
        ):
            raise G2BuilderError(
                "B2/F2 row-count mismatch "
                f"for {key}: "
                f"{b2_partition.row_count} != "
                f"{f2_partition.row_count}"
            )

        total_b2_rows += (
            b2_partition.row_count
        )
        total_f2_rows += (
            f2_partition.row_count
        )

    expected_rows = int(
        contract["output"][
            "reference_row_count"
        ]
    )

    if (
        total_b2_rows != expected_rows
        or total_f2_rows
        != expected_rows
    ):
        raise G2BuilderError(
            "B2/F2 total partition rows "
            "do not match the contract"
        )

    return (
        b2_partitions,
        f2_partitions,
    )


def read_small_table(
    resolved: ResolvedInput,
    columns: Sequence[str],
) -> pa.Table:
    dataset = ds.dataset(
        str(resolved.dataset_root),
        format="parquet",
    )

    table = dataset.to_table(
        columns=list(columns)
    )

    if (
        table.num_rows
        != resolved.reference_row_count
    ):
        raise G2BuilderError(
            "Small-dimension row-count mismatch "
            f"for {resolved.logical_input}"
        )

    return table.combine_chunks()


def canonical_date(value: Any) -> date:
    if hasattr(
        value,
        "to_pydatetime",
    ):
        value = value.to_pydatetime()

    if isinstance(value, datetime):
        return value.date()

    if isinstance(value, date):
        return value

    return date.fromisoformat(
        str(value).strip()[:10]
    )


def dimension_projection(
    resolved: ResolvedInput,
    key_column: str,
    lineage_rows: Sequence[
        Mapping[str, Any]
    ],
) -> tuple[
    dict[Any, int],
    pa.Table,
]:
    columns = required_columns_for_dataset(
        resolved.logical_dataset,
        lineage_rows,
        [key_column],
    )

    table = read_small_table(
        resolved,
        columns,
    )

    key_values = table[
        key_column
    ].to_pylist()

    index: dict[Any, int] = {}

    for row_index, value in enumerate(
        key_values
    ):
        normalized = (
            canonical_date(value)
            if key_column == "data"
            else value
        )

        if normalized in index:
            raise G2BuilderError(
                "Duplicate dimension key in "
                f"{resolved.logical_input}: "
                f"{normalized!r}"
            )

        index[normalized] = row_index

    arrays = []
    names = []

    for lineage in lineage_rows:
        arrays.append(
            table[
                lineage[
                    "source_column"
                ]
            ]
        )
        names.append(
            lineage[
                "output_column"
            ]
        )

    projection = pa.Table.from_arrays(
        arrays,
        names=names,
    ).combine_chunks()

    return index, projection


def dimension_take(
    projection: pa.Table,
    index: Mapping[Any, int],
    keys: Sequence[Any],
    label: str,
) -> pa.Table:
    indices = []

    for key in keys:
        normalized = (
            canonical_date(key)
            if isinstance(
                key,
                (
                    date,
                    datetime,
                ),
            )
            else key
        )

        try:
            indices.append(
                index[normalized]
            )
        except KeyError as exc:
            raise G2BuilderError(
                f"Missing {label} key: "
                f"{normalized!r}"
            ) from exc

    return projection.take(
        pa.array(
            indices,
            type=pa.int32(),
        )
    )


def scalar_for_date(
    data_type: pa.DataType,
    value: date,
) -> pa.Scalar:
    if pa.types.is_timestamp(
        data_type
    ):
        timestamp = datetime.combine(
            value,
            datetime_time.min,
        )

        return pa.scalar(
            timestamp,
            type=data_type,
        )

    if pa.types.is_date32(
        data_type
    ) or pa.types.is_date64(
        data_type
    ):
        return pa.scalar(
            value,
            type=data_type,
        )

    raise G2BuilderError(
        "Unsupported weather date type: "
        f"{data_type}"
    )



_WEATHER_DATE_BOUNDS_CACHE: dict[
    str,
    tuple[date, date],
] = {}


def observed_weather_date_bounds(
    resolved: ResolvedInput,
) -> tuple[date, date]:
    cache_key = str(
        resolved.dataset_root.resolve()
    )

    cached = _WEATHER_DATE_BOUNDS_CACHE.get(
        cache_key
    )

    if cached is not None:
        return cached

    dataset = ds.dataset(
        str(resolved.dataset_root),
        format="parquet",
    )

    table = dataset.to_table(
        columns=["data"],
    ).combine_chunks()

    observed_dates = [
        canonical_date(value)
        for value in table[
            "data"
        ].to_pylist()
        if value is not None
    ]

    if not observed_dates:
        raise G2BuilderError(
            "Observed-weather date coverage "
            "is empty"
        )

    bounds = (
        min(observed_dates),
        max(observed_dates),
    )

    _WEATHER_DATE_BOUNDS_CACHE[
        cache_key
    ] = bounds

    return bounds


def weather_projection_for_dates(
    resolved: ResolvedInput,
    lineage_rows: Sequence[
        Mapping[str, Any]
    ],
    target_dates: Sequence[date],
) -> tuple[
    dict[date, int],
    pa.Table,
]:
    if not target_dates:
        raise G2BuilderError(
            "Target weather date list is empty"
        )

    source_date_field = resolved.schema.field(
        resolved.schema.get_field_index(
            "data"
        )
    )

    observation_start = min(
        target_dates
    )

    observation_end = max(
        target_dates
    )

    source_columns = (
        required_columns_for_dataset(
            resolved.logical_dataset,
            lineage_rows,
            [
                "data",
                "source_location_id",
            ],
        )
    )

    dataset = ds.dataset(
        str(resolved.dataset_root),
        format="parquet",
    )

    (
        observed_weather_min_date,
        observed_weather_max_date,
    ) = observed_weather_date_bounds(
        resolved
    )

    lower = scalar_for_date(
        source_date_field.type,
        observation_start,
    )

    upper = scalar_for_date(
        source_date_field.type,
        observation_end,
    )

    table = dataset.to_table(
        columns=source_columns,
        filter=(
            (ds.field("data") >= lower)
            & (ds.field("data") <= upper)
        ),
    ).combine_chunks()

    target_date_set = set(
        target_dates
    )

    source_dates = table[
        "data"
    ].to_pylist()

    location_ids = table[
        "source_location_id"
    ].to_pylist()

    row_index: dict[
        tuple[date, str],
        int,
    ] = {}

    for index, (
        source_value,
        location_id,
    ) in enumerate(
        zip(
            source_dates,
            location_ids,
        )
    ):
        target_date = canonical_date(
            source_value
        )

        key = (
            target_date,
            str(location_id),
        )

        if key in row_index:
            raise G2BuilderError(
                "Duplicate weather target/location "
                f"key: {key}"
            )

        row_index[key] = index

    lineage_by_slot: dict[
        str,
        list[Mapping[str, Any]],
    ] = defaultdict(list)

    slot_locations: dict[
        str,
        str,
    ] = {}

    for row in lineage_rows:
        slot = str(
            row[
                "generic_location_slot"
            ]
        )

        location_id = str(
            row[
                "source_location_id"
            ]
        )

        if not slot or not location_id:
            raise G2BuilderError(
                "Weather lineage slot/location "
                "is missing"
            )

        previous = slot_locations.get(
            slot
        )

        if (
            previous is not None
            and previous != location_id
        ):
            raise G2BuilderError(
                "Weather slot maps to multiple "
                f"locations: {slot}"
            )

        slot_locations[slot] = (
            location_id
        )

        lineage_by_slot[slot].append(
            row
        )

    expected_slots = {
        "loc_01",
        "loc_02",
        "loc_03",
        "loc_04",
    }

    if set(slot_locations) != (
        expected_slots
    ):
        raise G2BuilderError(
            "Weather slots are incomplete"
        )

    sorted_target_dates = sorted(
        target_date_set
    )

    arrays = []
    names = []

    for slot in (
        "loc_01",
        "loc_02",
        "loc_03",
        "loc_04",
    ):
        location_id = slot_locations[
            slot
        ]

        indices = []

        for target_date in (
            sorted_target_dates
        ):
            key = (
                target_date,
                location_id,
            )

            source_index = row_index.get(
                key
            )

            if source_index is None:
                if (
                    target_date
                    > observed_weather_max_date
                ):
                    indices.append(None)
                    continue

                raise G2BuilderError(
                    "Missing weather row inside "
                    "or before observed coverage "
                    f"for {key}; observed range="
                    f"{observed_weather_min_date}"
                    ".."
                    f"{observed_weather_max_date}"
                )

            indices.append(
                source_index
            )

        take_indices = pa.array(
            indices,
            type=pa.int32(),
        )

        for lineage in sorted(
            lineage_by_slot[slot],
            key=lambda row: int(
                row["ordinal"]
            ),
        ):
            source_column = lineage[
                "source_column"
            ]

            arrays.append(
                pc.take(
                    table[source_column],
                    take_indices,
                )
            )

            names.append(
                lineage[
                    "output_column"
                ]
            )

    if len(names) != 2236:
        raise G2BuilderError(
            "Unexpected wide weather column "
            f"count: {len(names)}"
        )

    projection = pa.Table.from_arrays(
        arrays,
        names=names,
    ).combine_chunks()

    date_index = {
        value: index
        for index, value in enumerate(
            sorted_target_dates
        )
    }

    return date_index, projection


def partition_target_dates(
    partition: PartitionInfo,
) -> list[date]:
    values: set[date] = set()

    for path in partition.files:
        parquet = pq.ParquetFile(
            path
        )

        for batch in parquet.iter_batches(
            columns=["data"],
            batch_size=65536,
        ):
            for value in (
                batch.column(0).to_pylist()
            ):
                normalized = canonical_date(
                    value
                )

                if (
                    normalized.year
                    != partition.year
                    or normalized.month
                    != partition.month
                ):
                    raise G2BuilderError(
                        "B2 partition contains a "
                        "date outside its year/month: "
                        f"{normalized}"
                    )

                values.add(normalized)

    return sorted(values)


def table_batches(
    files: Sequence[Path],
    columns: Sequence[str],
    batch_rows: int,
) -> Iterator[pa.Table]:
    for path in files:
        parquet = pq.ParquetFile(path)

        for batch in parquet.iter_batches(
            columns=list(columns),
            batch_size=batch_rows,
            use_threads=True,
        ):
            yield pa.Table.from_batches(
                [batch]
            )


def aligned_table_batches(
    left_files: Sequence[Path],
    left_columns: Sequence[str],
    right_files: Sequence[Path],
    right_columns: Sequence[str],
    batch_rows: int,
) -> Iterator[
    tuple[
        pa.Table,
        pa.Table,
    ]
]:
    left_iterator = iter(
        table_batches(
            left_files,
            left_columns,
            batch_rows,
        )
    )

    right_iterator = iter(
        table_batches(
            right_files,
            right_columns,
            batch_rows,
        )
    )

    left_table: pa.Table | None = None
    right_table: pa.Table | None = None

    left_offset = 0
    right_offset = 0

    while True:
        if (
            left_table is None
            or left_offset
            >= left_table.num_rows
        ):
            try:
                left_table = next(
                    left_iterator
                )
                left_offset = 0
            except StopIteration:
                left_table = None

        if (
            right_table is None
            or right_offset
            >= right_table.num_rows
        ):
            try:
                right_table = next(
                    right_iterator
                )
                right_offset = 0
            except StopIteration:
                right_table = None

        if (
            left_table is None
            or right_table is None
        ):
            if (
                left_table is None
                and right_table is None
            ):
                break

            raise G2BuilderError(
                "B2/F2 batch streams have "
                "different lengths"
            )

        count = min(
            left_table.num_rows
            - left_offset,
            right_table.num_rows
            - right_offset,
            batch_rows,
        )

        yield (
            left_table.slice(
                left_offset,
                count,
            ),
            right_table.slice(
                right_offset,
                count,
            ),
        )

        left_offset += count
        right_offset += count


def chunked_arrays_equal(
    left: pa.ChunkedArray,
    right: pa.ChunkedArray,
) -> bool:
    return (
        left.combine_chunks().equals(
            right.combine_chunks()
        )
    )


def verify_sorted_keys(
    data_values: Sequence[Any],
    family_values: Sequence[Any],
    previous_key: tuple[
        date,
        str,
    ] | None,
) -> tuple[date, str] | None:
    current_previous = previous_key

    for raw_data, raw_family in zip(
        data_values,
        family_values,
    ):
        current = (
            canonical_date(raw_data),
            str(raw_family),
        )

        if (
            current_previous is not None
            and current
            <= current_previous
        ):
            raise G2BuilderError(
                "B2 keys are not strictly sorted "
                f"or contain duplicates: "
                f"{current_previous} → {current}"
            )

        current_previous = current

    return current_previous


def output_arrays_from_sources(
    contract: Mapping[str, Any],
    b2_table: pa.Table,
    f2_table: pa.Table,
    c2_taken: pa.Table,
    d2_day_taken: pa.Table,
    d2_context_taken: pa.Table,
    weather_taken: pa.Table,
) -> list[
    pa.Array | pa.ChunkedArray
]:
    arrays: dict[
        str,
        pa.Array | pa.ChunkedArray,
    ] = {}

    source_tables = {
        "dense_grids/family_day_dense_grid": (
            b2_table
        ),
        "feature_blocks/dense_sales_family_features": (
            f2_table
        ),
    }

    for dataset_name, table in (
        source_tables.items()
    ):
        for lineage in contract[
            "column_lineage"
        ]:
            if lineage[
                "source_dataset"
            ] != dataset_name:
                continue

            arrays[
                lineage[
                    "output_column"
                ]
            ] = table[
                lineage[
                    "source_column"
                ]
            ]

    for table in (
        c2_taken,
        d2_day_taken,
        d2_context_taken,
        weather_taken,
    ):
        for name in table.column_names:
            if name in arrays:
                raise G2BuilderError(
                    "Unexpected output collision: "
                    f"{name}"
                )

            arrays[name] = table[name]

    output_names = [
        row["name"]
        for row in contract[
            "output"
        ]["schema"]
    ]

    missing = [
        name
        for name in output_names
        if name not in arrays
    ]

    extras = sorted(
        set(arrays)
        - set(output_names)
    )

    if missing or extras:
        raise G2BuilderError(
            "Output mapping mismatch; "
            f"missing={missing[:10]}, "
            f"extras={extras[:10]}"
        )

    return [
        arrays[name]
        for name in output_names
    ]


def execute_build(
    contract: Mapping[str, Any],
    contract_path: Path,
    resolved_inputs: Mapping[
        str,
        ResolvedInput,
    ],
    output_schema: pa.Schema,
    b2_partitions: Mapping[
        tuple[int, int],
        PartitionInfo,
    ],
    f2_partitions: Mapping[
        tuple[int, int],
        PartitionInfo,
    ],
    output_root: Path,
    run_id: str,
    batch_rows: int,
    validator_path: Path,
    runs_root: Path,
    run_ids: Mapping[str, str],
    capacity: Mapping[str, Any],
) -> dict[str, Any]:
    if not validator_path.is_file():
        raise G2BuilderError(
            "Independent validator is required "
            f"before execute mode: "
            f"{validator_path}"
        )

    if not capacity[
        "free_space_sufficient"
    ]:
        raise G2BuilderError(
            "Insufficient free disk space; "
            f"free={capacity['free_bytes']}, "
            "required="
            f"{capacity['required_free_bytes']}"
        )

    output_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    final_run = (
        output_root / run_id
    ).resolve()

    candidate_run = (
        output_root
        / f".{run_id}.candidate"
    ).resolve()

    if final_run.exists():
        raise G2BuilderError(
            f"Final run already exists: "
            f"{final_run}"
        )

    if candidate_run.exists():
        raise G2BuilderError(
            f"Candidate run already exists: "
            f"{candidate_run}"
        )

    candidate_run.mkdir(
        parents=False,
        exist_ok=False,
    )

    metadata_root = (
        candidate_run / "metadata"
    )

    dataset_root = (
        candidate_run
        / "feature_lake"
        / "family_day"
    )

    metadata_root.mkdir(
        parents=True,
        exist_ok=False,
    )

    dataset_root.mkdir(
        parents=True,
        exist_ok=False,
    )

    resolved_manifest = {
        "run_id": run_id,
        "created_at_utc": (
            utc_timestamp()
        ),
        "contract_path": str(
            contract_path
        ),
        "contract_name": (
            contract["contract_name"]
        ),
        "contract_version": (
            contract["version"]
        ),
        "contract_fingerprint": (
            contract[
                "contract_fingerprint"
            ]
        ),
        "output_schema_fingerprint": (
            contract["output"][
                "schema_fingerprint"
            ]
        ),
        "inputs": input_manifest(
            resolved_inputs
        ),
        "run_ids": dict(run_ids),
        "runs_root": str(runs_root),
        "batch_rows": batch_rows,
        "database_write": False,
    }

    write_json_atomic(
        metadata_root
        / (
            "global_family_day_"
            "resolved_inputs.json"
        ),
        resolved_manifest,
    )

    lineage_groups = lineage_by_dataset(
        contract
    )

    dataset_map = source_by_dataset(
        resolved_inputs
    )

    c2_resolved = dataset_map[
        "product_features/"
        "family_product_features"
    ]

    d2_day_resolved = dataset_map[
        "calendar_features/"
        "calendar_day_features"
    ]

    d2_context_resolved = dataset_map[
        "calendar_features/"
        "calendar_context_features"
    ]

    e2_resolved = dataset_map[
        "outputs/"
        "weather_observed_features_day"
    ]

    b2_resolved = dataset_map[
        "dense_grids/"
        "family_day_dense_grid"
    ]

    f2_resolved = dataset_map[
        "feature_blocks/"
        "dense_sales_family_features"
    ]

    c2_index, c2_projection = (
        dimension_projection(
            c2_resolved,
            "famiglia",
            lineage_groups[
                c2_resolved.logical_dataset
            ],
        )
    )

    d2_day_index, d2_day_projection = (
        dimension_projection(
            d2_day_resolved,
            "data",
            lineage_groups[
                d2_day_resolved.logical_dataset
            ],
        )
    )

    (
        d2_context_index,
        d2_context_projection,
    ) = dimension_projection(
        d2_context_resolved,
        "data",
        lineage_groups[
            d2_context_resolved.logical_dataset
        ],
    )

    b2_columns = (
        required_columns_for_dataset(
            b2_resolved.logical_dataset,
            lineage_groups[
                b2_resolved.logical_dataset
            ],
            list(KEY_COLUMNS),
        )
    )

    f2_columns = (
        required_columns_for_dataset(
            f2_resolved.logical_dataset,
            lineage_groups[
                f2_resolved.logical_dataset
            ],
            list(KEY_COLUMNS),
        )
    )

    total_rows_written = 0
    partition_manifests = []
    build_started = utc_timestamp()

    for key in sorted(b2_partitions):
        b2_partition = b2_partitions[key]
        f2_partition = f2_partitions[key]

        target_dates = (
            partition_target_dates(
                b2_partition
            )
        )

        (
            weather_date_index,
            weather_projection,
        ) = weather_projection_for_dates(
            e2_resolved,
            lineage_groups[
                e2_resolved.logical_dataset
            ],
            target_dates,
        )

        partition_directory = (
            dataset_root
            / f"year={b2_partition.year:04d}"
            / f"month={b2_partition.month:02d}"
        )

        partition_directory.mkdir(
            parents=True,
            exist_ok=False,
        )

        output_path = (
            partition_directory
            / "part-00000.parquet"
        )

        writer = pq.ParquetWriter(
            str(output_path),
            output_schema,
            compression="zstd",
            use_dictionary=True,
            write_statistics=True,
        )

        partition_rows_written = 0
        row_group_count = 0
        previous_key: tuple[
            date,
            str,
        ] | None = None

        try:
            for (
                b2_table,
                f2_table,
            ) in aligned_table_batches(
                b2_partition.files,
                b2_columns,
                f2_partition.files,
                f2_columns,
                batch_rows,
            ):
                if (
                    b2_table.num_rows
                    != f2_table.num_rows
                ):
                    raise G2BuilderError(
                        "B2/F2 aligned batch "
                        "row-count mismatch"
                    )

                if not chunked_arrays_equal(
                    b2_table["data"],
                    f2_table["data"],
                ):
                    raise G2BuilderError(
                        "B2/F2 data keys differ"
                    )

                if not chunked_arrays_equal(
                    b2_table["famiglia"],
                    f2_table["famiglia"],
                ):
                    raise G2BuilderError(
                        "B2/F2 famiglia keys differ"
                    )

                data_values = b2_table[
                    "data"
                ].to_pylist()

                family_values = b2_table[
                    "famiglia"
                ].to_pylist()

                previous_key = verify_sorted_keys(
                    data_values,
                    family_values,
                    previous_key,
                )

                c2_taken = dimension_take(
                    c2_projection,
                    c2_index,
                    family_values,
                    "C2 famiglia",
                )

                d2_day_taken = dimension_take(
                    d2_day_projection,
                    d2_day_index,
                    data_values,
                    "D2 calendar-day data",
                )

                d2_context_taken = (
                    dimension_take(
                        d2_context_projection,
                        d2_context_index,
                        data_values,
                        "D2 calendar-context data",
                    )
                )

                weather_taken = dimension_take(
                    weather_projection,
                    weather_date_index,
                    data_values,
                    "E2 target data",
                )

                output_arrays = (
                    output_arrays_from_sources(
                        contract,
                        b2_table,
                        f2_table,
                        c2_taken,
                        d2_day_taken,
                        d2_context_taken,
                        weather_taken,
                    )
                )

                output_table = (
                    pa.Table.from_arrays(
                        output_arrays,
                        schema=output_schema,
                    )
                )

                if (
                    output_table.num_rows
                    != b2_table.num_rows
                ):
                    raise G2BuilderError(
                        "Output row growth or loss "
                        "detected"
                    )

                if not output_table.schema.equals(
                    output_schema,
                    check_metadata=True,
                ):
                    raise G2BuilderError(
                        "Output batch schema differs "
                        "from frozen schema"
                    )

                writer.write_table(
                    output_table,
                    row_group_size=(
                        output_table.num_rows
                    ),
                )

                partition_rows_written += (
                    output_table.num_rows
                )
                total_rows_written += (
                    output_table.num_rows
                )
                row_group_count += 1

                del (
                    output_table,
                    output_arrays,
                    weather_taken,
                    d2_context_taken,
                    d2_day_taken,
                    c2_taken,
                    b2_table,
                    f2_table,
                )
        finally:
            writer.close()

        if (
            partition_rows_written
            != b2_partition.row_count
        ):
            raise G2BuilderError(
                "Partition output row-count "
                "mismatch for "
                f"{key}: "
                f"{partition_rows_written} != "
                f"{b2_partition.row_count}"
            )

        parquet = pq.ParquetFile(
            output_path
        )

        if (
            parquet.metadata.num_rows
            != partition_rows_written
        ):
            raise G2BuilderError(
                "Written Parquet footer row-count "
                "mismatch"
            )

        if not (
            parquet.schema_arrow
            .remove_metadata()
            .equals(
                output_schema.remove_metadata()
            )
        ):
            raise G2BuilderError(
                "Written Parquet schema mismatch"
            )

        partition_manifests.append(
            {
                "year": b2_partition.year,
                "month": b2_partition.month,
                "target_date_count": len(
                    target_dates
                ),
                "rows": (
                    partition_rows_written
                ),
                "row_groups": (
                    row_group_count
                ),
                "file": str(
                    output_path.relative_to(
                        candidate_run
                    )
                ),
                "file_size_bytes": (
                    output_path.stat().st_size
                ),
                "file_sha256": (
                    file_sha256(
                        output_path
                    )
                ),
            }
        )

    expected_rows = int(
        contract["output"][
            "reference_row_count"
        ]
    )

    if total_rows_written != (
        expected_rows
    ):
        raise G2BuilderError(
            "Final output row-count mismatch: "
            f"{total_rows_written} != "
            f"{expected_rows}"
        )

    build_manifest = {
        "ok": True,
        "classification": (
            "PHASE2M_G2_FAMILY_DAY_"
            "CANDIDATE_BUILD_OK"
        ),
        "decision": (
            "READY_FOR_PHASE2M_G2_"
            "INDEPENDENT_VALIDATION"
        ),
        "run_id": run_id,
        "candidate_run": str(
            candidate_run
        ),
        "dataset": (
            contract["output"][
                "dataset"
            ]
        ),
        "grain": (
            contract["output"][
                "grain"
            ]
        ),
        "rows": total_rows_written,
        "columns": (
            contract["output"][
                "column_count"
            ]
        ),
        "partition_count": len(
            partition_manifests
        ),
        "partitions": (
            partition_manifests
        ),
        "contract_fingerprint": (
            contract[
                "contract_fingerprint"
            ]
        ),
        "schema_fingerprint": (
            contract["output"][
                "schema_fingerprint"
            ]
        ),
        "batch_rows": batch_rows,
        "compression": "zstd",
        "build_started_at_utc": (
            build_started
        ),
        "build_finished_at_utc": (
            utc_timestamp()
        ),
        "database_write": False,
        "success_marker_written": False,
        "promoted": False,
    }

    build_manifest_path = (
        metadata_root
        / (
            "global_family_day_"
            "build_manifest.json"
        )
    )

    write_json_atomic(
        build_manifest_path,
        build_manifest,
    )

    validator_command = [
        sys.executable,
        str(validator_path),
        "--contract",
        str(contract_path),
        "--candidate-run",
        str(candidate_run),
        "--runs-root",
        str(runs_root),
        "--b2-run",
        run_ids["B2"],
        "--c2-run",
        run_ids["C2"],
        "--d2-run",
        run_ids["D2"],
        "--e2-run",
        run_ids["E2"],
        "--f2-run",
        run_ids["F2"],
    ]

    try:
        del b2_partition
    except NameError:
        pass

    try:
        del b2_table
    except NameError:
        pass

    try:
        del c2_index
    except NameError:
        pass

    try:
        del c2_projection
    except NameError:
        pass

    try:
        del c2_taken
    except NameError:
        pass

    try:
        del d2_context_index
    except NameError:
        pass

    try:
        del d2_context_projection
    except NameError:
        pass

    try:
        del d2_context_taken
    except NameError:
        pass

    try:
        del d2_day_index
    except NameError:
        pass

    try:
        del d2_day_projection
    except NameError:
        pass

    try:
        del d2_day_taken
    except NameError:
        pass

    try:
        del f2_partition
    except NameError:
        pass

    try:
        del f2_table
    except NameError:
        pass

    try:
        del lineage_groups
    except NameError:
        pass

    try:
        del output_arrays
    except NameError:
        pass

    try:
        del output_schema
    except NameError:
        pass

    try:
        del output_table
    except NameError:
        pass

    try:
        del parquet
    except NameError:
        pass

    try:
        del resolved_inputs
    except NameError:
        pass

    try:
        del target_dates
    except NameError:
        pass

    try:
        del weather_date_index
    except NameError:
        pass

    try:
        del weather_projection
    except NameError:
        pass

    try:
        del weather_taken
    except NameError:
        pass

    try:
        del writer
    except NameError:
        pass

    try:
        del b2_partitions
    except NameError:
        pass

    try:
        del f2_partitions
    except NameError:
        pass

    pre_validator_memory_release = (
        release_process_memory()
    )

    build_manifest[
        "pre_validator_memory_release"
    ] = pre_validator_memory_release

    write_json_atomic(
        build_manifest_path,
        build_manifest,
    )

    write_json_atomic(
        metadata_root
        / (
            "global_family_day_"
            "pre_validator_memory_release.json"
        ),
        pre_validator_memory_release,
    )

    del build_manifest
    del pre_validator_memory_release

    final_pre_validator_release = (
        release_process_memory()
    )

    write_json_atomic(
        metadata_root
        / (
            "global_family_day_"
            "pre_validator_final_release.json"
        ),
        final_pre_validator_release,
    )

    del final_pre_validator_release

    gc.collect()
    pa.default_memory_pool().release_unused()

    subprocess.run(
        validator_command,
        check=True,
    )

    validation_path = (
        metadata_root
        / (
            "global_family_day_"
            "validation.json"
        )
    )

    if not validation_path.is_file():
        raise G2BuilderError(
            "Independent validator did not "
            "write its required report"
        )

    validation = json.loads(
        validation_path.read_text(
            encoding="utf-8"
        )
    )

    if validation.get("ok") is not True:
        raise G2BuilderError(
            "Independent validator did not pass"
        )

    success_payload = {
        "run_id": run_id,
        "validated_at_utc": (
            utc_timestamp()
        ),
        "contract_fingerprint": (
            contract[
                "contract_fingerprint"
            ]
        ),
        "schema_fingerprint": (
            contract["output"][
                "schema_fingerprint"
            ]
        ),
        "rows": total_rows_written,
        "columns": (
            contract["output"][
                "column_count"
            ]
        ),
        "validator_classification": (
            validation.get(
                "classification"
            )
        ),
    }

    write_json_atomic(
        candidate_run / "_SUCCESS",
        success_payload,
    )

    os.replace(
        candidate_run,
        final_run,
    )

    final_manifest_path = (
        final_run
        / "metadata"
        / (
            "global_family_day_"
            "build_manifest.json"
        )
    )

    final_manifest = json.loads(
        final_manifest_path.read_text(
            encoding="utf-8"
        )
    )

    final_manifest["candidate_run"] = (
        str(candidate_run)
    )
    final_manifest["final_run"] = str(
        final_run
    )
    final_manifest[
        "success_marker_written"
    ] = True
    final_manifest["promoted"] = True
    final_manifest[
        "promoted_at_utc"
    ] = utc_timestamp()

    write_json_atomic(
        final_manifest_path,
        final_manifest,
    )

    return {
        "ok": True,
        "classification": (
            "PHASE2M_G2_FAMILY_DAY_"
            "BUILD_AND_PROMOTION_OK"
        ),
        "decision": (
            "READY_FOR_PHASE2M_H2_"
            "FAMILY_PRICEBAND_ASSEMBLY"
        ),
        "run_id": run_id,
        "final_run": str(final_run),
        "rows": total_rows_written,
        "columns": (
            contract["output"][
                "column_count"
            ]
        ),
        "partition_count": len(
            partition_manifests
        ),
        "contract_fingerprint": (
            contract[
                "contract_fingerprint"
            ]
        ),
        "schema_fingerprint": (
            contract["output"][
                "schema_fingerprint"
            ]
        ),
        "database_write": False,
        "blockers": [],
    }


def validator_command(
    validator_path: Path,
    contract_path: Path,
    candidate_run: Path,
    runs_root: Path,
    run_ids: Mapping[str, str],
) -> list[str]:
    return [
        sys.executable,
        str(validator_path),
        "--contract",
        str(contract_path),
        "--candidate-run",
        str(candidate_run),
        "--runs-root",
        str(runs_root),
        "--b2-run",
        run_ids["B2"],
        "--c2-run",
        run_ids["C2"],
        "--d2-run",
        run_ids["D2"],
        "--e2-run",
        run_ids["E2"],
        "--f2-run",
        run_ids["F2"],
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build the contract-driven Phase "
            "2M-G2 dense family-day feature lake."
        )
    )

    parser.add_argument(
        "--mode",
        choices=(
            "dry-run",
            "execute",
            "validate-only",
        ),
        default="dry-run",
        help=(
            "dry-run reads only schemas and "
            "footers; execute builds a candidate "
            "and requires the independent "
            "validator; validate-only delegates "
            "to the independent validator."
        ),
    )

    parser.add_argument(
        "--contract",
        type=Path,
        default=DEFAULT_CONTRACT,
        help="Frozen executable G2 contract.",
    )

    parser.add_argument(
        "--runs-root",
        type=Path,
        default=DEFAULT_RUNS_ROOT,
        help="Root containing upstream run IDs.",
    )

    parser.add_argument(
        "--b2-run",
        help=(
            "B2 run ID. Defaults to the "
            "contract reference fixture."
        ),
    )

    parser.add_argument(
        "--c2-run",
        help=(
            "C2 run ID. Defaults to the "
            "contract reference fixture."
        ),
    )

    parser.add_argument(
        "--d2-run",
        help=(
            "D2 run ID. Defaults to the "
            "contract reference fixture."
        ),
    )

    parser.add_argument(
        "--e2-run",
        help=(
            "E2 run ID. Defaults to the "
            "contract reference fixture."
        ),
    )

    parser.add_argument(
        "--f2-run",
        help=(
            "F2 run ID. Defaults to the "
            "contract reference fixture."
        ),
    )

    parser.add_argument(
        "--output-root",
        type=Path,
        help=(
            "Run root used for execute mode. "
            "Defaults to --runs-root."
        ),
    )

    parser.add_argument(
        "--run-id",
        help=(
            "Output run ID. Generated "
            "automatically in execute mode "
            "when omitted."
        ),
    )

    parser.add_argument(
        "--batch-rows",
        type=int,
        default=8192,
        help=(
            "Maximum B2/F2 rows assembled per "
            "wide output batch."
        ),
    )

    parser.add_argument(
        "--validator",
        type=Path,
        default=DEFAULT_VALIDATOR,
        help=(
            "Independent G2 validator required "
            "for execute and validate-only."
        ),
    )

    parser.add_argument(
        "--existing-run",
        type=Path,
        help=(
            "Candidate/final run passed to the "
            "validator in validate-only mode."
        ),
    )

    parser.add_argument(
        "--dry-run-report",
        type=Path,
        help=(
            "Optional JSON report written by "
            "dry-run mode."
        ),
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.batch_rows < 512:
        raise G2BuilderError(
            "--batch-rows must be at least 512"
        )

    contract_path = args.contract.resolve(
        strict=True
    )

    runs_root = args.runs_root.resolve(
        strict=True
    )

    validator_path = args.validator.resolve()

    contract = load_contract(
        contract_path
    )

    run_ids = resolve_run_ids(
        contract,
        args,
    )

    if args.mode == "validate-only":
        if args.existing_run is None:
            raise G2BuilderError(
                "--existing-run is required for "
                "validate-only"
            )

        if not validator_path.is_file():
            raise G2BuilderError(
                "Independent validator not found: "
                f"{validator_path}"
            )

        command = validator_command(
            validator_path,
            contract_path,
            args.existing_run.resolve(
                strict=True
            ),
            runs_root,
            run_ids,
        )

        completed = subprocess.run(
            command,
            check=False,
        )

        return completed.returncode

    resolved_inputs = resolve_inputs(
        contract,
        runs_root,
        run_ids,
    )

    output_schema = (
        validate_lineage_against_sources(
            contract,
            resolved_inputs,
        )
    )

    (
        b2_partitions,
        f2_partitions,
    ) = validate_partition_alignment(
        contract,
        resolved_inputs,
    )

    output_root = (
        args.output_root.resolve()
        if args.output_root is not None
        else runs_root
    )

    capacity = capacity_estimate(
        contract,
        output_root,
    )

    validator_present = (
        validator_path.is_file()
    )

    execute_blockers = []

    if not validator_present:
        execute_blockers.append(
            "independent_validator_not_found"
        )

    if not capacity[
        "free_space_sufficient"
    ]:
        execute_blockers.append(
            "free_disk_below_conservative_"
            "execution_threshold"
        )

    dry_run_report = {
        "ok": True,
        "classification": (
            "PHASE2M_G2_BUILDER_DRY_RUN_OK"
        ),
        "decision": (
            "READY_FOR_PHASE2M_G2_"
            "VALIDATOR_SOURCE_IMPLEMENTATION"
            if not validator_present
            else (
                "READY_FOR_PHASE2M_G2_"
                "REFERENCE_EXECUTION_REVIEW"
            )
        ),
        "mode": "dry-run",
        "builder_source": str(
            Path(__file__).resolve()
        ),
        "contract": {
            "path": str(contract_path),
            "name": (
                contract[
                    "contract_name"
                ]
            ),
            "version": (
                contract["version"]
            ),
            "fingerprint": (
                contract[
                    "contract_fingerprint"
                ]
            ),
            "schema_fingerprint": (
                contract["output"][
                    "schema_fingerprint"
                ]
            ),
            "column_lineage_fingerprint": (
                contract[
                    "execution_mapping_policy"
                ][
                    "column_lineage_fingerprint"
                ]
            ),
        },
        "output": {
            "dataset": (
                contract["output"][
                    "dataset"
                ]
            ),
            "grain": (
                contract["output"][
                    "grain"
                ]
            ),
            "reference_rows": (
                contract["output"][
                    "reference_row_count"
                ]
            ),
            "columns": (
                contract["output"][
                    "column_count"
                ]
            ),
            "partition_count": len(
                b2_partitions
            ),
            "batch_rows": args.batch_rows,
        },
        "inputs": input_manifest(
            resolved_inputs
        ),
        "b2_f2_partition_alignment": {
            "exact": True,
            "partition_count": len(
                b2_partitions
            ),
            "rows": sum(
                partition.row_count
                for partition
                in b2_partitions.values()
            ),
        },
        "output_arrow_schema": {
            "field_count": len(
                output_schema
            ),
            "metadata_present": (
                output_schema.metadata
                is not None
            ),
        },
        "capacity": capacity,
        "validator": {
            "path": str(
                validator_path
            ),
            "present": (
                validator_present
            ),
        },
        "execute_ready": (
            not execute_blockers
        ),
        "execute_blockers": (
            execute_blockers
        ),
        "source_changes": False,
        "parquet_footer_read": True,
        "parquet_schema_read": True,
        "parquet_data_rows_read": 0,
        "parquet_write": False,
        "database_access": False,
        "git_actions": False,
        "blockers": [],
    }

    if args.mode == "dry-run":
        if args.dry_run_report is not None:
            write_json_atomic(
                args.dry_run_report.resolve(),
                dry_run_report,
            )

        print(
            json.dumps(
                dry_run_report,
                indent=2,
                ensure_ascii=False,
            )
        )

        return 0

    if args.mode != "execute":
        raise G2BuilderError(
            f"Unsupported mode: {args.mode}"
        )

    run_id = (
        args.run_id
        or generated_run_id()
    )

    result = execute_build(
        contract=contract,
        contract_path=contract_path,
        resolved_inputs=resolved_inputs,
        output_schema=output_schema,
        b2_partitions=b2_partitions,
        f2_partitions=f2_partitions,
        output_root=output_root,
        run_id=run_id,
        batch_rows=args.batch_rows,
        validator_path=validator_path,
        runs_root=runs_root,
        run_ids=run_ids,
        capacity=capacity,
    )

    print(
        json.dumps(
            result,
            indent=2,
            ensure_ascii=False,
        )
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except G2BuilderError as exc:
        print(
            f"ERROR={exc}",
            file=sys.stderr,
        )
        raise SystemExit(2)
