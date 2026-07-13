from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
import json

import pandas as pd
import pyarrow.parquet as pq


EXPECTED_MANIFEST_SAFETY = {
    "db_read": "NO",
    "db_write": "NO",
    "r3a_execution": "NO",
    "r3b_execution": "NO",
    "r3c_execution": "NO",
    "r3d_execution": "YES",
    "parquet_read": "YES_VALIDATED_R3B_R3C_OUTPUTS_ONLY",
    "parquet_write": "YES_R3D_ENRICHED_ONLY",
    "training_execution": "NO",
    "prediction_execution": "NO",
    "publish_execution": "NO",
}

REQUIRED_PRIOR_VALIDATIONS = (
    ("R3B", "r3b_validation.json"),
    ("R3C family_day", "r3c_family_day_validation.json"),
)

ENRICHED_REQUIRED_COLUMNS = (
    "data",
    "famiglia",
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
    "weather_date",
    "weather_record_type",
    "weather_day_source",
    "weather_match_status",
    "r3d_output_write_start",
    "r3d_output_write_end",
    "r3d_built_at_utc",
)

BASE_COMPARE_COLUMNS = (
    "data",
    "famiglia",
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
    "priceband_count",
    "source_priceband_rows",
    "avg_price_per_item",
)

WEATHER_ADDED_COLUMNS = (
    "temperature_2m_max_c",
    "temperature_2m_min_c",
    "temperature_2m_mean_c",
    "apparent_temperature_max_c",
    "apparent_temperature_min_c",
    "apparent_temperature_mean_c",
    "precipitation_sum_mm",
    "rain_sum_mm",
    "precipitation_hours",
    "wind_speed_10m_max_kmh",
    "uv_index_max",
    "weather_code",
    "daylight_duration_seconds",
    "sunshine_duration_seconds",
    "iso_year",
    "iso_week",
    "week_start",
    "month_num",
    "is_holiday",
    "holiday_name",
)


@dataclass(frozen=True)
class R3DEnrichmentValidationConfig:
    run_dir: Path | str
    write_report: bool = True
    strict_base_metrics: bool = True
    min_weather_added_columns: int = 10


@dataclass(frozen=True)
class R3DEnrichmentDatasetValidation:
    name: str
    ok: bool
    row_count: int = 0
    metadata_row_count: int = 0
    part_count: int = 0
    column_count: int = 0
    family_day_row_count: int | None = None
    date_min: str = ""
    date_max: str = ""
    family_count: int | None = None
    duplicate_key_count: int = 0
    required_columns_present: bool = False
    missing_required_columns: tuple[str, ...] = field(default_factory=tuple)
    critical_nulls: dict[str, int] = field(default_factory=dict)
    weather_date_nulls: int | None = None
    manifest_missing_weather_rows: int | None = None
    weather_match_counts: dict[str, int] = field(default_factory=dict)
    weather_added_column_count: int = 0
    weather_added_columns: tuple[str, ...] = field(default_factory=tuple)
    base_metric_mismatches: dict[str, dict[str, float | int]] = field(default_factory=dict)
    issues: tuple[str, ...] = field(default_factory=tuple)
    warnings: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class R3DEnrichmentValidationResult:
    ok: bool
    run_dir: str
    report_path: str
    created_at_utc: str
    issue_count: int
    warning_count: int
    issues: tuple[str, ...]
    warnings: tuple[str, ...]
    dataset: R3DEnrichmentDatasetValidation | None
    manifest_summary: dict[str, Any]
    prior_validation_summary: dict[str, Any]
    safety: dict[str, str]

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "run_dir": self.run_dir,
            "report_path": self.report_path,
            "created_at_utc": self.created_at_utc,
            "issue_count": self.issue_count,
            "warning_count": self.warning_count,
            "issues": list(self.issues),
            "warnings": list(self.warnings),
            "dataset": None if self.dataset is None else self.dataset.to_dict(),
            "manifest_summary": dict(self.manifest_summary),
            "prior_validation_summary": dict(self.prior_validation_summary),
            "safety": dict(self.safety),
        }


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, indent=2, sort_keys=True, default=str) + "\n",
        encoding="utf-8",
    )


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


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


def _normalize_date_string(series: pd.Series) -> pd.Series:
    return pd.to_datetime(series, errors="coerce").dt.strftime("%Y-%m-%d")


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


