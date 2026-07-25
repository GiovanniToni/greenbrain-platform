from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
import os
import resource
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Sequence

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq


G2_KEYS = [
    "data",
    "famiglia",
]

H2_KEYS = [
    "data",
    "famiglia",
    "fascia_prezzo_iva_inc",
]


@dataclass(frozen=True)
class DatasetInventory:
    root: Path
    partitions: tuple[str, ...]
    parquet_file_count: int
    parquet_bytes: int
    schema: pa.Schema


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_json(path: Path) -> Any:
    return json.loads(
        path.read_text(
            encoding="utf-8",
            errors="strict",
        )
    )


def write_json(
    path: Path,
    value: Any,
) -> None:
    path.write_text(
        json.dumps(
            value,
            indent=2,
            ensure_ascii=True,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def write_tsv(
    path: Path,
    fields: Sequence[str],
    rows: Iterable[dict[str, Any]],
) -> None:
    with path.open(
        "w",
        encoding="utf-8",
        newline="",
    ) as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=list(fields),
            delimiter="\t",
            extrasaction="ignore",
        )

        writer.writeheader()
        writer.writerows(rows)


def verify_contract(
    contract_path: Path,
) -> dict[str, Any]:
    contract = load_json(contract_path)

    if contract.get("version") != "1.0.0":
        raise AssertionError(
            "UNSUPPORTED_CONTRACT_VERSION:"
            f"{contract.get('version')}"
        )

    if contract.get("status") != (
        "FROZEN_EXECUTABLE_CONTRACT"
    ):
        raise AssertionError(
            "CONTRACT_NOT_FROZEN:"
            f"{contract.get('status')}"
        )

    preimage = copy.deepcopy(contract)

    try:
        embedded = preimage.pop(
            "contract_fingerprint"
        )
    except KeyError as exc:
        raise AssertionError(
            "CONTRACT_FINGERPRINT_MISSING"
        ) from exc

    recomputed = sha256_bytes(
        canonical_json_bytes(preimage)
    )

    if embedded != recomputed:
        raise AssertionError(
            "CONTRACT_FINGERPRINT_MISMATCH:"
            f"embedded={embedded}:"
            f"recomputed={recomputed}"
        )

    return contract


def partition_name(
    path: Path,
    root: Path,
) -> str:
    relative = path.relative_to(root)

    year = next(
        (
            component
            for component in relative.parts
            if component.startswith("year=")
        ),
        None,
    )

    month = next(
        (
            component
            for component in relative.parts
            if component.startswith("month=")
        ),
        None,
    )

    if year is None or month is None:
        raise AssertionError(
            f"INVALID_PARTITION_PATH:{path}"
        )

    return f"{year}/{month}"


def inventory_dataset(
    root: Path,
) -> DatasetInventory:
    if not root.is_dir():
        raise AssertionError(
            f"DATASET_ROOT_NOT_FOUND:{root}"
        )

    files = sorted(
        root.rglob("*.parquet"),
        key=lambda path: str(
            path.relative_to(root)
        ),
    )

    if not files:
        raise AssertionError(
            f"NO_PARQUET_FILES:{root}"
        )

    partitions: set[str] = set()
    total_bytes = 0
    reference_schema: pa.Schema | None = None

    for path in files:
        if path.is_symlink():
            raise AssertionError(
                f"PARQUET_SYMLINK_NOT_ALLOWED:{path}"
            )

        partitions.add(
            partition_name(path, root)
        )

        total_bytes += path.stat().st_size

        schema = pq.ParquetFile(
            path
        ).schema_arrow

        if reference_schema is None:
            reference_schema = schema

        elif not schema.equals(
            reference_schema,
            check_metadata=False,
        ):
            raise AssertionError(
                f"INTERNAL_SCHEMA_MISMATCH:{path}"
            )

    assert reference_schema is not None

    return DatasetInventory(
        root=root,
        partitions=tuple(
            sorted(partitions)
        ),
        parquet_file_count=len(files),
        parquet_bytes=total_bytes,
        schema=reference_schema,
    )


def files_for_partition(
    root: Path,
    partition: str,
) -> list[Path]:
    directory = root.joinpath(
        *partition.split("/")
    )

    files = sorted(
        directory.rglob("*.parquet"),
        key=lambda path: str(
            path.relative_to(directory)
        ),
    )

    if not files:
        raise AssertionError(
            f"PARTITION_NOT_FOUND:{directory}"
        )

    return files


def read_partition(
    root: Path,
    partition: str,
    columns: Sequence[str],
) -> pd.DataFrame:
    unique_columns = list(
        dict.fromkeys(columns)
    )

    tables = [
        pq.ParquetFile(path).read(
            columns=unique_columns,
        )
        for path in files_for_partition(
            root,
            partition,
        )
    ]

    table = (
        tables[0]
        if len(tables) == 1
        else pa.concat_tables(
            tables,
            promote_options="default",
        )
    )

    return table.to_pandas(
        split_blocks=True,
        self_destruct=True,
    )


def choose_columns_evenly(
    columns: Sequence[str],
    count: int,
) -> list[str]:
    if count <= 0 or count >= len(columns):
        return list(columns)

    if count == 1:
        return [columns[0]]

    indexes = sorted(
        {
            int(
                round(
                    index
                    * (len(columns) - 1)
                    / (count - 1)
                )
            )
            for index in range(count)
        }
    )

    selected = [
        columns[index]
        for index in indexes
    ]

    if len(selected) != count:
        raise AssertionError(
            "COLUMN_SAMPLE_CARDINALITY_MISMATCH:"
            f"expected={count}:actual={len(selected)}"
        )

    return selected


def chunked(
    values: Sequence[str],
    size: int,
) -> Iterable[list[str]]:
    if size <= 0:
        raise ValueError(
            "CHUNK_SIZE_MUST_BE_POSITIVE"
        )

    for start in range(
        0,
        len(values),
        size,
    ):
        yield list(
            values[start:start + size]
        )


def null_safe_mismatch_count(
    left: pd.Series,
    right: pd.Series,
    *,
    rtol: float,
    atol: float,
) -> int:
    both_null = (
        left.isna().to_numpy()
        & right.isna().to_numpy()
    )

    if (
        pd.api.types.is_numeric_dtype(
            left.dtype
        )
        and pd.api.types.is_numeric_dtype(
            right.dtype
        )
    ):
        left_values = pd.to_numeric(
            left,
            errors="coerce",
        ).to_numpy(
            dtype=float,
            na_value=np.nan,
        )

        right_values = pd.to_numeric(
            right,
            errors="coerce",
        ).to_numpy(
            dtype=float,
            na_value=np.nan,
        )

        equal = np.isclose(
            left_values,
            right_values,
            rtol=rtol,
            atol=atol,
            equal_nan=True,
        )

        return int(
            (~equal).sum()
        )

    equal = (
        left.eq(right)
        .fillna(False)
        .to_numpy()
        | both_null
    )

    return int(
        (~equal).sum()
    )


def compare_metric(
    left: pd.Series,
    right: pd.Series,
    *,
    exact_integer: bool,
    rtol: float,
    atol: float,
) -> dict[str, Any]:
    left_values = pd.to_numeric(
        left,
        errors="coerce",
    ).to_numpy(
        dtype=float,
        na_value=np.nan,
    )

    right_values = pd.to_numeric(
        right,
        errors="coerce",
    ).to_numpy(
        dtype=float,
        na_value=np.nan,
    )

    left_null = np.isnan(left_values)
    right_null = np.isnan(right_values)

    null_mismatch_count = int(
        np.logical_xor(
            left_null,
            right_null,
        ).sum()
    )

    if exact_integer:
        equal = (
            (left_values == right_values)
            | (
                left_null
                & right_null
            )
        )

    else:
        equal = np.isclose(
            left_values,
            right_values,
            rtol=rtol,
            atol=atol,
            equal_nan=True,
        )

    value_mismatch_count = int(
        (~equal).sum()
    )

    comparable = ~(
        left_null
        | right_null
    )

    maximum_absolute_difference = (
        float(
            np.abs(
                left_values[comparable]
                - right_values[comparable]
            ).max()
        )
        if comparable.any()
        else 0.0
    )

    return {
        "null_mismatch_count": (
            null_mismatch_count
        ),
        "value_mismatch_count": (
            value_mismatch_count
        ),
        "maximum_absolute_difference": (
            maximum_absolute_difference
        ),
    }


def peak_rss_bytes() -> int:
    status = Path(
        "/proc/self/status"
    )

    if status.is_file():
        for line in status.read_text(
            encoding="utf-8",
            errors="replace",
        ).splitlines():
            if line.startswith("VmHWM:"):
                return (
                    int(line.split()[1])
                    * 1024
                )

    return int(
        resource.getrusage(
            resource.RUSAGE_SELF
        ).ru_maxrss
    ) * 1024


def validate_schema_relationship(
    contract: dict[str, Any],
    g2: DatasetInventory,
    h2: DatasetInventory,
) -> dict[str, Any]:
    expected_g2 = contract[
        "datasets"
    ][
        "g2_family_day"
    ]

    expected_h2 = contract[
        "datasets"
    ][
        "h2_family_priceband_day"
    ]

    if len(g2.schema) != int(
        expected_g2["expected_columns"]
    ):
        raise AssertionError(
            "G2_COLUMN_COUNT_MISMATCH"
        )

    if len(h2.schema) != int(
        expected_h2["expected_columns"]
    ):
        raise AssertionError(
            "H2_COLUMN_COUNT_MISMATCH"
        )

    if len(g2.partitions) != int(
        expected_g2["expected_partitions"]
    ):
        raise AssertionError(
            "G2_PARTITION_COUNT_MISMATCH"
        )

    if len(h2.partitions) != int(
        expected_h2["expected_partitions"]
    ):
        raise AssertionError(
            "H2_PARTITION_COUNT_MISMATCH"
        )

    if g2.partitions != h2.partitions:
        raise AssertionError(
            "PARTITION_DOMAIN_MISMATCH"
        )

    g2_fields = {
        field.name: field
        for field in g2.schema
    }

    h2_fields = {
        field.name: field
        for field in h2.schema
    }

    g2_only = sorted(
        set(g2_fields)
        - set(h2_fields)
    )

    if g2_only:
        raise AssertionError(
            "G2_COLUMNS_MISSING_FROM_H2:"
            + ",".join(g2_only[:20])
        )

    shared_context = contract[
        "schema_relationship"
    ][
        "shared_context_columns"
    ]

    for column in shared_context:
        if column not in g2_fields:
            raise AssertionError(
                f"SHARED_COLUMN_MISSING_G2:{column}"
            )

        if column not in h2_fields:
            raise AssertionError(
                f"SHARED_COLUMN_MISSING_H2:{column}"
            )

        if not g2_fields[
            column
        ].type.equals(
            h2_fields[column].type
        ):
            raise AssertionError(
                f"SHARED_COLUMN_TYPE_MISMATCH:{column}"
            )

    return {
        "g2_column_count": len(g2.schema),
        "h2_column_count": len(h2.schema),
        "partition_count": len(g2.partitions),
        "shared_context_column_count": len(
            shared_context
        ),
        "result": "PASS",
    }


def validate_partition(
    *,
    contract: dict[str, Any],
    g2: DatasetInventory,
    h2: DatasetInventory,
    partition: str,
    context_sample_columns: int,
    context_batch_columns: int,
) -> dict[str, Any]:
    started = time.monotonic()

    g2_keys = read_partition(
        g2.root,
        partition,
        G2_KEYS,
    )

    h2_keys = read_partition(
        h2.root,
        partition,
        H2_KEYS,
    )

    g2_null_key_rows = int(
        g2_keys[G2_KEYS]
        .isna()
        .any(axis=1)
        .sum()
    )

    h2_null_key_rows = int(
        h2_keys[H2_KEYS]
        .isna()
        .any(axis=1)
        .sum()
    )

    g2_duplicate_key_rows = int(
        g2_keys.duplicated(
            G2_KEYS,
            keep=False,
        ).sum()
    )

    h2_duplicate_key_rows = int(
        h2_keys.duplicated(
            H2_KEYS,
            keep=False,
        ).sum()
    )

    if (
        g2_null_key_rows
        or h2_null_key_rows
        or g2_duplicate_key_rows
        or h2_duplicate_key_rows
    ):
        raise AssertionError(
            "KEY_INTEGRITY_FAILURE:"
            f"partition={partition}:"
            f"g2_null={g2_null_key_rows}:"
            f"h2_null={h2_null_key_rows}:"
            f"g2_duplicate={g2_duplicate_key_rows}:"
            f"h2_duplicate={h2_duplicate_key_rows}"
        )

    foreign_key = (
        h2_keys[G2_KEYS]
        .drop_duplicates()
        .merge(
            g2_keys[G2_KEYS],
            on=G2_KEYS,
            how="left",
            indicator=True,
            validate="one_to_one",
        )
    )

    orphan_key_count = int(
        (
            foreign_key["_merge"]
            != "both"
        ).sum()
    )

    if orphan_key_count:
        raise AssertionError(
            "H2_TO_G2_ORPHAN_KEYS:"
            f"partition={partition}:"
            f"count={orphan_key_count}"
        )

    shared_context = contract[
        "schema_relationship"
    ][
        "shared_context_columns"
    ]

    selected_context = (
        choose_columns_evenly(
            shared_context,
            context_sample_columns,
        )
    )

    context_rows: list[
        dict[str, Any]
    ] = []

    context_mismatch_count = 0
    context_missing_key_count = 0

    for column_batch in chunked(
        selected_context,
        context_batch_columns,
    ):
        g2_frame = read_partition(
            g2.root,
            partition,
            G2_KEYS + column_batch,
        )

        h2_frame = read_partition(
            h2.root,
            partition,
            H2_KEYS + column_batch,
        )

        merged = h2_frame.merge(
            g2_frame,
            on=G2_KEYS,
            how="left",
            suffixes=(
                "_h2",
                "_g2",
            ),
            indicator=True,
            validate="many_to_one",
        )

        missing_keys = int(
            (
                merged["_merge"]
                != "both"
            ).sum()
        )

        context_missing_key_count += (
            missing_keys
        )

        for column in column_batch:
            mismatch_count = (
                null_safe_mismatch_count(
                    merged[
                        f"{column}_h2"
                    ],
                    merged[
                        f"{column}_g2"
                    ],
                    rtol=1e-10,
                    atol=1e-8,
                )
            )

            context_mismatch_count += (
                mismatch_count
            )

            context_rows.append(
                {
                    "partition": partition,
                    "column": column,
                    "h2_rows": len(h2_frame),
                    "missing_g2_key_matches": (
                        missing_keys
                    ),
                    "value_mismatch_count": (
                        mismatch_count
                    ),
                    "result": (
                        "PASS"
                        if (
                            missing_keys == 0
                            and mismatch_count == 0
                        )
                        else "FAIL"
                    ),
                }
            )

    approved = contract[
        "commercial_reconciliations"
    ][
        "approved_exact_sum"
    ]

    h2_metric_columns = sorted(
        {
            record["h2_column"]
            for record in approved
        }
    )

    g2_metric_columns = sorted(
        {
            record["g2_column"]
            for record in approved
        }
    )

    g2_metrics = read_partition(
        g2.root,
        partition,
        G2_KEYS + g2_metric_columns,
    )

    h2_metrics = read_partition(
        h2.root,
        partition,
        H2_KEYS + h2_metric_columns,
    )

    aggregated = (
        h2_metrics[
            G2_KEYS
            + h2_metric_columns
        ]
        .groupby(
            G2_KEYS,
            as_index=False,
            sort=True,
            dropna=False,
        )
        .sum(
            min_count=1
        )
    )

    comparison = (
        g2_metrics[
            G2_KEYS
            + g2_metric_columns
        ]
        .merge(
            aggregated,
            on=G2_KEYS,
            how="outer",
            indicator=True,
            validate="one_to_one",
        )
    )

    metric_orphan_count = int(
        (
            comparison["_merge"]
            != "both"
        ).sum()
    )

    metric_rows: list[
        dict[str, Any]
    ] = []

    metric_mismatch_count = 0
    metric_null_mismatch_count = 0

    g2_fields = {
        field.name: field
        for field in g2.schema
    }

    h2_fields = {
        field.name: field
        for field in h2.schema
    }

    for record in approved:
        h2_column = record[
            "h2_column"
        ]

        g2_column = record[
            "g2_column"
        ]

        policy = record.get(
            "comparison",
            {},
        )

        mode = policy.get("mode")

        exact_integer = (
            mode == "exact_integer"
            or (
                mode is None
                and pa.types.is_integer(
                    h2_fields[h2_column].type
                )
                and pa.types.is_integer(
                    g2_fields[g2_column].type
                )
            )
        )

        rtol = float(
            policy.get(
                "rtol",
                1e-10,
            )
        )

        atol = float(
            policy.get(
                "atol",
                1e-8,
            )
        )

        result = compare_metric(
            comparison[h2_column],
            comparison[g2_column],
            exact_integer=exact_integer,
            rtol=rtol,
            atol=atol,
        )

        metric_mismatch_count += int(
            result[
                "value_mismatch_count"
            ]
        )

        metric_null_mismatch_count += int(
            result[
                "null_mismatch_count"
            ]
        )

        passed = (
            metric_orphan_count == 0
            and result[
                "null_mismatch_count"
            ] == 0
            and result[
                "value_mismatch_count"
            ] == 0
        )

        metric_rows.append(
            {
                "partition": partition,
                "h2_column": h2_column,
                "g2_column": g2_column,
                "g2_rows": len(g2_metrics),
                "h2_rows": len(h2_metrics),
                "orphan_key_count": (
                    metric_orphan_count
                ),
                "null_mismatch_count": (
                    result[
                        "null_mismatch_count"
                    ]
                ),
                "value_mismatch_count": (
                    result[
                        "value_mismatch_count"
                    ]
                ),
                "maximum_absolute_difference": (
                    result[
                        "maximum_absolute_difference"
                    ]
                ),
                "comparison_mode": (
                    "EXACT_INTEGER"
                    if exact_integer
                    else (
                        f"FLOAT_RTOL_{rtol}_ATOL_{atol}"
                    )
                ),
                "result": (
                    "PASS"
                    if passed
                    else "FAIL"
                ),
            }
        )

    elapsed_seconds = (
        time.monotonic()
        - started
    )

    passed = (
        orphan_key_count == 0
        and context_missing_key_count == 0
        and context_mismatch_count == 0
        and metric_orphan_count == 0
        and metric_null_mismatch_count == 0
        and metric_mismatch_count == 0
    )

    return {
        "partition": partition,
        "g2_rows": len(g2_keys),
        "h2_rows": len(h2_keys),
        "g2_null_key_rows": (
            g2_null_key_rows
        ),
        "h2_null_key_rows": (
            h2_null_key_rows
        ),
        "g2_duplicate_key_rows": (
            g2_duplicate_key_rows
        ),
        "h2_duplicate_key_rows": (
            h2_duplicate_key_rows
        ),
        "h2_to_g2_orphan_key_count": (
            orphan_key_count
        ),
        "context_checked_column_count": (
            len(selected_context)
        ),
        "context_missing_key_count": (
            context_missing_key_count
        ),
        "context_value_mismatch_count": (
            context_mismatch_count
        ),
        "approved_metric_count": len(
            approved
        ),
        "metric_orphan_key_count": (
            metric_orphan_count
        ),
        "metric_null_mismatch_count": (
            metric_null_mismatch_count
        ),
        "metric_value_mismatch_count": (
            metric_mismatch_count
        ),
        "elapsed_seconds": (
            elapsed_seconds
        ),
        "result": (
            "PASS"
            if passed
            else "FAIL"
        ),
        "context_rows": context_rows,
        "metric_rows": metric_rows,
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate consistency between the "
            "G2 family-day feature lake and the "
            "H2 family-priceband-day feature lake."
        )
    )

    parser.add_argument(
        "--contract",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--g2-root",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--h2-root",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--partition",
        action="append",
        default=[],
        help=(
            "Partition in year=YYYY/month=MM form. "
            "Repeat for multiple partitions. "
            "When omitted, all partitions are validated."
        ),
    )

    parser.add_argument(
        "--context-sample-columns",
        type=int,
        default=0,
        help=(
            "Number of evenly distributed inherited "
            "context columns to check. Zero means all."
        ),
    )

    parser.add_argument(
        "--context-batch-columns",
        type=int,
        default=32,
    )

    return parser.parse_args()


