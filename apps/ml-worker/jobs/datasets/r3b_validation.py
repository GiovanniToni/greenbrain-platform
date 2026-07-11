from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any
import json

import pandas as pd
import pyarrow.parquet as pq


EXPECTED_OUTPUTS = ("family_priceband_day", "weather_wide")

EXPECTED_SAFETY = {
    "db_read": "NO",
    "db_write": "NO",
    "r3a_execution": "NO",
    "r3b_execution": "YES",
    "parquet_read": "YES_RAW_EXTRACTS_ONLY",
    "parquet_write": "YES_R3B_OUTPUTS_ONLY",
    "training_execution": "NO",
    "prediction_execution": "NO",
    "publish_execution": "NO",
}

FAMILY_REQUIRED_COLUMNS = (
    "data",
    "famiglia",
    "fascia_prezzo_iva_inc",
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
    "r3b_source_read_start",
    "r3b_output_write_start",
    "r3b_output_write_end",
    "r3b_built_at_utc",
)

WEATHER_REQUIRED_COLUMNS = (
    "date",
    "location_id",
    "record_type",
    "temperature_2m_max_c",
    "temperature_2m_min_c",
    "temperature_2m_mean_c",
    "r3b_output_write_start",
    "r3b_output_write_end",
    "r3b_built_at_utc",
)


@dataclass(frozen=True)
class R3BValidationConfig:
    run_dir: Path | str
    write_report: bool = True
    strict_row_count_baseline: bool = True


@dataclass(frozen=True)
class DatasetValidation:
    name: str
    ok: bool
    row_count: int = 0
    part_count: int = 0
    column_count: int = 0
    date_col: str = ""
    date_min: str = ""
    date_max: str = ""
    duplicate_key_count: int = 0
    baseline_row_count: int | None = None
    record_type_counts: dict[str, int] = field(default_factory=dict)
    required_columns_present: bool = False
    missing_required_columns: tuple[str, ...] = field(default_factory=tuple)
    critical_nulls: dict[str, int] = field(default_factory=dict)
    issues: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class R3BValidationResult:
    ok: bool
    run_dir: str
    report_path: str
    created_at_utc: str
    dataset_count: int
    issue_count: int
    issues: tuple[str, ...]
    datasets: tuple[DatasetValidation, ...]
    manifest_summary: dict[str, Any]
    safety: dict[str, str]

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "run_dir": self.run_dir,
            "report_path": self.report_path,
            "created_at_utc": self.created_at_utc,
            "dataset_count": self.dataset_count,
            "issue_count": self.issue_count,
            "issues": list(self.issues),
            "datasets": [d.to_dict() for d in self.datasets],
            "manifest_summary": dict(self.manifest_summary),
            "safety": dict(self.safety),
        }


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, indent=2, sort_keys=True, default=str) + "\n",
        encoding="utf-8",
    )


def _parse_date(value: Any) -> date | None:
    if value is None:
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, str):
        try:
            return date.fromisoformat(value[:10])
        except ValueError:
            return None
    return None


def _parquet_files(path: Path) -> list[Path]:
    if not path.exists():
        return []
    return sorted(path.rglob("*.parquet"))


def _parquet_row_count(path: Path) -> tuple[int, int]:
    files = _parquet_files(path)
    row_count = 0
    for file in files:
        row_count += pq.ParquetFile(file).metadata.num_rows
    return len(files), row_count


def _read_parquet_dir(path: Path) -> pd.DataFrame:
    files = _parquet_files(path)
    if not files:
        raise FileNotFoundError(f"no parquet files under {path}")
    return pd.read_parquet(path)


def _date_bounds(series: pd.Series) -> tuple[str, str]:
    dates = pd.to_datetime(series, errors="coerce")
    if dates.empty:
        return "", ""
    min_value = dates.min()
    max_value = dates.max()
    date_min = "" if pd.isna(min_value) else str(min_value.date())
    date_max = "" if pd.isna(max_value) else str(max_value.date())
    return date_min, date_max


