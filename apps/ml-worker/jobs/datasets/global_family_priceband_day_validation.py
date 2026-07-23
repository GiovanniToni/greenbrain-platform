#!/usr/bin/env python3
"""Independent Phase 2M-H2 validator source scaffold.

Preflight validation is implemented. Full candidate data validation is
deliberately blocked until streaming coherence checks are implemented
and exercised on the deterministic micro-fixture.
"""

from __future__ import annotations

import hashlib as _h2v_hashlib
import json as _h2v_json
import os as _h2v_os
import re as _h2v_re
from pathlib import Path as _H2VPath

import pyarrow as _h2v_pa
import pyarrow.parquet as _h2v_pq

import argparse
import csv
import hashlib
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence

import pyarrow as pa
import pyarrow.parquet as pq


FULL_CANDIDATE_VALIDATION_IMPLEMENTED = True
CONTRACT_FILENAME = (
    "phase2m_h2_family_priceband_day_contract_v1.json"
)
OWNERSHIP_MARKER_RELATIVE_PATH = Path(
    "metadata/"
    "global_family_priceband_day_"
    "candidate_ownership.json"
)
EXIT_DRAFT_RUNTIME_BLOCKED = 78


class DraftRuntimeBlocked(RuntimeError):
    """Raised when full candidate validation is not yet approved."""


@dataclass(frozen=True)
class ResolvedInput:
    role: str
    run_id: str
    run_root: Path
    dataset_root: Path
    key_columns: tuple[str, ...]


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


def load_contract(path: Path) -> dict[str, Any]:
    payload = json.loads(
        path.read_text(
            encoding="utf-8",
            errors="strict",
        )
    )

    embedded = payload.get(
        "contract_fingerprint"
    )

    if not isinstance(embedded, str):
        raise ValueError(
            "CONTRACT_FINGERPRINT_MISSING"
        )

    preimage = dict(payload)
    preimage.pop(
        "contract_fingerprint"
    )

    actual = sha256_bytes(
        canonical_json_bytes(
            preimage
        )
    )

    if actual != embedded:
        raise ValueError(
            "CONTRACT_FINGERPRINT_MISMATCH:"
            f"expected={embedded}:actual={actual}"
        )

    return payload


def write_json_atomic(
    path: Path,
    payload: Any,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    temporary = path.with_name(
        f".{path.name}.{os.getpid()}.tmp"
    )

    try:
        with temporary.open(
            "w",
            encoding="utf-8",
        ) as handle:
            json.dump(
                payload,
                handle,
                indent=2,
                ensure_ascii=True,
                allow_nan=False,
                sort_keys=True,
            )
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(
            temporary,
            path,
        )

    finally:
        if temporary.exists():
            temporary.unlink()


def write_tsv_atomic(
    path: Path,
    fieldnames: Sequence[str],
    rows: Iterable[dict[str, Any]],
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    temporary = path.with_name(
        f".{path.name}.{os.getpid()}.tmp"
    )

    try:
        with temporary.open(
            "w",
            encoding="utf-8",
            newline="",
        ) as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=list(fieldnames),
                delimiter="\t",
                extrasaction="ignore",
            )
            writer.writeheader()
            writer.writerows(rows)
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(
            temporary,
            path,
        )

    finally:
        if temporary.exists():
            temporary.unlink()


def parse_args(
    argv: Sequence[str] | None = None,
) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate the Phase 2M-H2 "
            "family-priceband-day feature lake."
        )
    )

    parser.add_argument(
        "--mode",
        required=True,
        choices=(
            "preflight",
            "validate",
        ),
    )
    parser.add_argument(
        "--contract",
        required=True,
    )
    parser.add_argument(
        "--candidate-run",
    )
    parser.add_argument(
        "--runs-root",
        required=True,
    )
    parser.add_argument(
        "--b2-run",
        required=True,
    )
    parser.add_argument(
        "--f2-run",
        required=True,
    )
    parser.add_argument(
        "--c2-run",
        required=True,
    )
    parser.add_argument(
        "--g2-run",
        required=True,
    )
    parser.add_argument(
        "--key-batch-rows",
        type=int,
        default=4096,
    )
    parser.add_argument(
        "--value-batch-rows",
        type=int,
        default=256,
    )

    return parser.parse_args(argv)