def main() -> int:
    args = parse_arguments()

    if args.output_dir.exists():
        raise AssertionError(
            "OUTPUT_DIRECTORY_ALREADY_EXISTS:"
            f"{args.output_dir}"
        )

    args.output_dir.mkdir(
        parents=True,
        exist_ok=False,
    )

    started = time.monotonic()

    contract = verify_contract(
        args.contract
    )

    g2 = inventory_dataset(
        args.g2_root
    )

    h2 = inventory_dataset(
        args.h2_root
    )

    schema_result = (
        validate_schema_relationship(
            contract,
            g2,
            h2,
        )
    )

    partitions = (
        tuple(args.partition)
        if args.partition
        else g2.partitions
    )

    unknown_partitions = sorted(
        set(partitions)
        - set(g2.partitions)
    )

    if unknown_partitions:
        raise AssertionError(
            "UNKNOWN_PARTITIONS:"
            + ",".join(
                unknown_partitions
            )
        )

    partition_results: list[
        dict[str, Any]
    ] = []

    all_context_rows: list[
        dict[str, Any]
    ] = []

    all_metric_rows: list[
        dict[str, Any]
    ] = []

    for index, partition in enumerate(
        partitions,
        start=1,
    ):
        print(
            "I2_VALIDATION_PROGRESS="
            f"{index}/{len(partitions)};"
            f"{partition}",
            flush=True,
        )

        result = validate_partition(
            contract=contract,
            g2=g2,
            h2=h2,
            partition=partition,
            context_sample_columns=(
                args.context_sample_columns
            ),
            context_batch_columns=(
                args.context_batch_columns
            ),
        )

        all_context_rows.extend(
            result.pop("context_rows")
        )

        all_metric_rows.extend(
            result.pop("metric_rows")
        )

        partition_results.append(
            result
        )

    failed_partitions = [
        result
        for result in partition_results
        if result["result"] != "PASS"
    ]

    report = {
        "ok": not bool(
            failed_partitions
        ),
        "classification": (
            "PHASE2M_I2_CROSS_DATASET_"
            "VALIDATION_OK"
            if not failed_partitions
            else (
                "PHASE2M_I2_CROSS_DATASET_"
                "VALIDATION_FAILED"
            )
        ),
        "timestamp_utc": datetime.now(
            timezone.utc
        ).isoformat(),
        "contract": {
            "path": str(
                args.contract
            ),
            "version": contract[
                "version"
            ],
            "fingerprint": contract[
                "contract_fingerprint"
            ],
        },
        "datasets": {
            "g2_root": str(g2.root),
            "h2_root": str(h2.root),
            "g2_parquet_file_count": (
                g2.parquet_file_count
            ),
            "h2_parquet_file_count": (
                h2.parquet_file_count
            ),
            "g2_parquet_bytes": (
                g2.parquet_bytes
            ),
            "h2_parquet_bytes": (
                h2.parquet_bytes
            ),
        },
        "schema": schema_result,
        "execution": {
            "requested_partition_count": (
                len(partitions)
            ),
            "passed_partition_count": (
                len(partitions)
                - len(failed_partitions)
            ),
            "failed_partition_count": (
                len(failed_partitions)
            ),
            "context_sample_columns": (
                args.context_sample_columns
            ),
            "context_batch_columns": (
                args.context_batch_columns
            ),
            "elapsed_seconds": (
                time.monotonic()
                - started
            ),
            "peak_rss_bytes": (
                peak_rss_bytes()
            ),
        },
        "partition_results": (
            partition_results
        ),
        "parquet_write": False,
        "dataset_mutation": False,
    }

    write_json(
        args.output_dir
        / "i2_cross_dataset_validation_report.json",
        report,
    )

    write_tsv(
        args.output_dir
        / "partition_results.tsv",
        [
            "partition",
            "g2_rows",
            "h2_rows",
            "g2_null_key_rows",
            "h2_null_key_rows",
            "g2_duplicate_key_rows",
            "h2_duplicate_key_rows",
            "h2_to_g2_orphan_key_count",
            "context_checked_column_count",
            "context_missing_key_count",
            "context_value_mismatch_count",
            "approved_metric_count",
            "metric_orphan_key_count",
            "metric_null_mismatch_count",
            "metric_value_mismatch_count",
            "elapsed_seconds",
            "result",
        ],
        partition_results,
    )

    write_tsv(
        args.output_dir
        / "shared_context_results.tsv",
        [
            "partition",
            "column",
            "h2_rows",
            "missing_g2_key_matches",
            "value_mismatch_count",
            "result",
        ],
        all_context_rows,
    )

    write_tsv(
        args.output_dir
        / "metric_reconciliation_results.tsv",
        [
            "partition",
            "h2_column",
            "g2_column",
            "g2_rows",
            "h2_rows",
            "orphan_key_count",
            "null_mismatch_count",
            "value_mismatch_count",
            "maximum_absolute_difference",
            "comparison_mode",
            "result",
        ],
        all_metric_rows,
    )

    decision_lines = [
        report["classification"],
        (
            "READY_FOR_NEXT_VALIDATION_PHASE"
            if report["ok"]
            else "BLOCKED_VALIDATION_FAILURE"
        ),
        "",
        (
            "CONTRACT_VERSION="
            + contract["version"]
        ),
        (
            "CONTRACT_FINGERPRINT="
            + contract[
                "contract_fingerprint"
            ]
        ),
        (
            "REQUESTED_PARTITION_COUNT="
            + str(len(partitions))
        ),
        (
            "PASSED_PARTITION_COUNT="
            + str(
                len(partitions)
                - len(failed_partitions)
            )
        ),
        (
            "FAILED_PARTITION_COUNT="
            + str(len(failed_partitions))
        ),
        (
            "CONTEXT_SAMPLE_COLUMNS="
            + str(
                args.context_sample_columns
            )
        ),
        (
            "APPROVED_RECONCILIATION_COUNT="
            + str(
                len(
                    contract[
                        "commercial_reconciliations"
                    ][
                        "approved_exact_sum"
                    ]
                )
            )
        ),
        (
            "PEAK_RSS_MIB="
            + f"{peak_rss_bytes() / 1024**2:.2f}"
        ),
        "PARQUET_WRITE=NO",
        "DATASET_MUTATION=NO",
    ]

    (
        args.output_dir
        / "decision.txt"
    ).write_text(
        "\n".join(decision_lines)
        + "\n",
        encoding="utf-8",
    )

    print(report["classification"])
    print(
        "VALIDATION_REPORT="
        + str(
            args.output_dir
            / "i2_cross_dataset_validation_report.json"
        )
    )

    return (
        0
        if report["ok"]
        else 1
    )