def _critical_nulls(df: pd.DataFrame, columns: tuple[str, ...]) -> dict[str, int]:
    nulls: dict[str, int] = {}
    for column in columns:
        if column in df.columns:
            count = int(df[column].isna().sum())
            if count > 0:
                nulls[column] = count
    return nulls


def _manifest_checks(run_dir: Path) -> tuple[dict[str, Any], list[str]]:
    manifest_path = run_dir / "metadata" / "r3b_transform_manifest.json"
    issues: list[str] = []

    if not manifest_path.exists():
        return {"manifest_exists": False, "manifest_path": str(manifest_path)}, [
            "missing metadata/r3b_transform_manifest.json"
        ]

    manifest = _read_json(manifest_path)

    summary = {
        "manifest_exists": True,
        "manifest_path": str(manifest_path),
        "ok": manifest.get("ok"),
        "dry_run": manifest.get("dry_run"),
        "output_count": len(manifest.get("outputs") or []),
        "output_names": [
            output.get("name")
            for output in (manifest.get("outputs") or [])
            if isinstance(output, dict)
        ],
        "safety": manifest.get("safety") or {},
    }

    if manifest.get("ok") is not True:
        issues.append("manifest ok is not true")

    if manifest.get("dry_run") is not False:
        issues.append("manifest dry_run is not false")

    output_names = sorted(summary["output_names"])
    if output_names != sorted(EXPECTED_OUTPUTS):
        issues.append(
            "manifest outputs mismatch: expected "
            + ",".join(EXPECTED_OUTPUTS)
            + " got "
            + ",".join(output_names)
        )

    safety = manifest.get("safety") or {}
    for key, expected in EXPECTED_SAFETY.items():
        actual = safety.get(key)
        if actual != expected:
            issues.append(f"manifest safety mismatch {key}: expected {expected}, got {actual}")

    return summary, issues


def _window_from_manifest(run_dir: Path) -> tuple[date, date]:
    manifest_path = run_dir / "metadata" / "r3b_transform_manifest.json"
    if not manifest_path.exists():
        return date(2009, 1, 1), date.today()

    manifest = _read_json(manifest_path)
    window = manifest.get("window") or {}

    output_start = _parse_date(window.get("output_write_start")) or date(2009, 1, 1)
    output_end = _parse_date(window.get("output_write_end")) or date.today()

    return output_start, output_end