def _base_safety() -> dict[str, str]:
    return {
        "db_read": "NO",
        "db_write": "NO",
        "r3a_execution": "NO",
        "r3b_execution": "NO",
        "r3c_execution": "NO",
        "r3d_execution": "NO",
        "parquet_read": "YES_REVIEW_ONLY",
        "parquet_write": "NO",
        "training_execution": "NO",
        "prediction_execution": "NO",
        "publish_execution": "NO",
    }


def _manifest_checks(run_dir: Path) -> tuple[dict[str, Any], list[str]]:
    manifest_path = run_dir / "metadata" / "r3d_enrichment_manifest.json"
    issues: list[str] = []

    if not manifest_path.exists():
        return {"manifest_exists": False, "manifest_path": str(manifest_path)}, [
            "missing metadata/r3d_enrichment_manifest.json"
        ]

    manifest = _read_json(manifest_path)
    output = manifest.get("output") or {}
    safety = manifest.get("safety") or {}

    summary = {
        "manifest_exists": True,
        "manifest_path": str(manifest_path),
        "ok": manifest.get("ok"),
        "dry_run": manifest.get("dry_run"),
        "mode": manifest.get("mode"),
        "output": output,
        "safety": safety,
    }

    if manifest.get("ok") is not True:
        issues.append("manifest ok is not true")

    if manifest.get("dry_run") is not False:
        issues.append("manifest dry_run is not false")

    if output.get("name") != "enriched":
        issues.append(f"manifest output name is not enriched: {output.get('name')}")

    if output.get("status") != "ok":
        issues.append(f"manifest output status is not ok: {output.get('status')}")

    if output.get("duplicate_key_count") != 0:
        issues.append(f"manifest duplicate_key_count is not zero: {output.get('duplicate_key_count')}")

    for key, expected in EXPECTED_MANIFEST_SAFETY.items():
        actual = safety.get(key)
        if actual != expected:
            issues.append(f"manifest safety mismatch {key}: expected {expected}, got {actual}")

    return summary, issues


def _prior_validation_checks(run_dir: Path) -> tuple[dict[str, Any], list[str]]:
    issues: list[str] = []
    summary: dict[str, Any] = {}

    for label, filename in REQUIRED_PRIOR_VALIDATIONS:
        path = run_dir / "analysis" / filename
        key = label.lower().replace(" ", "_")

        if not path.exists():
            summary[key] = {"exists": False, "path": str(path)}
            issues.append(f"missing prior {label} validation report: {path}")
            continue

        validation = _read_json(path)
        item = {
            "exists": True,
            "path": str(path),
            "ok": validation.get("ok"),
            "issue_count": validation.get("issue_count"),
        }
        summary[key] = item

        if validation.get("ok") is not True:
            issues.append(f"prior {label} validation ok is not true")

        if validation.get("issue_count") != 0:
            issues.append(f"prior {label} validation issue_count is not zero: {validation.get('issue_count')}")

    return summary, issues


def _compare_base_metrics(
    enriched: pd.DataFrame,
    family_day: pd.DataFrame,
    strict_base_metrics: bool,
) -> tuple[dict[str, dict[str, float | int]], list[str]]:
    issues: list[str] = []
    metric_mismatches: dict[str, dict[str, float | int]] = {}

    missing = [c for c in BASE_COMPARE_COLUMNS if c not in enriched.columns or c not in family_day.columns]
    if missing:
        return metric_mismatches, ["cannot compare base family_day columns because missing: " + ",".join(missing)]

    left = enriched[list(BASE_COMPARE_COLUMNS)].copy()
    right = family_day[list(BASE_COMPARE_COLUMNS)].copy()

    left["data"] = _normalize_date_string(left["data"])
    right["data"] = _normalize_date_string(right["data"])

    merged = left.merge(
        right,
        on=["data", "famiglia"],
        how="outer",
        suffixes=("_enriched", "_family_day"),
        indicator=True,
    )

    if not (merged["_merge"] == "both").all():
        missing_in_enriched = int((merged["_merge"] == "right_only").sum())
        extra_in_enriched = int((merged["_merge"] == "left_only").sum())
        issues.append(
            f"key mismatch vs family_day: missing_in_enriched={missing_in_enriched}, extra_in_enriched={extra_in_enriched}"
        )

    for column in [c for c in BASE_COMPARE_COLUMNS if c not in ("data", "famiglia")]:
        e_col = f"{column}_enriched"
        f_col = f"{column}_family_day"

        if e_col not in merged.columns or f_col not in merged.columns:
            metric_mismatches[column] = {"mismatch_count": -1, "max_abs_diff": -1}
            issues.append(f"cannot compare base metric {column}: column missing")
            continue

        e = pd.to_numeric(merged[e_col], errors="coerce").fillna(0)
        f = pd.to_numeric(merged[f_col], errors="coerce").fillna(0)

        if column in {"priceband_count", "source_priceband_rows"}:
            diff = (e.astype("int64") - f.astype("int64")).abs()
            mismatch_count = int((diff != 0).sum())
            max_abs_diff = int(diff.max()) if len(diff) else 0
        else:
            diff = (e - f).abs()
            mismatch_count = int((diff > 1e-9).sum())
            max_abs_diff = float(diff.max()) if len(diff) else 0.0

        metric_mismatches[column] = {
            "mismatch_count": mismatch_count,
            "max_abs_diff": max_abs_diff,
        }

        if strict_base_metrics and mismatch_count > 0:
            issues.append(
                f"base metric mismatch {column}: mismatch_count={mismatch_count}, max_abs_diff={max_abs_diff}"
            )

    return metric_mismatches, issues


