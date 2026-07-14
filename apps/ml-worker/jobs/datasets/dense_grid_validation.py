"""Independent validation for GreenBrain dense-grid datasets.

The validator supports:

* validation of plan-only manifests produced by dense_grid_builder;
* future validation of temporary or final materialized dense-grid runs;
* schema fingerprint verification;
* monthly partition reconciliation;
* row-key, lifecycle, zero-fill and source reconciliation checks.

This module does not build or write feature parquet datasets.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import tempfile
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq


SUPPORTED_VALIDATION_MODES = (
    "auto",
    "plan_only",
    "materialized",
)

REQUIRED_OUTPUTS = (
    "family_activity_catalog",
    "family_priceband_activity_catalog",
    "family_day_dense_grid",
    "family_priceband_day_dense_grid",
)

PARTITION_COLUMNS = (
    "year",
    "month",
)

FAMILY_KEY = (
    "data",
    "famiglia",
)

PAIR_KEY = (
    "data",
    "famiglia",
    "fascia_prezzo_iva_inc",
)

FAMILY_ACTIVITY_KEY = (
    "famiglia",
)

PAIR_ACTIVITY_KEY = (
    "famiglia",
    "fascia_prezzo_iva_inc",
)

FAMILY_OBSERVED_COLUMNS = (
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
    "priceband_count",
    "source_priceband_rows",
)

PAIR_OBSERVED_COLUMNS = (
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
)

DENSE_MEASURE_MAPPING = {
    "qty_venduta": "qty_venduta_dense",
    "imponibile_netto_tot": "imponibile_dense",
    "num_articoli": "num_articoli_dense",
}


@dataclass(frozen=True)
class DenseGridValidationConfig:
    """Configuration for plan-only or materialized validation."""

    run_dir: Path
    source_run_dir: Path | None = None
    mode: str = "auto"
    report_path: Path | None = None
    logical_run_dir: Path | None = None
    expected_schema_fingerprint: str | None = None
    validate_source_reconciliation: bool = True


@dataclass
class DenseGridDatasetValidationResult:
    """Validation result for one planned or materialized output."""

    name: str
    ok: bool
    path: str
    row_count: int = 0
    metadata_row_count: int = 0
    file_count: int = 0
    partition_count: int = 0
    duplicate_key_count: int = 0
    critical_nulls: dict[str, int] = field(default_factory=dict)
    schema_fingerprint: str | None = None
    issues: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "ok": bool(self.ok),
            "path": self.path,
            "row_count": int(self.row_count),
            "metadata_row_count": int(self.metadata_row_count),
            "file_count": int(self.file_count),
            "partition_count": int(self.partition_count),
            "duplicate_key_count": int(
                self.duplicate_key_count
            ),
            "critical_nulls": {
                str(key): int(value)
                for key, value
                in self.critical_nulls.items()
            },
            "schema_fingerprint": self.schema_fingerprint,
            "issues": list(self.issues),
        }


@dataclass
class DenseGridValidationResult:
    """Top-level dense-grid validation result."""

    ok: bool
    mode: str
    run_dir: str
    source_run_dir: str
    manifest_path: str
    report_path: str
    validated_at_utc: str
    logical_run_dir: str | None = None
    manifest_summary: dict[str, Any] = field(
        default_factory=dict
    )
    datasets: tuple[
        DenseGridDatasetValidationResult,
        ...,
    ] = field(default_factory=tuple)
    source_reconciliation: dict[str, Any] = field(
        default_factory=dict
    )
    safety: dict[str, Any] = field(default_factory=dict)
    issues: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": bool(self.ok),
            "mode": self.mode,
            "run_dir": self.run_dir,
            "logical_run_dir": self.logical_run_dir,
            "source_run_dir": self.source_run_dir,
            "manifest_path": self.manifest_path,
            "report_path": self.report_path,
            "validated_at_utc": self.validated_at_utc,
            "manifest_summary": _json_safe(
                self.manifest_summary
            ),
            "datasets": [
                dataset.to_dict()
                for dataset in self.datasets
            ],
            "source_reconciliation": _json_safe(
                self.source_reconciliation
            ),
            "safety": _json_safe(self.safety),
            "issues": list(self.issues),
        }


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _json_safe(value: Any) -> Any:
    if value is None:
        return None

    if value is pd.NA:
        return None

    if isinstance(value, Path):
        return str(value)

    if isinstance(value, (datetime, date, pd.Timestamp)):
        return value.isoformat()

    if isinstance(value, dict):
        return {
            str(key): _json_safe(item)
            for key, item in value.items()
        }

    if isinstance(value, (list, tuple, set)):
        return [_json_safe(item) for item in value]

    if hasattr(value, "item"):
        try:
            return _json_safe(value.item())
        except (TypeError, ValueError):
            pass

    if isinstance(value, float) and math.isnan(value):
        return None

    return value


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json_atomic(
    path: Path,
    payload: dict[str, Any],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=str(path.parent),
    )

    temporary_path = Path(temporary_name)

    try:
        with os.fdopen(
            descriptor,
            "w",
            encoding="utf-8",
        ) as handle:
            json.dump(
                _json_safe(payload),
                handle,
                indent=2,
                sort_keys=True,
                ensure_ascii=False,
            )
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(temporary_path, path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def _is_relative_to(
    path: Path,
    root: Path,
) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False

    return True


def _resolve_manifest_path(run_dir: Path) -> Path:
    return (
        run_dir
        / "metadata"
        / "dense_grid_manifest.json"
    )


def _load_manifest(
    manifest_path: Path,
) -> tuple[dict[str, Any], list[str]]:
    issues: list[str] = []

    if not manifest_path.is_file():
        return {}, [
            f"manifest missing: {manifest_path}"
        ]

    try:
        manifest = _read_json(manifest_path)
    except Exception as exc:
        return {}, [
            "cannot read manifest "
            f"{manifest_path}: "
            f"{type(exc).__name__}: {exc}"
        ]

    if not isinstance(manifest, dict):
        issues.append(
            "manifest root must be a JSON object"
        )
        return {}, issues

    return manifest, issues


def _resolve_source_run_dir(
    config: DenseGridValidationConfig,
    manifest: dict[str, Any],
) -> tuple[Path | None, list[str]]:
    issues: list[str] = []

    raw_value: Any

    if config.source_run_dir is not None:
        raw_value = config.source_run_dir
    else:
        raw_value = manifest.get("source_run_dir")

    if raw_value in (None, ""):
        return None, [
            "source_run_dir is absent from both "
            "configuration and manifest"
        ]

    source_run = Path(raw_value).resolve()

    if not source_run.is_dir():
        issues.append(
            f"source run does not exist: {source_run}"
        )

    return source_run, issues


def _canonical_schema_fingerprint(
    planned_schemas: dict[
        str,
        list[dict[str, Any]],
    ],
) -> str:
    canonical_json = json.dumps(
        planned_schemas,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )

    return hashlib.sha256(
        canonical_json.encode("utf-8")
    ).hexdigest()


def _canonical_arrow_type_name(
    contract_type: str,
) -> str:
    """Resolve a stable schema-contract alias to PyArrow's type name."""

    return str(
        pa.type_for_alias(contract_type)
    )