def _validate_family(run_dir: Path, output_start: date, output_end: date, strict_row_count_baseline: bool) -> DatasetValidation:
    issues: list[str] = []
    output_dir = run_dir / "family_priceband_day"
    files, metadata_rows = _parquet_row_count(output_dir)

    try:
        family = _read_parquet_dir(output_dir)
    except Exception as exc:
        return DatasetValidation(
            name="family_priceband_day",
            ok=False,
            row_count=0,
            part_count=files,
            issues=(f"cannot read family_priceband_day parquet: {type(exc).__name__}: {exc}",),
        )

    missing = tuple(c for c in FAMILY_REQUIRED_COLUMNS if c not in family.columns)
    if missing:
        issues.append("missing required columns: " + ",".join(missing))

    row_count = int(len(family))
    if row_count <= 0:
        issues.append("row_count is zero")

    if metadata_rows != row_count:
        issues.append(f"metadata row count mismatch: metadata={metadata_rows}, pandas={row_count}")

    duplicate_key_count = -1
    key_cols = ["data", "famiglia", "fascia_prezzo_iva_inc"]
    if all(c in family.columns for c in key_cols):
        duplicate_key_count = int(family.duplicated(subset=key_cols).sum())
        if duplicate_key_count > 0:
            issues.append(f"duplicate key rows: {duplicate_key_count}")
    else:
        issues.append("cannot check duplicate key because key columns are missing")

    critical = _critical_nulls(
        family,
        (
            "data",
            "famiglia",
            "fascia_prezzo_iva_inc",
            "qty_venduta",
            "imponibile_netto_tot",
            "num_articoli",
        ),
    )
    for column, count in critical.items():
        issues.append(f"critical nulls in {column}: {count}")

    date_min = ""
    date_max = ""
    if "data" in family.columns:
        date_min, date_max = _date_bounds(family["data"])

    baseline_row_count = None
    raw_sales_dir = run_dir / "raw_extracts" / "sales_family_daily_fact"
    if raw_sales_dir.exists():
        try:
            raw_sales = _read_parquet_dir(raw_sales_dir)
            raw_dates = pd.to_datetime(raw_sales["data"], errors="coerce")
            mask = (raw_dates >= pd.Timestamp(output_start)) & (raw_dates <= pd.Timestamp(output_end))
            baseline_row_count = int(mask.sum())
            if strict_row_count_baseline and baseline_row_count != row_count:
                issues.append(
                    f"row count mismatch vs raw sales baseline: output={row_count}, baseline={baseline_row_count}"
                )
        except Exception as exc:
            issues.append(f"cannot compute raw sales baseline: {type(exc).__name__}: {exc}")

    return DatasetValidation(
        name="family_priceband_day",
        ok=not issues,
        row_count=row_count,
        part_count=files,
        column_count=len(family.columns),
        date_col="data",
        date_min=date_min,
        date_max=date_max,
        duplicate_key_count=duplicate_key_count,
        baseline_row_count=baseline_row_count,
        required_columns_present=not missing,
        missing_required_columns=missing,
        critical_nulls=critical,
        issues=tuple(issues),
    )


def _validate_weather(run_dir: Path, output_start: date, output_end: date, strict_row_count_baseline: bool) -> DatasetValidation:
    issues: list[str] = []
    output_dir = run_dir / "weather_wide"
    files, metadata_rows = _parquet_row_count(output_dir)

    try:
        weather = _read_parquet_dir(output_dir)
    except Exception as exc:
        return DatasetValidation(
            name="weather_wide",
            ok=False,
            row_count=0,
            part_count=files,
            issues=(f"cannot read weather_wide parquet: {type(exc).__name__}: {exc}",),
        )

    missing = tuple(c for c in WEATHER_REQUIRED_COLUMNS if c not in weather.columns)
    if missing:
        issues.append("missing required columns: " + ",".join(missing))

    row_count = int(len(weather))
    if row_count <= 0:
        issues.append("row_count is zero")

    if metadata_rows != row_count:
        issues.append(f"metadata row count mismatch: metadata={metadata_rows}, pandas={row_count}")

    record_type_counts: dict[str, int] = {}
    if "record_type" in weather.columns:
        record_type_counts = {
            str(k): int(v)
            for k, v in weather["record_type"].value_counts(dropna=False).to_dict().items()
        }
        if "actual" not in record_type_counts:
            issues.append("missing record_type=actual")
        if "forecast" not in record_type_counts:
            issues.append("missing record_type=forecast")
    else:
        issues.append("cannot check record_type because column is missing")

    duplicate_key_count = -1
    key_cols = ["date", "location_id", "record_type", "forecast_run_date", "forecast_horizon_days"]
    if all(c in weather.columns for c in key_cols):
        duplicate_key_count = int(weather.duplicated(subset=key_cols).sum())
        if duplicate_key_count > 0:
            issues.append(f"duplicate key rows: {duplicate_key_count}")
    else:
        issues.append("cannot check duplicate key because key columns are missing")

    critical = _critical_nulls(
        weather,
        (
            "date",
            "location_id",
            "record_type",
            "temperature_2m_max_c",
            "temperature_2m_min_c",
            "temperature_2m_mean_c",
        ),
    )
    for column, count in critical.items():
        issues.append(f"critical nulls in {column}: {count}")

    date_min = ""
    date_max = ""
    if "date" in weather.columns:
        date_min, date_max = _date_bounds(weather["date"])

    baseline_row_count = None
    actuals_dir = run_dir / "raw_extracts" / "weather_actuals"
    forecasts_dir = run_dir / "raw_extracts" / "weather_forecasts"

    if actuals_dir.exists() and forecasts_dir.exists():
        try:
            actuals = _read_parquet_dir(actuals_dir)
            forecasts = _read_parquet_dir(forecasts_dir)

            actual_dates = pd.to_datetime(actuals["weather_date"], errors="coerce")
            forecast_dates = pd.to_datetime(forecasts["forecast_date"], errors="coerce")

            actual_count = int(
                ((actual_dates >= pd.Timestamp(output_start)) & (actual_dates <= pd.Timestamp(output_end))).sum()
            )
            forecast_count = int(
                ((forecast_dates >= pd.Timestamp(output_start)) & (forecast_dates <= pd.Timestamp(output_end))).sum()
            )
            baseline_row_count = actual_count + forecast_count

            if strict_row_count_baseline and baseline_row_count != row_count:
                issues.append(
                    f"row count mismatch vs raw weather baseline: output={row_count}, baseline={baseline_row_count}"
                )
        except Exception as exc:
            issues.append(f"cannot compute raw weather baseline: {type(exc).__name__}: {exc}")

    return DatasetValidation(
        name="weather_wide",
        ok=not issues,
        row_count=row_count,
        part_count=files,
        column_count=len(weather.columns),
        date_col="date",
        date_min=date_min,
        date_max=date_max,
        duplicate_key_count=duplicate_key_count,
        baseline_row_count=baseline_row_count,
        record_type_counts=record_type_counts,
        required_columns_present=not missing,
        missing_required_columns=missing,
        critical_nulls=critical,
        issues=tuple(issues),
    )