# =============================================================================
# Phase 2M-I2 contract-compliance amendment.
# Implements I2V001-I2V010 and closes audit blockers I2A006-I2A014.
# =============================================================================

import traceback


TARGET_PEAK_RSS_MIB = 2048.0
TARGET_PEAK_RSS_BYTES = int(
    TARGET_PEAK_RSS_MIB
    * 1024
    * 1024
)

I2_CHECK_IDS = [
    "I2V001",
    "I2V002",
    "I2V003",
    "I2V004",
    "I2V005",
    "I2V006",
    "I2V007",
    "I2V008",
    "I2V009",
    "I2V010",
]


@dataclass(frozen=True)
class ExtendedDatasetInventory:
    root: Path
    partitions: tuple[str, ...]
    parquet_file_count: int
    parquet_bytes: int
    row_count: int
    schema: pa.Schema
    arrow_schema_sha256: str


def _expected_integer(
    record: dict[str, Any],
    *candidate_keys: str,
) -> int:
    for key in candidate_keys:
        if key in record:
            return int(record[key])

    raise AssertionError(
        "EXPECTED_INTEGER_FIELD_MISSING:"
        + ",".join(candidate_keys)
    )


def _expected_string(
    record: dict[str, Any],
    *candidate_keys: str,
) -> str:
    for key in candidate_keys:
        value = record.get(key)

        if value is not None:
            return str(value)

    raise AssertionError(
        "EXPECTED_STRING_FIELD_MISSING:"
        + ",".join(candidate_keys)
    )


