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
    "r3d_execution": "NO",
    "r3d2_execution": "YES",
    "parquet_read": "YES_VALIDATED_R3D_OUTPUTS_ONLY",
    "parquet_write": "YES_R3D2_ROLLING_SIDECAR_ONLY",
    "training_execution": "NO",
    "prediction_execution": "NO",
    "publish_execution": "NO",
}

REQUIRED_PRIOR_VALIDATIONS = (
    ("R3B", "r3b_validation.json"),
    ("R3C family_day", "r3c_family_day_validation.json"),
    ("R3D enrichment", "r3d_enrichment_validation.json"),
)

FEATURE_COLUMNS = (
    "qty_lag_1_obs",
    "imponibile_lag_1_obs",
    "num_articoli_lag_1_obs",
    "qty_roll_7_obs_mean",
    "qty_roll_7_obs_sum",
    "imponibile_roll_7_obs_mean",
    "num_articoli_roll_7_obs_mean",
    "qty_roll_14_obs_mean",
    "qty_roll_14_obs_sum",
    "imponibile_roll_14_obs_mean",
    "num_articoli_roll_14_obs_mean",
    "qty_roll_28_obs_mean",
    "qty_roll_28_obs_sum",
    "imponibile_roll_28_obs_mean",
    "num_articoli_roll_28_obs_mean",
    "qty_roll_56_obs_mean",
    "qty_roll_56_obs_sum",
    "imponibile_roll_56_obs_mean",
    "num_articoli_roll_56_obs_mean",
)

ROLLING_WINDOWS = (7, 14, 28, 56)

SIDECAR_REQUIRED_COLUMNS = (
    "data",
    "famiglia",
    *FEATURE_COLUMNS,
    "r3d2_output_write_start",
    "r3d2_output_write_end",
    "r3d2_built_at_utc",
)

ENRICHED_REQUIRED_COLUMNS = (
    "data",
    "famiglia",
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
)


@dataclass(frozen=True)
class R3D2RollingSidecarValidationConfig:
    run_dir: Path | str
    write_report: bool = True
    strict_feature_recompute: bool = True
    expected_feature_count: int = 19


@dataclass(frozen=True)
class R3D2RollingSidecarDatasetValidation:
    name: str
    ok: bool
    row_count: int = 0
    metadata_row_count: int = 0
    part_count: int = 0
    column_count: int = 0
    enriched_row_count: int | None = None
    date_min: str = ""
    date_max: str = ""
    family_count: int | None = None
    duplicate_key_count: int = 0
    feature_count: int = 0
    expected_first_row_null_count: int | None = None
    required_columns_present: bool = False
    missing_required_columns: tuple[str, ...] = field(default_factory=tuple)
    feature_null_counts: dict[str, int] = field(default_factory=dict)
    feature_non_null_counts: dict[str, int] = field(default_factory=dict)
    feature_mismatches: dict[str, dict[str, float | int]] = field(default_factory=dict)
    issues: tuple[str, ...] = field(default_factory=tuple)
    warnings: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class R3D2RollingSidecarValidationResult:
    ok: bool
    run_dir: str
    report_path: str
    created_at_utc: str
    issue_count: int
    warning_count: int
    issues: tuple[str, ...]
    warnings: tuple[str, ...]
    dataset: R3D2RollingSidecarDatasetValidation | None
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


def _read_parquet_dir(path: Path, columns: list[str] | None = None) -> pd.DataFrame:
    files = _parquet_files(path)
    if not files:
        raise FileNotFoundError(f"no parquet files under {path}")
    return pd.read_parquet(path, columns=columns)


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


def _base_safety() -> dict[str, str]:
    return {
        "db_read": "NO",
        "db_write": "NO",
        "r3a_execution": "NO",
        "r3b_execution": "NO",
        "r3c_execution": "NO",
        "r3d_execution": "NO",
        "r3d2_execution": "NO",
        "parquet_read": "YES_REVIEW_ONLY",
        "parquet_write": "NO",
        "training_execution": "NO",
        "prediction_execution": "NO",
        "publish_execution": "NO",
    }