def _direct_child(
    root: Path,
    name: str,
) -> Path:
    if not name:
        raise ValueError(
            "EMPTY_DIRECT_CHILD_NAME"
        )

    if Path(name).name != name:
        raise ValueError(
            f"NON_DIRECT_CHILD_NAME:{name}"
        )

    root_resolved = root.resolve(
        strict=True
    )

    child = root_resolved / name

    if child.parent != root_resolved:
        raise ValueError(
            f"PATH_ESCAPE:{child}"
        )

    return child


def resolve_inputs_independently(
    args: argparse.Namespace,
    contract: dict[str, Any],
) -> dict[str, ResolvedInput]:
    runs_root = Path(
        args.runs_root
    ).resolve(strict=True)

    argument_map = {
        "B2_GRID": args.b2_run,
        "F2_PAIR_SALES": args.f2_run,
        "C2_PAIR_PRODUCT": args.c2_run,
        "G2_FAMILY_DAY": args.g2_run,
    }

    resolved: dict[str, ResolvedInput] = {}

    for role, payload in contract[
        "required_inputs"
    ].items():
        run_id = argument_map[role]

        run_root = _direct_child(
            runs_root,
            run_id,
        ).resolve(strict=True)

        dataset_root = (
            run_root
            / payload["dataset_root"]
        ).resolve(strict=True)

        if not dataset_root.is_dir():
            raise NotADirectoryError(
                "INPUT_DATASET_NOT_DIRECTORY:"
                f"role={role}:path={dataset_root}"
            )

        if not dataset_root.is_relative_to(
            run_root
        ):
            raise ValueError(
                "INPUT_DATASET_ESCAPES_RUN_ROOT:"
                f"role={role}"
            )

        resolved[role] = ResolvedInput(
            role=role,
            run_id=run_id,
            run_root=run_root,
            dataset_root=dataset_root,
            key_columns=tuple(
                payload["key_columns"]
            ),
        )

    return resolved


def _partition_key(
    path: Path,
    dataset_root: Path,
) -> tuple[int, int]:
    relative = path.relative_to(
        dataset_root
    )

    year: int | None = None
    month: int | None = None

    for part in relative.parts:
        if part.startswith("year="):
            year = int(
                part.split("=", 1)[1]
            )

        elif part.startswith("month="):
            month = int(
                part.split("=", 1)[1]
            )

    if year is None or month is None:
        raise ValueError(
            "PARQUET_PARTITION_KEYS_MISSING:"
            f"{path}"
        )

    return year, month


def inventory_partitions(
    dataset_root: Path,
) -> list[dict[str, Any]]:
    paths = sorted(
        dataset_root.rglob("*.parquet")
    )

    if not paths:
        raise FileNotFoundError(
            "NO_PARQUET_FILES:"
            f"{dataset_root}"
        )

    rows: list[dict[str, Any]] = []

    for path in paths:
        year, month = _partition_key(
            path,
            dataset_root,
        )

        metadata = pq.read_metadata(
            path
        )

        rows.append(
            {
                "year": year,
                "month": month,
                "path": str(path),
                "rows": metadata.num_rows,
                "row_groups": (
                    metadata.num_row_groups
                ),
                "columns": (
                    metadata.num_columns
                ),
            }
        )

    return rows