def _validate_manifest_common(
    config: DenseGridValidationConfig,
    manifest: dict[str, Any],
    source_run: Path | None,
    mode: str,
) -> list[str]:
    issues: list[str] = []

    if config.mode not in SUPPORTED_VALIDATION_MODES:
        issues.append(
            "unsupported validation mode: "
            f"{config.mode}"
        )

    if manifest.get("schema_version") != 1:
        issues.append(
            "manifest schema_version must equal 1"
        )

    if manifest.get("stage") != "dense_grid_builder":
        issues.append(
            "manifest stage must equal "
            "dense_grid_builder"
        )

    if not manifest.get("build_id"):
        issues.append(
            "manifest build_id is missing"
        )

    manifest_mode = manifest.get("mode")

    if manifest_mode != mode:
        issues.append(
            "manifest mode mismatch: "
            f"resolved={mode}, manifest={manifest_mode}"
        )

    if mode == "plan_only":
        if manifest.get("dry_run") is not True:
            issues.append(
                "plan-only manifest dry_run must be true"
            )

        if manifest.get("ok") is not True:
            issues.append(
                "plan-only manifest ok must be true"
            )

        if manifest.get("decision") != (
            "DENSE_GRID_DRY_RUN_PLAN_READY"
        ):
            issues.append(
                "plan-only manifest decision is not ready"
            )

    elif mode == "materialized":
        if manifest.get("dry_run") is not False:
            issues.append(
                "materialized manifest dry_run must be false"
            )

        if manifest.get("ok") is not True:
            issues.append(
                "materialized manifest ok must be true"
            )

    configuration = manifest.get("configuration")

    if not isinstance(configuration, dict):
        issues.append(
            "manifest configuration must be an object"
        )
    else:
        if configuration.get("dense_scope") not in {
            "first_seen_to_dataset_end",
            "observed_lifecycle",
            "full_calendar",
        }:
            issues.append(
                "manifest dense_scope is unsupported"
            )

        for field_name in (
            "family_min_observed_days",
            "pair_min_observed_days",
        ):
            value = configuration.get(field_name)

            if (
                not isinstance(value, int)
                or value < 1
            ):
                issues.append(
                    f"manifest {field_name} must be >= 1"
                )

    validations = manifest.get(
        "required_validations"
    )

    if not isinstance(validations, list):
        issues.append(
            "required_validations must be a list"
        )
    else:
        labels = set()

        for validation in validations:
            if not isinstance(validation, dict):
                issues.append(
                    "invalid required validation summary"
                )
                continue

            label = validation.get("label")
            labels.add(label)

            if validation.get("ok") is not True:
                issues.append(
                    f"required validation not OK: {label}"
                )

            if validation.get("issue_count") != 0:
                issues.append(
                    "required validation issue_count "
                    f"is not zero: {label}"
                )

        if not {
            "R3B",
            "R3C family_day",
        }.issubset(labels):
            issues.append(
                "required R3B/R3C validation "
                "summaries are missing"
            )

    run_dir = Path(config.run_dir).resolve()

    if (
        source_run is not None
        and (
            source_run == run_dir
            or _is_relative_to(run_dir, source_run)
            or _is_relative_to(source_run, run_dir)
        )
    ):
        issues.append(
            "source run and candidate run must be "
            "independent directories"
        )

    safety = manifest.get("safety")

    if not isinstance(safety, dict):
        issues.append(
            "manifest safety must be an object"
        )
    else:
        for key in (
            "db_read",
            "db_write",
            "source_run_write",
            "latest_pointer_update",
        ):
            if safety.get(key) != "NO":
                issues.append(
                    f"manifest safety {key} must be NO"
                )

        if mode == "plan_only":
            if safety.get("parquet_write") != "NO":
                issues.append(
                    "plan-only parquet_write must be NO"
                )

            if safety.get("execution_enabled") != "NO":
                issues.append(
                    "plan-only execution_enabled must be NO"
                )

    return issues


def _validate_planned_schemas(
    config: DenseGridValidationConfig,
    manifest: dict[str, Any],
) -> tuple[
    dict[str, list[dict[str, Any]]],
    str | None,
    list[str],
]:
    issues: list[str] = []

    planned_schemas = manifest.get(
        "planned_output_schemas"
    )

    if not isinstance(planned_schemas, dict):
        return {}, None, [
            "planned_output_schemas must be an object"
        ]

    missing_datasets = sorted(
        set(REQUIRED_OUTPUTS)
        - set(planned_schemas)
    )

    if missing_datasets:
        issues.append(
            "planned schemas missing outputs: "
            f"{missing_datasets}"
        )

    for dataset_name, fields in (
        planned_schemas.items()
    ):
        if not isinstance(fields, list):
            issues.append(
                f"{dataset_name}: schema must be a list"
            )
            continue

        names = []

        for field_spec in fields:
            if not isinstance(field_spec, dict):
                issues.append(
                    f"{dataset_name}: invalid schema field"
                )
                continue

            name = field_spec.get("name")
            field_type = field_spec.get("type")

            names.append(name)

            if not name:
                issues.append(
                    f"{dataset_name}: field name missing"
                )

            if not field_type:
                issues.append(
                    f"{dataset_name}.{name}: type missing"
                )

            if field_type == "source":
                issues.append(
                    f"{dataset_name}.{name}: "
                    "unresolved source type"
                )

            if not isinstance(
                field_spec.get("nullable"),
                bool,
            ):
                issues.append(
                    f"{dataset_name}.{name}: "
                    "nullable must be boolean"
                )

        if len(names) != len(set(names)):
            issues.append(
                f"{dataset_name}: duplicate schema fields"
            )

    fingerprint = _canonical_schema_fingerprint(
        planned_schemas
    )

    manifest_fingerprint = manifest.get(
        "output_schema_fingerprint"
    )

    if fingerprint != manifest_fingerprint:
        issues.append(
            "schema fingerprint does not match "
            "canonical planned schemas"
        )

    if manifest.get(
        "output_schema_fingerprint_algorithm"
    ) != "sha256-canonical-json":
        issues.append(
            "schema fingerprint algorithm mismatch"
        )

    if (
        config.expected_schema_fingerprint
        and fingerprint
        != config.expected_schema_fingerprint
    ):
        issues.append(
            "schema fingerprint differs from "
            "configured expected value"
        )

    return planned_schemas, fingerprint, issues


def _validate_monthly_partition_plan(
    manifest: dict[str, Any],
) -> tuple[
    list[dict[str, Any]],
    dict[str, int],
    list[str],
]:
    issues: list[str] = []

    profile = manifest.get("profile")

    if not isinstance(profile, dict):
        return [], {}, [
            "manifest profile must be an object"
        ]

    partitioning = profile.get("partitioning")

    if not isinstance(partitioning, dict):
        return [], {}, [
            "profile.partitioning must be an object"
        ]

    if partitioning.get("columns") != [
        "year",
        "month",
    ]:
        issues.append(
            "partition columns must be year/month"
        )

    if partitioning.get(
        "generation_strategy"
    ) != "one calendar month at a time":
        issues.append(
            "monthly generation strategy mismatch"
        )

    month_count = partitioning.get(
        "planned_partition_count"
    )

    if (
        not isinstance(month_count, int)
        or month_count < 1
    ):
        issues.append(
            "planned_partition_count must be >= 1"
        )
        month_count = 0

    monthly_plan = profile.get(
        "monthly_partition_estimates"
    )

    if not isinstance(monthly_plan, list):
        return [], {}, [
            "monthly_partition_estimates "
            "must be a list"
        ]

    if len(monthly_plan) != month_count * 2:
        issues.append(
            "monthly plan must contain two entries "
            f"per month: months={month_count}, "
            f"rows={len(monthly_plan)}"
        )

    configured_scope = (
        manifest
        .get("configuration", {})
        .get("dense_scope")
    )

    keys = []
    totals: dict[str, int] = {}

    for item in monthly_plan:
        if not isinstance(item, dict):
            issues.append(
                "monthly plan contains invalid entry"
            )
            continue

        grain = item.get("grain")
        year = item.get("year")
        month = item.get("month")
        row_count = item.get("row_count")
        active_count = item.get(
            "active_entity_count"
        )

        key = (
            grain,
            year,
            month,
        )
        keys.append(key)

        if grain not in {
            "family_day_dense_grid",
            "family_priceband_day_dense_grid",
        }:
            issues.append(
                f"invalid monthly plan grain: {grain}"
            )

        if item.get("dense_scope") != configured_scope:
            issues.append(
                "monthly plan dense_scope mismatch "
                f"for {key}"
            )

        if (
            not isinstance(year, int)
            or not isinstance(month, int)
            or not 1 <= month <= 12
        ):
            issues.append(
                f"invalid monthly partition key: {key}"
            )

        if (
            not isinstance(row_count, int)
            or row_count < 0
        ):
            issues.append(
                f"invalid monthly row_count: {key}"
            )
            continue

        if (
            not isinstance(active_count, int)
            or active_count < 0
        ):
            issues.append(
                f"invalid active_entity_count: {key}"
            )

        totals[grain] = (
            totals.get(grain, 0)
            + row_count
        )

    if len(keys) != len(set(keys)):
        issues.append(
            "monthly plan contains duplicate "
            "grain/year/month keys"
        )

    outputs = {
        item.get("name"): item
        for item in manifest.get("outputs", [])
        if isinstance(item, dict)
    }

    for grain in (
        "family_day_dense_grid",
        "family_priceband_day_dense_grid",
    ):
        output = outputs.get(grain)

        if output is None:
            issues.append(
                f"planned output missing: {grain}"
            )
            continue

        expected_rows = output.get("row_count")

        if totals.get(grain) != expected_rows:
            issues.append(
                f"monthly total mismatch {grain}: "
                f"monthly={totals.get(grain)}, "
                f"output={expected_rows}"
            )

    return monthly_plan, totals, issues


