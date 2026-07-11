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
    "r3c_execution": "YES",
    "parquet_read": "YES_R3B_OUTPUTS_ONLY",
    "parquet_write": "YES_R3C_FAMILY_DAY_ONLY",
    "training_execution": "NO",
    "prediction_execution": "NO",
    "publish_execution": "NO",
}

FAMILY_DAY_REQUIRED_COLUMNS = (
    "data",
    "famiglia",
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
    "priceband_count",
    "source_priceband_rows",
    "avg_price_per_item",
    "r3c_output_write_start",
    "r3c_output_write_end",
    "r3c_built_at_utc",
)

FAMILY_PRICEBAND_REQUIRED_COLUMNS = (
    "data",
    "famiglia",
    "fascia_prezzo_iva_inc",
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
)


@dataclass(frozen=True)
class R3CFamilyDayValidationConfig:
    run_dir: Path | str
    write_report: bool = True
    strict_metric_baseline: bool = True


@dataclass(frozen=True)
class R3CFamilyDayDatasetValidation:
    name: str
    ok: bool
    row_count: int = 0
    metadata_row_count: int = 0
    part_count: int = 0
    column_count: int = 0
    baseline_row_count: int | None = None
    date_min: str = ""
    date_max: str = ""
    family_count: int | None = None
    duplicate_key_count: int = 0
    required_columns_present: bool = False
    missing_required_columns: tuple[str, ...] = field(default_factory=tuple)
    critical_nulls: dict[str, int] = field(default_factory=dict)
    metric_mismatches: dict[str, dict[str, float | int]] = field(default_factory=dict)
    avg_price_per_item_nulls: int | None = None
    zero_num_articoli_rows: int | None = None
    issues: tuple[str, ...] = field(default_factory=tuple)
    warnings: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class R3CFamilyDayValidationResult:
    ok: bool
    run_dir: str
    report_path: str
    created_at_utc: str
    issue_count: int
    warning_count: int
    issues: tuple[str, ...]
    warnings: tuple[str, ...]
    dataset: R3CFamilyDayDatasetValidation | None
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
        "parquet_read": "YES_REVIEW_ONLY",
        "parquet_write": "NO",
        "training_execution": "NO",
        "prediction_execution": "NO",
        "publish_execution": "NO",
    }