def physical_schema(
    contract: dict[str, Any],
) -> list[dict[str, Any]]:
    schema = contract[
        "output"
    ]["physical_schema"]

    if len(schema) != 2498:
        raise ValueError(
            "PHYSICAL_SCHEMA_COLUMN_COUNT_MISMATCH"
        )

    ordinals = [
        int(row["ordinal"])
        for row in schema
    ]

    if ordinals != list(
        range(0, 2498)
    ):
        raise ValueError(
            "PHYSICAL_SCHEMA_ORDINAL_MISMATCH"
        )

    return schema


def validate_candidate_ownership_marker(
    candidate: Path,
) -> dict[str, Any]:
    if candidate.is_symlink():
        raise ValueError(
            "CANDIDATE_SYMLINK_FORBIDDEN"
        )

    stat_result = candidate.stat(
        follow_symlinks=False
    )

    marker_path = (
        candidate
        / OWNERSHIP_MARKER_RELATIVE_PATH
    )

    marker = json.loads(
        marker_path.read_text(
            encoding="utf-8",
            errors="strict",
        )
    )

    required = {
        "format_version",
        "run_id",
        "candidate_name",
        "final_name",
        "owner_token_sha256",
        "reserved_st_dev",
        "reserved_st_ino",
        "supervisor_pid",
        "created_at_utc",
    }

    missing = sorted(required - set(marker))

    if missing:
        raise ValueError(
            "OWNERSHIP_MARKER_FIELDS_MISSING:"
            + ",".join(missing)
        )

    run_id = marker["run_id"]

    if (
        not isinstance(run_id, str)
        or not run_id
        or Path(run_id).name != run_id
    ):
        raise ValueError(
            "OWNERSHIP_MARKER_RUN_ID_INVALID"
        )

    expected_candidate_name = (
        f".{run_id}.candidate"
    )

    if marker["candidate_name"] != expected_candidate_name:
        raise ValueError(
            "OWNERSHIP_MARKER_RUN_ID_"
            "CANDIDATE_BINDING_MISMATCH"
        )

    if candidate.name != expected_candidate_name:
        raise ValueError(
            "CANDIDATE_RUN_ID_BINDING_MISMATCH"
        )

    if marker["final_name"] != run_id:
        raise ValueError(
            "OWNERSHIP_MARKER_RUN_ID_"
            "FINAL_BINDING_MISMATCH"
        )

    if (
        marker["reserved_st_dev"] != stat_result.st_dev
        or marker["reserved_st_ino"] != stat_result.st_ino
    ):
        raise ValueError(
            "OWNERSHIP_MARKER_FILESYSTEM_"
            "IDENTITY_MISMATCH"
        )

    return marker

def verify_strictly_sorted_three_part_keys(
    *_args: Any,
    **_kwargs: Any,
) -> None:
    raise DraftRuntimeBlocked(
        "H2_SORTED_KEY_STREAM_VALIDATION_NOT_IMPLEMENTED"
    )


def stream_candidate_b2_f2_coherence(
    *_args: Any,
    **_kwargs: Any,
) -> Iterator[Any]:
    raise DraftRuntimeBlocked(
        "H2_B2_F2_COHERENCE_VALIDATION_NOT_IMPLEMENTED"
    )


def stream_c2_pair_static_coherence(
    *_args: Any,
    **_kwargs: Any,
) -> Iterator[Any]:
    raise DraftRuntimeBlocked(
        "H2_C2_COHERENCE_VALIDATION_NOT_IMPLEMENTED"
    )


def stream_g2_family_day_representatives(
    *_args: Any,
    **_kwargs: Any,
) -> Iterator[Any]:
    raise DraftRuntimeBlocked(
        "H2_G2_REPRESENTATIVE_VALIDATION_NOT_IMPLEMENTED"
    )


def verify_g2_payload_constant_across_pricebands(
    *_args: Any,
    **_kwargs: Any,
) -> None:
    raise DraftRuntimeBlocked(
        "H2_G2_PAYLOAD_CONSTANT_VALIDATION_NOT_IMPLEMENTED"
    )


