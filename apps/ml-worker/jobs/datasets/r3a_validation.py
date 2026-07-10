"""R3A raw extract validation helpers.

This module validates R3A extract manifests without reading or writing the DB.

Two validation modes are intentionally separated:

1. Plan-only validation:
   - validates the dry-run manifest produced by build_global/R3A planning;
   - does not read parquet files;
   - does not import pyarrow.

2. Materialized validation:
   - validates real parquet extracts when R3A is later executed;
   - imports pyarrow only inside that branch;
   - still never reads the DB.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class R3ARequiredDataset:
    name: str
    source_table: str
    min_rows: int
    required_columns: tuple[str, ...]
    date_col: str | None = None
    min_expected_date: str | None = None
    min_expected_max_date: str | None = None


@dataclass
class R3AValidationIssue:
    severity: str
    code: str
    message: str
    dataset: str | None = None
    detail: dict[str, Any] = field(default_factory=dict)


@dataclass
class R3AValidationResult:
    ok: bool
    mode: str
    manifest_path: str
    run_dir: str | None
    dataset_count: int
    issues: list[R3AValidationIssue]
    safety: dict[str, str]

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "mode": self.mode,
            "manifest_path": self.manifest_path,
            "run_dir": self.run_dir,
            "dataset_count": self.dataset_count,
            "issues": [asdict(issue) for issue in self.issues],
            "safety": self.safety,
        }


REQUIRED_DATASETS: tuple[R3ARequiredDataset, ...] = (
    R3ARequiredDataset(
        name="sales_family_daily_fact",
        source_table="public.greenhouse_sales_family_daily_fact",
        min_rows=524_000,
        required_columns=(
            "data",
            "famiglia",
            "fascia_prezzo_iva_inc",
            "qty_venduta",
            "imponibile_netto_tot",
            "num_articoli",
        ),
        date_col="data",
        min_expected_date="2009-01-02",
        min_expected_max_date="2026-07-05",
    ),
    R3ARequiredDataset(
        name="products_normalized",
        source_table="public.greenhouse_products_normalized",
        min_rows=12_000,
        required_columns=(
            "codart",
            "famiglia",
            "fascia_prezzo_iva_inc",
            "categoria_corretta",
            "prezzo_iva_inclusa",
        ),
    ),
    R3ARequiredDataset(
        name="weather_actuals",
        source_table="gb_weather.daily_actuals",
        min_rows=25_500,
        required_columns=(
            "location_id",
            "weather_date",
            "temperature_2m_max_c",
            "temperature_2m_min_c",
            "temperature_2m_mean_c",
            "precipitation_sum_mm",
            "rain_sum_mm",
        ),
        date_col="weather_date",
        min_expected_date="2009-01-01",
        min_expected_max_date="2026-07-04",
    ),
    R3ARequiredDataset(
        name="weather_forecasts",
        source_table="gb_weather.daily_forecasts",
        min_rows=480,
        required_columns=(
            "location_id",
            "forecast_run_date",
            "forecast_date",
            "forecast_horizon_days",
            "temperature_2m_max_c",
            "temperature_2m_min_c",
            "temperature_2m_mean_c",
            "precipitation_sum_mm",
            "rain_sum_mm",
        ),
        date_col="forecast_date",
        min_expected_date="2026-06-23",
        min_expected_max_date="2026-07-14",
    ),
    R3ARequiredDataset(
        name="holidays",
        source_table="public.greenhouse_holidays",
        min_rows=254,
        required_columns=("data", "is_holiday", "holiday_name"),
        date_col="data",
        min_expected_date="2009-01-01",
        min_expected_max_date="2027-12-26",
    ),
    R3ARequiredDataset(
        name="calendar",
        source_table="public.dim_iso_day",
        min_rows=6_500,
        required_columns=("day", "iso_year", "iso_week", "week_start", "month_num"),
        date_col="day",
        min_expected_date="2009-01-01",
        min_expected_max_date="2027-01-24",
    ),
)

EXPECTED_DATASET_NAMES: frozenset[str] = frozenset(ds.name for ds in REQUIRED_DATASETS)
EXPECTED_SKIPPED_NAMES: frozenset[str] = frozenset(
    {"sales_raw_article_detail", "dense_legacy_tables"}
)


def _issue(
    issues: list[R3AValidationIssue],
    code: str,
    message: str,
    *,
    dataset: str | None = None,
    detail: dict[str, Any] | None = None,
) -> None:
    issues.append(
        R3AValidationIssue(
            severity="ERROR",
            code=code,
            message=message,
            dataset=dataset,
            detail=detail or {},
        )
    )


def _load_manifest(manifest_path: Path) -> dict[str, Any]:
    if not manifest_path.exists():
        raise FileNotFoundError(f"Manifest not found: {manifest_path}")
    return json.loads(manifest_path.read_text(encoding="utf-8"))


def _dataset_map(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    datasets = manifest.get("datasets")
    if not isinstance(datasets, list):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for item in datasets:
        if isinstance(item, dict) and isinstance(item.get("name"), str):
            result[item["name"]] = item
    return result


def _skipped_names(manifest: dict[str, Any]) -> set[str]:
    skipped = manifest.get("skipped")
    if not isinstance(skipped, list):
        return set()
    return {item.get("name") for item in skipped if isinstance(item, dict)}


def _result(
    *,
    mode: str,
    manifest_path: Path,
    run_dir: Path | None,
    dataset_count: int,
    issues: list[R3AValidationIssue],
    safety: dict[str, str],
) -> R3AValidationResult:
    return R3AValidationResult(
        ok=not any(issue.severity == "ERROR" for issue in issues),
        mode=mode,
        manifest_path=str(manifest_path),
        run_dir=str(run_dir) if run_dir is not None else None,
        dataset_count=dataset_count,
        issues=issues,
        safety=safety,
    )


def validate_plan_manifest(manifest_path: Path | str) -> R3AValidationResult:
    """Validate an R3A plan-only manifest.

    This function does not read parquet files and does not import pyarrow.
    """

    path = Path(manifest_path)
    issues: list[R3AValidationIssue] = []

    try:
        manifest = _load_manifest(path)
    except Exception as exc:
        _issue(issues, "MANIFEST_LOAD_FAILED", str(exc))
        return _result(
            mode="plan",
            manifest_path=path,
            run_dir=None,
            dataset_count=0,
            issues=issues,
            safety={"db_read": "NO", "db_write": "NO", "r3a_execution": "NO"},
        )

    datasets = _dataset_map(manifest)
    dataset_names = set(datasets)
    safety = dict(manifest.get("safety") or {})

    if manifest.get("dry_run") is not True:
        _issue(
            issues,
            "PLAN_DRY_RUN_NOT_TRUE",
            "Plan-only manifest must have dry_run=true.",
            detail={"dry_run": manifest.get("dry_run")},
        )

    if dataset_names != EXPECTED_DATASET_NAMES:
        _issue(
            issues,
            "PLAN_DATASET_NAMES_MISMATCH",
            "Plan-only manifest dataset names do not match expected R3A datasets.",
            detail={
                "expected": sorted(EXPECTED_DATASET_NAMES),
                "actual": sorted(dataset_names),
            },
        )

    for name in sorted(EXPECTED_DATASET_NAMES):
        ds = datasets.get(name)
        if not ds:
            continue
        if ds.get("status") != "planned":
            _issue(
                issues,
                "PLAN_DATASET_STATUS_NOT_PLANNED",
                "Plan-only dataset must have status=planned.",
                dataset=name,
                detail={"status": ds.get("status")},
            )

    for key in ("db_read", "db_write", "r3a_execution"):
        if safety.get(key) != "NO":
            _issue(
                issues,
                "PLAN_SAFETY_NOT_NO",
                f"Plan-only safety.{key} must be NO.",
                detail={key: safety.get(key)},
            )

    skipped_names = _skipped_names(manifest)
    if not EXPECTED_SKIPPED_NAMES.issubset(skipped_names):
        _issue(
            issues,
            "PLAN_SKIPPED_MISSING",
            "Plan-only manifest missing expected skipped datasets.",
            detail={
                "expected_subset": sorted(EXPECTED_SKIPPED_NAMES),
                "actual": sorted(skipped_names),
            },
        )

    return _result(
        mode="plan",
        manifest_path=path,
        run_dir=None,
        dataset_count=len(datasets),
        issues=issues,
        safety={
            "db_read": "NO",
            "db_write": "NO",
            "r3a_execution": "NO",
            "parquet_read": "NO",
        },
    )


def _required_by_name() -> dict[str, R3ARequiredDataset]:
    return {ds.name: ds for ds in REQUIRED_DATASETS}


def _dense_legacy_dirs(run_dir: Path) -> list[str]:
    raw_dir = run_dir / "raw_extracts"
    candidates = [
        raw_dir / "greenhouse_sales_family_daily_dense",
        raw_dir / "greenhouse_forecast_features_dense",
        raw_dir / "dense_legacy_tables",
    ]
    return [str(path) for path in candidates if path.exists()]


def validate_materialized_extract(
    run_dir: Path | str,
    manifest_path: Path | str | None = None,
) -> R3AValidationResult:
    """Validate materialized R3A parquet extracts without reading DB."""

    run_path = Path(run_dir)
    manifest = Path(manifest_path) if manifest_path is not None else (
        run_path / "metadata" / "extract_manifest.json"
    )

    issues: list[R3AValidationIssue] = []

    try:
        manifest_data = _load_manifest(manifest)
    except Exception as exc:
        _issue(issues, "MANIFEST_LOAD_FAILED", str(exc))
        return _result(
            mode="materialized",
            manifest_path=manifest,
            run_dir=run_path,
            dataset_count=0,
            issues=issues,
            safety={"db_read": "NO", "db_write": "NO", "parquet_read": "YES"},
        )

    # Pyarrow is intentionally imported only inside materialized validation.
    import pyarrow.parquet as pq

    datasets = _dataset_map(manifest_data)
    required = _required_by_name()
    dataset_names = set(datasets)

    if manifest_data.get("ok") is not True:
        _issue(
            issues,
            "MATERIALIZED_MANIFEST_NOT_OK",
            "Materialized manifest must have ok=true.",
            detail={"ok": manifest_data.get("ok")},
        )

    if manifest_data.get("dry_run") is True:
        _issue(
            issues,
            "MATERIALIZED_DRY_RUN_TRUE",
            "Materialized validation cannot run against dry_run=true manifest.",
        )

    if dataset_names != EXPECTED_DATASET_NAMES:
        _issue(
            issues,
            "MATERIALIZED_DATASET_NAMES_MISMATCH",
            "Materialized manifest dataset names do not match expected R3A datasets.",
            detail={
                "expected": sorted(EXPECTED_DATASET_NAMES),
                "actual": sorted(dataset_names),
            },
        )

    dense_found = _dense_legacy_dirs(run_path)
    if dense_found:
        _issue(
            issues,
            "DENSE_LEGACY_DIRS_FOUND",
            "Dense legacy extract directories must not exist.",
            detail={"paths": dense_found},
        )

    for name, spec in required.items():
        ds = datasets.get(name)
        if not ds:
            _issue(issues, "DATASET_MISSING", "Required dataset missing from manifest.", dataset=name)
            continue

        if ds.get("status") != "ok":
            _issue(
                issues,
                "DATASET_STATUS_NOT_OK",
                "Materialized dataset must have status=ok.",
                dataset=name,
                detail={"status": ds.get("status")},
            )

        ds_dir = run_path / "raw_extracts" / name
        files = sorted(ds_dir.glob("*.parquet"))

        if not files:
            _issue(
                issues,
                "PARQUET_FILES_MISSING",
                "No parquet files found for materialized dataset.",
                dataset=name,
                detail={"path": str(ds_dir)},
            )
            continue

        actual_parts = len(files)
        actual_rows = 0
        columns: list[str] | None = None
        min_date: str | None = None
        max_date: str | None = None

        for file_path in files:
            table = pq.read_table(file_path)
            actual_rows += table.num_rows
            if columns is None:
                columns = list(table.column_names)

            if spec.date_col and spec.date_col in table.column_names and table.num_rows > 0:
                values = [str(v) for v in table[spec.date_col].to_pylist() if v is not None]
                if values:
                    local_min = min(values)
                    local_max = max(values)
                    min_date = local_min if min_date is None or local_min < min_date else min_date
                    max_date = local_max if max_date is None or local_max > max_date else max_date

        manifest_rows = ds.get("row_count")
        manifest_parts = ds.get("part_count")

        if actual_rows != manifest_rows:
            _issue(
                issues,
                "ROW_COUNT_MISMATCH",
                "Actual parquet row count does not match manifest row_count.",
                dataset=name,
                detail={"actual": actual_rows, "manifest": manifest_rows},
            )

        if actual_parts != manifest_parts:
            _issue(
                issues,
                "PART_COUNT_MISMATCH",
                "Actual parquet part count does not match manifest part_count.",
                dataset=name,
                detail={"actual": actual_parts, "manifest": manifest_parts},
            )

        if actual_rows < spec.min_rows:
            _issue(
                issues,
                "TOO_FEW_ROWS",
                "Dataset row count is below expected minimum.",
                dataset=name,
                detail={"actual": actual_rows, "min_rows": spec.min_rows},
            )

        actual_columns = columns or []
        missing_columns = [col for col in spec.required_columns if col not in actual_columns]
        if missing_columns:
            _issue(
                issues,
                "REQUIRED_COLUMNS_MISSING",
                "Dataset is missing required columns.",
                dataset=name,
                detail={"missing": missing_columns},
            )

        if spec.date_col:
            if min_date is None or max_date is None:
                _issue(
                    issues,
                    "DATE_RANGE_MISSING",
                    "Date column has no min/max values.",
                    dataset=name,
                    detail={"date_col": spec.date_col},
                )
            else:
                if spec.min_expected_date and min_date > spec.min_expected_date:
                    _issue(
                        issues,
                        "MIN_DATE_TOO_RECENT",
                        "Dataset min date is later than expected.",
                        dataset=name,
                        detail={"actual": min_date, "expected_at_or_before": spec.min_expected_date},
                    )
                if spec.min_expected_max_date and max_date < spec.min_expected_max_date:
                    _issue(
                        issues,
                        "MAX_DATE_TOO_OLD",
                        "Dataset max date is earlier than expected.",
                        dataset=name,
                        detail={"actual": max_date, "expected_at_or_after": spec.min_expected_max_date},
                    )

    return _result(
        mode="materialized",
        manifest_path=manifest,
        run_dir=run_path,
        dataset_count=len(datasets),
        issues=issues,
        safety={
            "db_read": "NO",
            "db_write": "NO",
            "parquet_read": "YES",
            "r3a_execution": "NO",
        },
    )