def _validate_enriched_dataset(
    run_dir: Path,
    manifest_summary: dict[str, Any],
    strict_base_metrics: bool,
    min_weather_added_columns: int,
) -> R3DEnrichmentDatasetValidation:
    issues: list[str] = []
    warnings: list[str] = []

    enriched_dir = run_dir / "enriched"
    family_day_dir = run_dir / "family_day"

    part_count, metadata_row_count = _parquet_row_count(enriched_dir)

    try:
        enriched = _read_parquet_dir(enriched_dir)
    except Exception as exc:
        return R3DEnrichmentDatasetValidation(
            name="enriched",
            ok=False,
            part_count=part_count,
            metadata_row_count=metadata_row_count,
            issues=(f"cannot read enriched parquet: {type(exc).__name__}: {exc}",),
        )

    try:
        family_day = _read_parquet_dir(family_day_dir)
    except Exception as exc:
        return R3DEnrichmentDatasetValidation(
            name="enriched",
            ok=False,
            part_count=part_count,
            metadata_row_count=metadata_row_count,
            row_count=int(len(enriched)),
            issues=(f"cannot read family_day parquet: {type(exc).__name__}: {exc}",),
        )

    missing_required = tuple(c for c in ENRICHED_REQUIRED_COLUMNS if c not in enriched.columns)
    if missing_required:
        issues.append("missing required columns: " + ",".join(missing_required))

    row_count = int(len(enriched))
    family_day_row_count = int(len(family_day))

    if row_count <= 0:
        issues.append("row_count is zero")

    if row_count != family_day_row_count:
        issues.append(f"enriched row_count != family_day row_count: enriched={row_count}, family_day={family_day_row_count}")

    if metadata_row_count != row_count:
        issues.append(f"metadata vs pandas row count mismatch: metadata={metadata_row_count}, pandas={row_count}")

    manifest_output = (manifest_summary.get("output") or {}) if manifest_summary else {}
    manifest_row_count = manifest_output.get("row_count")
    if manifest_row_count is not None and int(manifest_row_count) != row_count:
        issues.append(f"manifest row_count mismatch: manifest={manifest_row_count}, actual={row_count}")

    duplicate_key_count = -1
    if all(c in enriched.columns for c in ("data", "famiglia")):
        tmp_keys = enriched[["data", "famiglia"]].copy()
        tmp_keys["data"] = _normalize_date_string(tmp_keys["data"])
        duplicate_key_count = int(tmp_keys.duplicated(subset=["data", "famiglia"]).sum())
        if duplicate_key_count > 0:
            issues.append(f"duplicate data+famiglia rows: {duplicate_key_count}")
    else:
        issues.append("cannot check duplicate data+famiglia because key columns are missing")

    critical = _critical_nulls(
        enriched,
        ("data", "famiglia", "qty_venduta", "imponibile_netto_tot", "num_articoli"),
    )
    for column, count in critical.items():
        issues.append(f"critical nulls in {column}: {count}")

    weather_date_nulls = None
    if "weather_date" in enriched.columns:
        weather_date_nulls = int(enriched["weather_date"].isna().sum())

    manifest_missing_weather_rows = manifest_output.get("missing_weather_rows")
    if weather_date_nulls is not None and manifest_missing_weather_rows is not None:
        if int(weather_date_nulls) != int(manifest_missing_weather_rows):
            issues.append(
                f"weather_date_nulls mismatch manifest: actual={weather_date_nulls}, manifest={manifest_missing_weather_rows}"
            )

    weather_match_counts: dict[str, int] = {}
    if "weather_match_status" in enriched.columns:
        weather_match_counts = {
            str(k): int(v)
            for k, v in enriched["weather_match_status"].value_counts(dropna=False).to_dict().items()
        }
        matched_count = int(weather_match_counts.get("matched", 0))
        missing_count = int(weather_match_counts.get("missing_actual_weather", 0))

        if matched_count + missing_count != row_count:
            issues.append(
                f"weather_match_status counts do not sum to row_count: matched={matched_count}, missing={missing_count}, rows={row_count}"
            )

        if weather_date_nulls is not None and missing_count != int(weather_date_nulls):
            issues.append(
                f"weather_match missing count != weather_date_nulls: missing={missing_count}, weather_date_nulls={weather_date_nulls}"
            )
    else:
        issues.append("missing weather_match_status column")

    date_min = ""
    date_max = ""
    if "data" in enriched.columns:
        date_min, date_max = _date_bounds(enriched["data"])

    family_count = None
    if "famiglia" in enriched.columns:
        family_count = int(enriched["famiglia"].nunique(dropna=True))

    weather_added_columns = tuple(c for c in WEATHER_ADDED_COLUMNS if c in enriched.columns)
    if len(weather_added_columns) < min_weather_added_columns:
        warnings.append(
            f"weather_added_column_count below threshold: {len(weather_added_columns)} < {min_weather_added_columns}"
        )

    base_metric_mismatches, base_issues = _compare_base_metrics(
        enriched=enriched,
        family_day=family_day,
        strict_base_metrics=strict_base_metrics,
    )
    issues.extend(base_issues)

    return R3DEnrichmentDatasetValidation(
        name="enriched",
        ok=not issues,
        row_count=row_count,
        metadata_row_count=metadata_row_count,
        part_count=part_count,
        column_count=len(enriched.columns),
        family_day_row_count=family_day_row_count,
        date_min=date_min,
        date_max=date_max,
        family_count=family_count,
        duplicate_key_count=duplicate_key_count,
        required_columns_present=not missing_required,
        missing_required_columns=missing_required,
        critical_nulls=critical,
        weather_date_nulls=weather_date_nulls,
        manifest_missing_weather_rows=None if manifest_missing_weather_rows is None else int(manifest_missing_weather_rows),
        weather_match_counts=weather_match_counts,
        weather_added_column_count=len(weather_added_columns),
        weather_added_columns=weather_added_columns,
        base_metric_mismatches=base_metric_mismatches,
        issues=tuple(issues),
        warnings=tuple(warnings),
    )