def verify_additive_reconciliation(
    *_args: Any,
    **_kwargs: Any,
) -> None:
    raise DraftRuntimeBlocked(
        "H2_ADDITIVE_RECONCILIATION_VALIDATION_NOT_IMPLEMENTED"
    )


def preflight(
    args: argparse.Namespace,
    contract: dict[str, Any],
) -> int:
    resolved = (
        resolve_inputs_independently(
            args,
            contract,
        )
    )

    inventories = {
        role: inventory_partitions(
            payload.dataset_root
        )
        for role, payload in (
            resolved.items()
        )
    }

    schema = physical_schema(
        contract
    )

    summary = {
        "ok": True,
        "mode": "preflight",
        "full_candidate_validation_implemented": (
            FULL_CANDIDATE_VALIDATION_IMPLEMENTED
        ),
        "contract_fingerprint": contract[
            "contract_fingerprint"
        ],
        "schema_columns": len(schema),
        "inputs": {
            role: {
                "run_id": payload.run_id,
                "dataset_root": str(
                    payload.dataset_root
                ),
                "parquet_files": len(
                    inventories[role]
                ),
                "rows": sum(
                    int(row["rows"])
                    for row in inventories[
                        role
                    ]
                ),
            }
            for role, payload in (
                resolved.items()
            )
        },
    }

    print(
        json.dumps(
            summary,
            indent=2,
            ensure_ascii=True,
            sort_keys=True,
        )
    )

    return 0


def validate_candidate(
    args: argparse.Namespace,
    contract: dict[str, Any],
) -> int:
    if not args.candidate_run:
        raise ValueError(
            "CANDIDATE_RUN_REQUIRED"
        )

    candidate = Path(
        args.candidate_run
    ).resolve(strict=True)

    validate_candidate_ownership_marker(
        candidate
    )
    physical_schema(contract)

    if not FULL_CANDIDATE_VALIDATION_IMPLEMENTED:
        raise DraftRuntimeBlocked(
            "H2_FULL_CANDIDATE_VALIDATION_NOT_IMPLEMENTED:"
            "validation is disabled in the report-only "
            "source scaffold"
        )

    return 0


_H2V_YEAR_RE = _h2v_re.compile(
    r"^year=\d{4}$"
)

_H2V_MONTH_RE = _h2v_re.compile(
    r"^month=(0[1-9]|1[0-2])$"
)