def _resolve_candidate_output_path(
    config: DenseGridValidationConfig,
    manifest: dict[str, Any],
    output: dict[str, Any],
    mode: str,
) -> tuple[Path | None, list[str]]:
    issues: list[str] = []

    candidate_root = Path(
        config.run_dir
    ).resolve()

    logical_raw = (
        config.logical_run_dir
        or manifest.get("logical_run_dir")
        or manifest.get("run_dir")
        or candidate_root
    )

    logical_root = Path(
        logical_raw
    ).resolve()

    relative_path = output.get("relative_path")

    if mode == "materialized":
        if not relative_path:
            return None, [
                f"{output.get('name')}: "
                "relative_path is required for "
                "materialized validation"
            ]

        relative = Path(relative_path)

        if relative.is_absolute():
            issues.append(
                f"{output.get('name')}: "
                "relative_path must not be absolute"
            )

        if ".." in relative.parts:
            issues.append(
                f"{output.get('name')}: "
                "relative_path must not contain .."
            )

        candidate_path = (
            candidate_root / relative
        ).resolve()

    else:
        if relative_path:
            candidate_path = (
                candidate_root
                / Path(relative_path)
            ).resolve()
        else:
            raw_output_path = output.get(
                "output_path"
            )

            if not raw_output_path:
                return None, [
                    f"{output.get('name')}: "
                    "output_path is missing"
                ]

            candidate_path = Path(
                raw_output_path
            ).resolve()

    if not _is_relative_to(
        candidate_path,
        candidate_root,
    ):
        if not (
            mode == "plan_only"
            and _is_relative_to(
                candidate_path,
                logical_root,
            )
        ):
            issues.append(
                f"{output.get('name')}: "
                "output path escapes candidate/logical "
                f"run root: {candidate_path}"
            )

    return candidate_path, issues


def _validate_output_paths(
    config: DenseGridValidationConfig,
    manifest: dict[str, Any],
    mode: str,
) -> tuple[dict[str, Path], list[str]]:
    issues: list[str] = []
    resolved: dict[str, Path] = {}

    outputs = manifest.get("outputs")

    if not isinstance(outputs, list):
        return {}, [
            "manifest outputs must be a list"
        ]

    names = []

    for output in outputs:
        if not isinstance(output, dict):
            issues.append(
                "manifest contains invalid output entry"
            )
            continue

        name = output.get("name")
        names.append(name)

        path, path_issues = (
            _resolve_candidate_output_path(
                config,
                manifest,
                output,
                mode,
            )
        )

        issues.extend(path_issues)

        if name and path is not None:
            resolved[name] = path

    if len(names) != len(set(names)):
        issues.append(
            "manifest contains duplicate output names"
        )

    missing = sorted(
        set(REQUIRED_OUTPUTS)
        - set(resolved)
    )

    if missing:
        issues.append(
            f"required output paths missing: {missing}"
        )

    return resolved, issues


def _parquet_files(path: Path) -> list[Path]:
    if not path.exists():
        return []

    if path.is_file():
        if path.suffix == ".parquet":
            return [path]
        return []

    return sorted(path.rglob("*.parquet"))


def _partition_key_from_path(
    root: Path,
    file: Path,
) -> tuple[int, int] | None:
    relative = file.relative_to(root)

    year: int | None = None
    month: int | None = None

    for part in relative.parts[:-1]:
        if part.startswith("year="):
            try:
                year = int(
                    part.split("=", 1)[1]
                )
            except ValueError:
                return None

        elif part.startswith("month="):
            try:
                month = int(
                    part.split("=", 1)[1]
                )
            except ValueError:
                return None

    if year is None or month is None:
        return None

    return year, month


