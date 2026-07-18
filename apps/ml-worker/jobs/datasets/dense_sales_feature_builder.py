#!/usr/bin/env python3
"""Phase 2M-F2 causal dense-sales feature builder.

The module builds two Parquet-only feature blocks:

* data + famiglia
* data + famiglia + fascia_prezzo_iva_inc

All predictive values emitted for date T use information strictly earlier
than T. Direct lags use shift(K), rolling windows cover [T-W, T-1], and
recursive state is emitted before the current row updates that state.
"""

from __future__ import annotations

import argparse
import gc
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import uuid
from collections import deque
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq


BUILDER_VERSION = "1.0.1"
PHASE = "2M-F2"

MODULE_PATH = Path(__file__).resolve()
REPOSITORY_ROOT = MODULE_PATH.parents[4]

DEFAULT_CONTRACT_PATH = (
    MODULE_PATH.parent
    / "contracts"
    / "phase2m_f2_dense_sales_contract_v1.json"
)

DEFAULT_VALIDATOR_PATH = (
    MODULE_PATH.parent
    / "dense_sales_feature_validation.py"
)

BUILD_ID_PATTERN = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
)

WINDOWS = (7, 14, 28, 56, 90)
STD_WINDOWS = (28, 56, 90)
SALE_WINDOWS = (7, 28, 90)
EWM_SPANS = (7, 28, 90)

WINDOW_OPERATORS = {
    "shifted_window",
    "shifted_filtered_window",
    "shifted_state_window",
}

STATE_OPERATORS = {
    "prior_state",
    "prior_history_state",
    "prior_event_state",
    "prior_event_window",
    "prior_recursive_state",
}

ARROW_TYPES: Mapping[str, pa.DataType] = {
    "bool": pa.bool_(),
    "int32": pa.int32(),
    "int64": pa.int64(),
    "float64": pa.float64(),
    "date32[day]": pa.date32(),
    "string": pa.string(),
}


class BuilderError(RuntimeError):
    """Controlled F2 builder failure."""


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
    required_columns: tuple[str, ...]
    required_column_types: Mapping[str, str]
    accepted_schema_fingerprint: str
    output_schema: tuple[Mapping[str, Any], ...]
    expected_column_count: int


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()

    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)

            if not chunk:
                break

            digest.update(chunk)

    return digest.hexdigest()


def schema_fingerprint(schema: pa.Schema) -> str:
    normalized = schema.remove_metadata().to_string(
        show_field_metadata=False
    )

    return sha256_bytes(
        normalized.encode("utf-8")
    )