def validate_r3b_outputs(config: R3BValidationConfig) -> R3BValidationResult:
    run_dir = Path(config.run_dir)
    report_path = run_dir / "analysis" / "r3b_validation.json"

    top_issues: list[str] = []

    if not run_dir.exists():
        result = R3BValidationResult(
            ok=False,
            run_dir=str(run_dir),
            report_path=str(report_path),
            created_at_utc=utc_now_iso(),
            dataset_count=0,
            issue_count=1,
            issues=(f"run_dir does not exist: {run_dir}",),
            datasets=tuple(),
            manifest_summary={"manifest_exists": False},
            safety={
                "db_read": "NO",
                "db_write": "NO",
                "r3a_execution": "NO",
                "r3b_execution": "NO",
                "parquet_read": "NO",
                "parquet_write": "NO",
                "training_execution": "NO",
                "prediction_execution": "NO",
                "publish_execution": "NO",
            },
        )
        if config.write_report:
            _write_json(report_path, result.to_dict())
        return result

    manifest_summary, manifest_issues = _manifest_checks(run_dir)
    top_issues.extend(manifest_issues)

    output_start, output_end = _window_from_manifest(run_dir)

    datasets = (
        _validate_family(run_dir, output_start, output_end, config.strict_row_count_baseline),
        _validate_weather(run_dir, output_start, output_end, config.strict_row_count_baseline),
    )

    for dataset in datasets:
        for issue in dataset.issues:
            top_issues.append(f"{dataset.name}: {issue}")

    result = R3BValidationResult(
        ok=not top_issues,
        run_dir=str(run_dir),
        report_path=str(report_path),
        created_at_utc=utc_now_iso(),
        dataset_count=len(datasets),
        issue_count=len(top_issues),
        issues=tuple(top_issues),
        datasets=datasets,
        manifest_summary=manifest_summary,
        safety={
            "db_read": "NO",
            "db_write": "NO",
            "r3a_execution": "NO",
            "r3b_execution": "NO",
            "parquet_read": "YES_REVIEW_ONLY",
            "parquet_write": "NO",
            "training_execution": "NO",
            "prediction_execution": "NO",
            "publish_execution": "NO",
        },
    )

    if config.write_report:
        _write_json(report_path, result.to_dict())

    return result