def _manifest_checks(run_dir: Path, expected_feature_count: int) -> tuple[dict[str, Any], list[str]]:
    manifest_path = run_dir / "metadata" / "r3d2_rolling_sidecar_manifest.json"
    issues: list[str] = []

    if not manifest_path.exists():
        return {"manifest_exists": False, "manifest_path": str(manifest_path)}, [
            "missing metadata/r3d2_rolling_sidecar_manifest.json"
        ]

    manifest = _read_json(manifest_path)
    output = manifest.get("output") or {}
    safety = manifest.get("safety") or {}
    feature_contract = manifest.get("feature_contract") or {}
    feature_columns = feature_contract.get("feature_columns") or []

    summary = {
        "manifest_exists": True,
        "manifest_path": str(manifest_path),
        "ok": manifest.get("ok"),
        "dry_run": manifest.get("dry_run"),
        "mode": manifest.get("mode"),
        "output": output,
        "feature_contract": feature_contract,
        "safety": safety,
    }

    if manifest.get("ok") is not True:
        issues.append("manifest ok is not true")

    if manifest.get("dry_run") is not False:
        issues.append("manifest dry_run is not false")

    if output.get("name") != "rolling_sidecar":
        issues.append(f"manifest output name is not rolling_sidecar: {output.get('name')}")

    if output.get("status") != "ok":
        issues.append(f"manifest output status is not ok: {output.get('status')}")

    if output.get("duplicate_key_count") != 0:
        issues.append(f"manifest duplicate_key_count is not zero: {output.get('duplicate_key_count')}")

    if output.get("feature_count") != expected_feature_count:
        issues.append(f"manifest feature_count mismatch: expected {expected_feature_count}, got {output.get('feature_count')}")

    if len(feature_columns) != expected_feature_count:
        issues.append(f"feature_contract feature_columns mismatch: expected {expected_feature_count}, got {len(feature_columns)}")

    if feature_contract.get("leakage_policy") != "all lag/rolling features are computed after shift(1) within famiglia":
        issues.append("feature_contract leakage_policy mismatch")

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


def _recompute_features(enriched: pd.DataFrame) -> pd.DataFrame:
    work = enriched.copy()
    work["data"] = pd.to_datetime(work["data"], errors="coerce")
    work = work.sort_values(["famiglia", "data"], kind="mergesort").reset_index(drop=True)

    for column in ("qty_venduta", "imponibile_netto_tot", "num_articoli"):
        work[column] = pd.to_numeric(work[column], errors="coerce").fillna(0)

    expected = work[["data", "famiglia"]].copy()
    expected["data"] = expected["data"].dt.strftime("%Y-%m-%d")

    group_key = work["famiglia"]
    grouped = work.groupby("famiglia", sort=False)

    qty_shifted = grouped["qty_venduta"].shift(1)
    imponibile_shifted = grouped["imponibile_netto_tot"].shift(1)
    num_articoli_shifted = grouped["num_articoli"].shift(1)

    expected["qty_lag_1_obs"] = qty_shifted
    expected["imponibile_lag_1_obs"] = imponibile_shifted
    expected["num_articoli_lag_1_obs"] = num_articoli_shifted

    for window in ROLLING_WINDOWS:
        expected[f"qty_roll_{window}_obs_mean"] = qty_shifted.groupby(group_key, sort=False).transform(
            lambda s, w=window: s.rolling(w, min_periods=1).mean()
        )
        expected[f"qty_roll_{window}_obs_sum"] = qty_shifted.groupby(group_key, sort=False).transform(
            lambda s, w=window: s.rolling(w, min_periods=1).sum()
        )
        expected[f"imponibile_roll_{window}_obs_mean"] = imponibile_shifted.groupby(group_key, sort=False).transform(
            lambda s, w=window: s.rolling(w, min_periods=1).mean()
        )
        expected[f"num_articoli_roll_{window}_obs_mean"] = num_articoli_shifted.groupby(group_key, sort=False).transform(
            lambda s, w=window: s.rolling(w, min_periods=1).mean()
        )

    return expected