def _manifest_checks(run_dir: Path) -> tuple[dict[str, Any], list[str]]:
    manifest_path = run_dir / "metadata" / "r3c_family_day_manifest.json"
    issues: list[str] = []

    if not manifest_path.exists():
        return {"manifest_exists": False, "manifest_path": str(manifest_path)}, [
            "missing metadata/r3c_family_day_manifest.json"
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

    if output.get("name") != "family_day":
        issues.append(f"manifest output name is not family_day: {output.get('name')}")

    if output.get("status") != "ok":
        issues.append(f"manifest output status is not ok: {output.get('status')}")

    for key, expected in EXPECTED_MANIFEST_SAFETY.items():
        actual = safety.get(key)
        if actual != expected:
            issues.append(f"manifest safety mismatch {key}: expected {expected}, got {actual}")

    return summary, issues


def _prior_validation_checks(run_dir: Path) -> tuple[dict[str, Any], list[str]]:
    path = run_dir / "analysis" / "r3b_validation.json"
    issues: list[str] = []

    if not path.exists():
        return {"r3b_validation_exists": False, "path": str(path)}, [
            "missing analysis/r3b_validation.json"
        ]

    validation = _read_json(path)
    summary = {
        "r3b_validation_exists": True,
        "path": str(path),
        "ok": validation.get("ok"),
        "issue_count": validation.get("issue_count"),
        "dataset_count": validation.get("dataset_count"),
    }

    if validation.get("ok") is not True:
        issues.append("prior R3B validation ok is not true")

    if validation.get("issue_count") != 0:
        issues.append(f"prior R3B validation issue_count is not zero: {validation.get('issue_count')}")

    return summary, issues


def _baseline_from_family_priceband(run_dir: Path) -> pd.DataFrame:
    family_priceband = _read_parquet_dir(run_dir / "family_priceband_day")

    missing = [c for c in FAMILY_PRICEBAND_REQUIRED_COLUMNS if c not in family_priceband.columns]
    if missing:
        raise ValueError("family_priceband_day missing columns: " + ",".join(missing))

    src = family_priceband.copy()
    src["data"] = _normalize_date_string(src["data"])

    for column in ("qty_venduta", "imponibile_netto_tot", "num_articoli"):
        src[column] = pd.to_numeric(src[column], errors="coerce").fillna(0)

    return (
        src.groupby(["data", "famiglia"], dropna=False)
        .agg(
            qty_venduta=("qty_venduta", "sum"),
            imponibile_netto_tot=("imponibile_netto_tot", "sum"),
            num_articoli=("num_articoli", "sum"),
            priceband_count=("fascia_prezzo_iva_inc", "nunique"),
            source_priceband_rows=("fascia_prezzo_iva_inc", "size"),
        )
        .reset_index()
    )


def _compare_against_baseline(
    family_day: pd.DataFrame,
    baseline: pd.DataFrame,
    strict_metric_baseline: bool,
) -> tuple[int, dict[str, dict[str, float | int]], list[str]]:
    issues: list[str] = []
    metric_mismatches: dict[str, dict[str, float | int]] = {}

    output = family_day.copy()
    output["data"] = _normalize_date_string(output["data"])
    baseline = baseline.copy()
    baseline["data"] = _normalize_date_string(baseline["data"])

    compare_cols = (
        "qty_venduta",
        "imponibile_netto_tot",
        "num_articoli",
        "priceband_count",
        "source_priceband_rows",
    )

    merged = output[["data", "famiglia"] + [c for c in compare_cols if c in output.columns]].merge(
        baseline,
        on=["data", "famiglia"],
        how="outer",
        suffixes=("_out", "_baseline"),
        indicator=True,
    )

    if not (merged["_merge"] == "both").all():
        missing_in_output = int((merged["_merge"] == "right_only").sum())
        extra_in_output = int((merged["_merge"] == "left_only").sum())
        issues.append(
            f"key mismatch vs baseline: missing_in_output={missing_in_output}, extra_in_output={extra_in_output}"
        )

    for column in compare_cols:
        out_col = f"{column}_out"
        base_col = f"{column}_baseline"

        if out_col not in merged.columns or base_col not in merged.columns:
            metric_mismatches[column] = {"mismatch_count": -1, "max_abs_diff": -1}
            issues.append(f"cannot compare metric {column}: column missing")
            continue

        out_values = pd.to_numeric(merged[out_col], errors="coerce").fillna(0)
        base_values = pd.to_numeric(merged[base_col], errors="coerce").fillna(0)

        if column in {"qty_venduta", "imponibile_netto_tot", "num_articoli"}:
            diff = (out_values - base_values).abs()
            mismatch_count = int((diff > 1e-9).sum())
            max_abs_diff = float(diff.max()) if len(diff) else 0.0
        else:
            diff = (out_values.astype("int64") - base_values.astype("int64")).abs()
            mismatch_count = int((diff != 0).sum())
            max_abs_diff = int(diff.max()) if len(diff) else 0

        metric_mismatches[column] = {
            "mismatch_count": mismatch_count,
            "max_abs_diff": max_abs_diff,
        }

        if strict_metric_baseline and mismatch_count > 0:
            issues.append(
                f"metric mismatch {column}: mismatch_count={mismatch_count}, max_abs_diff={max_abs_diff}"
            )

    return int(len(baseline)), metric_mismatches, issues


def _validate_family_day_dataset(
    run_dir: Path,
    strict_metric_baseline: bool,
) -> R3CFamilyDayDatasetValidation:
    issues: list[str] = []
    warnings: list[str] = []

    family_day_dir = run_dir / "family_day"
    part_count, metadata_row_count = _parquet_row_count(family_day_dir)

    try:
        family_day = _read_parquet_dir(family_day_dir)
    except Exception as exc:
        return R3CFamilyDayDatasetValidation(
            name="family_day",
            ok=False,
            part_count=part_count,
            metadata_row_count=metadata_row_count,
            issues=(f"cannot read family_day parquet: {type(exc).__name__}: {exc}",),
        )

    missing = tuple(c for c in FAMILY_DAY_REQUIRED_COLUMNS if c not in family_day.columns)
    if missing:
        issues.append("missing required columns: " + ",".join(missing))

    row_count = int(len(family_day))
    if row_count <= 0:
        issues.append("row_count is zero")

    if metadata_row_count != row_count:
        issues.append(f"metadata vs pandas row count mismatch: metadata={metadata_row_count}, pandas={row_count}")

    duplicate_key_count = -1
    if all(c in family_day.columns for c in ("data", "famiglia")):
        tmp_keys = family_day[["data", "famiglia"]].copy()
        tmp_keys["data"] = _normalize_date_string(tmp_keys["data"])
        duplicate_key_count = int(tmp_keys.duplicated(subset=["data", "famiglia"]).sum())
        if duplicate_key_count > 0:
            issues.append(f"duplicate data+famiglia rows: {duplicate_key_count}")
    else:
        issues.append("cannot check duplicate data+famiglia because key columns are missing")

    critical = _critical_nulls(
        family_day,
        (
            "data",
            "famiglia",
            "qty_venduta",
            "imponibile_netto_tot",
            "num_articoli",
            "priceband_count",
            "source_priceband_rows",
        ),
    )
    for column, count in critical.items():
        issues.append(f"critical nulls in {column}: {count}")

    avg_price_per_item_nulls = None
    zero_num_articoli_rows = None
    if "avg_price_per_item" in family_day.columns and "num_articoli" in family_day.columns:
        avg_price_per_item_nulls = int(family_day["avg_price_per_item"].isna().sum())
        zero_num_articoli_rows = int((pd.to_numeric(family_day["num_articoli"], errors="coerce") == 0).sum())
        if avg_price_per_item_nulls != zero_num_articoli_rows:
            warnings.append(
                "avg_price_per_item null count differs from zero num_articoli count: "
                f"avg_nulls={avg_price_per_item_nulls}, zero_num_articoli={zero_num_articoli_rows}"
            )

    date_min = ""
    date_max = ""
    if "data" in family_day.columns:
        date_min, date_max = _date_bounds(family_day["data"])

    family_count = None
    if "famiglia" in family_day.columns:
        family_count = int(family_day["famiglia"].nunique(dropna=True))

    baseline_row_count = None
    metric_mismatches: dict[str, dict[str, float | int]] = {}

    try:
        baseline = _baseline_from_family_priceband(run_dir)
        baseline_row_count, metric_mismatches, baseline_issues = _compare_against_baseline(
            family_day,
            baseline,
            strict_metric_baseline,
        )
        issues.extend(baseline_issues)

        if baseline_row_count != row_count:
            issues.append(f"baseline row count mismatch: family_day={row_count}, baseline={baseline_row_count}")

    except Exception as exc:
        issues.append(f"cannot compute or compare baseline: {type(exc).__name__}: {exc}")

    return R3CFamilyDayDatasetValidation(
        name="family_day",
        ok=not issues,
        row_count=row_count,
        metadata_row_count=metadata_row_count,
        part_count=part_count,
        column_count=len(family_day.columns),
        baseline_row_count=baseline_row_count,
        date_min=date_min,
        date_max=date_max,
        family_count=family_count,
        duplicate_key_count=duplicate_key_count,
        required_columns_present=not missing,
        missing_required_columns=missing,
        critical_nulls=critical,
        metric_mismatches=metric_mismatches,
        avg_price_per_item_nulls=avg_price_per_item_nulls,
        zero_num_articoli_rows=zero_num_articoli_rows,
        issues=tuple(issues),
        warnings=tuple(warnings),
    )


def validate_r3c_family_day(
    config: R3CFamilyDayValidationConfig,
) -> R3CFamilyDayValidationResult:
    run_dir = Path(config.run_dir)
    report_path = run_dir / "analysis" / "r3c_family_day_validation.json"

    issues: list[str] = []
    warnings: list[str] = []

    if not run_dir.exists():
        result = R3CFamilyDayValidationResult(
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
            prior_validation_summary={"r3b_validation_exists": False},
            safety={
                "db_read": "NO",
                "db_write": "NO",
                "r3a_execution": "NO",
                "r3b_execution": "NO",
                "r3c_execution": "NO",
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
    prior_summary, prior_issues = _prior_validation_checks(run_dir)

    issues.extend(manifest_issues)
    issues.extend(prior_issues)

    dataset = _validate_family_day_dataset(
        run_dir=run_dir,
        strict_metric_baseline=config.strict_metric_baseline,
    )

    for issue in dataset.issues:
        issues.append(f"family_day: {issue}")

    warnings.extend(dataset.warnings)

    result = R3CFamilyDayValidationResult(
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