def validate_r3d_enrichment(
    config: R3DEnrichmentValidationConfig,
) -> R3DEnrichmentValidationResult:
    run_dir = Path(config.run_dir)
    report_path = run_dir / "analysis" / "r3d_enrichment_validation.json"

    if not run_dir.exists():
        result = R3DEnrichmentValidationResult(
            ok=False,
            run_dir=str(run_dir),
            report_path=str(report_path),
            created_at_utc=utc_now_iso(),
            issue_count=1,
            warning_count=0,
            issues=(f"run_dir does not exist: {run_dir}",),
            warnings=tuple(),
            dataset=None,
            manifest_summary={"manifest_exists": False},
            prior_validation_summary={},
            safety={
                "db_read": "NO",
                "db_write": "NO",
                "r3a_execution": "NO",
                "r3b_execution": "NO",
                "r3c_execution": "NO",
                "r3d_execution": "NO",
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

    issues: list[str] = []
    warnings: list[str] = []

    manifest_summary, manifest_issues = _manifest_checks(run_dir)
    prior_summary, prior_issues = _prior_validation_checks(run_dir)

    issues.extend(manifest_issues)
    issues.extend(prior_issues)

    dataset = _validate_enriched_dataset(
        run_dir=run_dir,
        manifest_summary=manifest_summary,
        strict_base_metrics=config.strict_base_metrics,
        min_weather_added_columns=config.min_weather_added_columns,
    )

    for issue in dataset.issues:
        issues.append(f"enriched: {issue}")

    warnings.extend(dataset.warnings)

    result = R3DEnrichmentValidationResult(
        ok=not issues,
        run_dir=str(run_dir),
        report_path=str(report_path),
        created_at_utc=utc_now_iso(),
        issue_count=len(issues),
        warning_count=len(warnings),
        issues=tuple(issues),
        warnings=tuple(warnings),
        dataset=dataset,
        manifest_summary=manifest_summary,
        prior_validation_summary=prior_summary,
        safety=_base_safety(),
    )

    if config.write_report:
        _write_json(report_path, result.to_dict())

    return result