def _compare_recomputed_features(
    sidecar: pd.DataFrame,
    enriched: pd.DataFrame,
    strict_feature_recompute: bool,
) -> tuple[dict[str, dict[str, float | int]], list[str]]:
    issues: list[str] = []
    mismatches: dict[str, dict[str, float | int]] = {}

    expected = _recompute_features(enriched)

    actual_cols = ["data", "famiglia"] + [c for c in FEATURE_COLUMNS if c in sidecar.columns]
    actual = sidecar[actual_cols].copy()
    actual["data"] = _normalize_date_string(actual["data"])

    compare = actual.merge(
        expected,
        on=["data", "famiglia"],
        how="outer",
        suffixes=("_actual", "_expected"),
        indicator=True,
    )

    if not (compare["_merge"] == "both").all():
        missing_actual = int((compare["_merge"] == "right_only").sum())
        extra_actual = int((compare["_merge"] == "left_only").sum())
        issues.append(
            f"recomputed feature key mismatch: missing_actual={missing_actual}, extra_actual={extra_actual}"
        )

    for column in FEATURE_COLUMNS:
        actual_col = f"{column}_actual"
        expected_col = f"{column}_expected"

        if actual_col not in compare.columns or expected_col not in compare.columns:
            mismatches[column] = {"mismatch_count": -1, "max_abs_diff": -1}
            issues.append(f"cannot compare feature {column}: missing comparison column")
            continue

        a = pd.to_numeric(compare[actual_col], errors="coerce")
        e = pd.to_numeric(compare[expected_col], errors="coerce")

        both_null = a.isna() & e.isna()
        diff = (a.fillna(0) - e.fillna(0)).abs()
        mismatch_mask = (~both_null) & (diff > 1e-9)

        mismatch_count = int(mismatch_mask.sum())
        max_abs_diff = float(diff.max()) if len(diff) else 0.0

        mismatches[column] = {
            "mismatch_count": mismatch_count,
            "max_abs_diff": max_abs_diff,
        }

        if strict_feature_recompute and mismatch_count > 0:
            issues.append(f"feature mismatch {column}: mismatch_count={mismatch_count}, max_abs_diff={max_abs_diff}")

    return mismatches, issues