def _parquet_metadata_summary(
    path: Path,
    partitioned: bool,
) -> dict[str, Any]:
    files = _parquet_files(path)

    row_count = 0
    compressions: set[str] = set()
    partition_rows: dict[str, int] = {}
    physical_schemas: list[dict[str, str]] = []

    for file in files:
        parquet_file = pq.ParquetFile(file)
        metadata = parquet_file.metadata

        file_rows = int(metadata.num_rows)
        row_count += file_rows

        physical_schemas.append(
            {
                field.name: str(field.type)
                for field
                in parquet_file.schema_arrow
            }
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
                compressions.add(
                    str(
                        row_group
                        .column(column_index)
                        .compression
                    ).lower()
                )

        if partitioned:
            key = _partition_key_from_path(
                path,
                file,
            )

            if key is None:
                partition_rows[
                    f"INVALID:{file}"
                ] = file_rows
            else:
                text_key = (
                    f"{key[0]:04d}-{key[1]:02d}"
                )
                partition_rows[text_key] = (
                    partition_rows.get(
                        text_key,
                        0,
                    )
                    + file_rows
                )

    return {
        "files": files,
        "file_count": len(files),
        "row_count": row_count,
        "compressions": sorted(compressions),
        "partition_rows": partition_rows,
        "physical_schemas": physical_schemas,
    }


def _validate_dataset_schema(
    dataset_name: str,
    planned_fields: list[dict[str, Any]],
    metadata: dict[str, Any],
    partitioned: bool,
) -> tuple[str | None, list[str]]:
    issues: list[str] = []

    expected_all = {
        field["name"]: field["type"]
        for field in planned_fields
    }

    expected_physical = {
        name: field_type
        for name, field_type
        in expected_all.items()
        if (
            not partitioned
            or name not in PARTITION_COLUMNS
        )
    }

    for index, physical_schema in enumerate(
        metadata["physical_schemas"]
    ):
        physical_names = set(
            physical_schema
        )

        allowed_name_sets = {
            frozenset(expected_physical),
            frozenset(expected_all),
        }

        if frozenset(physical_names) not in (
            allowed_name_sets
        ):
            issues.append(
                f"{dataset_name}: physical schema "
                f"field mismatch in file index {index}: "
                f"expected={sorted(expected_physical)} "
                f"or {sorted(expected_all)}, "
                f"actual={sorted(physical_names)}"
            )
            continue

        expected_for_file = (
            expected_all
            if physical_names == set(expected_all)
            else expected_physical
        )

        for field_name, expected_type in (
            expected_for_file.items()
        ):
            actual_type = physical_schema.get(
                field_name
            )

            try:
                canonical_expected_type = (
                    _canonical_arrow_type_name(
                        expected_type
                    )
                )
            except Exception as exc:
                issues.append(
                    f"{dataset_name}.{field_name}: "
                    "cannot canonicalize planned "
                    f"Arrow type {expected_type}: "
                    f"{type(exc).__name__}: {exc}"
                )
                continue

            if actual_type != canonical_expected_type:
                issues.append(
                    f"{dataset_name}.{field_name}: "
                    "physical type mismatch: "
                    f"expected={expected_type} "
                    f"(canonical="
                    f"{canonical_expected_type}), "
                    f"actual={actual_type}"
                )

    fingerprint = _canonical_schema_fingerprint(
        {
            dataset_name: planned_fields,
        }
    )

    return fingerprint, issues


def _read_files_frame(
    files: list[Path],
) -> pd.DataFrame:
    frames = [
        pq.ParquetFile(file).read().to_pandas()
        for file in files
    ]

    if not frames:
        return pd.DataFrame()

    return pd.concat(
        frames,
        ignore_index=True,
    )


def _read_partition_frame(
    root: Path,
    year: int,
    month: int,
) -> pd.DataFrame:
    partition_dir = (
        root
        / f"year={year:04d}"
        / f"month={month:02d}"
    )

    files = _parquet_files(
        partition_dir
    )

    frame = _read_files_frame(files)

    if frame.empty:
        return frame

    if "year" not in frame.columns:
        frame["year"] = year

    if "month" not in frame.columns:
        frame["month"] = month

    return frame


def _critical_null_counts(
    frame: pd.DataFrame,
    columns: tuple[str, ...],
) -> dict[str, int]:
    counts: dict[str, int] = {}

    for column in columns:
        if column not in frame.columns:
            counts[column] = len(frame)
        else:
            counts[column] = int(
                frame[column].isna().sum()
            )

    return counts


def _frame_is_sorted(
    frame: pd.DataFrame,
    keys: tuple[str, ...],
) -> bool:
    if frame.empty:
        return True

    if any(
        key not in frame.columns
        for key in keys
    ):
        return False

    current = (
        frame
        .loc[:, list(keys)]
        .reset_index(drop=True)
    )

    expected = (
        frame
        .sort_values(list(keys), kind="mergesort")
        .loc[:, list(keys)]
        .reset_index(drop=True)
    )

    return current.equals(expected)


def _numeric_mismatch_count(
    left: pd.Series,
    right: pd.Series,
    tolerance: float = 1e-8,
) -> int:
    left_numeric = pd.to_numeric(
        left,
        errors="coerce",
    )
    right_numeric = pd.to_numeric(
        right,
        errors="coerce",
    )

    both_null = (
        left_numeric.isna()
        & right_numeric.isna()
    )

    mismatch = (
        (
            left_numeric.fillna(0)
            - right_numeric.fillna(0)
        ).abs()
        > tolerance
    ) & ~both_null

    null_mismatch = (
        left_numeric.isna()
        ^ right_numeric.isna()
    )

    return int(
        (mismatch | null_mismatch).sum()
    )


def _validate_family_partition(
    frame: pd.DataFrame,
    year: int,
    month: int,
    dense_scope: str,
    build_id: str,
) -> tuple[pd.DataFrame, dict[str, Any], list[str]]:
    issues: list[str] = []

    required_columns = (
        "data",
        "famiglia",
        "is_observed_sale",
        "is_relevant_family",
        "is_within_family_lifecycle",
        "family_first_sale_date",
        "family_last_sale_date",
        "family_observed_day_count",
        "qty_venduta",
        "imponibile_netto_tot",
        "num_articoli",
        "qty_venduta_dense",
        "imponibile_dense",
        "num_articoli_dense",
        "priceband_count",
        "source_priceband_rows",
        "dense_scope",
        "build_id",
        "year",
        "month",
    )

    missing = sorted(
        set(required_columns)
        - set(frame.columns)
    )

    if missing:
        return pd.DataFrame(), {}, [
            f"family partition missing columns: {missing}"
        ]

    frame = frame.copy()

    for date_column in (
        "data",
        "family_first_sale_date",
        "family_last_sale_date",
    ):
        frame[date_column] = pd.to_datetime(
            frame[date_column],
            errors="coerce",
        ).dt.normalize()

    duplicate_count = int(
        frame.duplicated(
            subset=list(FAMILY_KEY)
        ).sum()
    )

    if duplicate_count:
        issues.append(
            "family duplicate key count="
            f"{duplicate_count}"
        )

    critical_columns = (
        "data",
        "famiglia",
        "is_observed_sale",
        "is_relevant_family",
        "is_within_family_lifecycle",
        "family_first_sale_date",
        "family_last_sale_date",
        "family_observed_day_count",
        "qty_venduta_dense",
        "imponibile_dense",
        "num_articoli_dense",
        "dense_scope",
        "build_id",
        "year",
        "month",
    )

    nulls = _critical_null_counts(
        frame,
        critical_columns,
    )

    for column, count in nulls.items():
        if count:
            issues.append(
                f"family critical nulls {column}={count}"
            )

    if not _frame_is_sorted(
        frame,
        FAMILY_KEY,
    ):
        issues.append(
            "family partition is not sorted by "
            "data/famiglia"
        )

    if not (
        frame["year"].astype(int) == year
    ).all():
        issues.append(
            "family partition year values mismatch"
        )

    if not (
        frame["month"].astype(int) == month
    ).all():
        issues.append(
            "family partition month values mismatch"
        )

    if not (
        frame["dense_scope"].astype(str)
        == dense_scope
    ).all():
        issues.append(
            "family dense_scope values mismatch"
        )

    if not (
        frame["build_id"].astype(str)
        == build_id
    ).all():
        issues.append(
            "family build_id values mismatch"
        )

    if not (
        frame["is_relevant_family"].astype(bool)
    ).all():
        issues.append(
            "family output contains an irrelevant family"
        )

    expected_lifecycle = (
        (
            frame["data"]
            >= frame["family_first_sale_date"]
        )
        & (
            frame["data"]
            <= frame["family_last_sale_date"]
        )
    )

    actual_lifecycle = frame[
        "is_within_family_lifecycle"
    ].astype(bool)

    lifecycle_mismatch = int(
        (
            expected_lifecycle
            != actual_lifecycle
        ).sum()
    )

    if lifecycle_mismatch:
        issues.append(
            "family lifecycle flag mismatch="
            f"{lifecycle_mismatch}"
        )

    observed_mask = frame[
        "is_observed_sale"
    ].astype(bool)

    generated_mask = ~observed_mask

    for column in FAMILY_OBSERVED_COLUMNS:
        generated_non_null = int(
            frame.loc[
                generated_mask,
                column,
            ].notna().sum()
        )

        if generated_non_null:
            issues.append(
                f"family generated rows contain "
                f"{column}: {generated_non_null}"
            )

    for source_column, dense_column in (
        DENSE_MEASURE_MAPPING.items()
    ):
        generated_non_zero = int(
            (
                pd.to_numeric(
                    frame.loc[
                        generated_mask,
                        dense_column,
                    ],
                    errors="coerce",
                ).fillna(float("nan"))
                != 0
            ).sum()
        )

        if generated_non_zero:
            issues.append(
                f"family generated dense measure "
                f"{dense_column} is not zero: "
                f"{generated_non_zero}"
            )

        observed_null_count = int(
            frame.loc[
                observed_mask,
                source_column,
            ].isna().sum()
        )

        if observed_null_count:
            issues.append(
                f"family observed rows contain null "
                f"{source_column}: {observed_null_count}"
            )

        mismatch_count = _numeric_mismatch_count(
            frame.loc[
                observed_mask,
                source_column,
            ],
            frame.loc[
                observed_mask,
                dense_column,
            ],
        )

        if mismatch_count:
            issues.append(
                f"family observed/dense mismatch "
                f"{source_column}->{dense_column}: "
                f"{mismatch_count}"
            )

    observed = frame.loc[
        observed_mask,
        [
            *FAMILY_KEY,
            *FAMILY_OBSERVED_COLUMNS,
        ],
    ].copy()

    stats = {
        "row_count": int(len(frame)),
        "duplicate_key_count": duplicate_count,
        "critical_nulls": nulls,
        "observed_row_count": int(
            observed_mask.sum()
        ),
        "generated_row_count": int(
            generated_mask.sum()
        ),
    }

    return observed, stats, issues


def _validate_pair_partition(
    frame: pd.DataFrame,
    year: int,
    month: int,
    dense_scope: str,
    build_id: str,
) -> tuple[pd.DataFrame, dict[str, Any], list[str]]:
    issues: list[str] = []

    required_columns = (
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
        "is_observed_sale",
        "is_relevant_family",
        "is_relevant_family_priceband",
        "is_within_pair_lifecycle",
        "pair_first_sale_date",
        "pair_last_sale_date",
        "pair_observed_day_count",
        "qty_venduta",
        "imponibile_netto_tot",
        "num_articoli",
        "qty_venduta_dense",
        "imponibile_dense",
        "num_articoli_dense",
        "dense_scope",
        "build_id",
        "year",
        "month",
    )

    missing = sorted(
        set(required_columns)
        - set(frame.columns)
    )

    if missing:
        return pd.DataFrame(), {}, [
            f"pair partition missing columns: {missing}"
        ]

    frame = frame.copy()

    for date_column in (
        "data",
        "pair_first_sale_date",
        "pair_last_sale_date",
    ):
        frame[date_column] = pd.to_datetime(
            frame[date_column],
            errors="coerce",
        ).dt.normalize()

    duplicate_count = int(
        frame.duplicated(
            subset=list(PAIR_KEY)
        ).sum()
    )

    if duplicate_count:
        issues.append(
            "pair duplicate key count="
            f"{duplicate_count}"
        )

    critical_columns = (
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
        "is_observed_sale",
        "is_relevant_family",
        "is_relevant_family_priceband",
        "is_within_pair_lifecycle",
        "pair_first_sale_date",
        "pair_last_sale_date",
        "pair_observed_day_count",
        "qty_venduta_dense",
        "imponibile_dense",
        "num_articoli_dense",
        "dense_scope",
        "build_id",
        "year",
        "month",
    )

    nulls = _critical_null_counts(
        frame,
        critical_columns,
    )

    for column, count in nulls.items():
        if count:
            issues.append(
                f"pair critical nulls {column}={count}"
            )

    if not _frame_is_sorted(
        frame,
        PAIR_KEY,
    ):
        issues.append(
            "pair partition is not sorted by "
            "data/famiglia/priceband"
        )

    if not (
        frame["year"].astype(int) == year
    ).all():
        issues.append(
            "pair partition year values mismatch"
        )

    if not (
        frame["month"].astype(int) == month
    ).all():
        issues.append(
            "pair partition month values mismatch"
        )

    if not (
        frame["dense_scope"].astype(str)
        == dense_scope
    ).all():
        issues.append(
            "pair dense_scope values mismatch"
        )

    if not (
        frame["build_id"].astype(str)
        == build_id
    ).all():
        issues.append(
            "pair build_id values mismatch"
        )

    if not (
        frame["is_relevant_family"].astype(bool)
    ).all():
        issues.append(
            "pair output contains an irrelevant family"
        )

    if not (
        frame[
            "is_relevant_family_priceband"
        ].astype(bool)
    ).all():
        issues.append(
            "pair output contains an irrelevant pair"
        )

    expected_lifecycle = (
        (
            frame["data"]
            >= frame["pair_first_sale_date"]
        )
        & (
            frame["data"]
            <= frame["pair_last_sale_date"]
        )
    )

    actual_lifecycle = frame[
        "is_within_pair_lifecycle"
    ].astype(bool)

    lifecycle_mismatch = int(
        (
            expected_lifecycle
            != actual_lifecycle
        ).sum()
    )

    if lifecycle_mismatch:
        issues.append(
            "pair lifecycle flag mismatch="
            f"{lifecycle_mismatch}"
        )

    observed_mask = frame[
        "is_observed_sale"
    ].astype(bool)

    generated_mask = ~observed_mask

    for column in PAIR_OBSERVED_COLUMNS:
        generated_non_null = int(
            frame.loc[
                generated_mask,
                column,
            ].notna().sum()
        )

        if generated_non_null:
            issues.append(
                f"pair generated rows contain "
                f"{column}: {generated_non_null}"
            )

    for source_column, dense_column in (
        DENSE_MEASURE_MAPPING.items()
    ):
        generated_non_zero = int(
            (
                pd.to_numeric(
                    frame.loc[
                        generated_mask,
                        dense_column,
                    ],
                    errors="coerce",
                ).fillna(float("nan"))
                != 0
            ).sum()
        )

        if generated_non_zero:
            issues.append(
                f"pair generated dense measure "
                f"{dense_column} is not zero: "
                f"{generated_non_zero}"
            )

        observed_null_count = int(
            frame.loc[
                observed_mask,
                source_column,
            ].isna().sum()
        )

        if observed_null_count:
            issues.append(
                f"pair observed rows contain null "
                f"{source_column}: {observed_null_count}"
            )

        mismatch_count = _numeric_mismatch_count(
            frame.loc[
                observed_mask,
                source_column,
            ],
            frame.loc[
                observed_mask,
                dense_column,
            ],
        )

        if mismatch_count:
            issues.append(
                f"pair observed/dense mismatch "
                f"{source_column}->{dense_column}: "
                f"{mismatch_count}"
            )

    observed = frame.loc[
        observed_mask,
        [
            *PAIR_KEY,
            *PAIR_OBSERVED_COLUMNS,
        ],
    ].copy()

    stats = {
        "row_count": int(len(frame)),
        "duplicate_key_count": duplicate_count,
        "critical_nulls": nulls,
        "observed_row_count": int(
            observed_mask.sum()
        ),
        "generated_row_count": int(
            generated_mask.sum()
        ),
    }

    return observed, stats, issues


def _validate_activity_catalogs(
    family_path: Path,
    pair_path: Path,
    manifest: dict[str, Any],
) -> tuple[
    pd.DataFrame,
    pd.DataFrame,
    dict[str, dict[str, Any]],
    list[str],
]:
    issues: list[str] = []

    family_files = _parquet_files(
        family_path
    )
    pair_files = _parquet_files(
        pair_path
    )

    family = _read_files_frame(
        family_files
    )
    pair = _read_files_frame(
        pair_files
    )

    family_required = (
        "famiglia",
        "first_sale_date",
        "last_sale_date",
        "observed_day_count",
        "source_row_count",
        "is_relevant_family",
    )

    pair_required = (
        "famiglia",
        "fascia_prezzo_iva_inc",
        "first_sale_date",
        "last_sale_date",
        "observed_day_count",
        "source_row_count",
        "is_relevant_family_priceband",
    )

    family_missing = sorted(
        set(family_required)
        - set(family.columns)
    )

    pair_missing = sorted(
        set(pair_required)
        - set(pair.columns)
    )

    if family_missing:
        issues.append(
            "family activity catalog missing columns: "
            f"{family_missing}"
        )

    if pair_missing:
        issues.append(
            "pair activity catalog missing columns: "
            f"{pair_missing}"
        )

    configuration = manifest[
        "configuration"
    ]

    family_min = configuration[
        "family_min_observed_days"
    ]
    pair_min = configuration[
        "pair_min_observed_days"
    ]

    family_stats: dict[str, Any] = {}
    pair_stats: dict[str, Any] = {}

    if not family_missing:
        family = family.copy()

        for column in (
            "first_sale_date",
            "last_sale_date",
        ):
            family[column] = pd.to_datetime(
                family[column],
                errors="coerce",
            ).dt.normalize()

        family_duplicates = int(
            family.duplicated(
                subset=list(FAMILY_ACTIVITY_KEY)
            ).sum()
        )

        if family_duplicates:
            issues.append(
                "family activity duplicate keys="
                f"{family_duplicates}"
            )

        family_nulls = _critical_null_counts(
            family,
            family_required,
        )

        for column, count in family_nulls.items():
            if count:
                issues.append(
                    "family activity nulls "
                    f"{column}={count}"
                )

        expected_relevance = (
            family["observed_day_count"]
            .astype(int)
            >= family_min
        )

        actual_relevance = family[
            "is_relevant_family"
        ].astype(bool)

        relevance_mismatch = int(
            (
                expected_relevance
                != actual_relevance
            ).sum()
        )

        if relevance_mismatch:
            issues.append(
                "family activity relevance mismatch="
                f"{relevance_mismatch}"
            )

        if not actual_relevance.all():
            issues.append(
                "materialized family activity catalog "
                "contains irrelevant families"
            )

        family_stats = {
            "row_count": int(len(family)),
            "duplicate_key_count": family_duplicates,
            "critical_nulls": family_nulls,
        }

    if not pair_missing:
        pair = pair.copy()

        for column in (
            "first_sale_date",
            "last_sale_date",
        ):
            pair[column] = pd.to_datetime(
                pair[column],
                errors="coerce",
            ).dt.normalize()

        pair_duplicates = int(
            pair.duplicated(
                subset=list(PAIR_ACTIVITY_KEY)
            ).sum()
        )

        if pair_duplicates:
            issues.append(
                "pair activity duplicate keys="
                f"{pair_duplicates}"
            )

        pair_nulls = _critical_null_counts(
            pair,
            pair_required,
        )

        for column, count in pair_nulls.items():
            if count:
                issues.append(
                    "pair activity nulls "
                    f"{column}={count}"
                )

        relevant_families = set(
            family["famiglia"]
        ) if "famiglia" in family else set()

        expected_relevance = (
            pair["famiglia"].isin(
                relevant_families
            )
            & (
                pair["observed_day_count"]
                .astype(int)
                >= pair_min
            )
        )

        actual_relevance = pair[
            "is_relevant_family_priceband"
        ].astype(bool)

        relevance_mismatch = int(
            (
                expected_relevance
                != actual_relevance
            ).sum()
        )

        if relevance_mismatch:
            issues.append(
                "pair activity relevance mismatch="
                f"{relevance_mismatch}"
            )

        if not actual_relevance.all():
            issues.append(
                "materialized pair activity catalog "
                "contains irrelevant pairs"
            )

        pair_stats = {
            "row_count": int(len(pair)),
            "duplicate_key_count": pair_duplicates,
            "critical_nulls": pair_nulls,
        }

    return (
        family,
        pair,
        {
            "family_activity_catalog": (
                family_stats
            ),
            (
                "family_priceband_activity_catalog"
            ): pair_stats,
        },
        issues,
    )


def _compare_source_rows(
    actual: pd.DataFrame,
    expected: pd.DataFrame,
    keys: tuple[str, ...],
    value_columns: tuple[str, ...],
    label: str,
) -> tuple[dict[str, Any], list[str]]:
    issues: list[str] = []

    actual = actual.copy()
    expected = expected.copy()

    actual["data"] = pd.to_datetime(
        actual["data"],
        errors="coerce",
    ).dt.normalize()

    expected["data"] = pd.to_datetime(
        expected["data"],
        errors="coerce",
    ).dt.normalize()

    merged = expected.merge(
        actual,
        on=list(keys),
        how="outer",
        suffixes=("_expected", "_actual"),
        indicator=True,
    )

    key_mismatch = int(
        (
            merged["_merge"] != "both"
        ).sum()
    )

    if key_mismatch:
        issues.append(
            f"{label} source key mismatch="
            f"{key_mismatch}"
        )

    value_mismatches: dict[str, int] = {}

    for column in value_columns:
        expected_column = (
            merged[f"{column}_expected"]
        )
        actual_column = (
            merged[f"{column}_actual"]
        )

        mismatch = _numeric_mismatch_count(
            expected_column,
            actual_column,
        )

        value_mismatches[column] = mismatch

        if mismatch:
            issues.append(
                f"{label} source value mismatch "
                f"{column}={mismatch}"
            )

    return {
        "expected_rows": int(len(expected)),
        "actual_rows": int(len(actual)),
        "key_mismatch_count": key_mismatch,
        "value_mismatches": value_mismatches,
    }, issues


def _validate_source_reconciliation(
    source_run: Path,
    observed_family: pd.DataFrame,
    observed_pair: pd.DataFrame,
    family_activity: pd.DataFrame,
    pair_activity: pd.DataFrame,
    manifest: dict[str, Any],
) -> tuple[dict[str, Any], list[str]]:
    issues: list[str] = []

    family_columns = [
        *FAMILY_KEY,
        *FAMILY_OBSERVED_COLUMNS,
    ]

    pair_columns = [
        *PAIR_KEY,
        *PAIR_OBSERVED_COLUMNS,
    ]

    family_files = _parquet_files(
        source_run / "family_day"
    )
    pair_files = _parquet_files(
        source_run / "family_priceband_day"
    )

    source_family = _read_files_frame(
        family_files
    )

    source_pair = _read_files_frame(
        pair_files
    )

    family_missing = sorted(
        set(family_columns)
        - set(source_family.columns)
    )

    pair_missing = sorted(
        set(pair_columns)
        - set(source_pair.columns)
    )

    if family_missing:
        issues.append(
            "source family_day missing columns: "
            f"{family_missing}"
        )

    if pair_missing:
        issues.append(
            "source family_priceband_day missing columns: "
            f"{pair_missing}"
        )

    if family_missing or pair_missing:
        return {}, issues

    source_family = source_family[
        family_columns
    ].copy()

    source_pair = source_pair[
        pair_columns
    ].copy()

    # _THRESHOLD_AWARE_SOURCE_RECONCILIATION_V1
    #
    # Materialized observed rows contain only entities
    # admitted by the activity catalogs. Reconciliation
    # must therefore compare them against the matching
    # subset of source facts. The complete source frames
    # remain unchanged below for activity derivation and
    # family/pair aggregate consistency checks.
    relevant_family_keys = (
        family_activity.loc[
            :,
            ["famiglia"],
        ]
        .drop_duplicates()
        .reset_index(drop=True)
    )

    relevant_pair_keys = (
        pair_activity.loc[
            :,
            [
                "famiglia",
                "fascia_prezzo_iva_inc",
            ],
        ]
        .drop_duplicates()
        .reset_index(drop=True)
    )

    reconciled_source_family = (
        source_family.merge(
            relevant_family_keys,
            on=["famiglia"],
            how="inner",
            validate="many_to_one",
        )
    )

    reconciled_source_pair = (
        source_pair.merge(
            relevant_pair_keys,
            on=[
                "famiglia",
                "fascia_prezzo_iva_inc",
            ],
            how="inner",
            validate="many_to_one",
        )
    )

    family_summary, family_issues = (
        _compare_source_rows(
            observed_family,
            reconciled_source_family,
            FAMILY_KEY,
            FAMILY_OBSERVED_COLUMNS,
            "family",
        )
    )

    pair_summary, pair_issues = (
        _compare_source_rows(
            observed_pair,
            reconciled_source_pair,
            PAIR_KEY,
            PAIR_OBSERVED_COLUMNS,
            "pair",
        )
    )

    issues.extend(family_issues)
    issues.extend(pair_issues)

    configuration = manifest[
        "configuration"
    ]

    family_min = configuration[
        "family_min_observed_days"
    ]
    pair_min = configuration[
        "pair_min_observed_days"
    ]

    source_family["data"] = pd.to_datetime(
        source_family["data"],
        errors="coerce",
    ).dt.normalize()

    source_pair["data"] = pd.to_datetime(
        source_pair["data"],
        errors="coerce",
    ).dt.normalize()

    expected_family_activity = (
        source_family
        .groupby("famiglia", dropna=False)
        .agg(
            first_sale_date=("data", "min"),
            last_sale_date=("data", "max"),
            observed_day_count=("data", "nunique"),
            source_row_count=("data", "size"),
        )
        .reset_index()
    )

    expected_family_activity = (
        expected_family_activity.loc[
            expected_family_activity[
                "observed_day_count"
            ]
            >= family_min
        ].copy()
    )

    expected_family_keys = set(
        expected_family_activity[
            "famiglia"
        ]
    )

    actual_family_keys = set(
        family_activity[
            "famiglia"
        ]
    )

    family_catalog_key_mismatch = (
        len(
            expected_family_keys
            ^ actual_family_keys
        )
    )

    if family_catalog_key_mismatch:
        issues.append(
            "family activity/source key mismatch="
            f"{family_catalog_key_mismatch}"
        )

    expected_pair_activity = (
        source_pair
        .groupby(
            [
                "famiglia",
                "fascia_prezzo_iva_inc",
            ],
            dropna=False,
        )
        .agg(
            first_sale_date=("data", "min"),
            last_sale_date=("data", "max"),
            observed_day_count=("data", "nunique"),
            source_row_count=("data", "size"),
        )
        .reset_index()
    )

    expected_pair_activity = (
        expected_pair_activity.loc[
            expected_pair_activity[
                "famiglia"
            ].isin(expected_family_keys)
            & (
                expected_pair_activity[
                    "observed_day_count"
                ]
                >= pair_min
            )
        ].copy()
    )

    expected_pair_keys = set(
        zip(
            expected_pair_activity[
                "famiglia"
            ],
            expected_pair_activity[
                "fascia_prezzo_iva_inc"
            ],
        )
    )

    actual_pair_keys = set(
        zip(
            pair_activity["famiglia"],
            pair_activity[
                "fascia_prezzo_iva_inc"
            ],
        )
    )

    pair_catalog_key_mismatch = len(
        expected_pair_keys
        ^ actual_pair_keys
    )

    if pair_catalog_key_mismatch:
        issues.append(
            "pair activity/source key mismatch="
            f"{pair_catalog_key_mismatch}"
        )

    pair_to_family = (
        source_pair
        .groupby(
            ["data", "famiglia"],
            as_index=False,
        )
        .agg(
            qty_venduta_pair=(
                "qty_venduta",
                "sum",
            ),
            imponibile_pair=(
                "imponibile_netto_tot",
                "sum",
            ),
            num_articoli_pair=(
                "num_articoli",
                "sum",
            ),
        )
    )

    family_pair = source_family.merge(
        pair_to_family,
        on=["data", "famiglia"],
        how="outer",
        indicator=True,
    )

    family_pair_key_mismatch = int(
        (
            family_pair["_merge"] != "both"
        ).sum()
    )

    if family_pair_key_mismatch:
        issues.append(
            "family/pair aggregate key mismatch="
            f"{family_pair_key_mismatch}"
        )

    family_pair_value_mismatches = {
        "qty_venduta": _numeric_mismatch_count(
            family_pair["qty_venduta"],
            family_pair["qty_venduta_pair"],
        ),
        (
            "imponibile_netto_tot"
        ): _numeric_mismatch_count(
            family_pair[
                "imponibile_netto_tot"
            ],
            family_pair["imponibile_pair"],
        ),
        "num_articoli": _numeric_mismatch_count(
            family_pair["num_articoli"],
            family_pair["num_articoli_pair"],
        ),
    }

    for column, mismatch in (
        family_pair_value_mismatches.items()
    ):
        if mismatch:
            issues.append(
                "family/pair aggregate mismatch "
                f"{column}={mismatch}"
            )

    return {
        "family": family_summary,
        "family_priceband": pair_summary,
        "family_activity_key_mismatch": (
            family_catalog_key_mismatch
        ),
        "pair_activity_key_mismatch": (
            pair_catalog_key_mismatch
        ),
        "family_pair_key_mismatch": (
            family_pair_key_mismatch
        ),
        "family_pair_value_mismatches": (
            family_pair_value_mismatches
        ),
    }, issues


def _validate_plan_only(
    config: DenseGridValidationConfig,
    manifest: dict[str, Any],
    output_paths: dict[str, Path],
    schema_fingerprint: str | None,
) -> tuple[
    tuple[DenseGridDatasetValidationResult, ...],
    dict[str, Any],
    list[str],
]:
    issues: list[str] = []
    datasets = []

    outputs = {
        item["name"]: item
        for item in manifest["outputs"]
    }

    for output_name in REQUIRED_OUTPUTS:
        output = outputs[output_name]

        datasets.append(
            DenseGridDatasetValidationResult(
                name=output_name,
                ok=True,
                path=str(
                    output_paths[output_name]
                ),
                row_count=int(
                    output.get("row_count", 0)
                ),
                metadata_row_count=0,
                file_count=0,
                partition_count=int(
                    output.get("part_count", 0)
                ),
                schema_fingerprint=(
                    schema_fingerprint
                ),
            )
        )

    parquet_files = _parquet_files(
        Path(config.run_dir).resolve()
    )

    if parquet_files:
        issues.append(
            "plan-only run contains parquet files: "
            + ", ".join(
                str(file)
                for file in parquet_files
            )
        )

    return (
        tuple(datasets),
        {
            "performed": False,
            "reason": "plan_only",
        },
        issues,
    )


def _validate_materialized(
    config: DenseGridValidationConfig,
    manifest: dict[str, Any],
    source_run: Path,
    output_paths: dict[str, Path],
    planned_schemas: dict[
        str,
        list[dict[str, Any]],
    ],
    schema_fingerprint: str | None,
    monthly_plan: list[dict[str, Any]],
) -> tuple[
    tuple[DenseGridDatasetValidationResult, ...],
    dict[str, Any],
    list[str],
]:
    issues: list[str] = []
    dataset_results = []

    outputs = {
        item["name"]: item
        for item in manifest["outputs"]
    }

    metadata_by_output: dict[str, dict[str, Any]] = {}
    dataset_issues: dict[str, list[str]] = {
        name: []
        for name in REQUIRED_OUTPUTS
    }

    for output_name in REQUIRED_OUTPUTS:
        path = output_paths[output_name]
        partitioned = output_name in {
            "family_day_dense_grid",
            "family_priceband_day_dense_grid",
        }

        if not path.is_dir():
            dataset_issues[output_name].append(
                f"output directory missing: {path}"
            )

        metadata = _parquet_metadata_summary(
            path,
            partitioned,
        )
        metadata_by_output[output_name] = metadata

        if metadata["file_count"] == 0:
            dataset_issues[output_name].append(
                "no parquet files found"
            )

        output = outputs[output_name]

        expected_rows = int(
            output.get("row_count", 0)
        )

        if metadata["row_count"] != expected_rows:
            dataset_issues[output_name].append(
                "metadata row count mismatch: "
                f"expected={expected_rows}, "
                f"actual={metadata['row_count']}"
            )

        expected_file_count = output.get(
            "file_count"
        )

        if (
            expected_file_count is not None
            and metadata["file_count"]
            != expected_file_count
        ):
            dataset_issues[output_name].append(
                "file count mismatch: "
                f"expected={expected_file_count}, "
                f"actual={metadata['file_count']}"
            )

        if metadata["compressions"] != ["zstd"]:
            dataset_issues[output_name].append(
                "parquet compression must be zstd: "
                f"{metadata['compressions']}"
            )

        _, schema_issues = _validate_dataset_schema(
            output_name,
            planned_schemas[output_name],
            metadata,
            partitioned,
        )

        dataset_issues[output_name].extend(
            schema_issues
        )

    family_activity, pair_activity, activity_stats, activity_issues = (
        _validate_activity_catalogs(
            output_paths[
                "family_activity_catalog"
            ],
            output_paths[
                "family_priceband_activity_catalog"
            ],
            manifest,
        )
    )

    issues.extend(activity_issues)

    for output_name in (
        "family_activity_catalog",
        "family_priceband_activity_catalog",
    ):
        stats = activity_stats.get(
            output_name,
            {},
        )

        dataset_issues[output_name].extend(
            []
        )

        result_issues = dataset_issues[
            output_name
        ]

        dataset_results.append(
            DenseGridDatasetValidationResult(
                name=output_name,
                ok=not result_issues,
                path=str(
                    output_paths[output_name]
                ),
                row_count=int(
                    stats.get(
                        "row_count",
                        metadata_by_output[
                            output_name
                        ]["row_count"],
                    )
                ),
                metadata_row_count=int(
                    metadata_by_output[
                        output_name
                    ]["row_count"]
                ),
                file_count=int(
                    metadata_by_output[
                        output_name
                    ]["file_count"]
                ),
                partition_count=0,
                duplicate_key_count=int(
                    stats.get(
                        "duplicate_key_count",
                        0,
                    )
                ),
                critical_nulls=stats.get(
                    "critical_nulls",
                    {},
                ),
                schema_fingerprint=(
                    schema_fingerprint
                ),
                issues=tuple(result_issues),
            )
        )

        issues.extend(
            f"{output_name}: {issue}"
            for issue in result_issues
        )

    dense_scope = manifest[
        "configuration"
    ]["dense_scope"]

    build_id = manifest["build_id"]

    plans_by_grain: dict[
        str,
        list[dict[str, Any]],
    ] = {
        "family_day_dense_grid": [],
        "family_priceband_day_dense_grid": [],
    }

    for item in monthly_plan:
        plans_by_grain[
            item["grain"]
        ].append(item)

    observed_family_frames = []
    observed_pair_frames = []

    dense_stats: dict[str, dict[str, Any]] = {
        "family_day_dense_grid": {
            "row_count": 0,
            "duplicate_key_count": 0,
            "critical_nulls": {},
            "partition_count": 0,
        },
        "family_priceband_day_dense_grid": {
            "row_count": 0,
            "duplicate_key_count": 0,
            "critical_nulls": {},
            "partition_count": 0,
        },
    }

    for output_name in (
        "family_day_dense_grid",
        "family_priceband_day_dense_grid",
    ):
        root = output_paths[output_name]
        expected_partition_rows: dict[
            tuple[int, int],
            int,
        ] = {}

        for item in plans_by_grain[
            output_name
        ]:
            key = (
                int(item["year"]),
                int(item["month"]),
            )
            expected_partition_rows[key] = int(
                item["row_count"]
            )

        actual_partition_rows: dict[
            tuple[int, int],
            int,
        ] = {}

        for key_text, row_count in (
            metadata_by_output[
                output_name
            ]["partition_rows"].items()
        ):
            if key_text.startswith("INVALID:"):
                dataset_issues[
                    output_name
                ].append(
                    "parquet file is outside "
                    "year/month partition layout: "
                    f"{key_text}"
                )
                continue

            year_text, month_text = (
                key_text.split("-", 1)
            )
            actual_partition_rows[
                (
                    int(year_text),
                    int(month_text),
                )
            ] = int(row_count)

        expected_non_zero = {
            key: value
            for key, value
            in expected_partition_rows.items()
            if value > 0
        }

        if set(actual_partition_rows) != set(
            expected_non_zero
        ):
            dataset_issues[
                output_name
            ].append(
                "actual partition keys do not match "
                "monthly plan"
            )

        for key, expected_rows in (
            expected_non_zero.items()
        ):
            actual_rows = actual_partition_rows.get(
                key
            )

            if actual_rows != expected_rows:
                dataset_issues[
                    output_name
                ].append(
                    "partition row mismatch "
                    f"{key}: expected={expected_rows}, "
                    f"actual={actual_rows}"
                )

            frame = _read_partition_frame(
                root,
                key[0],
                key[1],
            )

            if output_name == (
                "family_day_dense_grid"
            ):
                observed, stats, part_issues = (
                    _validate_family_partition(
                        frame,
                        key[0],
                        key[1],
                        dense_scope,
                        build_id,
                    )
                )
                observed_family_frames.append(
                    observed
                )
            else:
                observed, stats, part_issues = (
                    _validate_pair_partition(
                        frame,
                        key[0],
                        key[1],
                        dense_scope,
                        build_id,
                    )
                )
                observed_pair_frames.append(
                    observed
                )

            dataset_issues[
                output_name
            ].extend(
                f"{key[0]:04d}-{key[1]:02d}: "
                f"{issue}"
                for issue in part_issues
            )

            dense_stats[
                output_name
            ]["row_count"] += int(
                stats.get("row_count", 0)
            )

            dense_stats[
                output_name
            ]["duplicate_key_count"] += int(
                stats.get(
                    "duplicate_key_count",
                    0,
                )
            )

            for column, count in (
                stats.get(
                    "critical_nulls",
                    {},
                ).items()
            ):
                dense_stats[
                    output_name
                ]["critical_nulls"][column] = (
                    dense_stats[
                        output_name
                    ]["critical_nulls"].get(
                        column,
                        0,
                    )
                    + int(count)
                )

        dense_stats[
            output_name
        ]["partition_count"] = len(
            actual_partition_rows
        )

        output = outputs[output_name]

        expected_partition_count = output.get(
            "partition_count",
            output.get("part_count"),
        )

        if (
            expected_partition_count is not None
            and len(actual_partition_rows)
            != int(expected_partition_count)
        ):
            dataset_issues[
                output_name
            ].append(
                "partition count mismatch: "
                f"expected={expected_partition_count}, "
                f"actual={len(actual_partition_rows)}"
            )

        result_issues = dataset_issues[
            output_name
        ]

        dataset_results.append(
            DenseGridDatasetValidationResult(
                name=output_name,
                ok=not result_issues,
                path=str(root),
                row_count=int(
                    dense_stats[
                        output_name
                    ]["row_count"]
                ),
                metadata_row_count=int(
                    metadata_by_output[
                        output_name
                    ]["row_count"]
                ),
                file_count=int(
                    metadata_by_output[
                        output_name
                    ]["file_count"]
                ),
                partition_count=int(
                    dense_stats[
                        output_name
                    ]["partition_count"]
                ),
                duplicate_key_count=int(
                    dense_stats[
                        output_name
                    ]["duplicate_key_count"]
                ),
                critical_nulls=dense_stats[
                    output_name
                ]["critical_nulls"],
                schema_fingerprint=(
                    schema_fingerprint
                ),
                issues=tuple(result_issues),
            )
        )

        issues.extend(
            f"{output_name}: {issue}"
            for issue in result_issues
        )

    observed_family = (
        pd.concat(
            observed_family_frames,
            ignore_index=True,
        )
        if observed_family_frames
        else pd.DataFrame()
    )

    observed_pair = (
        pd.concat(
            observed_pair_frames,
            ignore_index=True,
        )
        if observed_pair_frames
        else pd.DataFrame()
    )

    pair_catalog_keys = set(
        zip(
            pair_activity.get(
                "famiglia",
                pd.Series(dtype="object"),
            ),
            pair_activity.get(
                "fascia_prezzo_iva_inc",
                pd.Series(dtype="object"),
            ),
        )
    )

    observed_pair_keys = set(
        zip(
            observed_pair.get(
                "famiglia",
                pd.Series(dtype="object"),
            ),
            observed_pair.get(
                "fascia_prezzo_iva_inc",
                pd.Series(dtype="object"),
            ),
        )
    )

    unauthorized_pairs = len(
        observed_pair_keys
        - pair_catalog_keys
    )

    if unauthorized_pairs:
        issues.append(
            "observed dense pair rows contain "
            "unauthorized pairs="
            f"{unauthorized_pairs}"
        )

    source_reconciliation: dict[str, Any]

    if config.validate_source_reconciliation:
        (
            source_reconciliation,
            reconciliation_issues,
        ) = _validate_source_reconciliation(
            source_run,
            observed_family,
            observed_pair,
            family_activity,
            pair_activity,
            manifest,
        )

        source_reconciliation[
            "unauthorized_observed_pairs"
        ] = unauthorized_pairs

        issues.extend(
            reconciliation_issues
        )
    else:
        source_reconciliation = {
            "performed": False,
            "reason": (
                "validate_source_reconciliation=false"
            ),
            "unauthorized_observed_pairs": (
                unauthorized_pairs
            ),
        }

    return (
        tuple(dataset_results),
        source_reconciliation,
        issues,
    )


def _write_validation_report(
    result: DenseGridValidationResult,
    decision: str,
) -> None:
    payload = {
        "schema_version": 1,
        "stage": "dense_grid_validation",
        "mode": result.mode,
        "ok": result.ok,
        "issue_count": len(result.issues),
        "validated_at_utc": (
            result.validated_at_utc
        ),
        "run_dir": result.run_dir,
        "logical_run_dir": (
            result.logical_run_dir
        ),
        "source_run_dir": (
            result.source_run_dir
        ),
        "manifest_path": (
            result.manifest_path
        ),
        "manifest_summary": (
            result.manifest_summary
        ),
        "datasets": [
            dataset.to_dict()
            for dataset in result.datasets
        ],
        "source_reconciliation": (
            result.source_reconciliation
        ),
        "safety": result.safety,
        "issues": list(result.issues),
        "decision": decision,
    }

    _write_json_atomic(
        Path(result.report_path),
        payload,
    )


def validate_dense_grids(
    config: DenseGridValidationConfig,
) -> DenseGridValidationResult:
    """Validate a dense-grid plan or materialized candidate run."""

    run_dir = Path(
        config.run_dir
    ).resolve()

    manifest_path = _resolve_manifest_path(
        run_dir
    )

    report_path = (
        Path(config.report_path).resolve()
        if config.report_path is not None
        else (
            run_dir
            / "analysis"
            / "dense_grid_validation.json"
        )
    )

    issues: list[str] = []

    manifest, manifest_load_issues = (
        _load_manifest(manifest_path)
    )

    issues.extend(manifest_load_issues)

    manifest_mode = manifest.get(
        "mode"
    ) if manifest else None

    mode = (
        manifest_mode
        if config.mode == "auto"
        else config.mode
    )

    if mode not in {
        "plan_only",
        "materialized",
    }:
        issues.append(
            "resolved validation mode must be "
            "plan_only or materialized"
        )

    source_run, source_issues = (
        _resolve_source_run_dir(
            config,
            manifest,
        )
        if manifest
        else (None, [])
    )

    issues.extend(source_issues)

    planned_schemas: dict[
        str,
        list[dict[str, Any]],
    ] = {}

    schema_fingerprint: str | None = None
    monthly_plan: list[dict[str, Any]] = []
    monthly_totals: dict[str, int] = {}
    output_paths: dict[str, Path] = {}
    datasets: tuple[
        DenseGridDatasetValidationResult,
        ...,
    ] = tuple()
    source_reconciliation: dict[str, Any] = {}

    if manifest and mode in {
        "plan_only",
        "materialized",
    }:
        issues.extend(
            _validate_manifest_common(
                config,
                manifest,
                source_run,
                mode,
            )
        )

        (
            planned_schemas,
            schema_fingerprint,
            schema_issues,
        ) = _validate_planned_schemas(
            config,
            manifest,
        )

        issues.extend(schema_issues)

        (
            monthly_plan,
            monthly_totals,
            monthly_issues,
        ) = _validate_monthly_partition_plan(
            manifest
        )

        issues.extend(monthly_issues)

        (
            output_paths,
            output_path_issues,
        ) = _validate_output_paths(
            config,
            manifest,
            mode,
        )

        issues.extend(output_path_issues)

    pre_execution_issue_count = len(issues)

    if (
        pre_execution_issue_count == 0
        and mode == "plan_only"
    ):
        (
            datasets,
            source_reconciliation,
            mode_issues,
        ) = _validate_plan_only(
            config,
            manifest,
            output_paths,
            schema_fingerprint,
        )

        issues.extend(mode_issues)

    elif (
        pre_execution_issue_count == 0
        and mode == "materialized"
    ):
        if source_run is None:
            issues.append(
                "source run is required for "
                "materialized validation"
            )
        else:
            (
                datasets,
                source_reconciliation,
                mode_issues,
            ) = _validate_materialized(
                config,
                manifest,
                source_run,
                output_paths,
                planned_schemas,
                schema_fingerprint,
                monthly_plan,
            )

            issues.extend(mode_issues)

    logical_raw = (
        config.logical_run_dir
        or manifest.get("logical_run_dir")
        if manifest
        else config.logical_run_dir
    )

    logical_run_dir = (
        str(Path(logical_raw).resolve())
        if logical_raw
        else None
    )

    safety = {
        "db_read": "NO",
        "db_write": "NO",
        "feature_parquet_write": "NO",
        "source_run_write": "NO",
        "latest_pointer_update": "NO",
        "validation_report_write": "YES",
    }

    ok = not issues

    result = DenseGridValidationResult(
        ok=ok,
        mode=str(mode),
        run_dir=str(run_dir),
        logical_run_dir=logical_run_dir,
        source_run_dir=(
            str(source_run)
            if source_run is not None
            else ""
        ),
        manifest_path=str(manifest_path),
        report_path=str(report_path),
        validated_at_utc=_utc_now_iso(),
        manifest_summary={
            "schema_version": (
                manifest.get("schema_version")
                if manifest
                else None
            ),
            "stage": (
                manifest.get("stage")
                if manifest
                else None
            ),
            "mode": (
                manifest.get("mode")
                if manifest
                else None
            ),
            "build_id": (
                manifest.get("build_id")
                if manifest
                else None
            ),
            "dense_scope": (
                manifest
                .get("configuration", {})
                .get("dense_scope")
                if manifest
                else None
            ),
            "schema_fingerprint": (
                schema_fingerprint
            ),
            "monthly_totals": monthly_totals,
        },
        datasets=datasets,
        source_reconciliation=(
            source_reconciliation
        ),
        safety=safety,
        issues=tuple(issues),
    )

    if not ok:
        decision = (
            "DENSE_GRID_VALIDATION_FAILED"
        )
    elif mode == "plan_only":
        decision = (
            "DENSE_GRID_PLAN_VALIDATION_OK"
        )
    elif (
        logical_run_dir
        and Path(logical_run_dir).resolve()
        != run_dir
    ):
        decision = (
            "DENSE_GRID_TEMP_VALIDATION_OK"
        )
    else:
        decision = (
            "DENSE_GRID_MATERIALIZED_VALIDATION_OK"
        )

    _write_validation_report(
        result,
        decision,
    )

    return result