def _new_receipts() -> dict[str, dict[str, Any]]:
    return {
        check_id: {
            "check_id": check_id,
            "status": "PENDING",
            "evidence": "",
        }
        for check_id in I2_CHECK_IDS
    }


def _set_receipt(
    receipts: dict[str, dict[str, Any]],
    check_id: str,
    *,
    status: str,
    evidence: str,
) -> None:
    if check_id not in receipts:
        raise AssertionError(
            f"UNKNOWN_CHECK_RECEIPT:{check_id}"
        )

    receipts[check_id] = {
        "check_id": check_id,
        "status": status,
        "evidence": evidence,
    }


def _schema_fingerprint(
    schema: pa.Schema,
) -> str:
    return sha256_bytes(
        schema.serialize().to_pybytes()
    )


def inventory_dataset(
    root: Path,
) -> ExtendedDatasetInventory:
    if not root.is_dir():
        raise AssertionError(
            f"DATASET_ROOT_NOT_FOUND:{root}"
        )

    files = sorted(
        root.rglob("*.parquet"),
        key=lambda path: str(
            path.relative_to(root)
        ),
    )

    if not files:
        raise AssertionError(
            f"NO_PARQUET_FILES:{root}"
        )

    partitions: set[str] = set()
    parquet_bytes = 0
    row_count = 0
    reference_schema: pa.Schema | None = None

    for file_path in files:
        if file_path.is_symlink():
            raise AssertionError(
                "PARQUET_SYMLINK_NOT_ALLOWED:"
                f"{file_path}"
            )

        partitions.add(
            partition_name(
                file_path,
                root,
            )
        )

        parquet_bytes += (
            file_path.stat().st_size
        )

        parquet_file = pq.ParquetFile(
            file_path
        )

        row_count += int(
            parquet_file.metadata.num_rows
        )

        schema = (
            parquet_file.schema_arrow
        )

        if reference_schema is None:
            reference_schema = schema

        elif not schema.equals(
            reference_schema,
            check_metadata=False,
        ):
            raise AssertionError(
                "INTERNAL_SCHEMA_MISMATCH:"
                f"{file_path}"
            )

    assert reference_schema is not None

    return ExtendedDatasetInventory(
        root=root,
        partitions=tuple(
            sorted(partitions)
        ),
        parquet_file_count=len(files),
        parquet_bytes=parquet_bytes,
        row_count=row_count,
        schema=reference_schema,
        arrow_schema_sha256=(
            _schema_fingerprint(
                reference_schema
            )
        ),
    )


def _validate_dataset_identity(
    *,
    label: str,
    inventory: ExtendedDatasetInventory,
    specification: dict[str, Any],
) -> dict[str, Any]:
    expected_rows = _expected_integer(
        specification,
        "expected_rows",
        "expected_row_count",
        "row_count",
    )

    expected_columns = _expected_integer(
        specification,
        "expected_columns",
        "expected_column_count",
        "column_count",
    )

    expected_partitions = _expected_integer(
        specification,
        "expected_partitions",
        "expected_partition_count",
        "partition_count",
    )

    expected_schema_sha256 = _expected_string(
        specification,
        "arrow_schema_sha256",
        "schema_sha256",
    )

    if inventory.row_count != expected_rows:
        raise AssertionError(
            f"{label}_ROW_COUNT_MISMATCH:"
            f"expected={expected_rows}:"
            f"actual={inventory.row_count}"
        )

    if len(inventory.schema) != expected_columns:
        raise AssertionError(
            f"{label}_COLUMN_COUNT_MISMATCH:"
            f"expected={expected_columns}:"
            f"actual={len(inventory.schema)}"
        )

    if len(
        inventory.partitions
    ) != expected_partitions:
        raise AssertionError(
            f"{label}_PARTITION_COUNT_MISMATCH:"
            f"expected={expected_partitions}:"
            f"actual={len(inventory.partitions)}"
        )

    if (
        inventory.arrow_schema_sha256
        != expected_schema_sha256
    ):
        raise AssertionError(
            f"{label}_ARROW_SCHEMA_SHA256_MISMATCH:"
            f"expected={expected_schema_sha256}:"
            f"actual={inventory.arrow_schema_sha256}"
        )

    expected_run_id = (
        specification.get("run_id")
        or specification.get(
            "dataset_run_id"
        )
    )

    if (
        expected_run_id is not None
        and str(expected_run_id)
        not in str(inventory.root)
    ):
        raise AssertionError(
            f"{label}_RUN_ID_ROOT_MISMATCH:"
            f"run_id={expected_run_id}:"
            f"root={inventory.root}"
        )

    return {
        "label": label,
        "root": str(inventory.root),
        "row_count": inventory.row_count,
        "column_count": len(
            inventory.schema
        ),
        "partition_count": len(
            inventory.partitions
        ),
        "parquet_file_count": (
            inventory.parquet_file_count
        ),
        "parquet_bytes": (
            inventory.parquet_bytes
        ),
        "arrow_schema_sha256": (
            inventory.arrow_schema_sha256
        ),
        "result": "PASS",
    }


