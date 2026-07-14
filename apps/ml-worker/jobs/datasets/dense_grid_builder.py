"""Plan-only dense-grid builder for the GreenBrain global feature lake.

This first implementation deliberately supports dry-run planning only.

It validates the source parquet run, checks the required prior validation
reports, profiles the active family and family-priceband universes, computes
exact dense-grid row counts and writes a plan manifest.

It does not write dataset parquet. Materialized execution remains blocked until
the independent dense_grid_validation module exists and can validate temporary
outputs before atomic promotion.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import shutil
import tempfile
import uuid
from dataclasses import dataclass, field, replace
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd
import pyarrow as pa
import pyarrow.dataset as ds
import pyarrow.parquet as pq


SUPPORTED_DENSE_SCOPES = (
    "first_seen_to_dataset_end",
    "observed_lifecycle",
    "full_calendar",
)

REQUIRED_VALIDATIONS = (
    ("R3B", "r3b_validation.json"),
    ("R3C family_day", "r3c_family_day_validation.json"),
)

REQUIRED_SOURCE_COLUMNS: dict[str, tuple[str, ...]] = {
    "calendar": (
        "day",
    ),
    "family_day": (
        "data",
        "famiglia",
        "qty_venduta",
        "imponibile_netto_tot",
        "num_articoli",
        "priceband_count",
        "source_priceband_rows",
    ),
    "family_priceband_day": (
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
        "qty_venduta",
        "imponibile_netto_tot",
        "num_articoli",
    ),
}

OUTPUT_SCHEMAS: dict[str, tuple[dict[str, Any], ...]] = {
    "family_activity_catalog": (
        {"name": "famiglia", "type": "string", "nullable": False},
        {"name": "first_sale_date", "type": "date32", "nullable": False},
        {"name": "last_sale_date", "type": "date32", "nullable": False},
        {"name": "observed_day_count", "type": "int64", "nullable": False},
        {"name": "source_row_count", "type": "int64", "nullable": False},
        {"name": "is_relevant_family", "type": "bool", "nullable": False},
    ),
    "family_priceband_activity_catalog": (
        {"name": "famiglia", "type": "string", "nullable": False},
        {
            "name": "fascia_prezzo_iva_inc",
            "type": "source",
            "nullable": False,
        },
        {"name": "first_sale_date", "type": "date32", "nullable": False},
        {"name": "last_sale_date", "type": "date32", "nullable": False},
        {"name": "observed_day_count", "type": "int64", "nullable": False},
        {"name": "source_row_count", "type": "int64", "nullable": False},
        {
            "name": "is_relevant_family_priceband",
            "type": "bool",
            "nullable": False,
        },
    ),
    "family_day_dense_grid": (
        {"name": "data", "type": "date32", "nullable": False},
        {"name": "famiglia", "type": "string", "nullable": False},
        {"name": "is_observed_sale", "type": "bool", "nullable": False},
        {"name": "is_relevant_family", "type": "bool", "nullable": False},
        {
            "name": "is_within_family_lifecycle",
            "type": "bool",
            "nullable": False,
        },
        {
            "name": "family_first_sale_date",
            "type": "date32",
            "nullable": False,
        },
        {
            "name": "family_last_sale_date",
            "type": "date32",
            "nullable": False,
        },
        {
            "name": "family_observed_day_count",
            "type": "int64",
            "nullable": False,
        },
        {"name": "qty_venduta", "type": "source", "nullable": True},
        {
            "name": "imponibile_netto_tot",
            "type": "source",
            "nullable": True,
        },
        {"name": "num_articoli", "type": "source", "nullable": True},
        {
            "name": "qty_venduta_dense",
            "type": "source",
            "nullable": False,
        },
        {
            "name": "imponibile_dense",
            "type": "source",
            "nullable": False,
        },
        {
            "name": "num_articoli_dense",
            "type": "source",
            "nullable": False,
        },
        {"name": "priceband_count", "type": "source", "nullable": True},
        {
            "name": "source_priceband_rows",
            "type": "source",
            "nullable": True,
        },
        {"name": "dense_scope", "type": "string", "nullable": False},
        {"name": "build_id", "type": "string", "nullable": False},
        {"name": "year", "type": "int16", "nullable": False},
        {"name": "month", "type": "int8", "nullable": False},
    ),
    "family_priceband_day_dense_grid": (
        {"name": "data", "type": "date32", "nullable": False},
        {"name": "famiglia", "type": "string", "nullable": False},
        {
            "name": "fascia_prezzo_iva_inc",
            "type": "source",
            "nullable": False,
        },
        {"name": "is_observed_sale", "type": "bool", "nullable": False},
        {"name": "is_relevant_family", "type": "bool", "nullable": False},
        {
            "name": "is_relevant_family_priceband",
            "type": "bool",
            "nullable": False,
        },
        {
            "name": "is_within_pair_lifecycle",
            "type": "bool",
            "nullable": False,
        },
        {
            "name": "pair_first_sale_date",
            "type": "date32",
            "nullable": False,
        },
        {
            "name": "pair_last_sale_date",
            "type": "date32",
            "nullable": False,
        },
        {
            "name": "pair_observed_day_count",
            "type": "int64",
            "nullable": False,
        },
        {"name": "qty_venduta", "type": "source", "nullable": True},
        {
            "name": "imponibile_netto_tot",
            "type": "source",
            "nullable": True,
        },
        {"name": "num_articoli", "type": "source", "nullable": True},
        {
            "name": "qty_venduta_dense",
            "type": "source",
            "nullable": False,
        },
        {
            "name": "imponibile_dense",
            "type": "source",
            "nullable": False,
        },
        {
            "name": "num_articoli_dense",
            "type": "source",
            "nullable": False,
        },
        {"name": "dense_scope", "type": "string", "nullable": False},
        {"name": "build_id", "type": "string", "nullable": False},
        {"name": "year", "type": "int16", "nullable": False},
        {"name": "month", "type": "int8", "nullable": False},
    ),
}


@dataclass(frozen=True)
class DenseGridConfig:
    """Configuration for dense-grid planning and future execution."""

    source_run_dir: Path
    run_dir: Path
    build_id: str | None = None
    dense_scope: str = "first_seen_to_dataset_end"
    family_min_observed_days: int = 1
    pair_min_observed_days: int = 1
    compression: str = "zstd"
    execute: bool = False
    confirm_write_feature_lake: bool = False


@dataclass
class DenseGridOutputResult:
    """Planned or materialized result for one dense-grid output."""

    name: str
    status: str
    output_path: str
    row_count: int = 0
    part_count: int = 0
    grain: tuple[str, ...] = field(default_factory=tuple)
    partitioning: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status,
            "output_path": self.output_path,
            "row_count": int(self.row_count),
            "part_count": int(self.part_count),
            "grain": list(self.grain),
            "partitioning": list(self.partitioning),
        }


@dataclass
class DenseGridBuildResult:
    """Top-level result returned by build_dense_grids."""

    ok: bool
    dry_run: bool
    source_run_dir: str
    run_dir: str
    manifest_path: str
    outputs: tuple[DenseGridOutputResult, ...] = field(default_factory=tuple)
    safety: dict[str, Any] = field(default_factory=dict)
    issues: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": bool(self.ok),
            "dry_run": bool(self.dry_run),
            "source_run_dir": self.source_run_dir,
            "run_dir": self.run_dir,
            "manifest_path": self.manifest_path,
            "outputs": [output.to_dict() for output in self.outputs],
            "safety": _json_safe(self.safety),
            "issues": list(self.issues),
        }


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _default_build_id() -> str:
    return "gb_dense_grid_plan_" + datetime.now(timezone.utc).strftime(
        "%Y%m%d_%H%M%S"
    )


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


def _write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=str(path.parent),
    )
    temporary_path = Path(temporary_name)

    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
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


def _validate_config(config: DenseGridConfig) -> list[str]:
    issues: list[str] = []

    source_run = Path(config.source_run_dir).resolve()
    run_dir = Path(config.run_dir).resolve()

    if (
        source_run == run_dir
        or source_run in run_dir.parents
        or run_dir in source_run.parents
    ):
        raise ValueError(
            "source_run_dir and run_dir must be independent sibling "
            "or otherwise unrelated directories"
        )

    if not source_run.exists():
        issues.append(f"source run does not exist: {source_run}")

    if config.dense_scope not in SUPPORTED_DENSE_SCOPES:
        issues.append(
            "unsupported dense_scope: "
            f"{config.dense_scope}; expected one of "
            f"{SUPPORTED_DENSE_SCOPES}"
        )

    if config.family_min_observed_days < 1:
        issues.append("family_min_observed_days must be >= 1")

    if config.pair_min_observed_days < 1:
        issues.append("pair_min_observed_days must be >= 1")

    if not config.compression.strip():
        issues.append("compression must not be empty")

    if config.execute and not config.confirm_write_feature_lake:
        issues.append(
            "execute=true requires confirm_write_feature_lake=true"
        )

    required_paths = (
        source_run / "raw_extracts" / "calendar",
        source_run / "family_day",
        source_run / "family_priceband_day",
        source_run / "analysis" / "r3b_validation.json",
        source_run
        / "analysis"
        / "r3c_family_day_validation.json",
    )

    for required_path in required_paths:
        if not required_path.exists():
            issues.append(f"required input missing: {required_path}")

    return issues


def _require_validations(source_run: Path) -> tuple[list[dict[str, Any]], list[str]]:
    summaries: list[dict[str, Any]] = []
    issues: list[str] = []

    for label, filename in REQUIRED_VALIDATIONS:
        path = source_run / "analysis" / filename

        try:
            payload = _read_json(path)
        except Exception as exc:
            issues.append(
                f"cannot read required {label} validation report "
                f"{path}: {type(exc).__name__}: {exc}"
            )
            continue

        summary = {
            "label": label,
            "path": str(path),
            "ok": payload.get("ok"),
            "issue_count": payload.get("issue_count"),
        }
        summaries.append(summary)

        if payload.get("ok") is not True:
            issues.append(f"{label} validation ok is not true")

        if payload.get("issue_count") != 0:
            issues.append(
                f"{label} validation issue_count is not zero: "
                f"{payload.get('issue_count')}"
            )

    return summaries, issues


def _load_source_schema(path: Path) -> dict[str, str]:
    dataset = ds.dataset(path, format="parquet")
    return {
        field.name: str(field.type)
        for field in dataset.schema
    }


def _resolve_output_schemas(
    source_schemas: dict[str, dict[str, str]],
) -> dict[str, list[dict[str, Any]]]:
    """Resolve source-dependent output types from parquet schemas."""

    type_sources = {
        (
            "family_priceband_activity_catalog",
            "fascia_prezzo_iva_inc",
        ): source_schemas["family_priceband_day"][
            "fascia_prezzo_iva_inc"
        ],
        (
            "family_day_dense_grid",
            "qty_venduta",
        ): source_schemas["family_day"]["qty_venduta"],
        (
            "family_day_dense_grid",
            "imponibile_netto_tot",
        ): source_schemas["family_day"][
            "imponibile_netto_tot"
        ],
        (
            "family_day_dense_grid",
            "num_articoli",
        ): source_schemas["family_day"]["num_articoli"],
        (
            "family_day_dense_grid",
            "qty_venduta_dense",
        ): source_schemas["family_day"]["qty_venduta"],
        (
            "family_day_dense_grid",
            "imponibile_dense",
        ): source_schemas["family_day"][
            "imponibile_netto_tot"
        ],
        (
            "family_day_dense_grid",
            "num_articoli_dense",
        ): source_schemas["family_day"]["num_articoli"],
        (
            "family_day_dense_grid",
            "priceband_count",
        ): source_schemas["family_day"]["priceband_count"],
        (
            "family_day_dense_grid",
            "source_priceband_rows",
        ): source_schemas["family_day"][
            "source_priceband_rows"
        ],
        (
            "family_priceband_day_dense_grid",
            "fascia_prezzo_iva_inc",
        ): source_schemas["family_priceband_day"][
            "fascia_prezzo_iva_inc"
        ],
        (
            "family_priceband_day_dense_grid",
            "qty_venduta",
        ): source_schemas["family_priceband_day"][
            "qty_venduta"
        ],
        (
            "family_priceband_day_dense_grid",
            "imponibile_netto_tot",
        ): source_schemas["family_priceband_day"][
            "imponibile_netto_tot"
        ],
        (
            "family_priceband_day_dense_grid",
            "num_articoli",
        ): source_schemas["family_priceband_day"][
            "num_articoli"
        ],
        (
            "family_priceband_day_dense_grid",
            "qty_venduta_dense",
        ): source_schemas["family_priceband_day"][
            "qty_venduta"
        ],
        (
            "family_priceband_day_dense_grid",
            "imponibile_dense",
        ): source_schemas["family_priceband_day"][
            "imponibile_netto_tot"
        ],
        (
            "family_priceband_day_dense_grid",
            "num_articoli_dense",
        ): source_schemas["family_priceband_day"][
            "num_articoli"
        ],
    }

    resolved: dict[str, list[dict[str, Any]]] = {}

    for dataset_name, fields in OUTPUT_SCHEMAS.items():
        resolved_fields: list[dict[str, Any]] = []

        for field_spec in fields:
            resolved_field = dict(field_spec)

            if resolved_field["type"] == "source":
                key = (
                    dataset_name,
                    resolved_field["name"],
                )

                if key not in type_sources:
                    raise ValueError(
                        "unresolved output schema field: "
                        f"{dataset_name}."
                        f"{resolved_field['name']}"
                    )

                resolved_field["type"] = type_sources[key]

            resolved_fields.append(resolved_field)

        resolved[dataset_name] = resolved_fields

    return resolved


def _schema_fingerprint(
    resolved_output_schemas: dict[
        str,
        list[dict[str, Any]],
    ],
) -> str:
    """Return a deterministic SHA-256 fingerprint."""

    canonical_json = json.dumps(
        resolved_output_schemas,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )

    return hashlib.sha256(
        canonical_json.encode("utf-8")
    ).hexdigest()


def _required_column_issues(
    dataset_name: str,
    schema: dict[str, str],
) -> list[str]:
    missing = sorted(
        set(REQUIRED_SOURCE_COLUMNS[dataset_name])
        - set(schema)
    )

    if not missing:
        return []

    return [
        f"{dataset_name} missing required columns: {missing}"
    ]


def _load_calendar(source_run: Path) -> pd.DataFrame:
    path = source_run / "raw_extracts" / "calendar"

    calendar = (
        ds.dataset(path, format="parquet")
        .to_table(columns=["day"])
        .to_pandas()
    )

    calendar["day"] = pd.to_datetime(
        calendar["day"],
        errors="coerce",
    ).dt.normalize()

    null_count = int(calendar["day"].isna().sum())

    if null_count:
        raise ValueError(
            "calendar contains null or invalid day values: "
            f"{null_count}"
        )

    duplicate_count = int(
        calendar.duplicated(
            subset=["day"],
            keep=False,
        ).sum()
    )

    if duplicate_count:
        raise ValueError(
            "calendar contains duplicate day rows: "
            f"{duplicate_count}"
        )

    return (
        calendar
        .sort_values("day")
        .reset_index(drop=True)
    )


def _load_family_day(source_run: Path) -> pd.DataFrame:
    columns = list(REQUIRED_SOURCE_COLUMNS["family_day"])
    path = source_run / "family_day"

    frame = (
        ds.dataset(path, format="parquet")
        .to_table(columns=columns)
        .to_pandas()
    )

    frame["data"] = pd.to_datetime(
        frame["data"],
        errors="coerce",
    ).dt.normalize()

    return frame.sort_values(
        ["data", "famiglia"]
    ).reset_index(drop=True)


def _load_family_priceband_day(source_run: Path) -> pd.DataFrame:
    columns = list(
        REQUIRED_SOURCE_COLUMNS["family_priceband_day"]
    )
    path = source_run / "family_priceband_day"

    frame = (
        ds.dataset(path, format="parquet")
        .to_table(columns=columns)
        .to_pandas()
    )

    frame["data"] = pd.to_datetime(
        frame["data"],
        errors="coerce",
    ).dt.normalize()

    return frame.sort_values(
        [
            "data",
            "famiglia",
            "fascia_prezzo_iva_inc",
        ]
    ).reset_index(drop=True)


def _build_family_activity_catalog(
    family_day: pd.DataFrame,
    min_observed_days: int,
) -> pd.DataFrame:
    activity = (
        family_day
        .groupby("famiglia", dropna=False)
        .agg(
            first_sale_date=("data", "min"),
            last_sale_date=("data", "max"),
            observed_day_count=("data", "nunique"),
            source_row_count=("data", "size"),
        )
        .reset_index()
    )

    activity["is_relevant_family"] = (
        activity["observed_day_count"]
        >= min_observed_days
    )

    return activity.sort_values(
        ["famiglia"]
    ).reset_index(drop=True)


def _build_pair_activity_catalog(
    family_priceband_day: pd.DataFrame,
    relevant_families: set[Any],
    min_observed_days: int,
) -> pd.DataFrame:
    activity = (
        family_priceband_day
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

    activity["is_relevant_family_priceband"] = (
        activity["famiglia"].isin(relevant_families)
        & (
            activity["observed_day_count"]
            >= min_observed_days
        )
    )

    return activity.sort_values(
        [
            "famiglia",
            "fascia_prezzo_iva_inc",
        ]
    ).reset_index(drop=True)


def _estimate_dense_rows(
    activity: pd.DataFrame,
    dataset_start: pd.Timestamp,
    dataset_end: pd.Timestamp,
    dense_scope: str,
) -> int:
    if activity.empty:
        return 0

    if dense_scope == "first_seen_to_dataset_end":
        lengths = (
            dataset_end
            - activity["first_sale_date"]
        ).dt.days + 1
        return int(lengths.sum())

    if dense_scope == "observed_lifecycle":
        lengths = (
            activity["last_sale_date"]
            - activity["first_sale_date"]
        ).dt.days + 1
        return int(lengths.sum())

    if dense_scope == "full_calendar":
        day_count = int(
            (dataset_end - dataset_start).days + 1
        )
        return int(day_count * len(activity))

    raise ValueError(f"unsupported dense_scope: {dense_scope}")


def _month_count(
    dataset_start: pd.Timestamp,
    dataset_end: pd.Timestamp,
) -> int:
    return int(
        len(
            pd.period_range(
                dataset_start,
                dataset_end,
                freq="M",
            )
        )
    )


def _build_monthly_partition_plan(
    activity: pd.DataFrame,
    dataset_start: pd.Timestamp,
    dataset_end: pd.Timestamp,
    dense_scope: str,
    grain: str,
) -> list[dict[str, Any]]:
    """Calculate exact dense rows for every year/month partition."""

    rows: list[dict[str, Any]] = []

    month_starts = pd.date_range(
        dataset_start.to_period("M").start_time,
        dataset_end.to_period("M").start_time,
        freq="MS",
    )

    for raw_month_start in month_starts:
        month_start = max(
            raw_month_start,
            dataset_start,
        )
        month_end = min(
            raw_month_start + pd.offsets.MonthEnd(0),
            dataset_end,
        )

        row_count = 0
        active_entity_count = 0

        for item in activity.itertuples(index=False):
            first_sale_date = item.first_sale_date
            last_sale_date = item.last_sale_date

            if dense_scope == "first_seen_to_dataset_end":
                entity_start = max(
                    month_start,
                    first_sale_date,
                )
                entity_end = month_end

            elif dense_scope == "observed_lifecycle":
                entity_start = max(
                    month_start,
                    first_sale_date,
                )
                entity_end = min(
                    month_end,
                    last_sale_date,
                )

            elif dense_scope == "full_calendar":
                entity_start = month_start
                entity_end = month_end

            else:
                raise ValueError(
                    f"unsupported dense_scope: {dense_scope}"
                )

            if entity_start <= entity_end:
                active_entity_count += 1
                row_count += (
                    entity_end - entity_start
                ).days + 1

        rows.append(
            {
                "grain": grain,
                "dense_scope": dense_scope,
                "year": int(month_start.year),
                "month": int(month_start.month),
                "month_start": (
                    month_start.date().isoformat()
                ),
                "month_end": (
                    month_end.date().isoformat()
                ),
                "active_entity_count": int(
                    active_entity_count
                ),
                "row_count": int(row_count),
            }
        )

    return rows


def _planned_outputs(
    run_dir: Path,
    family_activity_rows: int,
    pair_activity_rows: int,
    family_dense_rows: int,
    pair_dense_rows: int,
    month_count: int,
    status: str,
) -> tuple[DenseGridOutputResult, ...]:
    dense_root = run_dir / "dense_grids"

    return (
        DenseGridOutputResult(
            name="family_activity_catalog",
            status=status,
            output_path=str(
                dense_root / "family_activity_catalog"
            ),
            row_count=family_activity_rows,
            part_count=1,
            grain=("famiglia",),
        ),
        DenseGridOutputResult(
            name="family_priceband_activity_catalog",
            status=status,
            output_path=str(
                dense_root
                / "family_priceband_activity_catalog"
            ),
            row_count=pair_activity_rows,
            part_count=1,
            grain=(
                "famiglia",
                "fascia_prezzo_iva_inc",
            ),
        ),
        DenseGridOutputResult(
            name="family_day_dense_grid",
            status=status,
            output_path=str(
                dense_root / "family_day_dense_grid"
            ),
            row_count=family_dense_rows,
            part_count=month_count,
            grain=("data", "famiglia"),
            partitioning=("year", "month"),
        ),
        DenseGridOutputResult(
            name="family_priceband_day_dense_grid",
            status=status,
            output_path=str(
                dense_root
                / "family_priceband_day_dense_grid"
            ),
            row_count=pair_dense_rows,
            part_count=month_count,
            grain=(
                "data",
                "famiglia",
                "fascia_prezzo_iva_inc",
            ),
            partitioning=("year", "month"),
        ),
    )


def _write_manifest(
    manifest_path: Path,
    result: DenseGridBuildResult,
    config: DenseGridConfig,
    build_id: str,
    prior_validations: list[dict[str, Any]],
    source_schemas: dict[str, dict[str, str]],
    resolved_output_schemas: dict[
        str,
        list[dict[str, Any]],
    ],
    output_schema_fingerprint: str | None,
    profile: dict[str, Any],
) -> None:
    payload = {
        "schema_version": 1,
        "stage": "dense_grid_builder",
        "mode": "plan_only",
        "ok": result.ok,
        "dry_run": result.dry_run,
        "built_at_utc": _utc_now_iso(),
        "build_id": build_id,
        "source_run_dir": result.source_run_dir,
        "run_dir": result.run_dir,
        "configuration": {
            "dense_scope": config.dense_scope,
            "family_min_observed_days": (
                config.family_min_observed_days
            ),
            "pair_min_observed_days": (
                config.pair_min_observed_days
            ),
            "compression": config.compression,
            "execute": config.execute,
            "confirm_write_feature_lake": (
                config.confirm_write_feature_lake
            ),
        },
        "required_validations": prior_validations,
        "source_schemas": source_schemas,
        "planned_output_schemas": (
            resolved_output_schemas
        ),
        "output_schema_fingerprint": (
            output_schema_fingerprint
        ),
        "output_schema_fingerprint_algorithm": (
            "sha256-canonical-json"
        ),
        "profile": profile,
        "outputs": [
            output.to_dict()
            for output in result.outputs
        ],
        "safety": result.safety,
        "issues": list(result.issues),
        "decision": (
            "DENSE_GRID_DRY_RUN_PLAN_READY"
            if result.ok
            else "DENSE_GRID_PLAN_BLOCKED"
        ),
    }

    _write_json_atomic(manifest_path, payload)


def _build_dense_grids_plan_only(
    config: DenseGridConfig,
) -> DenseGridBuildResult:
    """Validate inputs and generate the exact dense-grid plan manifest."""

    source_run = Path(config.source_run_dir).resolve()
    run_dir = Path(config.run_dir).resolve()
    build_id = config.build_id or _default_build_id()
    manifest_path = (
        run_dir
        / "metadata"
        / "dense_grid_manifest.json"
    )

    safety = {
        "db_read": "NO",
        "db_write": "NO",
        "source_run_write": "NO",
        "parquet_write": "NO",
        "latest_pointer_update": "NO",
        "build_global_change": "NO",
        "existing_pipeline_change": "NO",
        "execution_enabled": "NO",
    }

    issues = _validate_config(config)
    prior_validations: list[dict[str, Any]] = []
    source_schemas: dict[str, dict[str, str]] = {}
    resolved_output_schemas: dict[
        str,
        list[dict[str, Any]],
    ] = {}
    output_schema_fingerprint: str | None = None
    monthly_partition_plan: list[
        dict[str, Any]
    ] = []
    profile: dict[str, Any] = {}
    outputs: tuple[DenseGridOutputResult, ...] = tuple()

    if not issues:
        prior_validations, validation_issues = (
            _require_validations(source_run)
        )
        issues.extend(validation_issues)

    if config.execute:
        issues.append(
            "DENSE_GRID_VALIDATOR_REQUIRED_BEFORE_EXECUTE: "
            "materialized execution remains disabled until "
            "dense_grid_validation.py exists and validates "
            "temporary outputs"
        )

    if not issues:
        source_paths = {
            "calendar": (
                source_run
                / "raw_extracts"
                / "calendar"
            ),
            "family_day": source_run / "family_day",
            "family_priceband_day": (
                source_run / "family_priceband_day"
            ),
        }

        for dataset_name, path in source_paths.items():
            schema = _load_source_schema(path)
            source_schemas[dataset_name] = schema
            issues.extend(
                _required_column_issues(
                    dataset_name,
                    schema,
                )
            )

    if not issues:
        resolved_output_schemas = (
            _resolve_output_schemas(source_schemas)
        )
        output_schema_fingerprint = (
            _schema_fingerprint(
                resolved_output_schemas
            )
        )

    if not issues:
        calendar = _load_calendar(source_run)
        family_day = _load_family_day(source_run)
        family_priceband_day = (
            _load_family_priceband_day(source_run)
        )

        critical_nulls = {
            "calendar.day": int(
                calendar["day"].isna().sum()
            ),
            "family_day.data": int(
                family_day["data"].isna().sum()
            ),
            "family_day.famiglia": int(
                family_day["famiglia"].isna().sum()
            ),
            "family_priceband_day.data": int(
                family_priceband_day[
                    "data"
                ].isna().sum()
            ),
            "family_priceband_day.famiglia": int(
                family_priceband_day[
                    "famiglia"
                ].isna().sum()
            ),
            (
                "family_priceband_day."
                "fascia_prezzo_iva_inc"
            ): int(
                family_priceband_day[
                    "fascia_prezzo_iva_inc"
                ].isna().sum()
            ),
        }

        for column_name, null_count in critical_nulls.items():
            if null_count:
                issues.append(
                    f"critical null count "
                    f"{column_name}={null_count}"
                )

        family_duplicate_count = int(
            family_day.duplicated(
                subset=["data", "famiglia"]
            ).sum()
        )

        pair_duplicate_count = int(
            family_priceband_day.duplicated(
                subset=[
                    "data",
                    "famiglia",
                    "fascia_prezzo_iva_inc",
                ]
            ).sum()
        )

        if family_duplicate_count:
            issues.append(
                "family_day duplicate key count="
                f"{family_duplicate_count}"
            )

        if pair_duplicate_count:
            issues.append(
                "family_priceband_day duplicate key count="
                f"{pair_duplicate_count}"
            )

        if not issues:
            dataset_start = min(
                family_day["data"].min(),
                family_priceband_day["data"].min(),
            )

            dataset_end = max(
                family_day["data"].max(),
                family_priceband_day["data"].max(),
            )

            calendar_window = calendar.loc[
                (calendar["day"] >= dataset_start)
                & (calendar["day"] <= dataset_end),
                ["day"],
            ].copy()

            expected_days = pd.date_range(
                dataset_start,
                dataset_end,
                freq="D",
            )

            calendar_gap_count = int(
                len(
                    expected_days.difference(
                        pd.DatetimeIndex(
                            calendar_window["day"]
                        )
                    )
                )
            )

            if calendar_gap_count:
                issues.append(
                    f"calendar gap count={calendar_gap_count}"
                )

            family_activity = (
                _build_family_activity_catalog(
                    family_day,
                    config.family_min_observed_days,
                )
            )

            relevant_family_activity = (
                family_activity.loc[
                    family_activity[
                        "is_relevant_family"
                    ],
                    :,
                ].copy()
            )

            relevant_families = set(
                relevant_family_activity[
                    "famiglia"
                ].tolist()
            )

            pair_activity = (
                _build_pair_activity_catalog(
                    family_priceband_day,
                    relevant_families,
                    config.pair_min_observed_days,
                )
            )

            relevant_pair_activity = (
                pair_activity.loc[
                    pair_activity[
                        "is_relevant_family_priceband"
                    ],
                    :,
                ].copy()
            )

            family_dense_rows = _estimate_dense_rows(
                relevant_family_activity,
                dataset_start,
                dataset_end,
                config.dense_scope,
            )

            pair_dense_rows = _estimate_dense_rows(
                relevant_pair_activity,
                dataset_start,
                dataset_end,
                config.dense_scope,
            )

            partition_count = _month_count(
                dataset_start,
                dataset_end,
            )

            family_monthly_plan = (
                _build_monthly_partition_plan(
                    relevant_family_activity,
                    dataset_start,
                    dataset_end,
                    config.dense_scope,
                    "family_day_dense_grid",
                )
            )

            pair_monthly_plan = (
                _build_monthly_partition_plan(
                    relevant_pair_activity,
                    dataset_start,
                    dataset_end,
                    config.dense_scope,
                    (
                        "family_priceband_day_"
                        "dense_grid"
                    ),
                )
            )

            monthly_partition_plan = [
                *family_monthly_plan,
                *pair_monthly_plan,
            ]

            family_monthly_total = sum(
                int(item["row_count"])
                for item in family_monthly_plan
            )

            pair_monthly_total = sum(
                int(item["row_count"])
                for item in pair_monthly_plan
            )

            if family_monthly_total != family_dense_rows:
                issues.append(
                    "family monthly partition total "
                    "does not match dense estimate: "
                    f"monthly={family_monthly_total}, "
                    f"expected={family_dense_rows}"
                )

            if pair_monthly_total != pair_dense_rows:
                issues.append(
                    "family-priceband monthly partition "
                    "total does not match dense estimate: "
                    f"monthly={pair_monthly_total}, "
                    f"expected={pair_dense_rows}"
                )

            outputs = _planned_outputs(
                run_dir=run_dir,
                family_activity_rows=int(
                    len(relevant_family_activity)
                ),
                pair_activity_rows=int(
                    len(relevant_pair_activity)
                ),
                family_dense_rows=family_dense_rows,
                pair_dense_rows=pair_dense_rows,
                month_count=partition_count,
                status="planned",
            )

            profile = {
                "dataset_start": dataset_start,
                "dataset_end": dataset_end,
                "calendar_day_count": int(
                    len(calendar_window)
                ),
                "calendar_gap_count": (
                    calendar_gap_count
                ),
                "source_rows": {
                    "family_day": int(
                        len(family_day)
                    ),
                    "family_priceband_day": int(
                        len(family_priceband_day)
                    ),
                },
                "source_key_duplicates": {
                    "family_day": (
                        family_duplicate_count
                    ),
                    "family_priceband_day": (
                        pair_duplicate_count
                    ),
                },
                "critical_nulls": critical_nulls,
                "family_universe": {
                    "all_family_count": int(
                        len(family_activity)
                    ),
                    "relevant_family_count": int(
                        len(relevant_family_activity)
                    ),
                },
                "family_priceband_universe": {
                    "all_observed_pair_count": int(
                        len(pair_activity)
                    ),
                    "relevant_pair_count": int(
                        len(relevant_pair_activity)
                    ),
                    "global_priceband_count": int(
                        family_priceband_day[
                            "fascia_prezzo_iva_inc"
                        ].nunique(dropna=True)
                    ),
                    "policy": (
                        "observed family-priceband "
                        "pairs only"
                    ),
                },
                "dense_estimates": {
                    "family_day_dense_grid": (
                        family_dense_rows
                    ),
                    (
                        "family_priceband_day_"
                        "dense_grid"
                    ): pair_dense_rows,
                },
                "partitioning": {
                    "columns": ["year", "month"],
                    "planned_partition_count": (
                        partition_count
                    ),
                    "generation_strategy": (
                        "one calendar month at a time"
                    ),
                },
                "monthly_partition_estimates": (
                    monthly_partition_plan
                ),
                "zero_fill_policy": {
                    "preserve_nullable_observed": [
                        "qty_venduta",
                        "imponibile_netto_tot",
                        "num_articoli",
                    ],
                    "zero_fill_only": [
                        "qty_venduta_dense",
                        "imponibile_dense",
                        "num_articoli_dense",
                    ],
                },
                "lifecycle_semantics": {
                    "family": (
                        "between first and last "
                        "observed family sale"
                    ),
                    "family_priceband": (
                        "between first and last "
                        "observed pair sale"
                    ),
                },
            }

    ok = not issues and not config.execute

    if not outputs:
        outputs = _planned_outputs(
            run_dir=run_dir,
            family_activity_rows=0,
            pair_activity_rows=0,
            family_dense_rows=0,
            pair_dense_rows=0,
            month_count=0,
            status="blocked",
        )

    result = DenseGridBuildResult(
        ok=ok,
        dry_run=not config.execute,
        source_run_dir=str(source_run),
        run_dir=str(run_dir),
        manifest_path=str(manifest_path),
        outputs=outputs,
        safety=safety,
        issues=tuple(issues),
    )

    _write_manifest(
        manifest_path=manifest_path,
        result=result,
        config=config,
        build_id=build_id,
        prior_validations=prior_validations,
        source_schemas=source_schemas,
        resolved_output_schemas=(
            resolved_output_schemas
        ),
        output_schema_fingerprint=(
            output_schema_fingerprint
        ),
        profile=profile,
    )

    return result

# _DENSE_GRID_MATERIALIZATION_PATCH_V1

_MATERIALIZED_RELATIVE_PATHS = {
    "family_activity_catalog": (
        "dense_grids/family_activity_catalog"
    ),
    "family_priceband_activity_catalog": (
        "dense_grids/family_priceband_activity_catalog"
    ),
    "family_day_dense_grid": (
        "dense_grids/family_day_dense_grid"
    ),
    "family_priceband_day_dense_grid": (
        "dense_grids/family_priceband_day_dense_grid"
    ),
}


def _execution_failure_result(
    config: DenseGridConfig,
    issues: list[str] | tuple[str, ...],
) -> DenseGridBuildResult:
    """Return an execution failure without publishing a run."""

    source_run = Path(config.source_run_dir).resolve()
    run_dir = Path(config.run_dir).resolve()

    return DenseGridBuildResult(
        ok=False,
        dry_run=False,
        source_run_dir=str(source_run),
        run_dir=str(run_dir),
        manifest_path=str(
            run_dir
            / "metadata"
            / "dense_grid_manifest.json"
        ),
        outputs=tuple(),
        safety={
            "db_read": "NO",
            "db_write": "NO",
            "source_run_write": "NO",
            "parquet_write": "NO",
            "latest_pointer_update": "NO",
            "build_global_change": "NO",
            "existing_pipeline_change": "NO",
            "execution_enabled": "NO",
            "atomic_candidate_promotion": "NO",
        },
        issues=tuple(str(item) for item in issues),
    )


def _paths_overlap(
    first: Path,
    second: Path,
) -> bool:
    first = first.resolve()
    second = second.resolve()

    return (
        first == second
        or first in second.parents
        or second in first.parents
    )


def _resolve_materialization_paths(
    final_run_dir: Path,
    build_id: str,
) -> tuple[Path, Path, Path]:
    """Resolve same-filesystem candidate and quarantine paths."""

    final_run_dir = final_run_dir.resolve()
    parent = final_run_dir.parent.resolve()

    if final_run_dir.exists():
        raise FileExistsError(
            "final dense-grid run already exists: "
            f"{final_run_dir}"
        )

    safe_build_id = "".join(
        character
        if (
            character.isalnum()
            or character in {"-", "_"}
        )
        else "_"
        for character in build_id
    )

    unique_suffix = uuid.uuid4().hex[:12]

    candidate = (
        parent
        / (
            f".{final_run_dir.name}.candidate-"
            f"{safe_build_id}-{unique_suffix}"
        )
    )

    failed = (
        parent
        / (
            f".{final_run_dir.name}.failed-"
            f"{safe_build_id}-{unique_suffix}"
        )
    )

    if candidate.exists() or failed.exists():
        raise FileExistsError(
            "materialization sibling path already exists"
        )

    parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    return (
        final_run_dir,
        candidate,
        failed,
    )


def _arrow_schema_from_spec(
    field_specs: list[dict[str, Any]],
) -> pa.Schema:
    return pa.schema(
        [
            pa.field(
                item["name"],
                pa.type_for_alias(
                    item["type"]
                ),
                nullable=bool(
                    item.get("nullable", True)
                ),
            )
            for item in field_specs
        ]
    )


def _table_from_frame(
    frame: pd.DataFrame,
    field_specs: list[dict[str, Any]],
) -> pa.Table:
    schema = _arrow_schema_from_spec(
        field_specs
    )

    missing = [
        field.name
        for field in schema
        if field.name not in frame.columns
    ]

    if missing:
        raise ValueError(
            "materialized frame is missing schema "
            f"columns: {missing}"
        )

    ordered = frame.loc[
        :,
        schema.names,
    ].copy()

    for field in schema:
        name = field.name

        if pa.types.is_date32(field.type):
            ordered[name] = pd.to_datetime(
                ordered[name],
                errors="coerce",
            ).dt.date

        elif pa.types.is_boolean(field.type):
            if field.nullable:
                ordered[name] = ordered[
                    name
                ].astype("boolean")
            else:
                ordered[name] = ordered[
                    name
                ].astype(bool)

        elif pa.types.is_int8(field.type):
            ordered[name] = ordered[
                name
            ].astype(
                "Int8"
                if field.nullable
                else "int8"
            )

        elif pa.types.is_int16(field.type):
            ordered[name] = ordered[
                name
            ].astype(
                "Int16"
                if field.nullable
                else "int16"
            )

        elif pa.types.is_int64(field.type):
            ordered[name] = ordered[
                name
            ].astype(
                "Int64"
                if field.nullable
                else "int64"
            )

    return pa.Table.from_pandas(
        ordered,
        schema=schema,
        preserve_index=False,
        safe=True,
    )


def _write_parquet_file_atomic(
    frame: pd.DataFrame,
    output_file: Path,
    field_specs: list[dict[str, Any]],
    compression: str,
) -> dict[str, Any]:
    """Write one explicit-schema parquet file atomically."""

    output_file.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    table = _table_from_frame(
        frame,
        field_specs,
    )

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output_file.name}.",
        suffix=".tmp",
        dir=str(output_file.parent),
    )

    os.close(descriptor)
    temporary_file = Path(temporary_name)

    try:
        pq.write_table(
            table,
            temporary_file,
            compression=compression,
            write_statistics=True,
        )

        with temporary_file.open("rb") as handle:
            os.fsync(handle.fileno())

        os.replace(
            temporary_file,
            output_file,
        )
    except Exception:
        temporary_file.unlink(
            missing_ok=True
        )
        raise

    parquet_file = pq.ParquetFile(
        output_file
    )

    return {
        "path": str(output_file),
        "row_count": int(
            parquet_file.metadata.num_rows
        ),
        "file_size": int(
            output_file.stat().st_size
        ),
    }


def _build_activity_catalog_frames(
    family_day: pd.DataFrame,
    family_priceband_day: pd.DataFrame,
    family_min_observed_days: int,
    pair_min_observed_days: int,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    family_activity = (
        _build_family_activity_catalog(
            family_day,
            family_min_observed_days,
        )
    )

    relevant_family_activity = (
        family_activity.loc[
            family_activity[
                "is_relevant_family"
            ],
            :,
        ]
        .sort_values(["famiglia"])
        .reset_index(drop=True)
    )

    relevant_families = set(
        relevant_family_activity[
            "famiglia"
        ].tolist()
    )

    pair_activity = (
        _build_pair_activity_catalog(
            family_priceband_day,
            relevant_families,
            pair_min_observed_days,
        )
    )

    relevant_pair_activity = (
        pair_activity.loc[
            pair_activity[
                "is_relevant_family_priceband"
            ],
            :,
        ]
        .sort_values(
            [
                "famiglia",
                "fascia_prezzo_iva_inc",
            ]
        )
        .reset_index(drop=True)
    )

    return (
        relevant_family_activity,
        relevant_pair_activity,
    )


def _select_active_entities_for_month(
    activity: pd.DataFrame,
    month_start: pd.Timestamp,
    month_end: pd.Timestamp,
    dense_scope: str,
) -> pd.DataFrame:
    records: list[dict[str, Any]] = []

    for item in activity.to_dict(
        orient="records"
    ):
        first_sale_date = pd.Timestamp(
            item["first_sale_date"]
        ).normalize()

        last_sale_date = pd.Timestamp(
            item["last_sale_date"]
        ).normalize()

        if dense_scope == (
            "first_seen_to_dataset_end"
        ):
            entity_start = max(
                month_start,
                first_sale_date,
            )
            entity_end = month_end

        elif dense_scope == (
            "observed_lifecycle"
        ):
            entity_start = max(
                month_start,
                first_sale_date,
            )
            entity_end = min(
                month_end,
                last_sale_date,
            )

        elif dense_scope == "full_calendar":
            entity_start = month_start
            entity_end = month_end

        else:
            raise ValueError(
                "unsupported dense_scope: "
                f"{dense_scope}"
            )

        if entity_start > entity_end:
            continue

        record = dict(item)
        record["_entity_start"] = (
            entity_start
        )
        record["_entity_end"] = entity_end
        records.append(record)

    return pd.DataFrame(records)


def _expand_selected_entities(
    selected: pd.DataFrame,
    key_columns: list[str],
) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []

    for item in selected.to_dict(
        orient="records"
    ):
        entity_start = pd.Timestamp(
            item["_entity_start"]
        ).normalize()

        entity_end = pd.Timestamp(
            item["_entity_end"]
        ).normalize()

        shared = {
            key: item[key]
            for key in item
            if key
            not in {
                "_entity_start",
                "_entity_end",
            }
        }

        for day in pd.date_range(
            entity_start,
            entity_end,
            freq="D",
        ):
            row = dict(shared)
            row["data"] = day
            rows.append(row)

    if rows:
        return pd.DataFrame(rows)

    return pd.DataFrame(
        columns=[
            "data",
            *key_columns,
            *[
                column
                for column
                in selected.columns
                if column
                not in {
                    *key_columns,
                    "_entity_start",
                    "_entity_end",
                }
            ],
        ]
    )


def _materialize_family_month(
    family_activity: pd.DataFrame,
    family_day: pd.DataFrame,
    month_start: pd.Timestamp,
    month_end: pd.Timestamp,
    dense_scope: str,
    build_id: str,
) -> pd.DataFrame:
    selected = _select_active_entities_for_month(
        family_activity,
        month_start,
        month_end,
        dense_scope,
    )

    base = _expand_selected_entities(
        selected,
        ["famiglia"],
    )

    observations = family_day.loc[
        (
            family_day["data"]
            >= month_start
        )
        & (
            family_day["data"]
            <= month_end
        ),
        [
            "data",
            "famiglia",
            "qty_venduta",
            "imponibile_netto_tot",
            "num_articoli",
            "priceband_count",
            "source_priceband_rows",
        ],
    ].copy()

    merged = base.merge(
        observations,
        on=[
            "data",
            "famiglia",
        ],
        how="left",
        validate="one_to_one",
        indicator="_source_merge",
    )

    merged["is_observed_sale"] = (
        merged["_source_merge"] == "both"
    )

    merged[
        "is_relevant_family"
    ] = True

    merged[
        "is_within_family_lifecycle"
    ] = (
        (
            merged["data"]
            >= merged["first_sale_date"]
        )
        & (
            merged["data"]
            <= merged["last_sale_date"]
        )
    )

    merged[
        "family_first_sale_date"
    ] = merged["first_sale_date"]

    merged[
        "family_last_sale_date"
    ] = merged["last_sale_date"]

    merged[
        "family_observed_day_count"
    ] = merged["observed_day_count"]

    merged[
        "qty_venduta_dense"
    ] = merged["qty_venduta"].fillna(0)

    merged[
        "imponibile_dense"
    ] = merged[
        "imponibile_netto_tot"
    ].fillna(0)

    merged[
        "num_articoli_dense"
    ] = merged["num_articoli"].fillna(0)

    merged["dense_scope"] = dense_scope
    merged["build_id"] = build_id
    merged["year"] = merged[
        "data"
    ].dt.year.astype("int16")
    merged["month"] = merged[
        "data"
    ].dt.month.astype("int8")

    return (
        merged
        .drop(
            columns=[
                "_source_merge",
                "first_sale_date",
                "last_sale_date",
                "observed_day_count",
                "source_row_count",
            ],
            errors="ignore",
        )
        .sort_values(
            [
                "data",
                "famiglia",
            ]
        )
        .reset_index(drop=True)
    )


def _materialize_pair_month(
    pair_activity: pd.DataFrame,
    family_priceband_day: pd.DataFrame,
    month_start: pd.Timestamp,
    month_end: pd.Timestamp,
    dense_scope: str,
    build_id: str,
) -> pd.DataFrame:
    selected = _select_active_entities_for_month(
        pair_activity,
        month_start,
        month_end,
        dense_scope,
    )

    base = _expand_selected_entities(
        selected,
        [
            "famiglia",
            "fascia_prezzo_iva_inc",
        ],
    )

    observations = (
        family_priceband_day.loc[
            (
                family_priceband_day["data"]
                >= month_start
            )
            & (
                family_priceband_day["data"]
                <= month_end
            ),
            [
                "data",
                "famiglia",
                "fascia_prezzo_iva_inc",
                "qty_venduta",
                "imponibile_netto_tot",
                "num_articoli",
            ],
        ]
        .copy()
    )

    merged = base.merge(
        observations,
        on=[
            "data",
            "famiglia",
            "fascia_prezzo_iva_inc",
        ],
        how="left",
        validate="one_to_one",
        indicator="_source_merge",
    )

    merged["is_observed_sale"] = (
        merged["_source_merge"] == "both"
    )

    merged[
        "is_relevant_family"
    ] = True

    merged[
        "is_relevant_family_priceband"
    ] = True

    merged[
        "is_within_pair_lifecycle"
    ] = (
        (
            merged["data"]
            >= merged["first_sale_date"]
        )
        & (
            merged["data"]
            <= merged["last_sale_date"]
        )
    )

    merged[
        "pair_first_sale_date"
    ] = merged["first_sale_date"]

    merged[
        "pair_last_sale_date"
    ] = merged["last_sale_date"]

    merged[
        "pair_observed_day_count"
    ] = merged["observed_day_count"]

    merged[
        "qty_venduta_dense"
    ] = merged["qty_venduta"].fillna(0)

    merged[
        "imponibile_dense"
    ] = merged[
        "imponibile_netto_tot"
    ].fillna(0)

    merged[
        "num_articoli_dense"
    ] = merged["num_articoli"].fillna(0)

    merged["dense_scope"] = dense_scope
    merged["build_id"] = build_id
    merged["year"] = merged[
        "data"
    ].dt.year.astype("int16")
    merged["month"] = merged[
        "data"
    ].dt.month.astype("int8")

    return (
        merged
        .drop(
            columns=[
                "_source_merge",
                "first_sale_date",
                "last_sale_date",
                "observed_day_count",
                "source_row_count",
            ],
            errors="ignore",
        )
        .sort_values(
            [
                "data",
                "famiglia",
                "fascia_prezzo_iva_inc",
            ]
        )
        .reset_index(drop=True)
    )


def _collect_materialized_output_metadata(
    candidate_run_dir: Path,
    final_run_dir: Path,
    expected_rows: dict[str, int],
    output_schema_fingerprint: str,
    compression: str,
) -> list[dict[str, Any]]:
    outputs: list[dict[str, Any]] = []

    for name, relative_path in (
        _MATERIALIZED_RELATIVE_PATHS.items()
    ):
        root = (
            candidate_run_dir
            / relative_path
        )

        files = sorted(
            root.rglob("*.parquet")
        )

        row_count = sum(
            int(
                pq.ParquetFile(
                    file
                ).metadata.num_rows
            )
            for file in files
        )

        if row_count != expected_rows[name]:
            raise ValueError(
                f"{name}: actual row count "
                f"{row_count} does not match "
                f"planned {expected_rows[name]}"
            )

        partition_keys = set()

        if name in {
            "family_day_dense_grid",
            "family_priceband_day_dense_grid",
        }:
            for file in files:
                year_part = next(
                    (
                        part
                        for part in file.parts
                        if part.startswith("year=")
                    ),
                    None,
                )

                month_part = next(
                    (
                        part
                        for part in file.parts
                        if part.startswith("month=")
                    ),
                    None,
                )

                if (
                    year_part is not None
                    and month_part is not None
                ):
                    partition_keys.add(
                        (
                            year_part,
                            month_part,
                        )
                    )

        outputs.append(
            {
                "name": name,
                "relative_path": (
                    relative_path
                ),
                "output_path": str(
                    final_run_dir
                    / relative_path
                ),
                "candidate_output_path": str(
                    candidate_run_dir
                    / relative_path
                ),
                "row_count": int(row_count),
                "file_count": int(
                    len(files)
                ),
                "part_count": int(
                    len(files)
                ),
                "partition_count": int(
                    len(partition_keys)
                ),
                "actual_schema_fingerprint": (
                    output_schema_fingerprint
                ),
                "compression": compression,
                "status": "materialized",
            }
        )

    return outputs


def _build_materialized_manifest(
    plan_manifest: dict[str, Any],
    config: DenseGridConfig,
    build_id: str,
    source_run_dir: Path,
    candidate_run_dir: Path,
    final_run_dir: Path,
    outputs: list[dict[str, Any]],
    monthly_actuals: list[dict[str, Any]],
) -> dict[str, Any]:
    payload = json.loads(
        json.dumps(plan_manifest)
    )

    profile = payload.get(
        "profile",
        {},
    )

    partitioning = dict(
        profile.get(
            "partitioning",
            {},
        )
    )

    partitioning[
        "actual_partition_count"
    ] = int(
        len(
            {
                (
                    item["year"],
                    item["month"],
                )
                for item in monthly_actuals
                if item["grain"]
                == "family_day_dense_grid"
            }
        )
    )

    profile[
        "partitioning"
    ] = partitioning

    profile[
        "monthly_partition_actuals"
    ] = monthly_actuals

    payload.update(
        {
            "schema_version": 1,
            "stage": "dense_grid_builder",
            "mode": "materialized",
            "ok": True,
            "dry_run": False,
            "built_at_utc": _utc_now_iso(),
            "build_id": build_id,
            "source_run_dir": str(
                source_run_dir
            ),
            "run_dir": str(
                final_run_dir
            ),
            "logical_run_dir": str(
                final_run_dir
            ),
            "candidate_run_dir": str(
                candidate_run_dir
            ),
            "profile": profile,
            "outputs": outputs,
            "issues": [],
            "decision": (
                "DENSE_GRID_MATERIALIZED_"
                "READY_FOR_VALIDATION"
            ),
            "configuration": {
                "dense_scope": (
                    config.dense_scope
                ),
                "family_min_observed_days": (
                    config.family_min_observed_days
                ),
                "pair_min_observed_days": (
                    config.pair_min_observed_days
                ),
                "compression": (
                    config.compression
                ),
                "execute": True,
                "confirm_write_feature_lake": (
                    True
                ),
            },
            "validation": {
                "candidate_report_relative_path": (
                    "analysis/"
                    "dense_grid_candidate_validation.json"
                ),
                "candidate_required_decision": (
                    "DENSE_GRID_TEMP_VALIDATION_OK"
                ),
                "final_report_relative_path": (
                    "analysis/"
                    "dense_grid_validation.json"
                ),
                "final_required_decision": (
                    "DENSE_GRID_MATERIALIZED_"
                    "VALIDATION_OK"
                ),
            },
            "safety": {
                "db_read": "NO",
                "db_write": "NO",
                "source_run_write": "NO",
                "parquet_write": (
                    "YES_CONFIRMED"
                ),
                "latest_pointer_update": "NO",
                "build_global_change": "NO",
                "existing_pipeline_change": (
                    "NO"
                ),
                "execution_enabled": "YES",
                "atomic_candidate_promotion": (
                    "YES"
                ),
                "overwrite_existing_run": (
                    "NO"
                ),
            },
        }
    )

    return payload


def _validate_materialized_candidate(
    candidate_run_dir: Path,
    final_run_dir: Path,
    source_run_dir: Path,
    schema_fingerprint: str,
) -> Any:
    from jobs.datasets.dense_grid_validation import (
        DenseGridValidationConfig,
        validate_dense_grids,
    )

    result = validate_dense_grids(
        DenseGridValidationConfig(
            run_dir=candidate_run_dir,
            source_run_dir=source_run_dir,
            mode="materialized",
            logical_run_dir=final_run_dir,
            expected_schema_fingerprint=(
                schema_fingerprint
            ),
            validate_source_reconciliation=True,
        )
    )

    report = json.loads(
        Path(
            result.report_path
        ).read_text(
            encoding="utf-8"
        )
    )

    decision = report.get("decision")

    if (
        result.ok is not True
        or decision
        != "DENSE_GRID_TEMP_VALIDATION_OK"
    ):
        raise ValueError(
            "temporary dense-grid validation "
            f"failed: decision={decision}, "
            f"issues={result.issues}"
        )

    preserved_report = (
        candidate_run_dir
        / "analysis"
        / "dense_grid_candidate_validation.json"
    )

    preserved_report.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    shutil.copy2(
        result.report_path,
        preserved_report,
    )

    return result


def _promote_materialized_candidate(
    candidate_run_dir: Path,
    final_run_dir: Path,
) -> None:
    if final_run_dir.exists():
        raise FileExistsError(
            "cannot promote over an existing run: "
            f"{final_run_dir}"
        )

    os.replace(
        candidate_run_dir,
        final_run_dir,
    )


def _validate_promoted_run(
    final_run_dir: Path,
    source_run_dir: Path,
    schema_fingerprint: str,
) -> Any:
    from jobs.datasets.dense_grid_validation import (
        DenseGridValidationConfig,
        validate_dense_grids,
    )

    result = validate_dense_grids(
        DenseGridValidationConfig(
            run_dir=final_run_dir,
            source_run_dir=source_run_dir,
            mode="materialized",
            logical_run_dir=final_run_dir,
            expected_schema_fingerprint=(
                schema_fingerprint
            ),
            validate_source_reconciliation=True,
        )
    )

    report = json.loads(
        Path(
            result.report_path
        ).read_text(
            encoding="utf-8"
        )
    )

    decision = report.get("decision")

    if (
        result.ok is not True
        or decision
        != (
            "DENSE_GRID_MATERIALIZED_"
            "VALIDATION_OK"
        )
    ):
        raise ValueError(
            "promoted dense-grid validation "
            f"failed: decision={decision}, "
            f"issues={result.issues}"
        )

    return result


def _quarantine_failed_promoted_run(
    final_run_dir: Path,
    failed_run_dir: Path,
) -> Path | None:
    if not final_run_dir.exists():
        return None

    os.replace(
        final_run_dir,
        failed_run_dir,
    )

    return failed_run_dir


def _materialized_output_results(
    plan_outputs: tuple[
        DenseGridOutputResult,
        ...,
    ],
    final_run_dir: Path,
    metadata_outputs: list[
        dict[str, Any]
    ],
) -> tuple[
    DenseGridOutputResult,
    ...,
]:
    metadata_by_name = {
        item["name"]: item
        for item in metadata_outputs
    }

    results = []

    for output in plan_outputs:
        payload = output.to_dict()
        name = payload["name"]
        metadata = metadata_by_name[name]

        available_fields = set(
            DenseGridOutputResult
            .__dataclass_fields__
        )

        updates: dict[str, Any] = {}

        candidates = {
            "output_path": metadata[
                "output_path"
            ],
            "relative_path": metadata[
                "relative_path"
            ],
            "row_count": metadata[
                "row_count"
            ],
            "file_count": metadata[
                "file_count"
            ],
            "part_count": metadata[
                "part_count"
            ],
            "partition_count": metadata[
                "partition_count"
            ],
            "status": "materialized",
        }

        for key, value in candidates.items():
            if key in available_fields:
                updates[key] = value

        results.append(
            replace(
                output,
                **updates,
            )
        )

    return tuple(results)


def build_dense_grids(
    config: DenseGridConfig,
) -> DenseGridBuildResult:
    """Plan or atomically materialize dense-grid outputs."""

    if not config.execute:
        return _build_dense_grids_plan_only(
            config
        )

    source_run_dir = Path(
        config.source_run_dir
    ).resolve()

    final_run_dir = Path(
        config.run_dir
    ).resolve()

    build_id = (
        config.build_id
        or _default_build_id()
    )

    if not config.confirm_write_feature_lake:
        return _execution_failure_result(
            config,
            [
                (
                    "materialized execution requires "
                    "confirm_write_feature_lake=True"
                )
            ],
        )

    if _paths_overlap(
        source_run_dir,
        final_run_dir,
    ):
        return _execution_failure_result(
            config,
            [
                (
                    "source and final run paths "
                    "must not overlap"
                )
            ],
        )

    if final_run_dir.exists():
        return _execution_failure_result(
            config,
            [
                (
                    "final dense-grid run already "
                    f"exists: {final_run_dir}"
                )
            ],
        )

    try:
        (
            final_run_dir,
            candidate_run_dir,
            failed_run_dir,
        ) = _resolve_materialization_paths(
            final_run_dir,
            build_id,
        )
    except Exception as exc:
        return _execution_failure_result(
            config,
            [
                (
                    f"{type(exc).__name__}: "
                    f"{exc}"
                )
            ],
        )

    promoted = False

    try:
        plan_config = DenseGridConfig(
            source_run_dir=source_run_dir,
            run_dir=candidate_run_dir,
            build_id=build_id,
            dense_scope=config.dense_scope,
            family_min_observed_days=(
                config.family_min_observed_days
            ),
            pair_min_observed_days=(
                config.pair_min_observed_days
            ),
            compression=config.compression,
            execute=False,
            confirm_write_feature_lake=False,
        )

        plan_result = (
            _build_dense_grids_plan_only(
                plan_config
            )
        )

        if not plan_result.ok:
            raise ValueError(
                "dense-grid planning failed: "
                f"{plan_result.issues}"
            )

        plan_manifest_path = Path(
            plan_result.manifest_path
        )

        plan_manifest = json.loads(
            plan_manifest_path.read_text(
                encoding="utf-8"
            )
        )

        output_schemas = plan_manifest[
            "planned_output_schemas"
        ]

        schema_fingerprint = (
            plan_manifest[
                "output_schema_fingerprint"
            ]
        )

        calendar = _load_calendar(
            source_run_dir
        )

        family_day = _load_family_day(
            source_run_dir
        )

        family_priceband_day = (
            _load_family_priceband_day(
                source_run_dir
            )
        )

        (
            family_activity,
            pair_activity,
        ) = _build_activity_catalog_frames(
            family_day,
            family_priceband_day,
            config.family_min_observed_days,
            config.pair_min_observed_days,
        )

        expected_rows = {
            item["name"]: int(
                item["row_count"]
            )
            for item
            in plan_manifest["outputs"]
        }

        _write_parquet_file_atomic(
            family_activity,
            (
                candidate_run_dir
                / _MATERIALIZED_RELATIVE_PATHS[
                    "family_activity_catalog"
                ]
                / "part-00000.parquet"
            ),
            output_schemas[
                "family_activity_catalog"
            ],
            config.compression,
        )

        _write_parquet_file_atomic(
            pair_activity,
            (
                candidate_run_dir
                / _MATERIALIZED_RELATIVE_PATHS[
                    (
                        "family_priceband_"
                        "activity_catalog"
                    )
                ]
                / "part-00000.parquet"
            ),
            output_schemas[
                (
                    "family_priceband_"
                    "activity_catalog"
                )
            ],
            config.compression,
        )

        dataset_start = min(
            family_day["data"].min(),
            family_priceband_day[
                "data"
            ].min(),
        )

        dataset_end = max(
            family_day["data"].max(),
            family_priceband_day[
                "data"
            ].max(),
        )

        calendar_window = (
            calendar.loc[
                (
                    calendar["day"]
                    >= dataset_start
                )
                & (
                    calendar["day"]
                    <= dataset_end
                ),
                ["day"],
            ]
            .sort_values("day")
            .reset_index(drop=True)
        )

        monthly_estimates = (
            plan_manifest[
                "profile"
            ][
                "monthly_partition_estimates"
            ]
        )

        expected_month_rows = {
            (
                item["grain"],
                int(item["year"]),
                int(item["month"]),
            ): int(item["row_count"])
            for item in monthly_estimates
        }

        month_keys = sorted(
            {
                (
                    int(item["year"]),
                    int(item["month"]),
                )
                for item in monthly_estimates
            }
        )

        monthly_actuals: list[
            dict[str, Any]
        ] = []

        for year, month in month_keys:
            month_days = (
                calendar_window.loc[
                    (
                        calendar_window[
                            "day"
                        ].dt.year
                        == year
                    )
                    & (
                        calendar_window[
                            "day"
                        ].dt.month
                        == month
                    ),
                    "day",
                ]
            )

            if month_days.empty:
                raise ValueError(
                    "calendar month has no days: "
                    f"{year:04d}-{month:02d}"
                )

            month_start = pd.Timestamp(
                month_days.min()
            ).normalize()

            month_end = pd.Timestamp(
                month_days.max()
            ).normalize()

            family_frame = (
                _materialize_family_month(
                    family_activity,
                    family_day,
                    month_start,
                    month_end,
                    config.dense_scope,
                    build_id,
                )
            )

            expected_family_rows = (
                expected_month_rows[
                    (
                        "family_day_dense_grid",
                        year,
                        month,
                    )
                ]
            )

            if (
                len(family_frame)
                != expected_family_rows
            ):
                raise ValueError(
                    "family monthly row mismatch "
                    f"{year:04d}-{month:02d}: "
                    f"expected={expected_family_rows}, "
                    f"actual={len(family_frame)}"
                )

            family_write = (
                _write_parquet_file_atomic(
                    family_frame,
                    (
                        candidate_run_dir
                        / _MATERIALIZED_RELATIVE_PATHS[
                            "family_day_dense_grid"
                        ]
                        / f"year={year:04d}"
                        / f"month={month:02d}"
                        / "part-00000.parquet"
                    ),
                    output_schemas[
                        "family_day_dense_grid"
                    ],
                    config.compression,
                )
            )

            monthly_actuals.append(
                {
                    "grain": (
                        "family_day_dense_grid"
                    ),
                    "dense_scope": (
                        config.dense_scope
                    ),
                    "year": year,
                    "month": month,
                    "month_start": (
                        month_start.date().isoformat()
                    ),
                    "month_end": (
                        month_end.date().isoformat()
                    ),
                    "row_count": int(
                        family_write[
                            "row_count"
                        ]
                    ),
                    "file_count": 1,
                }
            )

            pair_frame = (
                _materialize_pair_month(
                    pair_activity,
                    family_priceband_day,
                    month_start,
                    month_end,
                    config.dense_scope,
                    build_id,
                )
            )

            expected_pair_rows = (
                expected_month_rows[
                    (
                        (
                            "family_priceband_day_"
                            "dense_grid"
                        ),
                        year,
                        month,
                    )
                ]
            )

            if (
                len(pair_frame)
                != expected_pair_rows
            ):
                raise ValueError(
                    "pair monthly row mismatch "
                    f"{year:04d}-{month:02d}: "
                    f"expected={expected_pair_rows}, "
                    f"actual={len(pair_frame)}"
                )

            pair_write = (
                _write_parquet_file_atomic(
                    pair_frame,
                    (
                        candidate_run_dir
                        / _MATERIALIZED_RELATIVE_PATHS[
                            (
                                "family_priceband_"
                                "day_dense_grid"
                            )
                        ]
                        / f"year={year:04d}"
                        / f"month={month:02d}"
                        / "part-00000.parquet"
                    ),
                    output_schemas[
                        (
                            "family_priceband_"
                            "day_dense_grid"
                        )
                    ],
                    config.compression,
                )
            )

            monthly_actuals.append(
                {
                    "grain": (
                        "family_priceband_day_"
                        "dense_grid"
                    ),
                    "dense_scope": (
                        config.dense_scope
                    ),
                    "year": year,
                    "month": month,
                    "month_start": (
                        month_start.date().isoformat()
                    ),
                    "month_end": (
                        month_end.date().isoformat()
                    ),
                    "row_count": int(
                        pair_write[
                            "row_count"
                        ]
                    ),
                    "file_count": 1,
                }
            )

        metadata_outputs = (
            _collect_materialized_output_metadata(
                candidate_run_dir,
                final_run_dir,
                expected_rows,
                schema_fingerprint,
                config.compression,
            )
        )

        materialized_manifest = (
            _build_materialized_manifest(
                plan_manifest,
                config,
                build_id,
                source_run_dir,
                candidate_run_dir,
                final_run_dir,
                metadata_outputs,
                monthly_actuals,
            )
        )

        candidate_manifest_path = (
            candidate_run_dir
            / "metadata"
            / "dense_grid_manifest.json"
        )

        _write_json_atomic(
            candidate_manifest_path,
            materialized_manifest,
        )

        _validate_materialized_candidate(
            candidate_run_dir,
            final_run_dir,
            source_run_dir,
            schema_fingerprint,
        )

        _promote_materialized_candidate(
            candidate_run_dir,
            final_run_dir,
        )

        promoted = True

        _validate_promoted_run(
            final_run_dir,
            source_run_dir,
            schema_fingerprint,
        )

        result_outputs = (
            _materialized_output_results(
                plan_result.outputs,
                final_run_dir,
                metadata_outputs,
            )
        )

        return DenseGridBuildResult(
            ok=True,
            dry_run=False,
            source_run_dir=str(
                source_run_dir
            ),
            run_dir=str(
                final_run_dir
            ),
            manifest_path=str(
                final_run_dir
                / "metadata"
                / "dense_grid_manifest.json"
            ),
            outputs=result_outputs,
            safety={
                "db_read": "NO",
                "db_write": "NO",
                "source_run_write": "NO",
                "parquet_write": (
                    "YES_CONFIRMED"
                ),
                "latest_pointer_update": "NO",
                "build_global_change": "NO",
                "existing_pipeline_change": (
                    "NO"
                ),
                "execution_enabled": "YES",
                "atomic_candidate_promotion": (
                    "YES"
                ),
                "overwrite_existing_run": (
                    "NO"
                ),
            },
            issues=tuple(),
        )

    except Exception as exc:
        quarantine_path = None

        if promoted:
            try:
                quarantine_path = (
                    _quarantine_failed_promoted_run(
                        final_run_dir,
                        failed_run_dir,
                    )
                )
            except Exception as quarantine_exc:
                quarantine_path = (
                    "QUARANTINE_FAILED: "
                    f"{type(quarantine_exc).__name__}: "
                    f"{quarantine_exc}"
                )

        if candidate_run_dir.exists():
            shutil.rmtree(
                candidate_run_dir,
                ignore_errors=True,
            )

        issue = (
            f"{type(exc).__name__}: {exc}"
        )

        if quarantine_path is not None:
            issue += (
                "; quarantine="
                f"{quarantine_path}"
            )

        return _execution_failure_result(
            config,
            [issue],
        )
