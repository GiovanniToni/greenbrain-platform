#!/usr/bin/env python3
"""Independent Phase 2M-F2 dense-sales validator.

The validator never imports builder calculation functions. It independently
recomputes all 60 causal features from the validated B2 dense source and
compares them with the F2 Parquet output.

The only permitted writes are atomic replacements of validation.json metadata
files. It never writes or modifies Parquet and never promotes a candidate.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys
import uuid
from collections import deque
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence

import pyarrow as pa
import pyarrow.parquet as pq


VALIDATOR_VERSION = "1.0.0"
PHASE = "2M-F2"

MODULE_PATH = Path(__file__).resolve()

DEFAULT_CONTRACT_PATH = (
    MODULE_PATH.parent
    / "contracts"
    / "phase2m_f2_dense_sales_contract_v1.json"
)

BUILD_ID_PATTERN = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
)

WINDOWS = (7, 14, 28, 56, 90)
STD_WINDOWS = (28, 56, 90)
SALE_WINDOWS = (7, 28, 90)

ARROW_TYPES: Mapping[str, pa.DataType] = {
    "bool": pa.bool_(),
    "int32": pa.int32(),
    "int64": pa.int64(),
    "float64": pa.float64(),
    "date32[day]": pa.date32(),
    "string": pa.string(),
}


class ValidationError(RuntimeError):
    """Controlled F2 validation failure."""


@dataclass(frozen=True)
class MonthlyPartition:
    year: int
    month: int
    path: Path
    row_count: int
    schema_fingerprint: str
    compression_values: tuple[str, ...]

    @property
    def key(self) -> tuple[int, int]:
        return (self.year, self.month)


@dataclass(frozen=True)
class GrainSpec:
    contract_key: str
    cli_value: str
    input_dataset: str
    output_dataset: str
    metadata_key: str
    keys: tuple[str, ...]
    source_required_column_types: Mapping[str, str]
    accepted_source_schema_fingerprint: str
    output_schema: tuple[Mapping[str, Any], ...]
    expected_output_schema_fingerprint: str
    expected_output_column_count: int
    feature_order: tuple[str, ...]


def utc_now() -> str:
    return datetime.now(
        timezone.utc
    ).isoformat()


def canonical_json_bytes(
    value: Any,
) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_bytes(
    payload: bytes,
) -> str:
    return hashlib.sha256(
        payload
    ).hexdigest()


def sha256_file(
    path: Path,
) -> str:
    digest = hashlib.sha256()

    with path.open("rb") as handle:
        while True:
            chunk = handle.read(
                1024 * 1024
            )

            if not chunk:
                break

            digest.update(chunk)

    return digest.hexdigest()


def schema_fingerprint(
    schema: pa.Schema,
) -> str:
    normalized = (
        schema
        .remove_metadata()
        .to_string(
            show_field_metadata=False
        )
    )

    return sha256_bytes(
        normalized.encode("utf-8")
    )


def path_is_relative_to(
    child: Path,
    parent: Path,
) -> bool:
    try:
        child.relative_to(parent)
    except ValueError:
        return False

    return True


def atomic_write_json(
    path: Path,
    value: Any,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    temporary = path.with_name(
        f".{path.name}.tmp-"
        f"{uuid.uuid4().hex}"
    )

    payload = (
        json.dumps(
            value,
            indent=2,
            ensure_ascii=False,
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")

    temporary.write_bytes(payload)
    os.chmod(temporary, 0o644)
    os.replace(temporary, path)


def validate_build_id(
    build_id: str,
) -> None:
    if not BUILD_ID_PATTERN.fullmatch(
        build_id
    ):
        raise ValidationError(
            "build-id must match "
            "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
        )


def load_contract(
    path: Path,
) -> dict[str, Any]:
    resolved = path.resolve(
        strict=True
    )

    payload = resolved.read_bytes()

    try:
        contract = json.loads(
            payload.decode("utf-8")
        )
    except Exception as exc:
        raise ValidationError(
            f"invalid contract JSON: "
            f"{resolved}"
        ) from exc

    if contract.get("phase") != PHASE:
        raise ValidationError(
            "unexpected contract phase"
        )

    if (
        contract.get("contract_version")
        != "1.0.0"
    ):
        raise ValidationError(
            "unsupported contract version"
        )

    stored = contract.get(
        "contract_fingerprint"
    )

    if not isinstance(stored, str):
        raise ValidationError(
            "contract fingerprint missing"
        )

    without = dict(contract)
    without.pop(
        "contract_fingerprint",
        None,
    )

    actual = sha256_bytes(
        canonical_json_bytes(
            without
        )
    )

    if stored != actual:
        raise ValidationError(
            "contract fingerprint mismatch"
        )

    features = contract.get(
        "features"
    )

    if not isinstance(features, list):
        raise ValidationError(
            "feature registry missing"
        )

    if len(features) != 60:
        raise ValidationError(
            "expected 60 contract features"
        )

    names = [
        feature.get("name")
        for feature in features
    ]

    if len(names) != len(set(names)):
        raise ValidationError(
            "duplicate feature names"
        )

    return contract


def arrow_schema_from_contract(
    schema_rows: Sequence[
        Mapping[str, Any]
    ],
) -> pa.Schema:
    fields: list[pa.Field] = []

    for row in schema_rows:
        type_name = row["type"]

        if type_name not in ARROW_TYPES:
            raise ValidationError(
                f"unsupported Arrow type: "
                f"{type_name}"
            )

        fields.append(
            pa.field(
                row["column"],
                ARROW_TYPES[type_name],
                nullable=bool(
                    row["nullable"]
                ),
            )
        )

    return pa.schema(fields)


def build_grain_specs(
    contract: Mapping[str, Any],
) -> dict[str, GrainSpec]:
    feature_order = tuple(
        feature["name"]
        for feature in contract["features"]
    )

    definitions = {
        "family": "family_day",
        "family_priceband": (
            "family_priceband_day"
        ),
    }

    accepted = contract[
        "runtime_compatibility"
    ]["accepted_schema_fingerprints"]

    specs: dict[str, GrainSpec] = {}

    for cli_value, contract_key in (
        definitions.items()
    ):
        input_spec = contract[
            "inputs"
        ][contract_key]

        output_spec = contract[
            "outputs"
        ][contract_key]

        output_schema = tuple(
            output_spec["schema"]
        )

        arrow_schema = (
            arrow_schema_from_contract(
                output_schema
            )
        )

        specs[cli_value] = GrainSpec(
            contract_key=contract_key,
            cli_value=cli_value,
            input_dataset=input_spec[
                "dataset"
            ],
            output_dataset=output_spec[
                "dataset"
            ],
            metadata_key=contract_key,
            keys=tuple(
                input_spec["grain"]
            ),
            source_required_column_types=dict(
                input_spec[
                    "required_columns"
                ]
            ),
            accepted_source_schema_fingerprint=(
                accepted[contract_key]
            ),
            output_schema=output_schema,
            expected_output_schema_fingerprint=(
                schema_fingerprint(
                    arrow_schema
                )
            ),
            expected_output_column_count=int(
                output_spec[
                    "column_count"
                ]
            ),
            feature_order=feature_order,
        )

    return specs


def parse_partition_path(
    dataset_root: Path,
    parquet_path: Path,
) -> tuple[int, int]:
    relative = parquet_path.relative_to(
        dataset_root
    )

    year: int | None = None
    month: int | None = None

    for part in relative.parts[:-1]:
        if part.startswith("year="):
            year = int(
                part.split("=", 1)[1]
            )

        elif part.startswith("month="):
            month = int(
                part.split("=", 1)[1]
            )

    if year is None or month is None:
        raise ValidationError(
            "Parquet path lacks year/month "
            f"partitions: {parquet_path}"
        )

    if not 1 <= month <= 12:
        raise ValidationError(
            f"invalid month partition: "
            f"{parquet_path}"
        )

    return year, month


def parquet_compressions(
    metadata: pq.FileMetaData,
) -> tuple[str, ...]:
    values: set[str] = set()

    for group_index in range(
        metadata.num_row_groups
    ):
        group = metadata.row_group(
            group_index
        )

        for column_index in range(
            group.num_columns
        ):
            values.add(
                str(
                    group.column(
                        column_index
                    ).compression
                ).upper()
            )

    return tuple(sorted(values))


def _inspect_partitions(
    dataset_root: Path,
    expected_fingerprint: str,
    required_column_types: (
        Mapping[str, str] | None
    ),
    expected_column_count: int | None,
) -> tuple[MonthlyPartition, ...]:
    if not dataset_root.is_dir():
        raise ValidationError(
            f"dataset directory missing: "
            f"{dataset_root}"
        )

    parquet_files = sorted(
        dataset_root.rglob(
            "*.parquet"
        )
    )

    if not parquet_files:
        raise ValidationError(
            f"no Parquet files found: "
            f"{dataset_root}"
        )

    by_partition: dict[
        tuple[int, int],
        list[Path],
    ] = {}

    for parquet_path in parquet_files:
        year, month = parse_partition_path(
            dataset_root,
            parquet_path,
        )

        by_partition.setdefault(
            (year, month),
            [],
        ).append(parquet_path)

    partitions: list[
        MonthlyPartition
    ] = []

    for (year, month), files in sorted(
        by_partition.items()
    ):
        if len(files) != 1:
            raise ValidationError(
                "expected exactly one "
                f"Parquet file for "
                f"{year:04d}-{month:02d}; "
                f"found {len(files)}"
            )

        path = files[0]
        parquet = pq.ParquetFile(path)
        schema = parquet.schema_arrow

        fingerprint = schema_fingerprint(
            schema
        )

        if fingerprint != expected_fingerprint:
            raise ValidationError(
                "schema fingerprint mismatch "
                f"for {path}: {fingerprint}"
            )

        if (
            expected_column_count
            is not None
            and len(schema)
            != expected_column_count
        ):
            raise ValidationError(
                "column-count mismatch for "
                f"{path}"
            )

        if required_column_types:
            type_map = {
                field.name: str(
                    field.type
                )
                for field in schema
            }

            for (
                column,
                expected_type,
            ) in required_column_types.items():
                actual_type = type_map.get(
                    column
                )

                if actual_type != expected_type:
                    raise ValidationError(
                        "required source type "
                        f"mismatch for {column}: "
                        f"expected {expected_type}; "
                        f"found {actual_type}"
                    )

        compressions = (
            parquet_compressions(
                parquet.metadata
            )
        )

        if compressions != ("ZSTD",):
            raise ValidationError(
                "Parquet compression is not "
                f"ZSTD for {path}: "
                f"{compressions}"
            )

        partitions.append(
            MonthlyPartition(
                year=year,
                month=month,
                path=path,
                row_count=(
                    parquet.metadata.num_rows
                ),
                schema_fingerprint=(
                    fingerprint
                ),
                compression_values=(
                    compressions
                ),
            )
        )

    previous: tuple[int, int] | None = None

    for partition in partitions:
        if previous is not None:
            expected_year = previous[0]
            expected_month = (
                previous[1] + 1
            )

            if expected_month == 13:
                expected_year += 1
                expected_month = 1

            if partition.key != (
                expected_year,
                expected_month,
            ):
                raise ValidationError(
                    "monthly partitions are "
                    "not continuous"
                )

        previous = partition.key

    return tuple(partitions)


def inspect_source_partitions(
    dataset_run_dir: Path,
    spec: GrainSpec,
) -> tuple[
    Path,
    tuple[MonthlyPartition, ...],
]:
    run_root = dataset_run_dir.resolve(
        strict=True
    )

    dataset_root = (
        run_root / spec.input_dataset
    ).resolve(strict=True)

    if not path_is_relative_to(
        dataset_root,
        run_root,
    ):
        raise ValidationError(
            "source dataset escapes run root"
        )

    partitions = _inspect_partitions(
        dataset_root=dataset_root,
        expected_fingerprint=(
            spec.accepted_source_schema_fingerprint
        ),
        required_column_types=(
            spec.source_required_column_types
        ),
        expected_column_count=None,
    )

    return dataset_root, partitions


def inspect_output_partitions(
    output_root: Path,
    spec: GrainSpec,
) -> tuple[
    Path,
    tuple[MonthlyPartition, ...],
]:
    resolved_root = output_root.resolve(
        strict=True
    )

    dataset_root = (
        resolved_root
        / spec.output_dataset
    ).resolve(strict=True)

    if not path_is_relative_to(
        dataset_root,
        resolved_root,
    ):
        raise ValidationError(
            "output dataset escapes run root"
        )

    partitions = _inspect_partitions(
        dataset_root=dataset_root,
        expected_fingerprint=(
            spec.expected_output_schema_fingerprint
        ),
        required_column_types=None,
        expected_column_count=(
            spec.expected_output_column_count
        ),
    )

    return dataset_root, partitions


def metadata_directory(
    output_root: Path,
    contract: Mapping[str, Any],
    metadata_key: str,
) -> Path:
    layout = contract[
        "metadata_contract"
    ]["metadata_path_layout"]

    template = layout[metadata_key]
    prefix = "<run-root>/"

    if not template.startswith(prefix):
        raise ValidationError(
            "invalid metadata path template"
        )

    resolved_root = output_root.resolve(
        strict=True
    )

    path = (
        resolved_root
        / template[len(prefix):]
    ).resolve(strict=False)

    if not path_is_relative_to(
        path,
        resolved_root,
    ):
        raise ValidationError(
            "metadata path escapes run root"
        )

    return path


def read_json(
    path: Path,
) -> Any:
    if not path.is_file():
        raise ValidationError(
            f"required metadata file missing: "
            f"{path}"
        )

    try:
        return json.loads(
            path.read_text(
                encoding="utf-8"
            )
        )
    except Exception as exc:
        raise ValidationError(
            f"invalid metadata JSON: {path}"
        ) from exc


def _manifest_content_fingerprint(
    file_records: Sequence[
        Mapping[str, Any]
    ],
) -> str:
    payload = [
        {
            "relative_path": record[
                "relative_path"
            ],
            "row_count": int(
                record["row_count"]
            ),
            "sha256": record[
                "sha256"
            ],
        }
        for record in file_records
    ]

    return sha256_bytes(
        canonical_json_bytes(
            payload
        )
    )


def validate_metadata(
    dataset_run_dir: Path,
    output_root: Path,
    build_id: str,
    contract: Mapping[str, Any],
    spec: GrainSpec,
    source_partitions: Sequence[
        MonthlyPartition
    ],
    output_partitions: Sequence[
        MonthlyPartition
    ],
) -> dict[str, Any]:
    metadata_root = metadata_directory(
        output_root,
        contract,
        spec.metadata_key,
    )

    manifest = read_json(
        metadata_root / "manifest.json"
    )

    schema_metadata = read_json(
        metadata_root / "schema.json"
    )

    fingerprint_metadata = read_json(
        metadata_root
        / "schema_fingerprint.json"
    )

    build_stats = read_json(
        metadata_root
        / "build_stats.json"
    )

    read_json(
        metadata_root / "validation.json"
    )

    required_fields = contract[
        "metadata_contract"
    ]["required_fields"]

    for field in required_fields:
        if field not in manifest:
            raise ValidationError(
                "manifest missing required "
                f"field: {field}"
            )

    if manifest["build_id"] != build_id:
        raise ValidationError(
            "manifest build-id mismatch"
        )

    if manifest["source_run_id"] != (
        dataset_run_dir.name
    ):
        raise ValidationError(
            "manifest source-run mismatch"
        )

    if manifest["contract_version"] != (
        contract["contract_version"]
    ):
        raise ValidationError(
            "manifest contract-version "
            "mismatch"
        )

    if manifest["contract_fingerprint"] != (
        contract["contract_fingerprint"]
    ):
        raise ValidationError(
            "manifest contract-fingerprint "
            "mismatch"
        )

    if manifest["dataset"] != (
        spec.output_dataset
    ):
        raise ValidationError(
            "manifest dataset mismatch"
        )

    if manifest["grain"] != list(
        spec.keys
    ):
        raise ValidationError(
            "manifest grain mismatch"
        )

    expected_rows = sum(
        partition.row_count
        for partition in output_partitions
    )

    source_rows = sum(
        partition.row_count
        for partition in source_partitions
    )

    if expected_rows != source_rows:
        raise ValidationError(
            "source/output row-count mismatch"
        )

    if int(manifest["row_count"]) != (
        expected_rows
    ):
        raise ValidationError(
            "manifest row-count mismatch"
        )

    if int(manifest["column_count"]) != (
        spec.expected_output_column_count
    ):
        raise ValidationError(
            "manifest column-count mismatch"
        )

    if int(manifest["file_count"]) != len(
        output_partitions
    ):
        raise ValidationError(
            "manifest file-count mismatch"
        )

    if str(
        manifest["compression"]
    ).lower() != "zstd":
        raise ValidationError(
            "manifest compression mismatch"
        )

    if manifest["sort_columns"] != list(
        spec.keys
    ):
        raise ValidationError(
            "manifest sort-column mismatch"
        )

    if schema_metadata.get(
        "dataset"
    ) != spec.output_dataset:
        raise ValidationError(
            "schema metadata dataset mismatch"
        )

    if schema_metadata.get(
        "schema"
    ) != list(spec.output_schema):
        raise ValidationError(
            "schema metadata differs from "
            "the contract"
        )

    if fingerprint_metadata.get(
        "schema_fingerprint"
    ) != (
        spec.expected_output_schema_fingerprint
    ):
        raise ValidationError(
            "output schema-fingerprint "
            "metadata mismatch"
        )

    if build_stats.get(
        "build_id"
    ) != build_id:
        raise ValidationError(
            "build-stats build-id mismatch"
        )

    manifest_files = manifest.get(
        "files"
    )

    if not isinstance(
        manifest_files,
        list,
    ):
        raise ValidationError(
            "manifest file registry missing"
        )

    if len(manifest_files) != len(
        output_partitions
    ):
        raise ValidationError(
            "manifest file-registry size "
            "mismatch"
        )

    actual_by_relative: dict[
        str,
        MonthlyPartition,
    ] = {}

    resolved_output_root = (
        output_root.resolve(
            strict=True
        )
    )

    for partition in output_partitions:
        relative = str(
            partition.path.relative_to(
                resolved_output_root
            )
        )

        actual_by_relative[
            relative
        ] = partition

    verified_records: list[
        dict[str, Any]
    ] = []

    for record in manifest_files:
        relative = record.get(
            "relative_path"
        )

        if relative not in actual_by_relative:
            raise ValidationError(
                "manifest references an "
                f"unexpected file: {relative}"
            )

        output_file = (
            resolved_output_root / relative
        ).resolve(strict=True)

        if not path_is_relative_to(
            output_file,
            resolved_output_root,
        ):
            raise ValidationError(
                "manifest file escapes output "
                "root"
            )

        partition = actual_by_relative[
            relative
        ]

        if int(record["row_count"]) != (
            partition.row_count
        ):
            raise ValidationError(
                "manifest file row-count "
                f"mismatch: {relative}"
            )

        actual_size = (
            output_file.stat().st_size
        )

        if int(record["size_bytes"]) != (
            actual_size
        ):
            raise ValidationError(
                "manifest file-size mismatch: "
                f"{relative}"
            )

        actual_sha = sha256_file(
            output_file
        )

        if record["sha256"] != actual_sha:
            raise ValidationError(
                "manifest file SHA mismatch: "
                f"{relative}"
            )

        if record[
            "schema_fingerprint"
        ] != (
            spec.expected_output_schema_fingerprint
        ):
            raise ValidationError(
                "manifest file schema "
                f"fingerprint mismatch: "
                f"{relative}"
            )

        verified_records.append(
            {
                "relative_path": relative,
                "row_count": (
                    partition.row_count
                ),
                "sha256": actual_sha,
            }
        )

    expected_content_fp = (
        _manifest_content_fingerprint(
            verified_records
        )
    )

    if manifest[
        "content_fingerprint"
    ] != expected_content_fp:
        raise ValidationError(
            "manifest content fingerprint "
            "mismatch"
        )

    return {
        "metadata_root": str(
            metadata_root
        ),
        "row_count": expected_rows,
        "file_count": len(
            output_partitions
        ),
        "content_fingerprint": (
            expected_content_fp
        ),
        "builder_version": manifest[
            "builder_version"
        ],
    }


def prefix_delta(
    prefix: deque[float] | deque[int],
    available: int,
) -> float | int:
    return (
        prefix[-1]
        - prefix[-(available + 1)]
    )


class CausalState:
    """Independent bounded causal state for one entity."""

    __slots__ = (
        "n",
        "last_date",
        "qty_history",
        "revenue_history",
        "article_history",
        "qty_total",
        "qty_square_total",
        "qty_prefix",
        "qty_square_prefix",
        "positive_qty_total",
        "positive_qty_square_total",
        "positive_count_total",
        "positive_qty_prefix",
        "positive_qty_square_prefix",
        "positive_count_prefix",
        "revenue_total",
        "revenue_prefix",
        "article_total",
        "article_prefix",
        "qty_max_28",
        "qty_max_90",
        "zero_runs",
        "zero_streak",
        "first_positive_date",
        "last_positive_date",
        "last_inter_sale_gap",
        "gap_events",
        "gap_event_sum",
        "ewm_7",
        "ewm_28",
        "ewm_90",
    )

    def __init__(self) -> None:
        self.n = 0
        self.last_date: date | None = None

        self.qty_history: deque[float] = (
            deque(maxlen=371)
        )

        self.revenue_history: deque[
            float
        ] = deque(maxlen=90)

        self.article_history: deque[
            int
        ] = deque(maxlen=90)

        self.qty_total = 0.0
        self.qty_square_total = 0.0

        self.qty_prefix: deque[
            float
        ] = deque([0.0], maxlen=91)

        self.qty_square_prefix: deque[
            float
        ] = deque([0.0], maxlen=91)

        self.positive_qty_total = 0.0
        self.positive_qty_square_total = 0.0
        self.positive_count_total = 0

        self.positive_qty_prefix: deque[
            float
        ] = deque([0.0], maxlen=91)

        self.positive_qty_square_prefix: deque[
            float
        ] = deque([0.0], maxlen=91)

        self.positive_count_prefix: deque[
            int
        ] = deque([0], maxlen=91)

        self.revenue_total = 0.0

        self.revenue_prefix: deque[
            float
        ] = deque([0.0], maxlen=29)

        self.article_total = 0

        self.article_prefix: deque[
            int
        ] = deque([0], maxlen=29)

        self.qty_max_28: deque[
            tuple[int, float]
        ] = deque()

        self.qty_max_90: deque[
            tuple[int, float]
        ] = deque()

        self.zero_runs: deque[
            list[int]
        ] = deque()

        self.zero_streak = 0

        self.first_positive_date: (
            date | None
        ) = None

        self.last_positive_date: (
            date | None
        ) = None

        self.last_inter_sale_gap: (
            int | None
        ) = None

        self.gap_events: deque[
            tuple[date, int]
        ] = deque()

        self.gap_event_sum = 0.0

        self.ewm_7: float | None = None
        self.ewm_28: float | None = None
        self.ewm_90: float | None = None

    def _lag(
        self,
        values: deque[Any],
        lag: int,
    ) -> Any | None:
        if self.n < lag:
            return None

        return values[-lag]

    def _rolling_sum(
        self,
        prefix: deque[float] | deque[int],
        window: int,
    ) -> float | int | None:
        available = min(
            window,
            self.n,
        )

        if available < 1:
            return None

        return prefix_delta(
            prefix,
            available,
        )

    def _rolling_mean(
        self,
        prefix: deque[float] | deque[int],
        window: int,
    ) -> float | None:
        available = min(
            window,
            self.n,
        )

        if available < 1:
            return None

        return float(
            prefix_delta(
                prefix,
                available,
            )
        ) / float(available)

    def _rolling_std(
        self,
        window: int,
    ) -> float | None:
        available = min(
            window,
            self.n,
        )

        if available < 2:
            return None

        total = float(
            prefix_delta(
                self.qty_prefix,
                available,
            )
        )

        square_total = float(
            prefix_delta(
                self.qty_square_prefix,
                available,
            )
        )

        mean = total / float(
            available
        )

        variance = (
            square_total
            / float(available)
            - mean * mean
        )

        return math.sqrt(
            max(0.0, variance)
        )

    def _positive_statistics(
        self,
        window: int,
    ) -> tuple[
        int | None,
        float | None,
        float | None,
    ]:
        available = min(
            window,
            self.n,
        )

        if available < 1:
            return None, None, None

        count = int(
            prefix_delta(
                self.positive_count_prefix,
                available,
            )
        )

        if count == 0:
            return 0, None, None

        total = float(
            prefix_delta(
                self.positive_qty_prefix,
                available,
            )
        )

        mean = total / float(count)

        if count < 2:
            return count, mean, None

        square_total = float(
            prefix_delta(
                self.positive_qty_square_prefix,
                available,
            )
        )

        variance = (
            square_total
            / float(count)
            - mean * mean
        )

        return (
            count,
            mean,
            math.sqrt(
                max(0.0, variance)
            ),
        )

    def _prune_gap_events(
        self,
        current_date: date,
    ) -> None:
        cutoff = (
            current_date
            - timedelta(days=90)
        )

        while (
            self.gap_events
            and self.gap_events[0][0]
            < cutoff
        ):
            _, gap = (
                self.gap_events.popleft()
            )

            self.gap_event_sum -= float(
                gap
            )

    def _mean_inter_sale_gap_90(
        self,
        current_date: date,
    ) -> float | None:
        self._prune_gap_events(
            current_date
        )

        if not self.gap_events:
            return None

        return (
            self.gap_event_sum
            / float(len(self.gap_events))
        )

    def _max_zero_streak_90(
        self,
    ) -> int | None:
        if self.n == 0:
            return None

        window_start = max(
            0,
            self.n - 90,
        )

        while (
            self.zero_runs
            and self.zero_runs[0][1]
            < window_start
        ):
            self.zero_runs.popleft()

        maximum = 0

        for start, end in self.zero_runs:
            overlap_start = max(
                start,
                window_start,
            )

            overlap_end = min(
                end,
                self.n - 1,
            )

            if overlap_end >= overlap_start:
                maximum = max(
                    maximum,
                    (
                        overlap_end
                        - overlap_start
                        + 1
                    ),
                )

        return maximum

    def snapshot(
        self,
        current_date: date,
    ) -> dict[str, Any]:
        history_days = self.n

        qty_sums = {
            window: self._rolling_sum(
                self.qty_prefix,
                window,
            )
            for window in WINDOWS
        }

        qty_means = {
            window: self._rolling_mean(
                self.qty_prefix,
                window,
            )
            for window in WINDOWS
        }

        qty_stds = {
            window: self._rolling_std(
                window
            )
            for window in STD_WINDOWS
        }

        positive_stats = {
            window: self._positive_statistics(
                window
            )
            for window in SALE_WINDOWS
        }

        sale_counts = {
            window: positive_stats[
                window
            ][0]
            for window in SALE_WINDOWS
        }

        sale_shares: dict[
            int,
            float | None,
        ] = {}

        for window in SALE_WINDOWS:
            available = min(
                window,
                self.n,
            )

            count = sale_counts[
                window
            ]

            sale_shares[window] = (
                None
                if available < 1
                or count is None
                else (
                    float(count)
                    / float(available)
                )
            )

        positive_28 = (
            positive_stats[28]
        )

        positive_90 = (
            positive_stats[90]
        )

        positive_mean_28 = (
            positive_28[1]
        )

        positive_mean_90 = (
            positive_90[1]
        )

        positive_std_90 = (
            positive_90[2]
        )

        positive_cv2_90 = None

        if (
            positive_std_90 is not None
            and positive_mean_90
            is not None
            and positive_mean_90 > 0.0
        ):
            positive_cv2_90 = (
                positive_std_90
                / positive_mean_90
            ) ** 2

        last_recency = (
            None
            if self.last_positive_date
            is None
            else (
                current_date
                - self.last_positive_date
            ).days
        )

        first_recency = (
            None
            if self.first_positive_date
            is None
            else (
                current_date
                - self.first_positive_date
            ).days
        )

        zero_streak = (
            None
            if self.n == 0
            else self.zero_streak
        )

        mean_7 = qty_means[7]
        mean_28 = qty_means[28]
        mean_90 = qty_means[90]

        delta_7_28 = (
            None
            if mean_7 is None
            or mean_28 is None
            else mean_7 - mean_28
        )

        delta_28_90 = (
            None
            if mean_28 is None
            or mean_90 is None
            else mean_28 - mean_90
        )

        return {
            "history_days_available": (
                history_days
            ),
            "is_full_history_7": (
                history_days >= 7
            ),
            "is_full_history_14": (
                history_days >= 14
            ),
            "is_full_history_28": (
                history_days >= 28
            ),
            "is_full_history_56": (
                history_days >= 56
            ),
            "is_full_history_90": (
                history_days >= 90
            ),
            "qty_lag_1": self._lag(
                self.qty_history,
                1,
            ),
            "qty_lag_7": self._lag(
                self.qty_history,
                7,
            ),
            "qty_lag_14": self._lag(
                self.qty_history,
                14,
            ),
            "qty_lag_28": self._lag(
                self.qty_history,
                28,
            ),
            "qty_roll_7_sum": qty_sums[7],
            "qty_roll_14_sum": qty_sums[14],
            "qty_roll_28_sum": qty_sums[28],
            "qty_roll_56_sum": qty_sums[56],
            "qty_roll_90_sum": qty_sums[90],
            "qty_roll_7_mean": qty_means[7],
            "qty_roll_14_mean": (
                qty_means[14]
            ),
            "qty_roll_28_mean": (
                qty_means[28]
            ),
            "qty_roll_56_mean": (
                qty_means[56]
            ),
            "qty_roll_90_mean": (
                qty_means[90]
            ),
            "qty_roll_28_std": qty_stds[28],
            "qty_roll_56_std": qty_stds[56],
            "qty_roll_90_std": qty_stds[90],
            "sale_day_count_7": (
                sale_counts[7]
            ),
            "sale_day_count_28": (
                sale_counts[28]
            ),
            "sale_day_count_90": (
                sale_counts[90]
            ),
            "sale_day_share_7": (
                sale_shares[7]
            ),
            "sale_day_share_28": (
                sale_shares[28]
            ),
            "sale_day_share_90": (
                sale_shares[90]
            ),
            "days_since_last_positive_sale": (
                last_recency
            ),
            "days_since_first_positive_sale": (
                first_recency
            ),
            "zero_sales_streak": (
                zero_streak
            ),
            "qty_mean_delta_7_28": (
                delta_7_28
            ),
            "qty_mean_delta_28_90": (
                delta_28_90
            ),
            "revenue_lag_1": self._lag(
                self.revenue_history,
                1,
            ),
            "revenue_lag_7": self._lag(
                self.revenue_history,
                7,
            ),
            "revenue_lag_28": self._lag(
                self.revenue_history,
                28,
            ),
            "revenue_roll_28_sum": (
                self._rolling_sum(
                    self.revenue_prefix,
                    28,
                )
            ),
            "revenue_roll_28_mean": (
                self._rolling_mean(
                    self.revenue_prefix,
                    28,
                )
            ),
            "article_count_lag_1": (
                self._lag(
                    self.article_history,
                    1,
                )
            ),
            "article_count_lag_7": (
                self._lag(
                    self.article_history,
                    7,
                )
            ),
            "article_count_lag_28": (
                self._lag(
                    self.article_history,
                    28,
                )
            ),
            "article_count_roll_28_sum": (
                self._rolling_sum(
                    self.article_prefix,
                    28,
                )
            ),
            "article_count_roll_28_mean": (
                self._rolling_mean(
                    self.article_prefix,
                    28,
                )
            ),
            "qty_lag_56": self._lag(
                self.qty_history,
                56,
            ),
            "qty_lag_90": self._lag(
                self.qty_history,
                90,
            ),
            "qty_lag_364": self._lag(
                self.qty_history,
                364,
            ),
            "qty_lag_371": self._lag(
                self.qty_history,
                371,
            ),
            "qty_roll_28_max": (
                None
                if self.n == 0
                or not self.qty_max_28
                else self.qty_max_28[0][1]
            ),
            "qty_roll_90_max": (
                None
                if self.n == 0
                or not self.qty_max_90
                else self.qty_max_90[0][1]
            ),
            "qty_nonzero_mean_28": (
                positive_mean_28
            ),
            "qty_nonzero_mean_90": (
                positive_mean_90
            ),
            "qty_nonzero_std_90": (
                positive_std_90
            ),
            "last_inter_sale_gap_days": (
                self.last_inter_sale_gap
            ),
            "mean_inter_sale_gap_90": (
                self._mean_inter_sale_gap_90(
                    current_date
                )
            ),
            "max_zero_sales_streak_90": (
                self._max_zero_streak_90()
            ),
            "positive_qty_cv2_90": (
                positive_cv2_90
            ),
            "qty_ewm_mean_7": self.ewm_7,
            "qty_ewm_mean_28": self.ewm_28,
            "qty_ewm_mean_90": self.ewm_90,
        }

    @staticmethod
    def _update_monotonic_max(
        values: deque[
            tuple[int, float]
        ],
        index: int,
        value: float,
        window: int,
    ) -> None:
        cutoff = (
            index + 1 - window
        )

        while (
            values
            and values[0][0] < cutoff
        ):
            values.popleft()

        while (
            values
            and values[-1][1] <= value
        ):
            values.pop()

        values.append(
            (index, value)
        )

    @staticmethod
    def _update_ewm(
        previous: float | None,
        current: float,
        span: int,
    ) -> float:
        if previous is None:
            return current

        alpha = 2.0 / float(
            span + 1
        )

        return (
            alpha * current
            + (1.0 - alpha)
            * previous
        )

    def update(
        self,
        current_date: date,
        quantity: float,
        revenue: float,
        article_count: int,
    ) -> None:
        if self.last_date is not None:
            expected = (
                self.last_date
                + timedelta(days=1)
            )

            if current_date != expected:
                raise ValidationError(
                    "entity dense-date "
                    "continuity failed"
                )

        index = self.n

        self._update_monotonic_max(
            self.qty_max_28,
            index,
            quantity,
            28,
        )

        self._update_monotonic_max(
            self.qty_max_90,
            index,
            quantity,
            90,
        )

        if quantity <= 0.0:
            if self.zero_streak == 0:
                self.zero_runs.append(
                    [index, index]
                )
            else:
                self.zero_runs[-1][1] = (
                    index
                )

            self.zero_streak += 1

        else:
            self.zero_streak = 0

            if (
                self.first_positive_date
                is None
            ):
                self.first_positive_date = (
                    current_date
                )

            if (
                self.last_positive_date
                is not None
            ):
                gap = (
                    current_date
                    - self.last_positive_date
                ).days

                self.last_inter_sale_gap = gap

                self.gap_events.append(
                    (current_date, gap)
                )

                self.gap_event_sum += float(
                    gap
                )

            self.last_positive_date = (
                current_date
            )

        self.ewm_7 = self._update_ewm(
            self.ewm_7,
            quantity,
            7,
        )

        self.ewm_28 = self._update_ewm(
            self.ewm_28,
            quantity,
            28,
        )

        self.ewm_90 = self._update_ewm(
            self.ewm_90,
            quantity,
            90,
        )

        self.qty_history.append(
            quantity
        )

        self.revenue_history.append(
            revenue
        )

        self.article_history.append(
            article_count
        )

        self.qty_total += quantity
        self.qty_square_total += (
            quantity * quantity
        )

        self.qty_prefix.append(
            self.qty_total
        )

        self.qty_square_prefix.append(
            self.qty_square_total
        )

        if quantity > 0.0:
            self.positive_qty_total += (
                quantity
            )

            self.positive_qty_square_total += (
                quantity * quantity
            )

            self.positive_count_total += 1

        self.positive_qty_prefix.append(
            self.positive_qty_total
        )

        self.positive_qty_square_prefix.append(
            self.positive_qty_square_total
        )

        self.positive_count_prefix.append(
            self.positive_count_total
        )

        self.revenue_total += revenue

        self.revenue_prefix.append(
            self.revenue_total
        )

        self.article_total += article_count

        self.article_prefix.append(
            self.article_total
        )

        self.n += 1
        self.last_date = current_date


def _first_array_mismatch(
    expected: pa.Array,
    actual: pa.Array,
) -> int | None:
    expected_values = (
        expected.to_pylist()
    )

    actual_values = (
        actual.to_pylist()
    )

    for index, (
        expected_value,
        actual_value,
    ) in enumerate(
        zip(
            expected_values,
            actual_values,
        )
    ):
        if expected_value != actual_value:
            return index

    if len(expected_values) != len(
        actual_values
    ):
        return min(
            len(expected_values),
            len(actual_values),
        )

    return None


def _assert_array_equal(
    expected: pa.Array,
    actual: pa.Array,
    label: str,
) -> None:
    if expected.equals(actual):
        return

    mismatch = _first_array_mismatch(
        expected,
        actual,
    )

    raise ValidationError(
        f"array mismatch for {label}; "
        f"first_index={mismatch}"
    )


def stream_validate_keys(
    source_table: pa.Table,
    output_table: pa.Table,
    spec: GrainSpec,
) -> None:
    if source_table.num_rows != (
        output_table.num_rows
    ):
        raise ValidationError(
            "partition row-count mismatch"
        )

    for key in spec.keys:
        source_array = (
            source_table[key]
            .combine_chunks()
        )

        output_array = (
            output_table[key]
            .combine_chunks()
        )

        _assert_array_equal(
            source_array,
            output_array,
            f"key:{key}",
        )


def stream_validate_causality(
    source_partitions: Sequence[
        MonthlyPartition
    ],
    output_partitions: Sequence[
        MonthlyPartition
    ],
    spec: GrainSpec,
    contract: Mapping[str, Any],
) -> dict[str, Any]:
    if [
        partition.key
        for partition in source_partitions
    ] != [
        partition.key
        for partition in output_partitions
    ]:
        raise ValidationError(
            "source/output partition inventory "
            "mismatch"
        )

    states: dict[
        Any,
        CausalState,
    ] = {}

    feature_types = {
        row["column"]: row["type"]
        for row in spec.output_schema
        if row["column"]
        not in spec.keys
    }

    total_rows = 0
    previous_global_key: (
        tuple[Any, ...] | None
    ) = None

    date_min: date | None = None
    date_max: date | None = None

    for (
        source_partition,
        output_partition,
    ) in zip(
        source_partitions,
        output_partitions,
    ):
        source_columns = list(
            dict.fromkeys(
                [
                    *spec.keys,
                    "qty_venduta_dense",
                    "imponibile_dense",
                    "num_articoli_dense",
                ]
            )
        )

        source_table = (
            pq.ParquetFile(
                source_partition.path
            ).read(
                columns=source_columns
            )
        )

        output_table = (
            pq.ParquetFile(
                output_partition.path
            ).read()
        )

        stream_validate_keys(
            source_table,
            output_table,
            spec,
        )

        dates = (
            source_table["data"]
            .combine_chunks()
            .to_pylist()
        )

        entity_columns = [
            (
                source_table[column]
                .combine_chunks()
                .to_pylist()
            )
            for column in spec.keys[1:]
        ]

        quantities = (
            source_table[
                "qty_venduta_dense"
            ]
            .combine_chunks()
            .to_pylist()
        )

        revenues = (
            source_table[
                "imponibile_dense"
            ]
            .combine_chunks()
            .to_pylist()
        )

        article_counts = (
            source_table[
                "num_articoli_dense"
            ]
            .combine_chunks()
            .to_pylist()
        )

        expected_values: dict[
            str,
            list[Any],
        ] = {
            name: []
            for name in spec.feature_order
        }

        for index, current_date in (
            enumerate(dates)
        ):
            if not isinstance(
                current_date,
                date,
            ):
                raise ValidationError(
                    "source date is invalid"
                )

            entity_parts = tuple(
                values[index]
                for values in entity_columns
            )

            if any(
                value is None
                for value in entity_parts
            ):
                raise ValidationError(
                    "null entity key"
                )

            global_key = (
                current_date,
                *entity_parts,
            )

            if (
                previous_global_key
                is not None
                and global_key
                <= previous_global_key
            ):
                raise ValidationError(
                    "source keys are not in "
                    "strict canonical order"
                )

            previous_global_key = (
                global_key
            )

            entity_key: Any

            if len(entity_parts) == 1:
                entity_key = (
                    entity_parts[0]
                )
            else:
                entity_key = (
                    entity_parts
                )

            state = states.get(
                entity_key
            )

            if state is None:
                state = CausalState()
                states[entity_key] = state

            snapshot = state.snapshot(
                current_date
            )

            if set(snapshot) != set(
                spec.feature_order
            ):
                raise ValidationError(
                    "independent feature set "
                    "does not match contract"
                )

            for name in (
                spec.feature_order
            ):
                expected_values[
                    name
                ].append(
                    snapshot[name]
                )

            quantity = float(
                quantities[index]
            )

            revenue = float(
                revenues[index]
            )

            article_count = int(
                article_counts[index]
            )

            if not math.isfinite(
                quantity
            ):
                raise ValidationError(
                    "non-finite source quantity"
                )

            if not math.isfinite(
                revenue
            ):
                raise ValidationError(
                    "non-finite source revenue"
                )

            state.update(
                current_date,
                quantity,
                revenue,
                article_count,
            )

            if date_min is None:
                date_min = current_date

            date_max = current_date

        for name in spec.feature_order:
            expected_array = pa.array(
                expected_values[name],
                type=ARROW_TYPES[
                    feature_types[name]
                ],
            )

            actual_array = (
                output_table[name]
                .combine_chunks()
            )

            _assert_array_equal(
                expected_array,
                actual_array,
                f"{spec.contract_key}:{name}:"
                f"{source_partition.year:04d}-"
                f"{source_partition.month:02d}",
            )

        total_rows += (
            source_table.num_rows
        )

    return {
        "row_count": total_rows,
        "entity_count": len(states),
        "date_min": (
            None
            if date_min is None
            else date_min.isoformat()
        ),
        "date_max": (
            None
            if date_max is None
            else date_max.isoformat()
        ),
        "partition_count": len(
            source_partitions
        ),
        "feature_count": len(
            spec.feature_order
        ),
    }


def validate_grain(
    dataset_run_dir: Path,
    output_root: Path,
    build_id: str,
    contract: Mapping[str, Any],
    spec: GrainSpec,
) -> dict[str, Any]:
    source_root, source_partitions = (
        inspect_source_partitions(
            dataset_run_dir,
            spec,
        )
    )

    output_dataset_root, output_partitions = (
        inspect_output_partitions(
            output_root,
            spec,
        )
    )

    if [
        partition.key
        for partition in source_partitions
    ] != [
        partition.key
        for partition in output_partitions
    ]:
        raise ValidationError(
            "source/output month coverage "
            "differs"
        )

    metadata_result = validate_metadata(
        dataset_run_dir=dataset_run_dir,
        output_root=output_root,
        build_id=build_id,
        contract=contract,
        spec=spec,
        source_partitions=source_partitions,
        output_partitions=output_partitions,
    )

    causal_result = (
        stream_validate_causality(
            source_partitions=(
                source_partitions
            ),
            output_partitions=(
                output_partitions
            ),
            spec=spec,
            contract=contract,
        )
    )

    if spec.cli_value == "family":
        decision = contract[
            "validation"
        ]["family_success_decision"]

    else:
        decision = contract[
            "validation"
        ][
            "family_priceband_success_decision"
        ]

    return {
        "ok": True,
        "classification": decision,
        "decision": decision,
        "grain": spec.contract_key,
        "source_dataset_root": str(
            source_root
        ),
        "output_dataset_root": str(
            output_dataset_root
        ),
        "metadata": metadata_result,
        "causality": causal_result,
    }


def write_validation_metadata(
    output_root: Path,
    contract: Mapping[str, Any],
    metadata_key: str,
    payload: Mapping[str, Any],
) -> Path:
    path = (
        metadata_directory(
            output_root,
            contract,
            metadata_key,
        )
        / "validation.json"
    )

    atomic_write_json(
        path,
        payload,
    )

    return path


def validate_both(
    dataset_run_dir: Path,
    output_root: Path,
    build_id: str,
    contract: Mapping[str, Any],
    specs: Mapping[str, GrainSpec],
) -> dict[str, Any]:
    family_result = validate_grain(
        dataset_run_dir,
        output_root,
        build_id,
        contract,
        specs["family"],
    )

    priceband_result = validate_grain(
        dataset_run_dir,
        output_root,
        build_id,
        contract,
        specs["family_priceband"],
    )

    combined_decision = contract[
        "validation"
    ]["combined_success_decision"]

    completed_at = utc_now()

    common = {
        "ok": True,
        "validator_version": (
            VALIDATOR_VERSION
        ),
        "contract_version": contract[
            "contract_version"
        ],
        "contract_fingerprint": contract[
            "contract_fingerprint"
        ],
        "build_id": build_id,
        "source_run_id": (
            dataset_run_dir.name
        ),
        "completed_at": completed_at,
    }

    family_payload = {
        **common,
        "classification": (
            family_result[
                "classification"
            ]
        ),
        "decision": (
            family_result["decision"]
        ),
        "result": family_result,
    }

    priceband_payload = {
        **common,
        "classification": (
            priceband_result[
                "classification"
            ]
        ),
        "decision": (
            priceband_result[
                "decision"
            ]
        ),
        "result": priceband_result,
    }

    run_payload = {
        **common,
        "classification": (
            combined_decision
        ),
        "decision": (
            combined_decision
        ),
        "family": family_result,
        "family_priceband": (
            priceband_result
        ),
    }

    write_validation_metadata(
        output_root,
        contract,
        "family_day",
        family_payload,
    )

    write_validation_metadata(
        output_root,
        contract,
        "family_priceband_day",
        priceband_payload,
    )

    write_validation_metadata(
        output_root,
        contract,
        "run",
        run_payload,
    )

    return run_payload


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Independently validate Phase "
            "2M-F2 dense-sales feature blocks."
        )
    )

    parser.add_argument(
        "--dataset-run-dir",
        required=True,
        type=Path,
        help=(
            "Validated B2 source run used "
            "for the F2 build."
        ),
    )

    parser.add_argument(
        "--output-root",
        required=True,
        type=Path,
        help=(
            "F2 candidate or final run root."
        ),
    )

    parser.add_argument(
        "--build-id",
        required=True,
        help=(
            "Expected F2 build ID."
        ),
    )

    parser.add_argument(
        "--contract",
        required=True,
        type=Path,
        help=(
            "Immutable F2 contract JSON."
        ),
    )

    parser.add_argument(
        "--grain",
        required=True,
        choices=[
            "family",
            "family_priceband",
            "both",
        ],
        help=(
            "Validation grain scope."
        ),
    )

    return parser


def run_validator_self_test(
    contract_path: Path = (
        DEFAULT_CONTRACT_PATH
    ),
) -> dict[str, Any]:
    contract = load_contract(
        contract_path
    )

    specs = build_grain_specs(
        contract
    )

    assert len(
        specs["family"].feature_order
    ) == 60

    state = CausalState()

    start = date(
        2023,
        1,
        1,
    )

    first = state.snapshot(start)

    assert first[
        "history_days_available"
    ] == 0

    assert first["qty_lag_1"] is None
    assert first["qty_roll_7_sum"] is None
    assert first["qty_ewm_mean_7"] is None

    for index in range(371):
        current_date = (
            start
            + timedelta(days=index)
        )

        snapshot = state.snapshot(
            current_date
        )

        assert set(snapshot) == set(
            specs[
                "family"
            ].feature_order
        )

        state.update(
            current_date=current_date,
            quantity=float(index + 1),
            revenue=float(
                (index + 1) * 10
            ),
            article_count=index + 1,
        )

    target = state.snapshot(
        start
        + timedelta(days=371)
    )

    assert target["qty_lag_371"] == 1.0
    assert target["qty_lag_364"] == 8.0
    assert target["qty_lag_90"] == 282.0
    assert target["qty_lag_56"] == 316.0

    expected = pa.array(
        [None, 1.0, 2.0],
        type=pa.float64(),
    )

    actual = pa.array(
        [None, 1.0, 2.0],
        type=pa.float64(),
    )

    _assert_array_equal(
        expected,
        actual,
        "self-test-equal",
    )

    corrupted = pa.array(
        [None, 1.0, 999.0],
        type=pa.float64(),
    )

    rejected_corruption = False

    try:
        _assert_array_equal(
            expected,
            corrupted,
            "self-test-corruption",
        )
    except ValidationError:
        rejected_corruption = True

    assert rejected_corruption is True

    assert len(
        contract["validation"]["checks"]
    ) == 40

    assert len(
        contract["validation"][
            "synthetic_cases"
        ]
    ) == 20

    assert len(
        contract["validation"][
            "corruption_cases"
        ]
    ) == 20

    return {
        "ok": True,
        "classification": (
            "PHASE2M_F2_VALIDATOR_SELF_TEST_OK"
        ),
        "feature_count": 60,
        "direct_lag_371": (
            target["qty_lag_371"]
        ),
        "direct_lag_364": (
            target["qty_lag_364"]
        ),
        "current_day_excluded": True,
        "corruption_rejected": True,
        "contract_check_count": 40,
        "synthetic_case_count": 20,
        "corruption_case_count": 20,
    }


def main(
    argv: Sequence[str] | None = None,
) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        validate_build_id(
            args.build_id
        )

        contract_path = (
            args.contract.resolve(
                strict=True
            )
        )

        contract = load_contract(
            contract_path
        )

        specs = build_grain_specs(
            contract
        )

        dataset_run_dir = (
            args.dataset_run_dir.resolve(
                strict=True
            )
        )

        output_root = (
            args.output_root.resolve(
                strict=True
            )
        )

        if path_is_relative_to(
            output_root,
            dataset_run_dir,
        ):
            raise ValidationError(
                "output root must not be "
                "inside source run"
            )

        if args.grain == "both":
            result = validate_both(
                dataset_run_dir,
                output_root,
                args.build_id,
                contract,
                specs,
            )

        else:
            spec = specs[args.grain]

            grain_result = validate_grain(
                dataset_run_dir,
                output_root,
                args.build_id,
                contract,
                spec,
            )

            completed_at = utc_now()

            payload = {
                "ok": True,
                "validator_version": (
                    VALIDATOR_VERSION
                ),
                "contract_version": (
                    contract[
                        "contract_version"
                    ]
                ),
                "contract_fingerprint": (
                    contract[
                        "contract_fingerprint"
                    ]
                ),
                "build_id": args.build_id,
                "source_run_id": (
                    dataset_run_dir.name
                ),
                "completed_at": (
                    completed_at
                ),
                "classification": (
                    grain_result[
                        "classification"
                    ]
                ),
                "decision": (
                    grain_result[
                        "decision"
                    ]
                ),
                "result": grain_result,
            }

            write_validation_metadata(
                output_root,
                contract,
                spec.metadata_key,
                payload,
            )

            result = payload

        print(
            json.dumps(
                result,
                indent=2,
                ensure_ascii=False,
                sort_keys=True,
            )
        )

        return 0

    except (
        ValidationError,
        OSError,
        ValueError,
        KeyError,
        AssertionError,
    ) as exc:
        print(
            f"ERROR={exc}",
            file=sys.stderr,
        )

        return 2


if __name__ == "__main__":
    raise SystemExit(main())