def validate_schema_relationship(
    contract: dict[str, Any],
    g2: ExtendedDatasetInventory,
    h2: ExtendedDatasetInventory,
) -> dict[str, Any]:
    expected_g2 = contract[
        "datasets"
    ][
        "g2_family_day"
    ]

    expected_h2 = contract[
        "datasets"
    ][
        "h2_family_priceband_day"
    ]

    g2_identity = (
        _validate_dataset_identity(
            label="G2",
            inventory=g2,
            specification=expected_g2,
        )
    )

    h2_identity = (
        _validate_dataset_identity(
            label="H2",
            inventory=h2,
            specification=expected_h2,
        )
    )

    if g2.partitions != h2.partitions:
        raise AssertionError(
            "PARTITION_DOMAIN_MISMATCH"
        )

    g2_fields = {
        field.name: field
        for field in g2.schema
    }

    h2_fields = {
        field.name: field
        for field in h2.schema
    }

    g2_only_columns = sorted(
        set(g2_fields)
        - set(h2_fields)
    )

    if g2_only_columns:
        raise AssertionError(
            "G2_COLUMNS_MISSING_FROM_H2:"
            + ",".join(
                g2_only_columns[:20]
            )
        )

    actual_h2_only_columns = sorted(
        set(h2_fields)
        - set(g2_fields)
    )

    expected_h2_only_columns = contract[
        "schema_relationship"
    ][
        "h2_only_columns"
    ]

    if (
        actual_h2_only_columns
        != expected_h2_only_columns
    ):
        raise AssertionError(
            "H2_ONLY_COLUMN_DOMAIN_MISMATCH"
        )

    expected_h2_only_count = int(
        contract[
            "schema_relationship"
        ][
            "h2_only_column_count"
        ]
    )

    if (
        len(actual_h2_only_columns)
        != expected_h2_only_count
    ):
        raise AssertionError(
            "H2_ONLY_COLUMN_COUNT_MISMATCH"
        )

    shared_context_columns = contract[
        "schema_relationship"
    ][
        "shared_context_columns"
    ]

    for column in shared_context_columns:
        if column not in g2_fields:
            raise AssertionError(
                "SHARED_COLUMN_MISSING_G2:"
                f"{column}"
            )

        if column not in h2_fields:
            raise AssertionError(
                "SHARED_COLUMN_MISSING_H2:"
                f"{column}"
            )

        if not g2_fields[
            column
        ].type.equals(
            h2_fields[column].type
        ):
            raise AssertionError(
                "SHARED_COLUMN_TYPE_MISMATCH:"
                f"{column}"
            )

    approved_records = contract[
        "commercial_reconciliations"
    ][
        "approved_exact_sum"
    ]

    excluded_records = contract[
        "commercial_reconciliations"
    ][
        "excluded_or_review"
    ]

    approved_h2_columns = {
        record["h2_column"]
        for record in approved_records
    }

    excluded_h2_columns = {
        record["h2_column"]
        for record in excluded_records
    }

    if (
        approved_h2_columns
        & excluded_h2_columns
    ):
        raise AssertionError(
            "APPROVED_EXCLUDED_COLUMN_OVERLAP"
        )

    numeric_pair_columns = {
        column
        for column in actual_h2_only_columns
        if (
            column.startswith(
                "family_priceband_grid__"
            )
            or column.startswith(
                "family_priceband_sales__"
            )
        )
        and (
            pa.types.is_integer(
                h2_fields[column].type
            )
            or pa.types.is_floating(
                h2_fields[column].type
            )
            or pa.types.is_decimal(
                h2_fields[column].type
            )
        )
    }

    if (
        approved_h2_columns
        | excluded_h2_columns
    ) != numeric_pair_columns:
        raise AssertionError(
            "NUMERIC_PAIR_COVERAGE_MISMATCH"
        )

    approved_expected_count = int(
        contract[
            "commercial_reconciliations"
        ][
            "approved_exact_sum_count"
        ]
    )

    excluded_expected_count = int(
        contract[
            "commercial_reconciliations"
        ][
            "excluded_or_review_count"
        ]
    )

    if (
        len(approved_records)
        != approved_expected_count
    ):
        raise AssertionError(
            "APPROVED_RECONCILIATION_COUNT_MISMATCH"
        )

    if (
        len(excluded_records)
        != excluded_expected_count
    ):
        raise AssertionError(
            "EXCLUDED_RECONCILIATION_COUNT_MISMATCH"
        )

    contract_check_ids = [
        record["check_id"]
        for record in contract[
            "checks"
        ]
    ]

    if contract_check_ids != I2_CHECK_IDS:
        raise AssertionError(
            "CONTRACT_CHECK_ID_DOMAIN_MISMATCH"
        )

    return {
        "g2": g2_identity,
        "h2": h2_identity,
        "g2_column_count": len(
            g2.schema
        ),
        "h2_column_count": len(
            h2.schema
        ),
        "partition_count": len(
            g2.partitions
        ),
        "shared_context_column_count": (
            len(shared_context_columns)
        ),
        "h2_only_column_count": (
            len(actual_h2_only_columns)
        ),
        "numeric_pair_column_count": (
            len(numeric_pair_columns)
        ),
        "approved_reconciliation_count": (
            len(approved_records)
        ),
        "excluded_or_review_count": (
            len(excluded_records)
        ),
        "result": "PASS",
    }


def _dense_semantic_pairs(
    *,
    dataset_label: str,
) -> list[tuple[str, str]]:
    if dataset_label == "G2":
        return [
            (
                "qty_venduta",
                "qty_venduta_dense",
            ),
            (
                "imponibile_netto_tot",
                "imponibile_dense",
            ),
            (
                "num_articoli",
                "num_articoli_dense",
            ),
        ]

    if dataset_label == "H2":
        prefix = (
            "family_priceband_grid__"
        )

        return [
            (
                prefix + "qty_venduta",
                prefix + "qty_venduta_dense",
            ),
            (
                prefix
                + "imponibile_netto_tot",
                prefix + "imponibile_dense",
            ),
            (
                prefix + "num_articoli",
                prefix + "num_articoli_dense",
            ),
        ]

    raise AssertionError(
        "UNKNOWN_DENSE_SEMANTIC_DATASET:"
        f"{dataset_label}"
    )


def _validate_dense_zero_observed_semantics(
    *,
    dataset_label: str,
    inventory: ExtendedDatasetInventory,
    partition: str,
    keys: Sequence[str],
) -> tuple[
    list[dict[str, Any]],
    dict[str, Any],
]:
    fields = {
        field.name: field
        for field in inventory.schema
    }

    pairs = _dense_semantic_pairs(
        dataset_label=dataset_label
    )

    for source_column, dense_column in pairs:
        if source_column not in fields:
            raise AssertionError(
                "DENSE_SOURCE_COLUMN_MISSING:"
                f"{dataset_label}:"
                f"{source_column}"
            )

        if dense_column not in fields:
            raise AssertionError(
                "DENSE_COLUMN_MISSING:"
                f"{dataset_label}:"
                f"{dense_column}"
            )

    columns = list(
        dict.fromkeys(
            list(keys)
            + [
                column
                for pair in pairs
                for column in pair
            ]
        )
    )

    frame = read_partition(
        inventory.root,
        partition,
        columns,
    )

    results: list[
        dict[str, Any]
    ] = []

    total_mismatches = 0
    total_dense_nulls = 0

    for source_column, dense_column in pairs:
        source_series = frame[
            source_column
        ]

        dense_series = frame[
            dense_column
        ]

        expected_dense = (
            source_series.fillna(0)
        )

        exact_integer = (
            pa.types.is_integer(
                fields[source_column].type
            )
            and pa.types.is_integer(
                fields[dense_column].type
            )
        )

        comparison = compare_metric(
            dense_series,
            expected_dense,
            exact_integer=exact_integer,
            rtol=1e-10,
            atol=1e-8,
        )

        dense_null_count = int(
            dense_series.isna().sum()
        )

        source_null_count = int(
            source_series.isna().sum()
        )

        mismatch_count = int(
            comparison[
                "value_mismatch_count"
            ]
        )

        total_mismatches += (
            mismatch_count
        )

        total_dense_nulls += (
            dense_null_count
        )

        passed = (
            dense_null_count == 0
            and mismatch_count == 0
        )

        results.append(
            {
                "partition": partition,
                "dataset": dataset_label,
                "source_column": (
                    source_column
                ),
                "dense_column": (
                    dense_column
                ),
                "row_count": len(frame),
                "source_null_count": (
                    source_null_count
                ),
                "dense_null_count": (
                    dense_null_count
                ),
                "value_mismatch_count": (
                    mismatch_count
                ),
                "maximum_absolute_difference": (
                    comparison[
                        "maximum_absolute_difference"
                    ]
                ),
                "result": (
                    "PASS"
                    if passed
                    else "FAIL"
                ),
            }
        )

    summary = {
        "dataset": dataset_label,
        "pair_count": len(pairs),
        "row_count": len(frame),
        "dense_null_count": (
            total_dense_nulls
        ),
        "value_mismatch_count": (
            total_mismatches
        ),
        "result": (
            "PASS"
            if (
                total_dense_nulls == 0
                and total_mismatches == 0
            )
            else "FAIL"
        ),
    }

    return results, summary


def _validate_priceband_key_domain(
    frame: pd.DataFrame,
) -> dict[str, Any]:
    key = "fascia_prezzo_iva_inc"

    series = frame[key]

    null_count = int(
        series.isna().sum()
    )

    blank_count = 0
    nonfinite_count = 0

    if pd.api.types.is_numeric_dtype(
        series.dtype
    ):
        numeric = pd.to_numeric(
            series,
            errors="coerce",
        ).to_numpy(
            dtype=float,
            na_value=np.nan,
        )

        nonfinite_count = int(
            (
                ~np.isfinite(numeric)
                & ~np.isnan(numeric)
            ).sum()
        )

        domain_values = sorted(
            {
                repr(float(value))
                for value in numeric
                if np.isfinite(value)
            }
        )

    else:
        strings = series.astype(
            "string"
        )

        blank_count = int(
            strings.str.strip()
            .eq("")
            .fillna(False)
            .sum()
        )

        domain_values = sorted(
            {
                str(value)
                for value in strings.dropna()
                if str(value).strip()
            }
        )

    unique_count = len(
        domain_values
    )

    if (
        null_count
        or blank_count
        or nonfinite_count
        or unique_count == 0
    ):
        raise AssertionError(
            "PRICEBAND_KEY_DOMAIN_FAILURE:"
            f"null={null_count}:"
            f"blank={blank_count}:"
            f"nonfinite={nonfinite_count}:"
            f"unique={unique_count}"
        )

    return {
        "null_count": null_count,
        "blank_count": blank_count,
        "nonfinite_count": (
            nonfinite_count
        ),
        "unique_count": unique_count,
        "domain_fingerprint": (
            sha256_bytes(
                canonical_json_bytes(
                    domain_values
                )
            )
        ),
        "result": "PASS",
    }