def atomic_write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    temp = path.with_name(
        f".{path.name}.tmp-{uuid.uuid4().hex}"
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

    temp.write_bytes(payload)
    os.chmod(temp, 0o644)
    os.replace(temp, path)


def path_is_relative_to(
    child: Path,
    parent: Path,
) -> bool:
    try:
        child.relative_to(parent)
    except ValueError:
        return False

    return True


def validate_build_id(build_id: str) -> None:
    if not BUILD_ID_PATTERN.fullmatch(build_id):
        raise BuilderError(
            "build-id must match "
            "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
        )


def load_contract(path: Path) -> dict[str, Any]:
    resolved = path.resolve(strict=True)
    payload = resolved.read_bytes()

    try:
        contract = json.loads(
            payload.decode("utf-8")
        )
    except Exception as exc:
        raise BuilderError(
            f"invalid contract JSON: {resolved}"
        ) from exc

    if contract.get("phase") != PHASE:
        raise BuilderError(
            f"unexpected contract phase: "
            f"{contract.get('phase')!r}"
        )

    if contract.get("contract_version") != "1.0.0":
        raise BuilderError(
            "unsupported F2 contract version"
        )

    stored_fingerprint = contract.get(
        "contract_fingerprint"
    )

    if not isinstance(stored_fingerprint, str):
        raise BuilderError(
            "contract fingerprint is missing"
        )

    without_fingerprint = dict(contract)
    without_fingerprint.pop(
        "contract_fingerprint",
        None,
    )

    actual_fingerprint = sha256_bytes(
        canonical_json_bytes(
            without_fingerprint
        )
    )

    if actual_fingerprint != stored_fingerprint:
        raise BuilderError(
            "contract fingerprint mismatch"
        )

    features = contract.get("features")

    if not isinstance(features, list):
        raise BuilderError(
            "contract feature registry is missing"
        )

    if len(features) != 60:
        raise BuilderError(
            f"expected 60 features, found "
            f"{len(features)}"
        )

    names = [
        feature.get("name")
        for feature in features
    ]

    if len(names) != len(set(names)):
        raise BuilderError(
            "duplicate feature names in contract"
        )

    expected_ordinals = list(
        range(1, len(features) + 1)
    )

    actual_ordinals = [
        feature.get("ordinal")
        for feature in features
    ]

    if actual_ordinals != expected_ordinals:
        raise BuilderError(
            "feature ordinals are not contiguous"
        )

    return contract


def build_grain_specs(
    contract: Mapping[str, Any],
) -> dict[str, GrainSpec]:
    inputs = contract["inputs"]
    outputs = contract["outputs"]
    compatibility = contract[
        "runtime_compatibility"
    ]
    accepted = compatibility[
        "accepted_schema_fingerprints"
    ]

    definitions = {
        "family": {
            "contract_key": "family_day",
            "metadata_key": "family_day",
        },
        "family_priceband": {
            "contract_key": (
                "family_priceband_day"
            ),
            "metadata_key": (
                "family_priceband_day"
            ),
        },
    }

    specs: dict[str, GrainSpec] = {}

    for cli_value, definition in (
        definitions.items()
    ):
        contract_key = definition[
            "contract_key"
        ]

        input_spec = inputs[contract_key]
        output_spec = outputs[contract_key]

        required_column_types = dict(
            input_spec["required_columns"]
        )

        required_columns = tuple(
            required_column_types.keys()
        )

        schema = tuple(
            output_spec["schema"]
        )

        spec = GrainSpec(
            contract_key=contract_key,
            cli_value=cli_value,
            input_dataset=input_spec[
                "dataset"
            ],
            output_dataset=output_spec[
                "dataset"
            ],
            metadata_key=definition[
                "metadata_key"
            ],
            keys=tuple(input_spec["grain"]),
            required_columns=required_columns,
            required_column_types=(
                required_column_types
            ),
            accepted_schema_fingerprint=(
                accepted[contract_key]
            ),
            output_schema=schema,
            expected_column_count=(
                output_spec["column_count"]
            ),
        )

        if len(schema) != (
            spec.expected_column_count
        ):
            raise BuilderError(
                f"output schema length mismatch "
                f"for {contract_key}"
            )

        specs[cli_value] = spec

    return specs


def selected_grains(
    grain: str,
) -> tuple[str, ...]:
    if grain == "both":
        return (
            "family",
            "family_priceband",
        )

    if grain in {
        "family",
        "family_priceband",
    }:
        return (grain,)

    raise BuilderError(
        f"unsupported grain: {grain}"
    )


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
            year = int(part.split("=", 1)[1])

        elif part.startswith("month="):
            month = int(part.split("=", 1)[1])

    if year is None or month is None:
        raise BuilderError(
            f"Parquet file is not under "
            f"year/month partitions: {parquet_path}"
        )

    if not 1 <= month <= 12:
        raise BuilderError(
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
            column = group.column(
                column_index
            )

            values.add(
                str(column.compression).upper()
            )

    return tuple(sorted(values))


def inspect_input_dataset(
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
        raise BuilderError(
            "input dataset escapes the run root"
        )

    parquet_files = sorted(
        dataset_root.rglob("*.parquet")
    )

    if not parquet_files:
        raise BuilderError(
            f"no Parquet files found under "
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

    partitions: list[MonthlyPartition] = []

    for (year, month), files in sorted(
        by_partition.items()
    ):
        if len(files) != 1:
            raise BuilderError(
                f"expected one input file for "
                f"{spec.contract_key} "
                f"{year:04d}-{month:02d}; "
                f"found {len(files)}"
            )

        parquet_path = files[0]
        parquet_file = pq.ParquetFile(
            parquet_path
        )

        metadata = parquet_file.metadata
        arrow_schema = (
            parquet_file.schema_arrow
        )

        actual_fingerprint = (
            schema_fingerprint(
                arrow_schema
            )
        )

        if actual_fingerprint != (
            spec.accepted_schema_fingerprint
        ):
            raise BuilderError(
                f"input schema fingerprint "
                f"mismatch for "
                f"{spec.contract_key}: "
                f"{actual_fingerprint}"
            )

        compression_values = (
            parquet_compressions(
                metadata
            )
        )

        if compression_values != ("ZSTD",):
            raise BuilderError(
                f"input compression mismatch "
                f"for {parquet_path}: "
                f"{compression_values}"
            )

        schema_names = set(
            arrow_schema.names
        )

        missing = sorted(
            set(spec.required_columns)
            - schema_names
        )

        if missing:
            raise BuilderError(
                f"missing required columns in "
                f"{parquet_path}: {missing}"
            )

        for (
            required_column,
            expected_type,
        ) in spec.required_column_types.items():
            actual_type = str(
                arrow_schema.field(
                    required_column
                ).type
            )

            if actual_type != expected_type:
                raise BuilderError(
                    f"input type mismatch for "
                    f"{spec.contract_key}."
                    f"{required_column}: "
                    f"expected {expected_type}; "
                    f"found {actual_type}"
                )

        partitions.append(
            MonthlyPartition(
                year=year,
                month=month,
                path=parquet_path,
                row_count=metadata.num_rows,
                schema_fingerprint=(
                    actual_fingerprint
                ),
                compression_values=(
                    compression_values
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
                raise BuilderError(
                    "input monthly partitions "
                    "are not continuous"
                )

        previous = partition.key

    return dataset_root, tuple(partitions)


def arrow_schema_from_contract(
    schema_rows: Sequence[
        Mapping[str, Any]
    ],
) -> pa.Schema:
    fields: list[pa.Field] = []

    for row in schema_rows:
        type_name = row["type"]

        if type_name not in ARROW_TYPES:
            raise BuilderError(
                f"unsupported Arrow type "
                f"in contract: {type_name}"
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


def prefix_delta(
    prefix: deque[float] | deque[int],
    available: int,
) -> float | int:
    return (
        prefix[-1]
        - prefix[-(available + 1)]
    )


class EntityState:
    """Bounded causal state for one entity."""

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

        self.qty_prefix: deque[float] = (
            deque([0.0], maxlen=91)
        )

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

        if len(values) < lag:
            raise BuilderError(
                "bounded history is shorter "
                "than a required lag"
            )

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

        mean = total / float(available)

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
            _, gap = self.gap_events.popleft()
            self.gap_event_sum -= float(gap)

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

            count = sale_counts[window]

            sale_shares[window] = (
                None
                if available < 1
                or count is None
                else (
                    float(count)
                    / float(available)
                )
            )

        positive_28 = positive_stats[28]
        positive_90 = positive_stats[90]

        positive_mean_28 = positive_28[1]
        positive_mean_90 = positive_90[1]
        positive_std_90 = positive_90[2]

        positive_cv2_90 = None

        if (
            positive_std_90 is not None
            and positive_mean_90 is not None
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

        quantity_roll_28_mean = (
            qty_means[28]
        )

        quantity_roll_90_mean = (
            qty_means[90]
        )

        quantity_roll_7_mean = (
            qty_means[7]
        )

        mean_delta_7_28 = (
            None
            if quantity_roll_7_mean
            is None
            or quantity_roll_28_mean
            is None
            else (
                quantity_roll_7_mean
                - quantity_roll_28_mean
            )
        )

        mean_delta_28_90 = (
            None
            if quantity_roll_28_mean
            is None
            or quantity_roll_90_mean
            is None
            else (
                quantity_roll_28_mean
                - quantity_roll_90_mean
            )
        )

        features: dict[str, Any] = {
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
            "qty_roll_14_mean": qty_means[14],
            "qty_roll_28_mean": qty_means[28],
            "qty_roll_56_mean": qty_means[56],
            "qty_roll_90_mean": qty_means[90],
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
            "zero_sales_streak": zero_streak,
            "qty_mean_delta_7_28": (
                mean_delta_7_28
            ),
            "qty_mean_delta_28_90": (
                mean_delta_28_90
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
                else (
                    self.qty_max_28[0][1]
                    if self.qty_max_28
                    else None
                )
            ),
            "qty_roll_90_max": (
                None
                if self.n == 0
                else (
                    self.qty_max_90[0][1]
                    if self.qty_max_90
                    else None
                )
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

        return features

    @staticmethod
    def _update_monotonic_max(
        values: deque[
            tuple[int, float]
        ],
        index: int,
        value: float,
        window: int,
    ) -> None:
        cutoff = index + 1 - window

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

        values.append((index, value))

    @staticmethod
    def _update_ewm(
        previous: float | None,
        current: float,
        span: int,
    ) -> float:
        if previous is None:
            return current

        alpha = 2.0 / float(span + 1)

        return (
            alpha * current
            + (1.0 - alpha) * previous
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
                raise BuilderError(
                    "entity dense-date continuity "
                    f"failed: expected {expected}, "
                    f"found {current_date}"
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

            if self.first_positive_date is None:
                self.first_positive_date = (
                    current_date
                )

            if self.last_positive_date is not None:
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


def validate_contract_feature_engine(
    contract: Mapping[str, Any],
) -> tuple[str, ...]:
    contract_names = tuple(
        feature["name"]
        for feature in contract["features"]
    )

    state = EntityState()

    snapshot = state.snapshot(
        date(2024, 1, 1)
    )

    engine_names = tuple(
        snapshot.keys()
    )

    if set(engine_names) != set(
        contract_names
    ):
        missing = sorted(
            set(contract_names)
            - set(engine_names)
        )

        extra = sorted(
            set(engine_names)
            - set(contract_names)
        )

        raise BuilderError(
            f"feature engine mismatch; "
            f"missing={missing}; extra={extra}"
        )

    return contract_names


def validate_input_table(
    table: pa.Table,
    required_columns: Sequence[str],
) -> None:
    for column in required_columns:
        if column not in table.column_names:
            raise BuilderError(
                f"missing input column: {column}"
            )

        if table[column].null_count:
            raise BuilderError(
                f"null input values in "
                f"required column: {column}"
            )


def table_column_to_numpy(
    table: pa.Table,
    column: str,
    dtype: np.dtype[Any],
) -> np.ndarray:
    array = table[column].combine_chunks()

    values = array.to_numpy(
        zero_copy_only=False
    )

    return np.asarray(
        values,
        dtype=dtype,
    )


def table_column_to_pylist(
    table: pa.Table,
    column: str,
) -> list[Any]:
    return (
        table[column]
        .combine_chunks()
        .to_pylist()
    )


def transform_partition(
    partition: MonthlyPartition,
    spec: GrainSpec,
    contract: Mapping[str, Any],
    states: dict[Any, EntityState],
) -> tuple[
    pa.Table,
    dict[str, Any],
]:
    read_columns = list(
        dict.fromkeys(
            [
                *spec.keys,
                "qty_venduta_dense",
                "imponibile_dense",
                "num_articoli_dense",
            ]
        )
    )

    parquet_file = pq.ParquetFile(
        partition.path
    )

    table = parquet_file.read(
        columns=read_columns
    )

    validate_input_table(
        table,
        read_columns,
    )

    row_count = table.num_rows

    dates = table_column_to_pylist(
        table,
        "data",
    )

    key_columns = [
        table_column_to_pylist(
            table,
            column,
        )
        for column in spec.keys[1:]
    ]

    quantities = table_column_to_numpy(
        table,
        "qty_venduta_dense",
        np.dtype("float64"),
    )

    revenues = table_column_to_numpy(
        table,
        "imponibile_dense",
        np.dtype("float64"),
    )

    article_counts = table_column_to_numpy(
        table,
        "num_articoli_dense",
        np.dtype("int64"),
    )

    feature_order = [
        feature["name"]
        for feature in contract["features"]
    ]

    feature_values: dict[
        str,
        list[Any],
    ] = {
        name: []
        for name in feature_order
    }

    previous_global_key: (
        tuple[Any, ...] | None
    ) = None

    date_min: date | None = None
    date_max: date | None = None

    for index in range(row_count):
        current_date = dates[index]

        if not isinstance(current_date, date):
            raise BuilderError(
                "input date is not a date value"
            )

        entity_parts = tuple(
            values[index]
            for values in key_columns
        )

        if any(
            value is None
            for value in entity_parts
        ):
            raise BuilderError(
                "null entity key encountered"
            )

        entity_key: Any

        if len(entity_parts) == 1:
            entity_key = entity_parts[0]
        else:
            entity_key = entity_parts

        global_key = (
            current_date,
            *entity_parts,
        )

        if (
            previous_global_key is not None
            and global_key
            <= previous_global_key
        ):
            raise BuilderError(
                "input rows are not strictly "
                "ordered by canonical key"
            )

        previous_global_key = global_key

        quantity = float(
            quantities[index]
        )

        revenue = float(
            revenues[index]
        )

        article_count = int(
            article_counts[index]
        )

        if not math.isfinite(quantity):
            raise BuilderError(
                "non-finite dense quantity"
            )

        if not math.isfinite(revenue):
            raise BuilderError(
                "non-finite dense revenue"
            )

        state = states.get(
            entity_key
        )

        if state is None:
            state = EntityState()
            states[entity_key] = state

        snapshot = state.snapshot(
            current_date
        )

        if set(snapshot) != set(
            feature_order
        ):
            raise BuilderError(
                "runtime feature set mismatch"
            )

        for name in feature_order:
            feature_values[name].append(
                snapshot[name]
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

    output_schema = (
        arrow_schema_from_contract(
            spec.output_schema
        )
    )

    arrays: list[
        pa.Array | pa.ChunkedArray
    ] = []

    for key in spec.keys:
        key_array = table[
            key
        ].combine_chunks()

        expected_type = output_schema.field(
            key
        ).type

        if key_array.type != expected_type:
            key_array = key_array.cast(
                expected_type
            )

        arrays.append(key_array)

    for feature in contract["features"]:
        name = feature["name"]
        field = output_schema.field(name)

        arrays.append(
            pa.array(
                feature_values[name],
                type=field.type,
            )
        )

    output_table = pa.Table.from_arrays(
        arrays,
        schema=output_schema,
    )

    if output_table.num_rows != row_count:
        raise BuilderError(
            "partition row count changed"
        )

    if output_table.num_columns != (
        spec.expected_column_count
    ):
        raise BuilderError(
            "partition column count mismatch"
        )

    stats = {
        "input_path": str(
            partition.path
        ),
        "year": partition.year,
        "month": partition.month,
        "row_count": row_count,
        "date_min": (
            date_min.isoformat()
            if date_min is not None
            else None
        ),
        "date_max": (
            date_max.isoformat()
            if date_max is not None
            else None
        ),
        "entity_state_count": len(
            states
        ),
    }

    return output_table, stats


def write_output_partition(
    table: pa.Table,
    candidate_root: Path,
    spec: GrainSpec,
    partition: MonthlyPartition,
) -> dict[str, Any]:
    output_directory = (
        candidate_root
        / spec.output_dataset
        / f"year={partition.year:04d}"
        / f"month={partition.month:02d}"
    )

    output_directory.mkdir(
        parents=True,
        exist_ok=False,
    )

    output_path = (
        output_directory
        / "part-00000.parquet"
    )

    temp_path = output_directory / (
        ".part-00000.parquet.tmp-"
        f"{uuid.uuid4().hex}"
    )

    pq.write_table(
        table,
        temp_path,
        compression="zstd",
        use_dictionary=True,
        write_statistics=True,
    )

    os.chmod(temp_path, 0o644)
    os.replace(temp_path, output_path)

    parquet_file = pq.ParquetFile(
        output_path
    )

    compressions = parquet_compressions(
        parquet_file.metadata
    )

    if compressions != ("ZSTD",):
        raise BuilderError(
            "output Parquet compression "
            "is not ZSTD"
        )

    return {
        "relative_path": str(
            output_path.relative_to(
                candidate_root
            )
        ),
        "row_count": table.num_rows,
        "column_count": table.num_columns,
        "size_bytes": (
            output_path.stat().st_size
        ),
        "sha256": sha256_file(
            output_path
        ),
        "schema_fingerprint": (
            schema_fingerprint(
                parquet_file.schema_arrow
            )
        ),
    }


def metadata_directory(
    candidate_root: Path,
    contract: Mapping[str, Any],
    metadata_key: str,
) -> Path:
    layout = contract[
        "metadata_contract"
    ]["metadata_path_layout"]

    template = layout[metadata_key]

    prefix = "<run-root>/"

    if not template.startswith(prefix):
        raise BuilderError(
            "metadata path template does "
            "not begin with <run-root>/"
        )

    relative = template[
        len(prefix):
    ]

    path = (
        candidate_root / relative
    ).resolve(strict=False)

    candidate_resolved = candidate_root.resolve(
        strict=False
    )

    if not path_is_relative_to(
        path,
        candidate_resolved,
    ):
        raise BuilderError(
            "metadata path escapes candidate"
        )

    return path


def build_grain(
    dataset_run_dir: Path,
    candidate_root: Path,
    spec: GrainSpec,
    contract: Mapping[str, Any],
    build_id: str,
    started_at: str,
) -> dict[str, Any]:
    dataset_root, partitions = (
        inspect_input_dataset(
            dataset_run_dir,
            spec,
        )
    )

    states: dict[Any, EntityState] = {}

    file_records: list[
        dict[str, Any]
    ] = []

    partition_records: list[
        dict[str, Any]
    ] = []

    total_rows = 0
    date_min: str | None = None
    date_max: str | None = None

    output_arrow_schema = (
        arrow_schema_from_contract(
            spec.output_schema
        )
    )

    output_schema_fingerprint = (
        schema_fingerprint(
            output_arrow_schema
        )
    )

    for partition in partitions:
        output_table, stats = (
            transform_partition(
                partition,
                spec,
                contract,
                states,
            )
        )

        output_file = (
            write_output_partition(
                output_table,
                candidate_root,
                spec,
                partition,
            )
        )

        file_records.append(
            output_file
        )

        partition_records.append(
            {
                **stats,
                "output_relative_path": (
                    output_file[
                        "relative_path"
                    ]
                ),
                "output_sha256": (
                    output_file["sha256"]
                ),
            }
        )

        total_rows += int(
            stats["row_count"]
        )

        if date_min is None:
            date_min = stats["date_min"]

        date_max = stats["date_max"]

        del output_table
        gc.collect()

    expected_input_rows = sum(
        partition.row_count
        for partition in partitions
    )

    if total_rows != expected_input_rows:
        raise BuilderError(
            f"grain row-count mismatch: "
            f"input={expected_input_rows}; "
            f"output={total_rows}"
        )

    fingerprint_payload = [
        {
            "relative_path": record[
                "relative_path"
            ],
            "row_count": record[
                "row_count"
            ],
            "sha256": record["sha256"],
        }
        for record in file_records
    ]

    content_fingerprint = sha256_bytes(
        canonical_json_bytes(
            fingerprint_payload
        )
    )

    metadata_dir = metadata_directory(
        candidate_root,
        contract,
        spec.metadata_key,
    )

    completed_at = utc_now()

    common_metadata = {
        "builder_version": (
            BUILDER_VERSION
        ),
        "validator_version": None,
        "contract_version": contract[
            "contract_version"
        ],
        "contract_fingerprint": contract[
            "contract_fingerprint"
        ],
        "source_run_id": (
            dataset_run_dir.name
        ),
        "build_id": build_id,
        "started_at": started_at,
        "completed_at": completed_at,
        "input_paths": [
            str(dataset_root)
        ],
        "input_schema_fingerprints": {
            spec.contract_key: (
                spec.accepted_schema_fingerprint
            )
        },
        "grain": list(spec.keys),
        "partition_columns": [
            "year",
            "month",
        ],
        "sort_columns": list(
            spec.keys
        ),
        "row_count": total_rows,
        "column_count": (
            spec.expected_column_count
        ),
        "date_min": date_min,
        "date_max": date_max,
        "compression": "zstd",
        "file_count": len(file_records),
        "content_fingerprint": (
            content_fingerprint
        ),
    }

    atomic_write_json(
        metadata_dir / "manifest.json",
        {
            **common_metadata,
            "dataset": spec.output_dataset,
            "files": file_records,
        },
    )

    atomic_write_json(
        metadata_dir / "schema.json",
        {
            "dataset": spec.output_dataset,
            "schema": list(
                spec.output_schema
            ),
        },
    )

    atomic_write_json(
        metadata_dir
        / "schema_fingerprint.json",
        {
            "dataset": spec.output_dataset,
            "schema_fingerprint": (
                output_schema_fingerprint
            ),
        },
    )

    atomic_write_json(
        metadata_dir / "build_stats.json",
        {
            **common_metadata,
            "partitions": (
                partition_records
            ),
            "entity_state_count": (
                len(states)
            ),
        },
    )

    atomic_write_json(
        metadata_dir / "validation.json",
        {
            "ok": False,
            "status": (
                "pending_independent_validation"
            ),
            "decision": None,
            "validator_version": None,
        },
    )

    result = {
        **common_metadata,
        "dataset": spec.output_dataset,
        "schema_fingerprint": (
            output_schema_fingerprint
        ),
        "files": file_records,
    }

    states.clear()
    del states
    gc.collect()

    return result


def make_validator_command(
    contract: Mapping[str, Any],
    dataset_run_dir: Path,
    candidate_root: Path,
    build_id: str,
    contract_path: Path,
) -> list[str]:
    execution = contract["execution"]

    if execution[
        "validator_invocation_policy"
    ] != (
        "sibling_module_with_current_python"
    ):
        raise BuilderError(
            "unsupported validator "
            "invocation policy"
        )

    validator_relative = Path(
        execution["validator_path"]
    )

    validator_path = (
        REPOSITORY_ROOT
        / validator_relative
    ).resolve(strict=False)

    command: list[str] = []

    replacements = {
        "<current-python>": sys.executable,
        (
            "apps/ml-worker/jobs/datasets/"
            "dense_sales_feature_validation.py"
        ): str(validator_path),
        "<dataset-run-dir>": str(
            dataset_run_dir
        ),
        "<candidate-root>": str(
            candidate_root
        ),
        "<build-id>": build_id,
        (
            "apps/ml-worker/jobs/datasets/"
            "contracts/"
            "phase2m_f2_dense_sales_contract_v1.json"
        ): str(contract_path),
    }

    for token in execution[
        "validator_command_template"
    ]:
        command.append(
            replacements.get(
                token,
                token,
            )
        )

    return command


def run_validator(
    contract: Mapping[str, Any],
    dataset_run_dir: Path,
    candidate_root: Path,
    build_id: str,
    contract_path: Path,
) -> None:
    validator_path = (
        REPOSITORY_ROOT
        / contract["execution"][
            "validator_path"
        ]
    ).resolve(strict=False)

    if not validator_path.is_file():
        raise BuilderError(
            "independent F2 validator "
            f"not found: {validator_path}"
        )

    command = make_validator_command(
        contract,
        dataset_run_dir,
        candidate_root,
        build_id,
        contract_path,
    )

    result = subprocess.run(
        command,
        cwd=REPOSITORY_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    if result.stdout:
        print(
            result.stdout,
            end="",
        )

    if result.stderr:
        print(
            result.stderr,
            end="",
            file=sys.stderr,
        )

    if result.returncode != 0:
        raise BuilderError(
            "independent validator failed "
            f"with exit code "
            f"{result.returncode}"
        )

    validation_path = (
        metadata_directory(
            candidate_root,
            contract,
            "run",
        )
        / "validation.json"
    )

    if not validation_path.is_file():
        raise BuilderError(
            "validator did not create "
            "run validation metadata"
        )

    validation = json.loads(
        validation_path.read_text(
            encoding="utf-8"
        )
    )

    expected_decision = contract[
        "validation"
    ]["combined_success_decision"]

    if (
        validation.get("ok") is not True
        or validation.get("decision")
        != expected_decision
    ):
        raise BuilderError(
            "validator result did not "
            "authorize promotion"
        )


def create_run_metadata(
    candidate_root: Path,
    contract: Mapping[str, Any],
    dataset_run_dir: Path,
    build_id: str,
    started_at: str,
    grain_results: Mapping[
        str,
        Any,
    ],
) -> None:
    run_metadata_dir = metadata_directory(
        candidate_root,
        contract,
        "run",
    )

    completed_at = utc_now()

    atomic_write_json(
        run_metadata_dir
        / "manifest.json",
        {
            "builder_version": (
                BUILDER_VERSION
            ),
            "validator_version": None,
            "contract_version": contract[
                "contract_version"
            ],
            "contract_fingerprint": contract[
                "contract_fingerprint"
            ],
            "source_run_id": (
                dataset_run_dir.name
            ),
            "build_id": build_id,
            "started_at": started_at,
            "completed_at": completed_at,
            "input_paths": [
                str(dataset_run_dir)
            ],
            "input_schema_fingerprints": {
                key: value[
                    "input_schema_fingerprints"
                ]
                for key, value
                in grain_results.items()
            },
            "grain": "both",
            "partition_columns": [
                "year",
                "month",
            ],
            "sort_columns": None,
            "row_count": sum(
                int(result["row_count"])
                for result
                in grain_results.values()
            ),
            "column_count": None,
            "date_min": min(
                result["date_min"]
                for result
                in grain_results.values()
            ),
            "date_max": max(
                result["date_max"]
                for result
                in grain_results.values()
            ),
            "compression": "zstd",
            "file_count": sum(
                int(result["file_count"])
                for result
                in grain_results.values()
            ),
            "content_fingerprint": (
                sha256_bytes(
                    canonical_json_bytes(
                        {
                            key: result[
                                "content_fingerprint"
                            ]
                            for key, result
                            in grain_results.items()
                        }
                    )
                )
            ),
            "datasets": (
                grain_results
            ),
            "status": (
                "awaiting_independent_validation"
            ),
        },
    )

    atomic_write_json(
        run_metadata_dir
        / "validation.json",
        {
            "ok": False,
            "status": (
                "pending_independent_validation"
            ),
            "decision": None,
            "validator_version": None,
        },
    )


def dry_run_plan(
    args: argparse.Namespace,
    contract: Mapping[str, Any],
    specs: Mapping[str, GrainSpec],
) -> dict[str, Any]:
    dataset_run_dir = (
        args.dataset_run_dir.resolve(
            strict=True
        )
    )

    selected = selected_grains(
        args.grain
    )

    grain_plans: dict[
        str,
        Any,
    ] = {}

    for grain in selected:
        spec = specs[grain]

        dataset_root, partitions = (
            inspect_input_dataset(
                dataset_run_dir,
                spec,
            )
        )

        grain_plans[grain] = {
            "input_dataset": (
                spec.input_dataset
            ),
            "input_path": str(
                dataset_root
            ),
            "output_dataset": (
                spec.output_dataset
            ),
            "monthly_partition_count": (
                len(partitions)
            ),
            "row_count": sum(
                partition.row_count
                for partition in partitions
            ),
            "date_partition_min": (
                f"{partitions[0].year:04d}-"
                f"{partitions[0].month:02d}"
            ),
            "date_partition_max": (
                f"{partitions[-1].year:04d}-"
                f"{partitions[-1].month:02d}"
            ),
            "input_schema_fingerprint": (
                spec.accepted_schema_fingerprint
            ),
            "output_column_count": (
                spec.expected_column_count
            ),
            "output_feature_count": 60,
            "compression": "zstd",
            "monthly_output_file_count": 1,
        }

    output_root = args.output_root.resolve(
        strict=False
    )

    candidate_root = (
        output_root
        / f".tmp-{args.build_id}"
    )

    final_root = (
        output_root
        / args.build_id
    )

    return {
        "ok": True,
        "classification": (
            "PHASE2M_F2_DRY_RUN_PLAN_READY"
        ),
        "decision": (
            "READY_FOR_PHASE2M_F2_"
            "DRY_RUN_PLAN_VALIDATION"
        ),
        "mode": "dry-run",
        "builder_version": (
            BUILDER_VERSION
        ),
        "contract_version": contract[
            "contract_version"
        ],
        "contract_fingerprint": contract[
            "contract_fingerprint"
        ],
        "dataset_run_dir": str(
            dataset_run_dir
        ),
        "output_root": str(
            output_root
        ),
        "candidate_root": str(
            candidate_root
        ),
        "final_root": str(
            final_root
        ),
        "selected_grains": list(
            selected
        ),
        "grains": grain_plans,
        "maximum_quantity_lookback_days": (
            contract["causality"][
                "maximum_quantity_lookback_days"
            ]
        ),
        "maximum_revenue_lookback_days": (
            contract["causality"][
                "maximum_revenue_lookback_days"
            ]
        ),
        "maximum_article_lookback_days": (
            contract["causality"][
                "maximum_article_lookback_days"
            ]
        ),
        "source_write": False,
        "parquet_data_rows_read": 0,
        "parquet_metadata_read": True,
        "database_access": False,
        "git_action": False,
    }


def execute_build(
    args: argparse.Namespace,
    contract: Mapping[str, Any],
    specs: Mapping[str, GrainSpec],
    contract_path: Path,
) -> dict[str, Any]:
    if args.grain != "both":
        raise BuilderError(
            "--execute requires --grain both"
        )

    if not args.confirm_write_feature_lake:
        raise BuilderError(
            "--execute requires "
            "--confirm-write-feature-lake"
        )

    if args.overwrite_policy != "fail":
        raise BuilderError(
            "F2 v1 supports overwrite "
            "policy fail only"
        )

    dataset_run_dir = (
        args.dataset_run_dir.resolve(
            strict=True
        )
    )

    output_root = args.output_root.resolve(
        strict=False
    )

    if path_is_relative_to(
        output_root,
        dataset_run_dir,
    ):
        raise BuilderError(
            "output root must not be inside "
            "the source dataset run"
        )

    output_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    output_root = output_root.resolve(
        strict=True
    )

    candidate_root = (
        output_root
        / f".tmp-{args.build_id}"
    )

    final_root = (
        output_root
        / args.build_id
    )

    failed_root = (
        output_root
        / f".failed-{args.build_id}"
    )

    if candidate_root.exists():
        raise BuilderError(
            f"candidate already exists: "
            f"{candidate_root}"
        )

    if final_root.exists():
        raise BuilderError(
            f"final output already exists: "
            f"{final_root}"
        )

    if failed_root.exists():
        raise BuilderError(
            f"failed-run path already exists: "
            f"{failed_root}"
        )

    candidate_root.mkdir(
        parents=False,
        exist_ok=False,
    )

    if (
        os.stat(candidate_root).st_dev
        != os.stat(output_root).st_dev
    ):
        raise BuilderError(
            "candidate and final paths are "
            "not on the same filesystem"
        )

    started_at = utc_now()

    try:
        grain_results: dict[
            str,
            Any,
        ] = {}

        for grain in (
            "family",
            "family_priceband",
        ):
            grain_results[grain] = (
                build_grain(
                    dataset_run_dir,
                    candidate_root,
                    specs[grain],
                    contract,
                    args.build_id,
                    started_at,
                )
            )

            gc.collect()

        create_run_metadata(
            candidate_root,
            contract,
            dataset_run_dir,
            args.build_id,
            started_at,
            grain_results,
        )

        grain_results_copy = dict(
            grain_results
        )

        grain_results.clear()
        del grain_results
        gc.collect()

        run_validator(
            contract,
            dataset_run_dir,
            candidate_root,
            args.build_id,
            contract_path,
        )

        os.replace(
            candidate_root,
            final_root,
        )

        return {
            "ok": True,
            "classification": (
                "PHASE2M_F2_DENSE_SALES_"
                "MATERIALIZATION_OK"
            ),
            "decision": (
                "PHASE2M_F2_DENSE_SALES_"
                "VALIDATION_OK"
            ),
            "mode": "execute",
            "builder_version": (
                BUILDER_VERSION
            ),
            "contract_fingerprint": (
                contract[
                    "contract_fingerprint"
                ]
            ),
            "source_run_id": (
                dataset_run_dir.name
            ),
            "build_id": args.build_id,
            "final_root": str(
                final_root
            ),
            "grains": grain_results_copy,
        }

    except Exception:
        if candidate_root.exists():
            os.replace(
                candidate_root,
                failed_root,
            )

        raise


def delegate_validate_only(
    args: argparse.Namespace,
    contract: Mapping[str, Any],
    contract_path: Path,
) -> dict[str, Any]:
    output_root = args.output_root.resolve(
        strict=True
    )

    dataset_run_dir = (
        args.dataset_run_dir.resolve(
            strict=True
        )
    )

    validator_path = (
        REPOSITORY_ROOT
        / contract["execution"][
            "validator_path"
        ]
    ).resolve(strict=False)

    if not validator_path.is_file():
        raise BuilderError(
            "independent F2 validator "
            f"not found: {validator_path}"
        )

    command = make_validator_command(
        contract,
        dataset_run_dir,
        output_root,
        args.build_id,
        contract_path,
    )

    if args.grain != "both":
        grain_index = command.index(
            "--grain"
        )

        command[
            grain_index + 1
        ] = args.grain

    completed = subprocess.run(
        command,
        cwd=REPOSITORY_ROOT,
        check=False,
    )

    if completed.returncode != 0:
        raise BuilderError(
            "independent validator failed "
            f"with exit code "
            f"{completed.returncode}"
        )

    return {
        "ok": True,
        "classification": (
            "PHASE2M_F2_VALIDATE_ONLY_"
            "DELEGATION_OK"
        ),
        "decision": (
            "VALIDATOR_COMPLETED"
        ),
        "mode": "validate-only",
        "validator_path": str(
            validator_path
        ),
        "output_root": str(
            output_root
        ),
        "grain": args.grain,
    }


def validate_cli_args(
    args: argparse.Namespace,
) -> None:
    validate_build_id(
        args.build_id
    )

    selected_mode_count = sum(
        [
            bool(args.dry_run),
            bool(args.execute),
            bool(args.validate_only),
        ]
    )

    if selected_mode_count != 1:
        raise BuilderError(
            "exactly one execution mode "
            "must be selected"
        )

    if (
        args.execute
        and args.grain != "both"
    ):
        raise BuilderError(
            "partial-grain execution "
            "is forbidden"
        )

    if (
        args.execute
        and not args.confirm_write_feature_lake
    ):
        raise BuilderError(
            "--execute requires explicit "
            "write confirmation"
        )

    if (
        not args.execute
        and args.confirm_write_feature_lake
    ):
        raise BuilderError(
            "write confirmation is valid "
            "only with --execute"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Build causal Phase 2M-F2 "
            "dense-sales feature blocks."
        )
    )

    modes = parser.add_mutually_exclusive_group(
        required=True
    )

    modes.add_argument(
        "--dry-run",
        action="store_true",
        help=(
            "Inspect input Parquet metadata and "
            "emit the deterministic build plan "
            "without writing output."
        ),
    )

    modes.add_argument(
        "--execute",
        action="store_true",
        help=(
            "Build both feature grains, run the "
            "independent validator, and promote "
            "the candidate atomically."
        ),
    )

    modes.add_argument(
        "--validate-only",
        action="store_true",
        help=(
            "Delegate validation of an existing "
            "candidate or final run to the "
            "independent validator."
        ),
    )

    parser.add_argument(
        "--dataset-run-dir",
        type=Path,
        required=True,
        help=(
            "Validated B2 dataset run directory."
        ),
    )

    parser.add_argument(
        "--output-root",
        type=Path,
        required=True,
        help=(
            "Parent output directory for dry-run "
            "planning or execution; in "
            "validate-only mode this is the "
            "candidate/final run root."
        ),
    )

    parser.add_argument(
        "--build-id",
        required=True,
        help=(
            "Filesystem-safe immutable F2 build ID."
        ),
    )

    parser.add_argument(
        "--contract",
        type=Path,
        default=DEFAULT_CONTRACT_PATH,
        help=(
            "F2 contract JSON. Feature semantics "
            "cannot be overridden from the CLI."
        ),
    )

    parser.add_argument(
        "--grain",
        choices=[
            "family",
            "family_priceband",
            "both",
        ],
        default="both",
        help=(
            "Grain scope. --execute requires both."
        ),
    )

    parser.add_argument(
        "--overwrite-policy",
        choices=["fail"],
        default="fail",
        help=(
            "F2 v1 immutable-output policy."
        ),
    )

    parser.add_argument(
        "--confirm-write-feature-lake",
        action="store_true",
        help=(
            "Required explicit gate for --execute."
        ),
    )

    return parser


def run_feature_kernel_self_test(
    contract_path: Path = (
        DEFAULT_CONTRACT_PATH
    ),
) -> dict[str, Any]:
    contract = load_contract(
        contract_path
    )

    feature_order = (
        validate_contract_feature_engine(
            contract
        )
    )

    state = EntityState()
    day_1 = date(2024, 1, 1)

    first = state.snapshot(day_1)

    assert first["qty_lag_1"] is None
    assert first["qty_roll_7_sum"] is None
    assert first["qty_ewm_mean_7"] is None
    assert (
        first["history_days_available"]
        == 0
    )

    state.update(
        day_1,
        quantity=2.0,
        revenue=20.0,
        article_count=1,
    )

    second_date = day_1 + timedelta(
        days=1
    )

    second = state.snapshot(
        second_date
    )

    assert second["qty_lag_1"] == 2.0
    assert second["qty_roll_7_sum"] == 2.0
    assert second["qty_roll_7_mean"] == 2.0
    assert second["sale_day_count_7"] == 1
    assert second["sale_day_share_7"] == 1.0
    assert (
        second["days_since_last_positive_sale"]
        == 1
    )
    assert second["zero_sales_streak"] == 0
    assert second["qty_ewm_mean_7"] == 2.0

    state.update(
        second_date,
        quantity=0.0,
        revenue=0.0,
        article_count=0,
    )

    third_date = day_1 + timedelta(
        days=2
    )

    third = state.snapshot(
        third_date
    )

    assert third["qty_lag_1"] == 0.0
    assert third["zero_sales_streak"] == 1
    assert (
        third["days_since_last_positive_sale"]
        == 2
    )

    state.update(
        third_date,
        quantity=4.0,
        revenue=40.0,
        article_count=2,
    )

    fourth_date = day_1 + timedelta(
        days=3
    )

    fourth = state.snapshot(
        fourth_date
    )

    assert fourth[
        "last_inter_sale_gap_days"
    ] == 2

    assert fourth[
        "mean_inter_sale_gap_90"
    ] == 2.0

    assert (
        fourth["days_since_last_positive_sale"]
        == 1
    )

    seasonal = EntityState()
    seasonal_start = date(
        2023,
        1,
        1,
    )

    for index in range(371):
        current_date = (
            seasonal_start
            + timedelta(days=index)
        )

        snapshot = seasonal.snapshot(
            current_date
        )

        assert set(snapshot) == set(
            feature_order
        )

        seasonal.update(
            current_date,
            quantity=float(index + 1),
            revenue=float(
                (index + 1) * 10
            ),
            article_count=index + 1,
        )

    target_date = (
        seasonal_start
        + timedelta(days=371)
    )

    target = seasonal.snapshot(
        target_date
    )

    assert target["qty_lag_371"] == 1.0
    assert target["qty_lag_364"] == 8.0
    assert target["qty_lag_90"] == 282.0
    assert target["qty_lag_56"] == 316.0

    return {
        "ok": True,
        "classification": (
            "PHASE2M_F2_FEATURE_KERNEL_"
            "SELF_TEST_OK"
        ),
        "feature_count": len(
            feature_order
        ),
        "direct_lag_371": (
            target["qty_lag_371"]
        ),
        "direct_lag_364": (
            target["qty_lag_364"]
        ),
        "current_day_excluded": True,
    }


def main(
    argv: Sequence[str] | None = None,
) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        validate_cli_args(args)

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

        validate_contract_feature_engine(
            contract
        )

        if args.dry_run:
            result = dry_run_plan(
                args,
                contract,
                specs,
            )

        elif args.execute:
            result = execute_build(
                args,
                contract,
                specs,
                contract_path,
            )

        else:
            result = delegate_validate_only(
                args,
                contract,
                contract_path,
            )

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
        BuilderError,
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