def _validate_sidecar_dataset(
    run_dir: Path,
    manifest_summary: dict[str, Any],
    strict_feature_recompute: bool,
    expected_feature_count: int,
) -> R3D2RollingSidecarDatasetValidation:
    issues: list[str] = []
    warnings: list[str] = []

    sidecar_dir = run_dir / "rolling_sidecar"
    enriched_dir = run_dir / "enriched"

    part_count, metadata_row_count = _parquet_row_count(sidecar_dir)

    try:
        sidecar = _read_parquet_dir(sidecar_dir)
    except Exception as exc:
        return R3D2RollingSidecarDatasetValidation(
            name="rolling_sidecar",
            ok=False,
            part_count=part_count,
            metadata_row_count=metadata_row_count,
            issues=(f"cannot read rolling_sidecar parquet: {type(exc).__name__}: {exc}",),
        )

    try:
        enriched = _read_parquet_dir(enriched_dir, columns=list(ENRICHED_REQUIRED_COLUMNS))
    except Exception as exc:
        return R3D2RollingSidecarDatasetValidation(
            name="rolling_sidecar",
            ok=False,
            part_count=part_count,
            metadata_row_count=metadata_row_count,
            row_count=int(len(sidecar)),
            issues=(f"cannot read enriched parquet: {type(exc).__name__}: {exc}",),
        )

    missing_required = tuple(c for c in SIDECAR_REQUIRED_COLUMNS if c not in sidecar.columns)
    if missing_required:
        issues.append("missing required columns: " + ",".join(missing_required))

    row_count = int(len(sidecar))
    enriched_row_count = int(len(enriched))

    if row_count <= 0:
        issues.append("row_count is zero")

    if row_count != enriched_row_count:
        issues.append(f"rolling_sidecar row_count != enriched row_count: sidecar={row_count}, enriched={enriched_row_count}")

    if metadata_row_count != row_count:
        issues.append(f"metadata vs pandas row count mismatch: metadata={metadata_row_count}, pandas={row_count}")

    manifest_output = (manifest_summary.get("output") or {}) if manifest_summary else {}
    manifest_row_count = manifest_output.get("row_count")
    if manifest_row_count is not None and int(manifest_row_count) != row_count:
        issues.append(f"manifest row_count mismatch: manifest={manifest_row_count}, actual={row_count}")

    duplicate_key_count = -1
    if all(c in sidecar.columns for c in ("data", "famiglia")):
        sidecar_keys = sidecar[["data", "famiglia"]].copy()
        sidecar_keys["data"] = _normalize_date_string(sidecar_keys["data"])
        duplicate_key_count = int(sidecar_keys.duplicated(subset=["data", "famiglia"]).sum())
        if duplicate_key_count > 0:
            issues.append(f"duplicate data+famiglia rows: {duplicate_key_count}")
    else:
        issues.append("cannot check duplicate data+famiglia because key columns are missing")

    if all(c in sidecar.columns for c in ("data", "famiglia")):
        sidecar_keys = sidecar[["data", "famiglia"]].copy()
        sidecar_keys["data"] = _normalize_date_string(sidecar_keys["data"])

        enriched_keys = enriched[["data", "famiglia"]].copy()
        enriched_keys["data"] = _normalize_date_string(enriched_keys["data"])

        key_merge = sidecar_keys.merge(
            enriched_keys,
            on=["data", "famiglia"],
            how="outer",
            indicator=True,
        )

        if not (key_merge["_merge"] == "both").all():
            missing_in_sidecar = int((key_merge["_merge"] == "right_only").sum())
            extra_in_sidecar = int((key_merge["_merge"] == "left_only").sum())
            issues.append(
                f"key mismatch vs enriched: missing_in_sidecar={missing_in_sidecar}, extra_in_sidecar={extra_in_sidecar}"
            )

    feature_count = len([c for c in FEATURE_COLUMNS if c in sidecar.columns])
    if feature_count != expected_feature_count:
        issues.append(f"feature_count mismatch: expected={expected_feature_count}, actual={feature_count}")

    date_min = ""
    date_max = ""
    if "data" in sidecar.columns:
        date_min, date_max = _date_bounds(sidecar["data"])

    family_count = None
    if "famiglia" in sidecar.columns:
        family_count = int(sidecar["famiglia"].nunique(dropna=True))

    expected_first_row_null_count = family_count

    feature_null_counts = {}
    feature_non_null_counts = {}
    for column in FEATURE_COLUMNS:
        if column in sidecar.columns:
            feature_null_counts[column] = int(sidecar[column].isna().sum())
            feature_non_null_counts[column] = int(sidecar[column].notna().sum())

            if expected_first_row_null_count is not None and feature_null_counts[column] != expected_first_row_null_count:
                warnings.append(
                    f"{column} null count differs from family_count: "
                    f"nulls={feature_null_counts[column]}, family_count={expected_first_row_null_count}"
                )

    feature_mismatches, feature_issues = _compare_recomputed_features(
        sidecar=sidecar,
        enriched=enriched,
        strict_feature_recompute=strict_feature_recompute,
    )
    issues.extend(feature_issues)

    return R3D2RollingSidecarDatasetValidation(
        name="rolling_sidecar",
        ok=not issues,
        row_count=row_count,
        metadata_row_count=metadata_row_count,
        part_count=part_count,
        column_count=len(sidecar.columns),
        enriched_row_count=enriched_row_count,
        date_min=date_min,
        date_max=date_max,
        family_count=family_count,
        duplicate_key_count=duplicate_key_count,
        feature_count=feature_count,
        expected_first_row_null_count=expected_first_row_null_count,
        required_columns_present=not missing_required,
        missing_required_columns=missing_required,
        feature_null_counts=feature_null_counts,
        feature_non_null_counts=feature_non_null_counts,
        feature_mismatches=feature_mismatches,
        issues=tuple(issues),
        warnings=tuple(warnings),
    )


def validate_r3d2_rolling_sidecar(
    config: R3D2RollingSidecarValidationConfig,
) -> R3D2RollingSidecarValidationResult:
    run_dir = Path(config.run_dir)
    report_path = run_dir / "analysis" / "r3d2_rolling_sidecar_validation.json"

    if not run_dir.exists():
        result = R3D2RollingSidecarValidationResult(
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
                "r3d2_execution": "NO",
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

    manifest_summary, manifest_issues = _manifest_checks(
        run_dir=run_dir,
        expected_feature_count=config.expected_feature_count,
    )
    prior_summary, prior_issues = _prior_validation_checks(run_dir)

    issues.extend(manifest_issues)
    issues.extend(prior_issues)

    dataset = _validate_sidecar_dataset(
        run_dir=run_dir,
        manifest_summary=manifest_summary,
        strict_feature_recompute=config.strict_feature_recompute,
        expected_feature_count=config.expected_feature_count,
    )

    for issue in dataset.issues:
        issues.append(f"rolling_sidecar: {issue}")

    warnings.extend(dataset.warnings)

    result = R3D2RollingSidecarValidationResult(
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