def _h2v_canonical_json_bytes(
    value,
):
    return _h2v_json.dumps(
        value,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def candidate_schema_fingerprint(
    schema,
):
    payload = [
        {
            "ordinal": ordinal,
            "name": field.name,
            "type": str(field.type),
            "nullable": bool(field.nullable),
        }
        for ordinal, field in enumerate(
            schema
        )
    ]

    return _h2v_hashlib.sha256(
        _h2v_canonical_json_bytes(
            payload
        )
    ).hexdigest()


def _h2v_assert_absolute_no_symlink_chain(
    path,
    *,
    label,
):
    candidate = _H2VPath(
        path
    )

    if not candidate.is_absolute():
        raise ValueError(
            "VALIDATOR_PATH_MUST_BE_ABSOLUTE:"
            f"label={label};path={candidate}"
        )

    current = _H2VPath(
        candidate.anchor
    )

    for part in candidate.parts[1:]:
        current = current / part

        if current.is_symlink():
            raise ValueError(
                "VALIDATOR_PATH_COMPONENT_SYMLINK:"
                f"label={label};path={current}"
            )

    if not candidate.exists():
        raise ValueError(
            "VALIDATOR_PATH_MISSING:"
            f"label={label};path={candidate}"
        )

    return candidate


def discover_candidate_partitions(
    candidate_root,
):
    root = (
        _h2v_assert_absolute_no_symlink_chain(
            candidate_root,
            label="candidate_root",
        )
    )

    if not root.is_dir():
        raise ValueError(
            "VALIDATOR_CANDIDATE_ROOT_NOT_DIRECTORY:"
            f"{root}"
        )

    allowed_root_files = {
        "_SUCCESS",
        "_VALIDATION.json",
        "manifest.json",
        "dataset_manifest.json",
        "run_manifest.json",
    }

    partitions = []

    for year_path in sorted(
        root.iterdir(),
        key=lambda item: item.name,
    ):
        if year_path.is_symlink():
            raise ValueError(
                "VALIDATOR_YEAR_PATH_SYMLINK:"
                f"{year_path}"
            )

        if year_path.is_file():
            if (
                year_path.name
                not in allowed_root_files
            ):
                raise ValueError(
                    "VALIDATOR_UNEXPECTED_ROOT_FILE:"
                    f"{year_path}"
                )

            continue

        if (
            not year_path.is_dir()
            or not _H2V_YEAR_RE.fullmatch(
                year_path.name
            )
        ):
            raise ValueError(
                "VALIDATOR_YEAR_PARTITION_INVALID:"
                f"{year_path}"
            )

        for month_path in sorted(
            year_path.iterdir(),
            key=lambda item: item.name,
        ):
            if month_path.is_symlink():
                raise ValueError(
                    "VALIDATOR_MONTH_PATH_SYMLINK:"
                    f"{month_path}"
                )

            if (
                not month_path.is_dir()
                or not _H2V_MONTH_RE.fullmatch(
                    month_path.name
                )
            ):
                raise ValueError(
                    "VALIDATOR_MONTH_PARTITION_INVALID:"
                    f"{month_path}"
                )

            parquet_files = []

            for child in sorted(
                month_path.iterdir(),
                key=lambda item: item.name,
            ):
                if child.is_symlink():
                    raise ValueError(
                        "VALIDATOR_PARQUET_FILE_SYMLINK:"
                        f"{child}"
                    )

                if (
                    not child.is_file()
                    or child.suffix != ".parquet"
                ):
                    raise ValueError(
                        "VALIDATOR_PARTITION_CONTENT_INVALID:"
                        f"{child}"
                    )

                _h2v_assert_absolute_no_symlink_chain(
                    child,
                    label="candidate_parquet_file",
                )

                parquet_files.append(
                    child
                )

            if not parquet_files:
                raise ValueError(
                    "VALIDATOR_PARTITION_HAS_NO_PARQUET:"
                    f"{month_path}"
                )

            partitions.append(
                (
                    year_path.name
                    + "/"
                    + month_path.name,
                    parquet_files,
                )
            )

    if not partitions:
        raise ValueError(
            "VALIDATOR_CANDIDATE_HAS_NO_PARTITIONS"
        )

    return partitions


def validate_candidate_dataset_streaming(
    candidate_root,
    projection_plan,
    expected_partition_rows,
    *,
    expected_total_rows,
    expected_output_columns,
    expected_schema=None,
    batch_rows=4096,
):
    if not isinstance(
        projection_plan,
        list,
    ):
        raise ValueError(
            "VALIDATOR_PROJECTION_PLAN_LIST_REQUIRED"
        )

    if (
        len(projection_plan)
        != expected_output_columns
    ):
        raise ValueError(
            "VALIDATOR_PROJECTION_COLUMN_COUNT_MISMATCH:"
            f"expected={expected_output_columns};"
            f"actual={len(projection_plan)}"
        )

    expected_names = []

    for expected_ordinal, record in enumerate(
        projection_plan
    ):
        if not isinstance(
            record,
            dict,
        ):
            raise ValueError(
                "VALIDATOR_PROJECTION_RECORD_INVALID:"
                f"ordinal={expected_ordinal}"
            )

        actual_ordinal = int(
            record.get(
                "ordinal",
                -1,
            )
        )

        output_column = str(
            record.get(
                "output_column",
                "",
            )
        ).strip()

        if actual_ordinal != expected_ordinal:
            raise ValueError(
                "VALIDATOR_PROJECTION_ORDINAL_INVALID:"
                f"expected={expected_ordinal};"
                f"actual={actual_ordinal}"
            )

        if not output_column:
            raise ValueError(
                "VALIDATOR_PROJECTION_OUTPUT_NAME_EMPTY:"
                f"ordinal={expected_ordinal}"
            )

        expected_names.append(
            output_column
        )

    if len(expected_names) != len(
        set(expected_names)
    ):
        raise ValueError(
            "VALIDATOR_PROJECTION_OUTPUT_NAMES_NOT_UNIQUE"
        )

    if not isinstance(
        expected_partition_rows,
        dict,
    ):
        raise ValueError(
            "VALIDATOR_EXPECTED_PARTITION_ROWS_MAP_REQUIRED"
        )

    normalized_expected_rows = {
        str(partition): int(row_count)
        for partition, row_count
        in expected_partition_rows.items()
    }

    if not normalized_expected_rows:
        raise ValueError(
            "VALIDATOR_EXPECTED_PARTITIONS_EMPTY"
        )

    if any(
        row_count <= 0
        for row_count
        in normalized_expected_rows.values()
    ):
        raise ValueError(
            "VALIDATOR_EXPECTED_PARTITION_ROW_COUNT_INVALID"
        )

    discovered = (
        discover_candidate_partitions(
            candidate_root
        )
    )

    discovered_names = [
        partition
        for partition, _
        in discovered
    ]

    expected_names_set = set(
        normalized_expected_rows
    )

    discovered_names_set = set(
        discovered_names
    )

    if (
        discovered_names_set
        != expected_names_set
    ):
        raise ValueError(
            "VALIDATOR_PARTITION_SET_MISMATCH:"
            f"missing={sorted(expected_names_set - discovered_names_set)};"
            f"unexpected={sorted(discovered_names_set - expected_names_set)}"
        )

    reference_schema = (
        expected_schema
    )

    if (
        reference_schema is not None
        and reference_schema.names
        != expected_names
    ):
        raise ValueError(
            "VALIDATOR_EXPECTED_SCHEMA_NAMES_MISMATCH"
        )

    key_columns = (
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
    )

    total_rows = 0
    total_batches = 0
    peak_batch_rows = 0

    previous_global_key = None
    partition_reports = []

    for partition, files in discovered:
        partition_rows = 0
        partition_batches = 0
        first_key = None
        last_key = None

        for parquet_file in files:
            parquet = _h2v_pq.ParquetFile(
                parquet_file
            )

            file_schema = (
                parquet.schema_arrow
            )

            if file_schema.names != expected_names:
                raise ValueError(
                    "VALIDATOR_SCHEMA_NAME_ORDER_MISMATCH:"
                    f"partition={partition};"
                    f"file={parquet_file}"
                )

            if (
                len(file_schema)
                != expected_output_columns
            ):
                raise ValueError(
                    "VALIDATOR_SCHEMA_COLUMN_COUNT_MISMATCH:"
                    f"partition={partition};"
                    f"expected={expected_output_columns};"
                    f"actual={len(file_schema)}"
                )

            if reference_schema is None:
                reference_schema = file_schema

            elif not file_schema.equals(
                reference_schema,
                check_metadata=False,
            ):
                raise ValueError(
                    "VALIDATOR_SCHEMA_TYPE_OR_NULLABILITY_MISMATCH:"
                    f"partition={partition};"
                    f"file={parquet_file}"
                )

            for batch in parquet.iter_batches(
                batch_size=batch_rows
            ):
                if batch.num_rows <= 0:
                    raise ValueError(
                        "VALIDATOR_EMPTY_RECORD_BATCH:"
                        f"partition={partition};"
                        f"file={parquet_file}"
                    )

                if not batch.schema.equals(
                    reference_schema,
                    check_metadata=False,
                ):
                    raise ValueError(
                        "VALIDATOR_BATCH_SCHEMA_MISMATCH:"
                        f"partition={partition};"
                        f"file={parquet_file}"
                    )

                key_indexes = []

                for key_column in key_columns:
                    key_index = (
                        batch.schema.get_field_index(
                            key_column
                        )
                    )

                    if key_index < 0:
                        raise ValueError(
                            "VALIDATOR_KEY_COLUMN_MISSING:"
                            f"partition={partition};"
                            f"column={key_column}"
                        )

                    key_array = batch.column(
                        key_index
                    )

                    if key_array.null_count:
                        raise ValueError(
                            "VALIDATOR_NULL_KEY_FORBIDDEN:"
                            f"partition={partition};"
                            f"column={key_column}"
                        )

                    key_indexes.append(
                        key_index
                    )

                key_values = [
                    batch.column(index).to_pylist()
                    for index in key_indexes
                ]

                for key in zip(
                    key_values[0],
                    key_values[1],
                    key_values[2],
                ):
                    if (
                        previous_global_key is not None
                        and not (
                            previous_global_key < key
                        )
                    ):
                        raise ValueError(
                            "VALIDATOR_GLOBAL_KEY_NOT_"
                            "STRICTLY_INCREASING:"
                            f"partition={partition};"
                            f"previous={previous_global_key};"
                            f"current={key}"
                        )

                    if first_key is None:
                        first_key = key

                    last_key = key
                    previous_global_key = key

                partition_rows += (
                    batch.num_rows
                )

                total_rows += (
                    batch.num_rows
                )

                partition_batches += 1
                total_batches += 1

                peak_batch_rows = max(
                    peak_batch_rows,
                    batch.num_rows,
                )

        expected_rows = (
            normalized_expected_rows[
                partition
            ]
        )

        if partition_rows != expected_rows:
            raise ValueError(
                "VALIDATOR_PARTITION_ROW_COUNT_MISMATCH:"
                f"partition={partition};"
                f"expected={expected_rows};"
                f"actual={partition_rows}"
            )

        partition_reports.append(
            {
                "partition": partition,
                "expected_rows": expected_rows,
                "actual_rows": partition_rows,
                "batch_count": partition_batches,
                "first_key": (
                    None
                    if first_key is None
                    else [
                        str(value)
                        for value in first_key
                    ]
                ),
                "last_key": (
                    None
                    if last_key is None
                    else [
                        str(value)
                        for value in last_key
                    ]
                ),
                "result": "PASS",
            }
        )

    if total_rows != expected_total_rows:
        raise ValueError(
            "VALIDATOR_TOTAL_ROW_COUNT_MISMATCH:"
            f"expected={expected_total_rows};"
            f"actual={total_rows}"
        )

    if reference_schema is None:
        raise ValueError(
            "VALIDATOR_REFERENCE_SCHEMA_MISSING"
        )

    return {
        "ok": True,
        "partition_count": len(
            partition_reports
        ),
        "partition_pass_count": len(
            partition_reports
        ),
        "total_rows": total_rows,
        "batch_count": total_batches,
        "column_count": len(
            reference_schema
        ),
        "schema_fingerprint": (
            candidate_schema_fingerprint(
                reference_schema
            )
        ),
        "strict_global_key_order": True,
        "peak_batch_rows": peak_batch_rows,
        "partitions": partition_reports,
    }

def main(
    argv: Sequence[str] | None = None,
) -> int:
    args = parse_args(argv)

    try:
        contract = load_contract(
            Path(args.contract)
        )

        if args.mode == "preflight":
            return preflight(
                args,
                contract,
            )

        if args.mode == "validate":
            return validate_candidate(
                args,
                contract,
            )

        raise AssertionError(
            f"UNREACHABLE_MODE:{args.mode}"
        )

    except DraftRuntimeBlocked as exc:
        print(
            f"ERROR={exc}",
            file=sys.stderr,
        )
        return EXIT_DRAFT_RUNTIME_BLOCKED

    except Exception as exc:
        print(
            f"ERROR={type(exc).__name__}:{exc}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
