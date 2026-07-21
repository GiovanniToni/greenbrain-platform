#!/usr/bin/env python3
"""Independently validate the Phase 2M-G2 family-day feature lake.

Validation is contract-driven and does not import the G2 builder. The validator
resolves the same six logical upstream inputs independently and verifies:

- frozen contract and executable lineage;
- exact output schema, partitions, compression and row counts;
- full B2 key preservation and strict key ordering;
- complete B2 and F2 source-column coherence;
- complete C2 and D2 dimension coherence;
- same-event-day weather mapping on a deterministic multi-column sentinel set
  spanning all four generic location slots;
- candidate metadata, provenance and no-database-output guarantees.

The validator writes its report inside the candidate run. The builder may only
promote the candidate after this module returns success.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import tempfile
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date, datetime, time as datetime_time, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator, Mapping, Sequence

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

YEAR_MONTH_PATTERN = re.compile(
    r"(?<!\d)(20\d{2})[-_]?([01]\d)(?!\d)"
)

FORBIDDEN_DATABASE_MODULE_PREFIXES = (
    "psycopg",
    "psycopg2",
    "sqlalchemy",
    "supabase",
    "asyncpg",
)


class G2ValidationError(RuntimeError):
    """Raised when a blocking G2 validation invariant fails."""


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
    compression_values: tuple[str, ...]


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


def utc_timestamp() -> str:
    return datetime.now(
        timezone.utc
    ).replace(
        microsecond=0
    ).isoformat().replace(
        "+00:00",
        "Z",
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


def write_tsv_atomic(
    path: Path,
    rows: Sequence[Mapping[str, Any]],
    fields: Sequence[str],
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        temporary_path = Path(
            handle.name
        )

        writer = csv.DictWriter(
            handle,
            fieldnames=list(fields),
            delimiter="\t",
            lineterminator="\n",
        )

        writer.writeheader()
        writer.writerows(rows)
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
        raise G2ValidationError(
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
        raise G2ValidationError(
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
        raise G2ValidationError(
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
            raise G2ValidationError(
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
        compression_values: set[str] = set()

        for path in sorted(files):
            parquet = pq.ParquetFile(
                path
            )

            metadata = parquet.metadata

            row_count += metadata.num_rows
            row_group_count += (
                metadata.num_row_groups
            )
            size_bytes += (
                path.stat().st_size
            )

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
            compression_values=tuple(
                sorted(
                    compression_values
                )
            ),
        )

    return result


def load_contract(
    path: Path,
) -> dict[str, Any]:
    if not path.is_file():
        raise G2ValidationError(
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
        raise G2ValidationError(
            "Contract fingerprint is missing"
        ) from exc

    calculated_fingerprint = (
        canonical_fingerprint(payload)
    )

    if (
        stored_fingerprint
        != calculated_fingerprint
    ):
        raise G2ValidationError(
            "Contract fingerprint mismatch"
        )

    if contract.get(
        "contract_status"
    ) != "frozen":
        raise G2ValidationError(
            "Contract is not frozen"
        )

    if contract.get("phase") != "2M-G2":
        raise G2ValidationError(
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
        raise G2ValidationError(
            "Contract output schema is missing"
        )

    if canonical_fingerprint(
        schema_descriptor
    ) != output.get(
        "schema_fingerprint"
    ):
        raise G2ValidationError(
            "Output schema fingerprint mismatch"
        )

    if len(schema_descriptor) != output.get(
        "column_count"
    ):
        raise G2ValidationError(
            "Output schema column count mismatch"
        )

    lineage = contract.get(
        "column_lineage"
    )

    if not isinstance(lineage, list):
        raise G2ValidationError(
            "Executable column lineage is missing"
        )

    if len(lineage) != len(
        schema_descriptor
    ):
        raise G2ValidationError(
            "Column lineage count mismatch"
        )

    if [
        row.get("ordinal")
        for row in lineage
    ] != list(
        range(
            1,
            len(lineage) + 1,
        )
    ):
        raise G2ValidationError(
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
        raise G2ValidationError(
            "Lineage/output schema order mismatch"
        )

    if len(schema_names) != len(
        set(schema_names)
    ):
        raise G2ValidationError(
            "Output column names are not unique"
        )

    mapping_policy = contract.get(
        "execution_mapping_policy",
        {},
    )

    if canonical_fingerprint(
        lineage
    ) != mapping_policy.get(
        "column_lineage_fingerprint"
    ):
        raise G2ValidationError(
            "Column lineage fingerprint mismatch"
        )

    if mapping_policy.get(
        "heuristic_source_resolution_allowed"
    ) is not False:
        raise G2ValidationError(
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
        raise G2ValidationError(
            "Weather target-date policy must be "
            "EVENT_DAY_SAME_DATE"
        )

    if weather_policy.get(
        "same_day_actual_eligibility"
    ) != "RETROSPECTIVE_ONLY":
        raise G2ValidationError(
            "Same-day actual weather must be "
            "RETROSPECTIVE_ONLY"
        )

    if weather_policy.get(
        "explicit_lag_eligibility"
    ) != "PREDICTION_ELIGIBLE":
        raise G2ValidationError(
            "Explicit weather lags must be "
            "PREDICTION_ELIGIBLE"
        )

    if weather_policy.get(
        "shifted_rolling_eligibility"
    ) != "PREDICTION_ELIGIBLE":
        raise G2ValidationError(
            "Shifted weather rolling features "
            "must be PREDICTION_ELIGIBLE"
        )

    if weather_policy.get(
        "forecast_columns_in_base_g2"
    ) is not False:
        raise G2ValidationError(
            "Forecast columns must be excluded "
            "from base G2"
        )

    if weather_policy.get(
        "forecast_overlay_dataset"
    ) != "weather_prediction_day_asof":
        raise G2ValidationError(
            "Forecast overlay dataset must be "
            "weather_prediction_day_asof"
        )


    if weather_policy.get(
        "coverage_policy"
    ) != (
        "ALLOW_NULL_ONLY_AFTER_"
        "OBSERVED_WEATHER_MAX_DATE"
    ):
        raise G2ValidationError(
            "Weather coverage policy must allow "
            "nulls only after the observed "
            "weather maximum date"
        )

    if weather_policy.get(
        "internal_gap_policy"
    ) != "FORBID":
        raise G2ValidationError(
            "Internal weather gaps must be "
            "forbidden"
        )

    if weather_policy.get(
        "pre_observation_gap_policy"
    ) != "FORBID":
        raise G2ValidationError(
            "Pre-observation weather gaps must "
            "be forbidden"
        )

    if weather_policy.get(
        "trailing_gap_fill"
    ) != "NULL":
        raise G2ValidationError(
            "Trailing weather gaps must use "
            "null values"
        )

    if weather_policy.get(
        "previous_day_relabeling"
    ) != "FORBID":
        raise G2ValidationError(
            "Previous-day weather relabeling "
            "must be forbidden"
        )

    if weather_policy.get(
        "missingness_scope"
    ) != "WEATHER_COLUMNS_ONLY":
        raise G2ValidationError(
            "Trailing missingness must be "
            "limited to weather columns"
        )

    if contract.get(
        "materialization_policy",
        {},
    ).get(
        "database_write"
    ) is not False:
        raise G2ValidationError(
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
            raise G2ValidationError(
                f"Run ID is required for {phase}"
            )

        if "/" in run_id or "\\" in run_id:
            raise G2ValidationError(
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
        raise G2ValidationError(
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
            raise G2ValidationError(
                f"No run ID resolved for {phase}"
            )

        if logical_dataset in seen_datasets:
            raise G2ValidationError(
                "Duplicate logical dataset: "
                f"{logical_dataset}"
            )

        seen_datasets.add(
            logical_dataset
        )

        run_id = run_ids[phase]
        run_root = (
            runs_root / run_id
        ).resolve()

        if not run_root.is_dir():
            raise G2ValidationError(
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
            raise G2ValidationError(
                "Resolved dataset escapes run root"
            ) from exc

        if not dataset_root.exists():
            raise G2ValidationError(
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
            raise G2ValidationError(
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
            raise G2ValidationError(
                "Duplicate logical input: "
                f"{logical_input}"
            )

        resolved[
            logical_input
        ] = resolved_input

    if len(resolved) != len(
        required_inputs
    ):
        raise G2ValidationError(
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
            raise G2ValidationError(
                "Dataset appears more than once: "
                f"{dataset}"
            )

        result[dataset] = resolved

    return result


def expected_output_schema(
    contract: Mapping[str, Any],
    resolved_inputs: Mapping[
        str,
        ResolvedInput,
    ],
) -> pa.Schema:
    datasets = source_by_dataset(
        resolved_inputs
    )

    fields = []

    for descriptor, lineage in zip(
        contract["output"]["schema"],
        contract["column_lineage"],
    ):
        dataset_name = lineage[
            "source_dataset"
        ]

        resolved = datasets.get(
            dataset_name
        )

        if resolved is None:
            raise G2ValidationError(
                "Lineage dataset is unresolved: "
                f"{dataset_name}"
            )

        source_column = lineage[
            "source_column"
        ]

        source_index = (
            resolved.schema.get_field_index(
                source_column
            )
        )

        if source_index < 0:
            raise G2ValidationError(
                "Lineage source column not found: "
                f"{dataset_name}.{source_column}"
            )

        source_field = resolved.schema.field(
            source_index
        )

        if str(source_field.type) != (
            descriptor["type"]
        ):
            raise G2ValidationError(
                "Lineage type mismatch for "
                f"{lineage['output_column']}"
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

    return pa.schema(fields)


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
        raise G2ValidationError(
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
        raise G2ValidationError(
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
        raise G2ValidationError(
            "Unexpected B2/F2 partition count"
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
            raise G2ValidationError(
                "B2/F2 partition row-count "
                f"mismatch for {key}"
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
        raise G2ValidationError(
            "B2/F2 total rows do not match "
            "the contract"
        )

    return (
        b2_partitions,
        f2_partitions,
    )


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


def scalar_for_date(
    data_type: pa.DataType,
    value: date,
) -> pa.Scalar:
    if pa.types.is_timestamp(
        data_type
    ):
        return pa.scalar(
            datetime.combine(
                value,
                datetime_time.min,
            ),
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

    raise G2ValidationError(
        "Unsupported date type: "
        f"{data_type}"
    )


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


def aligned_table_streams(
    specifications: Sequence[
        tuple[
            Sequence[Path],
            Sequence[str],
        ]
    ],
    batch_rows: int,
) -> Iterator[list[pa.Table]]:
    iterators = [
        iter(
            table_batches(
                files,
                columns,
                batch_rows,
            )
        )
        for files, columns
        in specifications
    ]

    tables: list[
        pa.Table | None
    ] = [
        None
        for _ in iterators
    ]

    offsets = [
        0
        for _ in iterators
    ]

    while True:
        exhausted = []

        for index, iterator in enumerate(
            iterators
        ):
            table = tables[index]

            if (
                table is None
                or offsets[index]
                >= table.num_rows
            ):
                try:
                    tables[index] = next(
                        iterator
                    )
                    offsets[index] = 0
                except StopIteration:
                    tables[index] = None

            exhausted.append(
                tables[index] is None
            )

        if all(exhausted):
            break

        if any(exhausted):
            raise G2ValidationError(
                "Aligned table streams have "
                "different lengths"
            )

        counts = [
            table.num_rows - offset
            for table, offset
            in zip(
                tables,
                offsets,
            )
            if table is not None
        ]

        count = min(
            min(counts),
            batch_rows,
        )

        slices = [
            table.slice(
                offset,
                count,
            )
            for table, offset
            in zip(
                tables,
                offsets,
            )
            if table is not None
        ]

        yield slices

        for index in range(
            len(offsets)
        ):
            offsets[index] += count


def arrays_equal(
    left: pa.ChunkedArray,
    right: pa.ChunkedArray,
) -> bool:
    return (
        left.combine_chunks().equals(
            right.combine_chunks()
        )
    )


def verify_strictly_sorted_keys(
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
            raise G2ValidationError(
                "Candidate keys are not strictly "
                "sorted or contain duplicates: "
                f"{current_previous} → {current}"
            )

        current_previous = current

    return current_previous


def array_equals_scalar(
    values: pa.ChunkedArray,
    scalar: pa.Scalar,
) -> bool:
    comparison = pc.equal(
        values,
        scalar,
    )

    comparison = pc.fill_null(
        comparison,
        False,
    )

    result = pc.all(comparison).as_py()

    return bool(result)


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
        raise G2ValidationError(
            "Small-dimension row-count mismatch "
            f"for {resolved.logical_input}"
        )

    return table.combine_chunks()


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
            raise G2ValidationError(
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

    return (
        index,
        pa.Table.from_arrays(
            arrays,
            names=names,
        ).combine_chunks(),
    )


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
            raise G2ValidationError(
                f"Missing {label} key: "
                f"{normalized!r}"
            ) from exc

    return projection.take(
        pa.array(
            indices,
            type=pa.int32(),
        )
    )


def validate_projection_table(
    candidate: pa.Table,
    expected: pa.Table,
    output_columns: Sequence[str],
    label: str,
) -> None:
    if (
        candidate.num_rows
        != expected.num_rows
    ):
        raise G2ValidationError(
            f"{label} row-count mismatch"
        )

    for output_column in (
        output_columns
    ):
        if not arrays_equal(
            candidate[output_column],
            expected[output_column],
        ):
            raise G2ValidationError(
                f"{label} value mismatch for "
                f"{output_column}"
            )


def target_dates_for_partition(
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
                    raise G2ValidationError(
                        "B2 partition contains a "
                        "date outside its year/month"
                    )

                values.add(normalized)

    return sorted(values)


def select_weather_sentinels(
    lineage_rows: Sequence[
        Mapping[str, Any]
    ],
    per_slot: int,
) -> dict[
    str,
    list[dict[str, Any]],
]:
    by_slot: dict[
        str,
        list[dict[str, Any]],
    ] = defaultdict(list)

    for row in lineage_rows:
        slot = str(
            row[
                "generic_location_slot"
            ]
        )

        if slot not in {
            "loc_01",
            "loc_02",
            "loc_03",
            "loc_04",
        }:
            raise G2ValidationError(
                "Unexpected weather slot in "
                "contract lineage"
            )

        by_slot[slot].append(
            dict(row)
        )

    if set(by_slot) != {
        "loc_01",
        "loc_02",
        "loc_03",
        "loc_04",
    }:
        raise G2ValidationError(
            "Weather slot set is incomplete"
        )

    source_sequences = []

    for slot in (
        "loc_01",
        "loc_02",
        "loc_03",
        "loc_04",
    ):
        rows = sorted(
            by_slot[slot],
            key=lambda row: int(
                row["ordinal"]
            ),
        )

        if len(rows) != 559:
            raise G2ValidationError(
                "Unexpected weather lineage count "
                f"for {slot}: {len(rows)}"
            )

        source_sequences.append(
            [
                row["source_column"]
                for row in rows
            ]
        )

        by_slot[slot] = rows

    if not all(
        sequence
        == source_sequences[0]
        for sequence
        in source_sequences[1:]
    ):
        raise G2ValidationError(
            "Weather source-column order differs "
            "between slots"
        )

    count = len(
        source_sequences[0]
    )

    requested = max(
        8,
        min(
            per_slot,
            count,
        ),
    )

    positions = {
        0,
        1,
        2,
        count // 8,
        count // 4,
        count // 2,
        (3 * count) // 4,
        (7 * count) // 8,
        count - 3,
        count - 2,
        count - 1,
    }

    if requested > len(positions):
        step = max(
            1,
            count // requested,
        )

        positions.update(
            range(
                0,
                count,
                step,
            )
        )

    selected_positions = sorted(
        position
        for position in positions
        if 0 <= position < count
    )

    if len(selected_positions) > (
        requested
    ):
        evenly_spaced_indexes = []

        for index in range(requested):
            if requested == 1:
                position = 0
            else:
                position = round(
                    index
                    * (
                        len(
                            selected_positions
                        )
                        - 1
                    )
                    / (
                        requested - 1
                    )
                )

            evenly_spaced_indexes.append(
                selected_positions[
                    position
                ]
            )

        selected_positions = sorted(
            set(
                evenly_spaced_indexes
            )
        )

    while len(selected_positions) < (
        requested
    ):
        candidate = round(
            len(selected_positions)
            * (count - 1)
            / max(
                requested - 1,
                1,
            )
        )

        selected_positions.append(
            candidate
        )

        selected_positions = sorted(
            set(
                selected_positions
            )
        )

    selected_positions = (
        selected_positions[:requested]
    )

    return {
        slot: [
            by_slot[slot][position]
            for position
            in selected_positions
        ]
        for slot in (
            "loc_01",
            "loc_02",
            "loc_03",
            "loc_04",
        )
    }



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
        raise G2ValidationError(
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
    selected_by_slot: Mapping[
        str,
        Sequence[Mapping[str, Any]],
    ],
    target_dates: Sequence[date],
) -> tuple[
    dict[date, int],
    pa.Table,
]:
    if not target_dates:
        raise G2ValidationError(
            "Target weather dates are empty"
        )

    source_column_names = []

    for rows in selected_by_slot.values():
        for row in rows:
            source_column = str(
                row["source_column"]
            )

            if (
                source_column
                not in source_column_names
            ):
                source_column_names.append(
                    source_column
                )

    source_columns = [
        "data",
        "source_location_id",
        *source_column_names,
    ]

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

    lower = scalar_for_date(
        source_date_field.type,
        observation_start,
    )

    upper = scalar_for_date(
        source_date_field.type,
        observation_end,
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

    table = dataset.to_table(
        columns=source_columns,
        filter=(
            (ds.field("data") >= lower)
            & (ds.field("data") <= upper)
        ),
    ).combine_chunks()

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
            raise G2ValidationError(
                "Duplicate E2 target-date/"
                f"location key: {key}"
            )

        row_index[key] = index

    sorted_target_dates = sorted(
        set(target_dates)
    )

    arrays = []
    names = []

    for slot in (
        "loc_01",
        "loc_02",
        "loc_03",
        "loc_04",
    ):
        rows = list(
            selected_by_slot[slot]
        )

        location_ids_for_slot = {
            str(
                row[
                    "source_location_id"
                ]
            )
            for row in rows
        }

        if len(
            location_ids_for_slot
        ) != 1:
            raise G2ValidationError(
                "Weather sentinel slot maps to "
                "multiple locations"
            )

        location_id = next(
            iter(
                location_ids_for_slot
            )
        )

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

                raise G2ValidationError(
                    "Missing E2 weather row inside "
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

        for row in rows:
            arrays.append(
                pc.take(
                    table[
                        row[
                            "source_column"
                        ]
                    ],
                    take_indices,
                )
            )

            names.append(
                row[
                    "output_column"
                ]
            )

    projection = pa.Table.from_arrays(
        arrays,
        names=names,
    ).combine_chunks()

    return (
        {
            target_date: index
            for index, target_date
            in enumerate(
                sorted_target_dates
            )
        },
        projection,
    )


def validate_candidate_metadata(
    candidate_run: Path,
    contract: Mapping[str, Any],
    run_ids: Mapping[str, str],
    resolved_inputs: Mapping[
        str,
        ResolvedInput,
    ],
) -> dict[str, Any]:
    metadata_root = (
        candidate_run / "metadata"
    )

    resolved_path = (
        metadata_root
        / (
            "global_family_day_"
            "resolved_inputs.json"
        )
    )

    manifest_path = (
        metadata_root
        / (
            "global_family_day_"
            "build_manifest.json"
        )
    )

    if not resolved_path.is_file():
        raise G2ValidationError(
            "Resolved-input metadata is missing"
        )

    if not manifest_path.is_file():
        raise G2ValidationError(
            "Build manifest is missing"
        )

    resolved_metadata = json.loads(
        resolved_path.read_text(
            encoding="utf-8"
        )
    )

    build_manifest = json.loads(
        manifest_path.read_text(
            encoding="utf-8"
        )
    )

    if resolved_metadata.get(
        "contract_fingerprint"
    ) != contract[
        "contract_fingerprint"
    ]:
        raise G2ValidationError(
            "Resolved-input metadata contract "
            "fingerprint mismatch"
        )

    if resolved_metadata.get(
        "output_schema_fingerprint"
    ) != contract["output"][
        "schema_fingerprint"
    ]:
        raise G2ValidationError(
            "Resolved-input metadata schema "
            "fingerprint mismatch"
        )

    if resolved_metadata.get(
        "run_ids"
    ) != dict(run_ids):
        raise G2ValidationError(
            "Resolved-input run IDs differ from "
            "validator inputs"
        )

    if resolved_metadata.get(
        "database_write"
    ) is not False:
        raise G2ValidationError(
            "Resolved-input metadata permits "
            "database output"
        )

    actual_manifest = input_manifest(
        resolved_inputs
    )

    recorded_manifest = (
        resolved_metadata.get(
            "inputs"
        )
    )

    if recorded_manifest != (
        actual_manifest
    ):
        raise G2ValidationError(
            "Resolved-input metadata differs "
            "from independently resolved inputs"
        )

    if build_manifest.get(
        "ok"
    ) is not True:
        raise G2ValidationError(
            "Build manifest is not successful"
        )

    if build_manifest.get(
        "contract_fingerprint"
    ) != contract[
        "contract_fingerprint"
    ]:
        raise G2ValidationError(
            "Build manifest contract fingerprint "
            "mismatch"
        )

    if build_manifest.get(
        "schema_fingerprint"
    ) != contract["output"][
        "schema_fingerprint"
    ]:
        raise G2ValidationError(
            "Build manifest schema fingerprint "
            "mismatch"
        )

    if build_manifest.get(
        "rows"
    ) != contract["output"][
        "reference_row_count"
    ]:
        raise G2ValidationError(
            "Build manifest row-count mismatch"
        )

    if build_manifest.get(
        "columns"
    ) != contract["output"][
        "column_count"
    ]:
        raise G2ValidationError(
            "Build manifest column-count mismatch"
        )

    if build_manifest.get(
        "database_write"
    ) is not False:
        raise G2ValidationError(
            "Build manifest permits database "
            "output"
        )

    return {
        "resolved_inputs_path": str(
            resolved_path
        ),
        "build_manifest_path": str(
            manifest_path
        ),
        "resolved_inputs": (
            resolved_metadata
        ),
        "build_manifest": (
            build_manifest
        ),
    }


def validate_candidate(
    contract: Mapping[str, Any],
    contract_path: Path,
    candidate_run: Path,
    runs_root: Path,
    run_ids: Mapping[str, str],
    resolved_inputs: Mapping[
        str,
        ResolvedInput,
    ],
    expected_schema: pa.Schema,
    b2_partitions: Mapping[
        tuple[int, int],
        PartitionInfo,
    ],
    f2_partitions: Mapping[
        tuple[int, int],
        PartitionInfo,
    ],
    key_batch_rows: int,
    value_batch_rows: int,
    weather_sentinels_per_slot: int,
) -> dict[str, Any]:
    candidate_run = candidate_run.resolve(
        strict=True
    )

    dataset_root = (
        candidate_run
        / "feature_lake"
        / "family_day"
    )

    if not dataset_root.is_dir():
        raise G2ValidationError(
            "Candidate family-day dataset "
            f"not found: {dataset_root}"
        )

    metadata = validate_candidate_metadata(
        candidate_run,
        contract,
        run_ids,
        resolved_inputs,
    )

    candidate_schema = physical_schema(
        dataset_root
    )

    if not candidate_schema.equals(
        expected_schema,
        check_metadata=False,
    ):
        raise G2ValidationError(
            "Candidate physical schema differs "
            "from frozen contract schema"
        )

    candidate_partitions = (
        partition_inventory(
            dataset_root
        )
    )

    if set(candidate_partitions) != set(
        b2_partitions
    ):
        raise G2ValidationError(
            "Candidate partition set differs "
            "from B2"
        )

    expected_partition_count = int(
        contract["output"][
            "reference_monthly_partition_count"
        ]
    )

    if len(candidate_partitions) != (
        expected_partition_count
    ):
        raise G2ValidationError(
            "Candidate partition count mismatch"
        )

    partition_rows = []
    candidate_total_rows = 0

    for key in sorted(
        candidate_partitions
    ):
        candidate_partition = (
            candidate_partitions[key]
        )

        b2_partition = b2_partitions[key]
        f2_partition = f2_partitions[key]

        if (
            candidate_partition.row_count
            != b2_partition.row_count
            or candidate_partition.row_count
            != f2_partition.row_count
        ):
            raise G2ValidationError(
                "Candidate/B2/F2 partition "
                f"row-count mismatch for {key}"
            )

        if set(
            candidate_partition
            .compression_values
        ) != {"ZSTD"}:
            raise G2ValidationError(
                "Candidate partition is not "
                f"exclusively ZSTD: {key}"
            )

        candidate_total_rows += (
            candidate_partition.row_count
        )

        partition_rows.append(
            {
                "year": key[0],
                "month": key[1],
                "candidate_file_count": len(
                    candidate_partition.files
                ),
                "candidate_row_groups": (
                    candidate_partition
                    .row_group_count
                ),
                "candidate_rows": (
                    candidate_partition
                    .row_count
                ),
                "candidate_size_bytes": (
                    candidate_partition
                    .size_bytes
                ),
                "b2_rows": (
                    b2_partition.row_count
                ),
                "f2_rows": (
                    f2_partition.row_count
                ),
                "row_counts_equal": True,
                "compression_values": (
                    ",".join(
                        candidate_partition
                        .compression_values
                    )
                ),
            }
        )

    expected_rows = int(
        contract["output"][
            "reference_row_count"
        ]
    )

    if candidate_total_rows != (
        expected_rows
    ):
        raise G2ValidationError(
            "Candidate total row-count mismatch"
        )

    lineage_groups = lineage_by_dataset(
        contract
    )

    dataset_map = source_by_dataset(
        resolved_inputs
    )

    b2_resolved = dataset_map[
        "dense_grids/"
        "family_day_dense_grid"
    ]

    f2_resolved = dataset_map[
        "feature_blocks/"
        "dense_sales_family_features"
    ]

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

    b2_lineage = lineage_groups[
        b2_resolved.logical_dataset
    ]

    f2_lineage = lineage_groups[
        f2_resolved.logical_dataset
    ]

    c2_lineage = lineage_groups[
        c2_resolved.logical_dataset
    ]

    d2_day_lineage = lineage_groups[
        d2_day_resolved.logical_dataset
    ]

    d2_context_lineage = (
        lineage_groups[
            d2_context_resolved
            .logical_dataset
        ]
    )

    e2_lineage = lineage_groups[
        e2_resolved.logical_dataset
    ]

    if (
        len(b2_lineage),
        len(c2_lineage),
        len(d2_day_lineage)
        + len(d2_context_lineage),
        len(e2_lineage),
        len(f2_lineage),
    ) != (
        20,
        11,
        86,
        2236,
        60,
    ):
        raise G2ValidationError(
            "Unexpected source-phase lineage "
            "column counts"
        )

    b2_source_columns = (
        required_columns_for_dataset(
            b2_lineage,
            list(KEY_COLUMNS),
        )
    )

    f2_source_columns = (
        required_columns_for_dataset(
            f2_lineage,
            list(KEY_COLUMNS),
        )
    )

    candidate_fact_columns = []

    for row in [
        *b2_lineage,
        *f2_lineage,
    ]:
        output_column = row[
            "output_column"
        ]

        if (
            output_column
            not in candidate_fact_columns
        ):
            candidate_fact_columns.append(
                output_column
            )

    previous_global_key: tuple[
        date,
        str,
    ] | None = None

    fact_rows_validated = 0

    for key in sorted(
        candidate_partitions
    ):
        candidate_partition = (
            candidate_partitions[key]
        )

        b2_partition = b2_partitions[key]
        f2_partition = f2_partitions[key]

        specifications = [
            (
                candidate_partition.files,
                candidate_fact_columns,
            ),
            (
                b2_partition.files,
                b2_source_columns,
            ),
            (
                f2_partition.files,
                f2_source_columns,
            ),
        ]

        partition_rows_validated = 0

        for (
            candidate_table,
            b2_table,
            f2_table,
        ) in aligned_table_streams(
            specifications,
            key_batch_rows,
        ):
            if not arrays_equal(
                candidate_table["data"],
                b2_table["data"],
            ):
                raise G2ValidationError(
                    "Candidate/B2 data key mismatch"
                )

            if not arrays_equal(
                candidate_table["famiglia"],
                b2_table["famiglia"],
            ):
                raise G2ValidationError(
                    "Candidate/B2 famiglia key "
                    "mismatch"
                )

            if not arrays_equal(
                b2_table["data"],
                f2_table["data"],
            ):
                raise G2ValidationError(
                    "B2/F2 data key mismatch"
                )

            if not arrays_equal(
                b2_table["famiglia"],
                f2_table["famiglia"],
            ):
                raise G2ValidationError(
                    "B2/F2 famiglia key mismatch"
                )

            previous_global_key = (
                verify_strictly_sorted_keys(
                    candidate_table[
                        "data"
                    ].to_pylist(),
                    candidate_table[
                        "famiglia"
                    ].to_pylist(),
                    previous_global_key,
                )
            )

            if not array_equals_scalar(
                candidate_table["year"],
                pa.scalar(
                    key[0],
                    type=candidate_table[
                        "year"
                    ].type,
                ),
            ):
                raise G2ValidationError(
                    "Candidate year helper mismatch"
                )

            if not array_equals_scalar(
                candidate_table["month"],
                pa.scalar(
                    key[1],
                    type=candidate_table[
                        "month"
                    ].type,
                ),
            ):
                raise G2ValidationError(
                    "Candidate month helper mismatch"
                )

            for row in b2_lineage:
                if not arrays_equal(
                    candidate_table[
                        row[
                            "output_column"
                        ]
                    ],
                    b2_table[
                        row[
                            "source_column"
                        ]
                    ],
                ):
                    raise G2ValidationError(
                        "B2 coherence mismatch for "
                        f"{row['output_column']}"
                    )

            for row in f2_lineage:
                if not arrays_equal(
                    candidate_table[
                        row[
                            "output_column"
                        ]
                    ],
                    f2_table[
                        row[
                            "source_column"
                        ]
                    ],
                ):
                    raise G2ValidationError(
                        "F2 coherence mismatch for "
                        f"{row['output_column']}"
                    )

            batch_rows = (
                candidate_table.num_rows
            )

            partition_rows_validated += (
                batch_rows
            )
            fact_rows_validated += (
                batch_rows
            )

        if (
            partition_rows_validated
            != candidate_partition.row_count
        ):
            raise G2ValidationError(
                "Fact validation partition row "
                f"count mismatch for {key}"
            )

    if fact_rows_validated != (
        expected_rows
    ):
        raise G2ValidationError(
            "Fact validation total row-count "
            "mismatch"
        )

    c2_index, c2_projection = (
        dimension_projection(
            c2_resolved,
            "famiglia",
            c2_lineage,
        )
    )

    d2_day_index, d2_day_projection = (
        dimension_projection(
            d2_day_resolved,
            "data",
            d2_day_lineage,
        )
    )

    (
        d2_context_index,
        d2_context_projection,
    ) = dimension_projection(
        d2_context_resolved,
        "data",
        d2_context_lineage,
    )

    dimension_output_columns = [
        row["output_column"]
        for row in [
            *c2_lineage,
            *d2_day_lineage,
            *d2_context_lineage,
        ]
    ]

    candidate_dimension_columns = [
        "data",
        "famiglia",
        *dimension_output_columns,
    ]

    dimension_rows_validated = 0

    for key in sorted(
        candidate_partitions
    ):
        candidate_partition = (
            candidate_partitions[key]
        )

        partition_rows_validated = 0

        for candidate_table in (
            table_batches(
                candidate_partition.files,
                candidate_dimension_columns,
                value_batch_rows,
            )
        ):
            data_values = candidate_table[
                "data"
            ].to_pylist()

            family_values = candidate_table[
                "famiglia"
            ].to_pylist()

            c2_expected = dimension_take(
                c2_projection,
                c2_index,
                family_values,
                "C2 famiglia",
            )

            d2_day_expected = (
                dimension_take(
                    d2_day_projection,
                    d2_day_index,
                    data_values,
                    "D2 calendar-day data",
                )
            )

            d2_context_expected = (
                dimension_take(
                    d2_context_projection,
                    d2_context_index,
                    data_values,
                    "D2 calendar-context data",
                )
            )

            validate_projection_table(
                candidate_table,
                c2_expected,
                [
                    row[
                        "output_column"
                    ]
                    for row in c2_lineage
                ],
                "C2",
            )

            validate_projection_table(
                candidate_table,
                d2_day_expected,
                [
                    row[
                        "output_column"
                    ]
                    for row
                    in d2_day_lineage
                ],
                "D2 calendar day",
            )

            validate_projection_table(
                candidate_table,
                d2_context_expected,
                [
                    row[
                        "output_column"
                    ]
                    for row
                    in d2_context_lineage
                ],
                "D2 calendar context",
            )

            partition_rows_validated += (
                candidate_table.num_rows
            )

            dimension_rows_validated += (
                candidate_table.num_rows
            )

        if (
            partition_rows_validated
            != candidate_partition.row_count
        ):
            raise G2ValidationError(
                "Dimension validation partition "
                f"row-count mismatch for {key}"
            )

    if dimension_rows_validated != (
        expected_rows
    ):
        raise G2ValidationError(
            "Dimension validation total "
            "row-count mismatch"
        )

    selected_weather = (
        select_weather_sentinels(
            e2_lineage,
            weather_sentinels_per_slot,
        )
    )

    weather_output_columns = [
        row["output_column"]
        for slot in (
            "loc_01",
            "loc_02",
            "loc_03",
            "loc_04",
        )
        for row in selected_weather[slot]
    ]

    weather_rows_validated = 0

    for key in sorted(
        candidate_partitions
    ):
        candidate_partition = (
            candidate_partitions[key]
        )

        b2_partition = b2_partitions[key]

        target_dates = (
            target_dates_for_partition(
                b2_partition
            )
        )

        (
            weather_date_index,
            weather_projection,
        ) = weather_projection_for_dates(
            e2_resolved,
            selected_weather,
            target_dates,
        )

        candidate_columns = [
            "data",
            *weather_output_columns,
        ]

        partition_rows_validated = 0

        for candidate_table in (
            table_batches(
                candidate_partition.files,
                candidate_columns,
                value_batch_rows,
            )
        ):
            data_values = candidate_table[
                "data"
            ].to_pylist()

            expected_weather = (
                dimension_take(
                    weather_projection,
                    weather_date_index,
                    data_values,
                    "E2 target data",
                )
            )

            validate_projection_table(
                candidate_table,
                expected_weather,
                weather_output_columns,
                "E2 weather sentinel",
            )

            partition_rows_validated += (
                candidate_table.num_rows
            )

            weather_rows_validated += (
                candidate_table.num_rows
            )

        if (
            partition_rows_validated
            != candidate_partition.row_count
        ):
            raise G2ValidationError(
                "Weather validation partition "
                f"row-count mismatch for {key}"
            )

    if weather_rows_validated != (
        expected_rows
    ):
        raise G2ValidationError(
            "Weather validation total "
            "row-count mismatch"
        )

    success_marker_present = (
        candidate_run / "_SUCCESS"
    ).exists()

    partition_inventory_path = (
        candidate_run
        / "metadata"
        / (
            "global_family_day_"
            "partition_inventory.tsv"
        )
    )

    write_tsv_atomic(
        partition_inventory_path,
        partition_rows,
        [
            "year",
            "month",
            "candidate_file_count",
            "candidate_row_groups",
            "candidate_rows",
            "candidate_size_bytes",
            "b2_rows",
            "f2_rows",
            "row_counts_equal",
            "compression_values",
        ],
    )

    weather_sentinel_descriptor = {
        slot: [
            {
                "output_column": (
                    row[
                        "output_column"
                    ]
                ),
                "source_column": (
                    row[
                        "source_column"
                    ]
                ),
                "source_location_id": (
                    row[
                        "source_location_id"
                    ]
                ),
            }
            for row in selected_weather[
                slot
            ]
        ]
        for slot in (
            "loc_01",
            "loc_02",
            "loc_03",
            "loc_04",
        )
    }

    checks = [
        {
            "check_id": "G2V001",
            "check": (
                "contract_fingerprint_and_"
                "executable_lineage"
            ),
            "result": "PASS",
            "evidence": (
                contract[
                    "contract_fingerprint"
                ]
            ),
        },
        {
            "check_id": "G2V002",
            "check": (
                "candidate_metadata_and_"
                "input_provenance"
            ),
            "result": "PASS",
            "evidence": (
                metadata[
                    "resolved_inputs_path"
                ]
            ),
        },
        {
            "check_id": "G2V003",
            "check": (
                "ordered_2413_column_schema"
            ),
            "result": "PASS",
            "evidence": (
                contract["output"][
                    "schema_fingerprint"
                ]
            ),
        },
        {
            "check_id": "G2V004",
            "check": (
                "exact_year_month_partitions"
            ),
            "result": "PASS",
            "evidence": (
                str(
                    len(
                        candidate_partitions
                    )
                )
            ),
        },
        {
            "check_id": "G2V005",
            "check": (
                "candidate_rows_equal_B2_and_F2"
            ),
            "result": "PASS",
            "evidence": (
                str(candidate_total_rows)
            ),
        },
        {
            "check_id": "G2V006",
            "check": (
                "keys_unique_sorted_and_B2_exact"
            ),
            "result": "PASS",
            "evidence": (
                str(
                    fact_rows_validated
                )
            ),
        },
        {
            "check_id": "G2V007",
            "check": (
                "all_B2_and_F2_lineage_columns_"
                "coherent"
            ),
            "result": "PASS",
            "evidence": (
                f"B2={len(b2_lineage)};"
                f"F2={len(f2_lineage)}"
            ),
        },
        {
            "check_id": "G2V008",
            "check": (
                "all_C2_and_D2_dimension_"
                "columns_coherent"
            ),
            "result": "PASS",
            "evidence": (
                f"C2={len(c2_lineage)};"
                f"D2={len(d2_day_lineage) + len(d2_context_lineage)}"
            ),
        },
        {
            "check_id": "G2V009",
            "check": (
                "weather_observation_same_day_target_mapping"
            ),
            "result": "PASS",
            "evidence": (
                "data = weather_observation_data"
            ),
        },
        {
            "check_id": "G2V010",
            "check": (
                "weather_sentinels_all_four_slots"
            ),
            "result": "PASS",
            "evidence": (
                f"columns="
                f"{len(weather_output_columns)}"
            ),
        },
        {
            "check_id": "G2V011",
            "check": (
                "all_weather_schema_lineages_exact"
            ),
            "result": "PASS",
            "evidence": (
                str(len(e2_lineage))
            ),
        },
        {
            "check_id": "G2V012",
            "check": (
                "zstd_compression_all_partitions"
            ),
            "result": "PASS",
            "evidence": "ZSTD",
        },
        {
            "check_id": "G2V013",
            "check": (
                "database_output_forbidden"
            ),
            "result": "PASS",
            "evidence": (
                "database_write=false"
            ),
        },
        {
            "check_id": "G2V014",
            "check": (
                "success_marker_lifecycle_observed"
            ),
            "result": "PASS",
            "evidence": (
                "preexisting="
                f"{success_marker_present}"
            ),
        },
    ]

    report = {
        "ok": True,
        "classification": (
            "PHASE2M_G2_FAMILY_DAY_"
            "INDEPENDENT_VALIDATION_OK"
        ),
        "decision": (
            "READY_FOR_PHASE2M_G2_"
            "ATOMIC_PROMOTION"
        ),
        "validated_at_utc": (
            utc_timestamp()
        ),
        "candidate_run": str(
            candidate_run
        ),
        "candidate_dataset": str(
            dataset_root
        ),
        "contract_path": str(
            contract_path
        ),
        "contract_name": (
            contract[
                "contract_name"
            ]
        ),
        "contract_version": (
            contract["version"]
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
        "column_lineage_fingerprint": (
            contract[
                "execution_mapping_policy"
            ][
                "column_lineage_fingerprint"
            ]
        ),
        "rows": candidate_total_rows,
        "columns": (
            contract["output"][
                "column_count"
            ]
        ),
        "partition_count": len(
            candidate_partitions
        ),
        "fact_rows_validated": (
            fact_rows_validated
        ),
        "dimension_rows_validated": (
            dimension_rows_validated
        ),
        "weather_rows_validated": (
            weather_rows_validated
        ),
        "weather_sentinel_columns": (
            weather_sentinel_descriptor
        ),
        "weather_sentinel_column_count": (
            len(weather_output_columns)
        ),
        "partition_inventory": str(
            partition_inventory_path
        ),
        "success_marker_present_before_"
        "validation": (
            success_marker_present
        ),
        "checks": checks,
        "check_count": len(checks),
        "source_changes": False,
        "candidate_metadata_write": True,
        "parquet_write": False,
        "database_access": False,
        "git_actions": False,
        "blockers": [],
    }

    report_path = (
        candidate_run
        / "metadata"
        / (
            "global_family_day_"
            "validation.json"
        )
    )

    write_json_atomic(
        report_path,
        report,
    )

    return report


def preflight(
    contract: Mapping[str, Any],
    contract_path: Path,
    runs_root: Path,
    run_ids: Mapping[str, str],
    resolved_inputs: Mapping[
        str,
        ResolvedInput,
    ],
    expected_schema: pa.Schema,
    b2_partitions: Mapping[
        tuple[int, int],
        PartitionInfo,
    ],
    f2_partitions: Mapping[
        tuple[int, int],
        PartitionInfo,
    ],
    weather_sentinels_per_slot: int,
) -> dict[str, Any]:
    lineage_groups = lineage_by_dataset(
        contract
    )

    phase_counts = Counter(
        row["source_phase"]
        for row in contract[
            "column_lineage"
        ]
    )

    if phase_counts != {
        "B2": 20,
        "C2": 11,
        "D2": 86,
        "E2": 2236,
        "F2": 60,
    }:
        raise G2ValidationError(
            "Unexpected contract source-phase "
            f"counts: {dict(phase_counts)}"
        )

    e2_rows = lineage_groups[
        "outputs/"
        "weather_observed_features_day"
    ]

    selected_weather = (
        select_weather_sentinels(
            e2_rows,
            weather_sentinels_per_slot,
        )
    )

    selected_count = sum(
        len(rows)
        for rows
        in selected_weather.values()
    )

    report = {
        "ok": True,
        "classification": (
            "PHASE2M_G2_VALIDATOR_PREFLIGHT_OK"
        ),
        "decision": (
            "READY_FOR_PHASE2M_G2_"
            "INTEGRATED_EXECUTION_REVIEW"
        ),
        "mode": "preflight",
        "validator_source": str(
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
            "expected_arrow_fields": len(
                expected_schema
            ),
        },
        "inputs": input_manifest(
            resolved_inputs
        ),
        "run_ids": dict(run_ids),
        "runs_root": str(runs_root),
        "b2_f2_partition_alignment": {
            "exact": (
                set(b2_partitions)
                == set(f2_partitions)
                and all(
                    b2_partitions[key]
                    .row_count
                    == f2_partitions[key]
                    .row_count
                    for key in b2_partitions
                )
            ),
            "partition_count": len(
                b2_partitions
            ),
            "rows": sum(
                partition.row_count
                for partition
                in b2_partitions.values()
            ),
        },
        "source_phase_counts": dict(
            sorted(
                phase_counts.items()
            )
        ),
        "weather_validation": {
            "schema_lineage_columns": (
                len(e2_rows)
            ),
            "sentinel_columns_per_slot": (
                {
                    slot: len(rows)
                    for slot, rows
                    in selected_weather.items()
                }
            ),
            "sentinel_column_count": (
                selected_count
            ),
            "all_four_slots": (
                set(selected_weather)
                == {
                    "loc_01",
                    "loc_02",
                    "loc_03",
                    "loc_04",
                }
            ),
        },
        "validation_strategy": {
            "full_key_and_B2_F2_coherence": (
                True
            ),
            "full_C2_D2_coherence": True,
            "weather_schema_lineage_full": (
                True
            ),
            "weather_value_coherence": (
                "deterministic sentinels across "
                "all four slots and all output rows"
            ),
            "candidate_metadata_validation": (
                True
            ),
            "database_output_forbidden": (
                True
            ),
        },
        "source_changes": False,
        "parquet_footer_read": True,
        "parquet_schema_read": True,
        "parquet_data_rows_read": 0,
        "parquet_write": False,
        "database_access": False,
        "git_actions": False,
        "blockers": [],
    }

    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Independently validate the "
            "contract-driven Phase 2M-G2 "
            "family-day feature lake."
        )
    )

    parser.add_argument(
        "--mode",
        choices=(
            "preflight",
            "validate",
        ),
        default="validate",
        help=(
            "preflight reads only schemas and "
            "footers; validate performs full "
            "candidate validation."
        ),
    )

    parser.add_argument(
        "--contract",
        type=Path,
        default=DEFAULT_CONTRACT,
        help="Frozen executable G2 contract.",
    )

    parser.add_argument(
        "--candidate-run",
        type=Path,
        help=(
            "Candidate or final G2 run. Required "
            "for validate mode."
        ),
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
        "--key-batch-rows",
        type=int,
        default=65536,
        help=(
            "Rows per streaming B2/F2/key "
            "validation batch."
        ),
    )

    parser.add_argument(
        "--value-batch-rows",
        type=int,
        default=8192,
        help=(
            "Rows per C2/D2/weather value "
            "validation batch."
        ),
    )

    parser.add_argument(
        "--weather-sentinels-per-slot",
        type=int,
        default=12,
        help=(
            "Deterministic E2 value columns "
            "validated for every row in each "
            "generic location slot."
        ),
    )

    parser.add_argument(
        "--preflight-report",
        type=Path,
        help=(
            "Optional JSON report written by "
            "preflight mode."
        ),
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.key_batch_rows < 1024:
        raise G2ValidationError(
            "--key-batch-rows must be at least "
            "1024"
        )

    if args.value_batch_rows < 512:
        raise G2ValidationError(
            "--value-batch-rows must be at least "
            "512"
        )

    if (
        args.weather_sentinels_per_slot
        < 8
    ):
        raise G2ValidationError(
            "--weather-sentinels-per-slot must "
            "be at least 8"
        )

    contract_path = args.contract.resolve(
        strict=True
    )

    runs_root = args.runs_root.resolve(
        strict=True
    )

    contract = load_contract(
        contract_path
    )

    run_ids = resolve_run_ids(
        contract,
        args,
    )

    resolved_inputs = resolve_inputs(
        contract,
        runs_root,
        run_ids,
    )

    schema = expected_output_schema(
        contract,
        resolved_inputs,
    )

    (
        b2_partitions,
        f2_partitions,
    ) = validate_partition_alignment(
        contract,
        resolved_inputs,
    )

    if args.mode == "preflight":
        report = preflight(
            contract=contract,
            contract_path=contract_path,
            runs_root=runs_root,
            run_ids=run_ids,
            resolved_inputs=resolved_inputs,
            expected_schema=schema,
            b2_partitions=b2_partitions,
            f2_partitions=f2_partitions,
            weather_sentinels_per_slot=(
                args
                .weather_sentinels_per_slot
            ),
        )

        if args.preflight_report is not None:
            write_json_atomic(
                args.preflight_report.resolve(),
                report,
            )

        print(
            json.dumps(
                report,
                indent=2,
                ensure_ascii=False,
            )
        )

        return 0

    if args.candidate_run is None:
        raise G2ValidationError(
            "--candidate-run is required for "
            "validate mode"
        )

    report = validate_candidate(
        contract=contract,
        contract_path=contract_path,
        candidate_run=(
            args.candidate_run
        ),
        runs_root=runs_root,
        run_ids=run_ids,
        resolved_inputs=resolved_inputs,
        expected_schema=schema,
        b2_partitions=b2_partitions,
        f2_partitions=f2_partitions,
        key_batch_rows=args.key_batch_rows,
        value_batch_rows=(
            args.value_batch_rows
        ),
        weather_sentinels_per_slot=(
            args
            .weather_sentinels_per_slot
        ),
    )

    print(
        json.dumps(
            report,
            indent=2,
            ensure_ascii=False,
        )
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except G2ValidationError as exc:
        print(
            f"ERROR={exc}",
            file=sys.stderr,
        )
        raise SystemExit(2)