_legacy_validate_partition = (
    validate_partition
)


def validate_partition(
    *,
    contract: dict[str, Any],
    g2: ExtendedDatasetInventory,
    h2: ExtendedDatasetInventory,
    partition: str,
    context_sample_columns: int,
    context_batch_columns: int,
) -> dict[str, Any]:
    result = _legacy_validate_partition(
        contract=contract,
        g2=g2,
        h2=h2,
        partition=partition,
        context_sample_columns=(
            context_sample_columns
        ),
        context_batch_columns=(
            context_batch_columns
        ),
    )

    h2_keys = read_partition(
        h2.root,
        partition,
        H2_KEYS,
    )

    priceband_domain = (
        _validate_priceband_key_domain(
            h2_keys
        )
    )

    g2_dense_rows, g2_dense_summary = (
        _validate_dense_zero_observed_semantics(
            dataset_label="G2",
            inventory=g2,
            partition=partition,
            keys=G2_KEYS,
        )
    )

    h2_dense_rows, h2_dense_summary = (
        _validate_dense_zero_observed_semantics(
            dataset_label="H2",
            inventory=h2,
            partition=partition,
            keys=H2_KEYS,
        )
    )

    dense_rows = (
        g2_dense_rows
        + h2_dense_rows
    )

    dense_mismatch_count = sum(
        int(
            row[
                "value_mismatch_count"
            ]
        )
        for row in dense_rows
    )

    dense_null_count = sum(
        int(
            row[
                "dense_null_count"
            ]
        )
        for row in dense_rows
    )

    result[
        "priceband_unique_count"
    ] = priceband_domain[
        "unique_count"
    ]

    result[
        "priceband_domain_fingerprint"
    ] = priceband_domain[
        "domain_fingerprint"
    ]

    result[
        "priceband_null_count"
    ] = priceband_domain[
        "null_count"
    ]

    result[
        "priceband_blank_count"
    ] = priceband_domain[
        "blank_count"
    ]

    result[
        "priceband_nonfinite_count"
    ] = priceband_domain[
        "nonfinite_count"
    ]

    result[
        "dense_semantic_pair_count"
    ] = len(dense_rows)

    result[
        "dense_semantic_null_count"
    ] = dense_null_count

    result[
        "dense_semantic_mismatch_count"
    ] = dense_mismatch_count

    result[
        "g2_dense_semantic_result"
    ] = g2_dense_summary[
        "result"
    ]

    result[
        "h2_dense_semantic_result"
    ] = h2_dense_summary[
        "result"
    ]

    result[
        "dense_semantic_rows"
    ] = dense_rows

    if (
        result["result"] != "PASS"
        or priceband_domain[
            "result"
        ] != "PASS"
        or g2_dense_summary[
            "result"
        ] != "PASS"
        or h2_dense_summary[
            "result"
        ] != "PASS"
    ):
        result["result"] = "FAIL"

    return result


def _build_cross_dataset_coverage(
    partition_results: Sequence[
        dict[str, Any]
    ],
) -> list[dict[str, Any]]:
    coverage_rows: list[
        dict[str, Any]
    ] = []

    for record in partition_results:
        g2_rows = int(
            record["g2_rows"]
        )

        h2_rows = int(
            record["h2_rows"]
        )

        coverage_rows.append(
            {
                "partition": record[
                    "partition"
                ],
                "g2_rows": g2_rows,
                "h2_rows": h2_rows,
                "h2_to_g2_row_ratio": (
                    float(h2_rows / g2_rows)
                    if g2_rows
                    else None
                ),
                "priceband_unique_count": (
                    record[
                        "priceband_unique_count"
                    ]
                ),
                "h2_to_g2_orphan_key_count": (
                    record[
                        "h2_to_g2_orphan_key_count"
                    ]
                ),
                "context_missing_key_count": (
                    record[
                        "context_missing_key_count"
                    ]
                ),
                "context_value_mismatch_count": (
                    record[
                        "context_value_mismatch_count"
                    ]
                ),
                "metric_value_mismatch_count": (
                    record[
                        "metric_value_mismatch_count"
                    ]
                ),
                "dense_semantic_mismatch_count": (
                    record[
                        "dense_semantic_mismatch_count"
                    ]
                ),
                "result": record[
                    "result"
                ],
            }
        )

    return coverage_rows


def _write_unified_feature_lake_manifest(
    *,
    path: Path,
    contract: dict[str, Any],
    g2: ExtendedDatasetInventory,
    h2: ExtendedDatasetInventory,
    schema_result: dict[str, Any],
    partition_results: Sequence[
        dict[str, Any]
    ],
    check_receipts: Sequence[
        dict[str, Any]
    ],
    elapsed_seconds: float,
    peak_rss: int,
) -> None:
    manifest = {
        "ok": all(
            record["result"] == "PASS"
            for record in partition_results
        ),
        "classification": (
            "PHASE2M_I2_UNIFIED_FEATURE_LAKE_"
            "MANIFEST"
        ),
        "timestamp_utc": datetime.now(
            timezone.utc
        ).isoformat(),
        "contract": {
            "version": contract[
                "version"
            ],
            "fingerprint": contract[
                "contract_fingerprint"
            ],
        },
        "g2_family_day": {
            "root": str(g2.root),
            "row_count": g2.row_count,
            "column_count": len(
                g2.schema
            ),
            "partition_count": len(
                g2.partitions
            ),
            "parquet_file_count": (
                g2.parquet_file_count
            ),
            "parquet_bytes": (
                g2.parquet_bytes
            ),
            "arrow_schema_sha256": (
                g2.arrow_schema_sha256
            ),
        },
        "h2_family_priceband_day": {
            "root": str(h2.root),
            "row_count": h2.row_count,
            "column_count": len(
                h2.schema
            ),
            "partition_count": len(
                h2.partitions
            ),
            "parquet_file_count": (
                h2.parquet_file_count
            ),
            "parquet_bytes": (
                h2.parquet_bytes
            ),
            "arrow_schema_sha256": (
                h2.arrow_schema_sha256
            ),
        },
        "schema_relationship": (
            schema_result
        ),
        "validation": {
            "requested_partition_count": (
                len(partition_results)
            ),
            "passed_partition_count": sum(
                record["result"] == "PASS"
                for record
                in partition_results
            ),
            "failed_partition_count": sum(
                record["result"] != "PASS"
                for record
                in partition_results
            ),
            "elapsed_seconds": (
                elapsed_seconds
            ),
            "peak_rss_bytes": peak_rss,
            "target_peak_rss_bytes": (
                TARGET_PEAK_RSS_BYTES
            ),
        },
        "check_receipts": list(
            check_receipts
        ),
        "parquet_write": False,
        "dataset_mutation": False,
    }

    write_json(
        path,
        manifest,
    )


def _write_partial_report(
    *,
    output_dir: Path,
    contract_path: Path,
    g2_root: Path,
    h2_root: Path,
    receipts: dict[
        str,
        dict[str, Any]
    ],
    failed_check: str,
    error: BaseException,
    started: float,
) -> None:
    partial_report = {
        "ok": False,
        "classification": (
            "PHASE2M_I2_CROSS_DATASET_"
            "VALIDATION_PARTIAL_FAILURE"
        ),
        "timestamp_utc": datetime.now(
            timezone.utc
        ).isoformat(),
        "failed_check": failed_check,
        "error_type": type(
            error
        ).__name__,
        "error": str(error),
        "traceback": traceback.format_exc(),
        "contract_path": str(
            contract_path
        ),
        "g2_root": str(g2_root),
        "h2_root": str(h2_root),
        "elapsed_seconds": (
            time.monotonic()
            - started
        ),
        "peak_rss_bytes": (
            peak_rss_bytes()
        ),
        "target_peak_rss_bytes": (
            TARGET_PEAK_RSS_BYTES
        ),
        "check_receipts": [
            receipts[
                check_id
            ]
            for check_id in I2_CHECK_IDS
        ],
        "partial_report": True,
        "parquet_write": False,
        "dataset_mutation": False,
    }

    write_json(
        output_dir
        / "partial_report.json",
        partial_report,
    )

    (
        output_dir
        / "decision.txt"
    ).write_text(
        "\n".join(
            [
                (
                    "PHASE2M_I2_CROSS_DATASET_"
                    "VALIDATION_PARTIAL_FAILURE"
                ),
                "BLOCKED_VALIDATION_FAILURE",
                "",
                (
                    "FAILED_CHECK="
                    + failed_check
                ),
                (
                    "ERROR_TYPE="
                    + type(error).__name__
                ),
                (
                    "ERROR="
                    + str(error)
                ),
                (
                    "PEAK_RSS_MIB="
                    + f"{peak_rss_bytes() / 1024**2:.2f}"
                ),
                (
                    "TARGET_PEAK_RSS_MIB="
                    + f"{TARGET_PEAK_RSS_MIB:.2f}"
                ),
                "PARTIAL_REPORT_WRITTEN=YES",
                "PARQUET_WRITE=NO",
                "DATASET_MUTATION=NO",
            ]
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_arguments()

    if args.output_dir.exists():
        raise AssertionError(
            "OUTPUT_DIRECTORY_ALREADY_EXISTS:"
            f"{args.output_dir}"
        )

    args.output_dir.mkdir(
        parents=True,
        exist_ok=False,
    )

    started = time.monotonic()
    receipts = _new_receipts()
    current_check = "I2V001"

    try:
        contract = verify_contract(
            args.contract
        )

        contract_check_ids = [
            record["check_id"]
            for record in contract[
                "checks"
            ]
        ]

        if contract_check_ids != I2_CHECK_IDS:
            raise AssertionError(
                "CONTRACT_CHECK_ID_DOMAIN_MISMATCH"
            )

        g2 = inventory_dataset(
            args.g2_root
        )

        h2 = inventory_dataset(
            args.h2_root
        )

        schema_result = (
            validate_schema_relationship(
                contract,
                g2,
                h2,
            )
        )

        _set_receipt(
            receipts,
            "I2V001",
            status="PASS",
            evidence=(
                "Frozen contract fingerprint, "
                "dataset identities, global rows, "
                "columns and Arrow schema hashes pass."
            ),
        )

        current_check = "I2V002"

        if g2.partitions != h2.partitions:
            raise AssertionError(
                "PARTITION_DOMAIN_MISMATCH"
            )

        _set_receipt(
            receipts,
            "I2V002",
            status="PASS",
            evidence=(
                f"Shared partition domain contains "
                f"{len(g2.partitions)} partitions."
            ),
        )

        partitions = (
            tuple(args.partition)
            if args.partition
            else g2.partitions
        )

        unknown_partitions = sorted(
            set(partitions)
            - set(g2.partitions)
        )

        if unknown_partitions:
            raise AssertionError(
                "UNKNOWN_PARTITIONS:"
                + ",".join(
                    unknown_partitions
                )
            )

        partition_results: list[
            dict[str, Any]
        ] = []

        all_context_rows: list[
            dict[str, Any]
        ] = []

        all_metric_rows: list[
            dict[str, Any]
        ] = []

        all_dense_rows: list[
            dict[str, Any]
        ] = []

        for index, partition in enumerate(
            partitions,
            start=1,
        ):
            print(
                "I2_VALIDATION_PROGRESS="
                f"{index}/{len(partitions)};"
                f"{partition}",
                flush=True,
            )

            result = validate_partition(
                contract=contract,
                g2=g2,
                h2=h2,
                partition=partition,
                context_sample_columns=(
                    args.context_sample_columns
                ),
                context_batch_columns=(
                    args.context_batch_columns
                ),
            )

            all_context_rows.extend(
                result.pop(
                    "context_rows"
                )
            )

            all_metric_rows.extend(
                result.pop(
                    "metric_rows"
                )
            )

            all_dense_rows.extend(
                result.pop(
                    "dense_semantic_rows"
                )
            )

            partition_results.append(
                result
            )

        current_check = "I2V003"

        foreign_key_failures = sum(
            int(
                result[
                    "h2_to_g2_orphan_key_count"
                ]
            )
            for result
            in partition_results
        )

        if foreign_key_failures:
            raise AssertionError(
                "H2_TO_G2_FOREIGN_KEY_FAILURES:"
                f"{foreign_key_failures}"
            )

        _set_receipt(
            receipts,
            "I2V003",
            status="PASS",
            evidence=(
                "H2-to-G2 orphan key count is zero "
                "for every validated partition."
            ),
        )

        current_check = "I2V004"

        context_missing = sum(
            int(
                result[
                    "context_missing_key_count"
                ]
            )
            for result
            in partition_results
        )

        context_mismatches = sum(
            int(
                result[
                    "context_value_mismatch_count"
                ]
            )
            for result
            in partition_results
        )

        if (
            context_missing
            or context_mismatches
        ):
            raise AssertionError(
                "SHARED_CONTEXT_REPLICATION_FAILURE:"
                f"missing={context_missing}:"
                f"mismatches={context_mismatches}"
            )

        _set_receipt(
            receipts,
            "I2V004",
            status="PASS",
            evidence=(
                "Shared-context missing keys and "
                "value mismatches are zero."
            ),
        )

        current_check = "I2V005"

        priceband_failures = sum(
            int(
                result[
                    "priceband_null_count"
                ]
            )
            + int(
                result[
                    "priceband_blank_count"
                ]
            )
            + int(
                result[
                    "priceband_nonfinite_count"
                ]
            )
            for result
            in partition_results
        )

        if priceband_failures:
            raise AssertionError(
                "PRICEBAND_KEY_DOMAIN_FAILURES:"
                f"{priceband_failures}"
            )

        _set_receipt(
            receipts,
            "I2V005",
            status="PASS",
            evidence=(
                "Priceband keys contain no null, "
                "blank or non-finite values."
            ),
        )

        current_check = "I2V006"

        metric_failures = sum(
            int(
                result[
                    "metric_orphan_key_count"
                ]
            )
            + int(
                result[
                    "metric_null_mismatch_count"
                ]
            )
            + int(
                result[
                    "metric_value_mismatch_count"
                ]
            )
            for result
            in partition_results
        )

        if metric_failures:
            raise AssertionError(
                "COMMERCIAL_RECONCILIATION_FAILURES:"
                f"{metric_failures}"
            )

        _set_receipt(
            receipts,
            "I2V006",
            status="PASS",
            evidence=(
                f"All "
                f"{schema_result['approved_reconciliation_count']} "
                "approved commercial reconciliations pass."
            ),
        )

        current_check = "I2V007"

        dense_failures = sum(
            int(
                result[
                    "dense_semantic_null_count"
                ]
            )
            + int(
                result[
                    "dense_semantic_mismatch_count"
                ]
            )
            for result
            in partition_results
        )

        if dense_failures:
            raise AssertionError(
                "DENSE_ZERO_OBSERVED_SEMANTIC_FAILURES:"
                f"{dense_failures}"
            )

        _set_receipt(
            receipts,
            "I2V007",
            status="PASS",
            evidence=(
                "Dense values equal observed values "
                "when present and zero-fill missing "
                "observations."
            ),
        )

        current_check = "I2V008"

        coverage_rows = (
            _build_cross_dataset_coverage(
                partition_results
            )
        )

        if any(
            row["result"] != "PASS"
            for row in coverage_rows
        ):
            raise AssertionError(
                "CROSS_DATASET_COVERAGE_FAILURE"
            )

        write_tsv(
            args.output_dir
            / "coverage_report.tsv",
            [
                "partition",
                "g2_rows",
                "h2_rows",
                "h2_to_g2_row_ratio",
                "priceband_unique_count",
                "h2_to_g2_orphan_key_count",
                "context_missing_key_count",
                "context_value_mismatch_count",
                "metric_value_mismatch_count",
                "dense_semantic_mismatch_count",
                "result",
            ],
            coverage_rows,
        )

        _set_receipt(
            receipts,
            "I2V008",
            status="PASS",
            evidence=(
                "Dedicated coverage_report.tsv "
                "created with no failed partitions."
            ),
        )

        current_check = "I2V010"

        current_peak_rss = (
            peak_rss_bytes()
        )

        if (
            current_peak_rss
            > TARGET_PEAK_RSS_BYTES
        ):
            raise AssertionError(
                "RESOURCE_ENVELOPE_EXCEEDED:"
                f"peak={current_peak_rss}:"
                f"limit={TARGET_PEAK_RSS_BYTES}"
            )

        _set_receipt(
            receipts,
            "I2V010",
            status="PASS",
            evidence=(
                f"Peak RSS "
                f"{current_peak_rss / 1024**2:.2f} MiB "
                f"is within "
                f"{TARGET_PEAK_RSS_MIB:.2f} MiB; "
                "partial-report failure path is active."
            ),
        )

        current_check = "I2V009"

        _set_receipt(
            receipts,
            "I2V009",
            status="PASS",
            evidence=(
                "Unified feature-lake manifest "
                "prepared and persisted."
            ),
        )

        check_receipts = [
            receipts[check_id]
            for check_id in I2_CHECK_IDS
        ]

        _write_unified_feature_lake_manifest(
            path=(
                args.output_dir
                / "unified_feature_lake_manifest.json"
            ),
            contract=contract,
            g2=g2,
            h2=h2,
            schema_result=schema_result,
            partition_results=(
                partition_results
            ),
            check_receipts=(
                check_receipts
            ),
            elapsed_seconds=(
                time.monotonic()
                - started
            ),
            peak_rss=peak_rss_bytes(),
        )

        write_tsv(
            args.output_dir
            / "check_receipts.tsv",
            [
                "check_id",
                "status",
                "evidence",
            ],
            check_receipts,
        )

        write_tsv(
            args.output_dir
            / "partition_results.tsv",
            [
                "partition",
                "g2_rows",
                "h2_rows",
                "g2_null_key_rows",
                "h2_null_key_rows",
                "g2_duplicate_key_rows",
                "h2_duplicate_key_rows",
                "h2_to_g2_orphan_key_count",
                "context_checked_column_count",
                "context_missing_key_count",
                "context_value_mismatch_count",
                "approved_metric_count",
                "metric_orphan_key_count",
                "metric_null_mismatch_count",
                "metric_value_mismatch_count",
                "priceband_unique_count",
                "priceband_null_count",
                "priceband_blank_count",
                "priceband_nonfinite_count",
                "dense_semantic_pair_count",
                "dense_semantic_null_count",
                "dense_semantic_mismatch_count",
                "elapsed_seconds",
                "result",
            ],
            partition_results,
        )

        write_tsv(
            args.output_dir
            / "shared_context_results.tsv",
            [
                "partition",
                "column",
                "h2_rows",
                "missing_g2_key_matches",
                "value_mismatch_count",
                "result",
            ],
            all_context_rows,
        )

        write_tsv(
            args.output_dir
            / "metric_reconciliation_results.tsv",
            [
                "partition",
                "h2_column",
                "g2_column",
                "g2_rows",
                "h2_rows",
                "orphan_key_count",
                "null_mismatch_count",
                "value_mismatch_count",
                "maximum_absolute_difference",
                "comparison_mode",
                "result",
            ],
            all_metric_rows,
        )

        write_tsv(
            args.output_dir
            / "dense_zero_observed_semantics.tsv",
            [
                "partition",
                "dataset",
                "source_column",
                "dense_column",
                "row_count",
                "source_null_count",
                "dense_null_count",
                "value_mismatch_count",
                "maximum_absolute_difference",
                "result",
            ],
            all_dense_rows,
        )

        failed_partitions = [
            result
            for result
            in partition_results
            if result["result"] != "PASS"
        ]

        report = {
            "ok": not bool(
                failed_partitions
            ),
            "classification": (
                "PHASE2M_I2_CROSS_DATASET_"
                "VALIDATION_OK"
                if not failed_partitions
                else (
                    "PHASE2M_I2_CROSS_DATASET_"
                    "VALIDATION_FAILED"
                )
            ),
            "timestamp_utc": datetime.now(
                timezone.utc
            ).isoformat(),
            "contract": {
                "path": str(
                    args.contract
                ),
                "version": contract[
                    "version"
                ],
                "fingerprint": contract[
                    "contract_fingerprint"
                ],
            },
            "datasets": {
                "g2_root": str(g2.root),
                "h2_root": str(h2.root),
                "g2_row_count": (
                    g2.row_count
                ),
                "h2_row_count": (
                    h2.row_count
                ),
                "g2_column_count": len(
                    g2.schema
                ),
                "h2_column_count": len(
                    h2.schema
                ),
                "g2_parquet_file_count": (
                    g2.parquet_file_count
                ),
                "h2_parquet_file_count": (
                    h2.parquet_file_count
                ),
                "g2_parquet_bytes": (
                    g2.parquet_bytes
                ),
                "h2_parquet_bytes": (
                    h2.parquet_bytes
                ),
                "g2_arrow_schema_sha256": (
                    g2.arrow_schema_sha256
                ),
                "h2_arrow_schema_sha256": (
                    h2.arrow_schema_sha256
                ),
            },
            "schema": schema_result,
            "execution": {
                "requested_partition_count": (
                    len(partitions)
                ),
                "passed_partition_count": (
                    len(partitions)
                    - len(failed_partitions)
                ),
                "failed_partition_count": (
                    len(failed_partitions)
                ),
                "context_sample_columns": (
                    args.context_sample_columns
                ),
                "context_batch_columns": (
                    args.context_batch_columns
                ),
                "elapsed_seconds": (
                    time.monotonic()
                    - started
                ),
                "peak_rss_bytes": (
                    peak_rss_bytes()
                ),
                "target_peak_rss_mib": (
                    TARGET_PEAK_RSS_MIB
                ),
                "target_peak_rss_bytes": (
                    TARGET_PEAK_RSS_BYTES
                ),
            },
            "check_receipts": (
                check_receipts
            ),
            "partition_results": (
                partition_results
            ),
            "artifacts": {
                "coverage_report": (
                    "coverage_report.tsv"
                ),
                "unified_feature_lake_manifest": (
                    "unified_feature_lake_manifest.json"
                ),
                "dense_zero_observed_semantics": (
                    "dense_zero_observed_semantics.tsv"
                ),
                "check_receipts": (
                    "check_receipts.tsv"
                ),
                "partial_report_on_failure": (
                    "partial_report.json"
                ),
            },
            "partial_report": False,
            "parquet_write": False,
            "dataset_mutation": False,
        }

        write_json(
            args.output_dir
            / "i2_cross_dataset_validation_report.json",
            report,
        )

        decision_lines = [
            report["classification"],
            (
                "READY_FOR_NEXT_VALIDATION_PHASE"
                if report["ok"]
                else "BLOCKED_VALIDATION_FAILURE"
            ),
            "",
            (
                "CONTRACT_VERSION="
                + contract["version"]
            ),
            (
                "CONTRACT_FINGERPRINT="
                + contract[
                    "contract_fingerprint"
                ]
            ),
            (
                "GLOBAL_G2_ROW_COUNT="
                + str(g2.row_count)
            ),
            (
                "GLOBAL_H2_ROW_COUNT="
                + str(h2.row_count)
            ),
            (
                "REQUESTED_PARTITION_COUNT="
                + str(len(partitions))
            ),
            (
                "PASSED_PARTITION_COUNT="
                + str(
                    len(partitions)
                    - len(failed_partitions)
                )
            ),
            (
                "FAILED_PARTITION_COUNT="
                + str(
                    len(failed_partitions)
                )
            ),
            (
                "CONTEXT_SAMPLE_COLUMNS="
                + str(
                    args.context_sample_columns
                )
            ),
            (
                "APPROVED_RECONCILIATION_COUNT="
                + str(
                    schema_result[
                        "approved_reconciliation_count"
                    ]
                )
            ),
            "I2_CHECK_RECEIPT_COUNT=10",
            "I2_CHECK_FAILURE_COUNT=0",
            "COVERAGE_REPORT_WRITTEN=YES",
            (
                "UNIFIED_FEATURE_LAKE_MANIFEST_"
                "WRITTEN=YES"
            ),
            (
                "DENSE_ZERO_OBSERVED_SEMANTICS_"
                "WRITTEN=YES"
            ),
            "PARTIAL_REPORT_ON_FAILURE=ENABLED",
            (
                "PEAK_RSS_MIB="
                + f"{peak_rss_bytes() / 1024**2:.2f}"
            ),
            (
                "TARGET_PEAK_RSS_MIB="
                + f"{TARGET_PEAK_RSS_MIB:.2f}"
            ),
            "PARQUET_WRITE=NO",
            "DATASET_MUTATION=NO",
        ]

        (
            args.output_dir
            / "decision.txt"
        ).write_text(
            "\n".join(
                decision_lines
            )
            + "\n",
            encoding="utf-8",
        )

        print(
            report[
                "classification"
            ]
        )

        print(
            "VALIDATION_REPORT="
            + str(
                args.output_dir
                / (
                    "i2_cross_dataset_"
                    "validation_report.json"
                )
            )
        )

        return (
            0
            if report["ok"]
            else 1
        )

    except BaseException as error:
        if (
            current_check in receipts
            and receipts[
                current_check
            ][
                "status"
            ] == "PENDING"
        ):
            _set_receipt(
                receipts,
                current_check,
                status="FAIL",
                evidence=(
                    f"{type(error).__name__}:"
                    f"{error}"
                ),
            )

        _write_partial_report(
            output_dir=args.output_dir,
            contract_path=args.contract,
            g2_root=args.g2_root,
            h2_root=args.h2_root,
            receipts=receipts,
            failed_check=current_check,
            error=error,
            started=started,
        )

        print(
            "VALIDATION_ERROR="
            f"{type(error).__name__}:"
            f"{error}",
            file=sys.stderr,
        )

        return 1


if __name__ == "__main__":
    raise SystemExit(main())
