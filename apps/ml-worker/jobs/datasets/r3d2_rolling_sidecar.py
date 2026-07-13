from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
import json
import shutil

import pandas as pd


VALID_MODES = {"full", "incremental_daily"}

REQUIRED_PRIOR_VALIDATIONS = (
    ("R3B", "r3b_validation.json"),
    ("R3C family_day", "r3c_family_day_validation.json"),
    ("R3D enrichment", "r3d_enrichment_validation.json"),
)

ENRICHED_REQUIRED_COLUMNS = (
    "data",
    "famiglia",
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
)

ROLLING_WINDOWS = (7, 14, 28, 56)

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


@dataclass(frozen=True)
class R3D2RollingSidecarConfig:
    run_id: str
    run_dir: Path | str
    mode: str = "full"
    as_of_date: str | date | None = None
    output_write_start: str | date | None = None
    output_write_end: str | date | None = None
    lookback_days: int = 40
    execute: bool = False
    source: str = "cloud"


@dataclass(frozen=True)
class R3D2RollingSidecarOutput:
    name: str
    status: str
    row_count: int = 0
    part_count: int = 0
    input_dataset: str = "enriched"
    output_path: str = ""
    feature_count: int = 0
    family_count: int = 0
    duplicate_key_count: int = 0
    feature_null_counts: dict[str, int] = field(default_factory=dict)
    feature_non_null_counts: dict[str, int] = field(default_factory=dict)
    expected_first_row_null_count: int = 0
    issues: tuple[str, ...] = field(default_factory=tuple)
    warnings: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class R3D2RollingSidecarResult:
    run_id: str
    run_dir: str
    mode: str
    dry_run: bool
    ok: bool
    output: R3D2RollingSidecarOutput
    manifest_path: str
    safety: dict[str, str]
    issues: tuple[str, ...] = field(default_factory=tuple)
    warnings: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "run_dir": self.run_dir,
            "mode": self.mode,
            "dry_run": self.dry_run,
            "ok": self.ok,
            "output": self.output.to_dict(),
            "manifest_path": self.manifest_path,
            "safety": dict(self.safety),
            "issues": list(self.issues),
            "warnings": list(self.warnings),
        }


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_iso_date(value: str | date | None, field_name: str) -> date | None:
    if value is None:
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, str):
        try:
            return date.fromisoformat(value)
        except ValueError as exc:
            raise ValueError(f"{field_name} must be ISO date YYYY-MM-DD, got {value!r}") from exc
    raise TypeError(f"{field_name} must be str/date/None, got {type(value).__name__}")


def _default_as_of_date(config: R3D2RollingSidecarConfig) -> date:
    return _parse_iso_date(config.as_of_date, "as_of_date") or date.today()


def _window(config: R3D2RollingSidecarConfig) -> tuple[date, date]:
    as_of = _default_as_of_date(config)
    output_end = _parse_iso_date(config.output_write_end, "output_write_end") or as_of

    if config.mode == "full":
        output_start = _parse_iso_date(config.output_write_start, "output_write_start") or date(2009, 1, 1)
    elif config.mode == "incremental_daily":
        output_start = _parse_iso_date(config.output_write_start, "output_write_start") or (
            output_end - timedelta(days=int(config.lookback_days))
        )
    else:
        raise ValueError(f"unsupported R3D2 mode: {config.mode!r}")

    if output_start > output_end:
        raise ValueError("output_write_start cannot be after output_write_end")

    return output_start, output_end


def _validate_config(config: R3D2RollingSidecarConfig) -> tuple[Path, date, date]:
    if not config.run_id:
        raise ValueError("run_id is required")

    if config.mode not in VALID_MODES:
        raise ValueError(f"mode must be one of {sorted(VALID_MODES)}, got {config.mode!r}")

    if config.lookback_days < 0:
        raise ValueError("lookback_days must be >= 0")

    run_dir = Path(config.run_dir)
    output_start, output_end = _window(config)

    return run_dir, output_start, output_end


def _safety(execute: bool) -> dict[str, str]:
    return {
        "db_read": "NO",
        "db_write": "NO",
        "r3a_execution": "NO",
        "r3b_execution": "NO",
        "r3c_execution": "NO",
        "r3d_execution": "NO",
        "r3d2_execution": "YES" if execute else "NO",
        "parquet_read": "YES_VALIDATED_R3D_OUTPUTS_ONLY" if execute else "NO",
        "parquet_write": "YES_R3D2_ROLLING_SIDECAR_ONLY" if execute else "NO",
        "training_execution": "NO",
        "prediction_execution": "NO",
        "publish_execution": "NO",
        "cli_global_change": "NO",
    }


def _json_safe(value: Any) -> Any:
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, tuple):
        return [_json_safe(v) for v in value]
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    if isinstance(value, dict):
        return {str(k): _json_safe(v) for k, v in value.items()}
    return value


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _read_parquet_dataset(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"missing parquet directory: {path}")
    files = sorted(path.rglob("*.parquet"))
    if not files:
        raise FileNotFoundError(f"missing parquet files under: {path}")
    return pd.read_parquet(path)


def _filter_by_date(df: pd.DataFrame, column: str, start: date, end: date) -> pd.DataFrame:
    if column not in df.columns:
        raise ValueError(f"missing date column {column!r}")
    dates = pd.to_datetime(df[column], errors="coerce").dt.date
    mask = (dates >= start) & (dates <= end)
    out = df.loc[mask].copy()
    out[column] = pd.to_datetime(out[column], errors="coerce").dt.strftime("%Y-%m-%d")
    return out


def _write_partitioned_parquet(df: pd.DataFrame, output_dir: Path, max_rows_per_file: int = 50_000) -> int:
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if df.empty:
        return 0

    part_count = 0
    for start in range(0, len(df), max_rows_per_file):
        chunk = df.iloc[start : start + max_rows_per_file].copy()
        part_path = output_dir / f"part-{part_count:05d}.parquet"
        chunk.to_parquet(part_path, index=False)
        part_count += 1

    return part_count


def _require_validations(run_dir: Path) -> list[str]:
    issues: list[str] = []

    for label, filename in REQUIRED_PRIOR_VALIDATIONS:
        path = run_dir / "analysis" / filename
        if not path.exists():
            issues.append(f"missing required {label} validation report: {path}")
            continue

        try:
            validation = _read_json(path)
        except Exception as exc:
            issues.append(f"cannot read {label} validation report: {type(exc).__name__}: {exc}")
            continue

        if validation.get("ok") is not True:
            issues.append(f"{label} validation ok is not true")

        if validation.get("issue_count") != 0:
            issues.append(f"{label} validation issue_count is not zero: {validation.get('issue_count')}")

    return issues


def _planned_output(run_dir: Path) -> R3D2RollingSidecarOutput:
    return R3D2RollingSidecarOutput(
        name="rolling_sidecar",
        status="planned",
        input_dataset="enriched",
        output_path=str(run_dir / "rolling_sidecar"),
        feature_count=len(FEATURE_COLUMNS),
    )


def _write_manifest(
    *,
    config: R3D2RollingSidecarConfig,
    run_dir: Path,
    manifest_path: Path,
    output_start: date,
    output_end: date,
    output: R3D2RollingSidecarOutput,
    issues: Iterable[str],
    warnings: Iterable[str],
) -> R3D2RollingSidecarResult:
    issues_tuple = tuple(issues)
    warnings_tuple = tuple(warnings)

    if config.execute:
        ok = not issues_tuple and output.status == "ok"
    else:
        ok = not issues_tuple and output.status in {"planned", "ok"}

    result = R3D2RollingSidecarResult(
        run_id=config.run_id,
        run_dir=str(run_dir),
        mode=config.mode,
        dry_run=not config.execute,
        ok=ok,
        output=output,
        manifest_path=str(manifest_path),
        safety=_safety(config.execute),
        issues=issues_tuple,
        warnings=warnings_tuple,
    )

    manifest = {
        "created_at_utc": utc_now_iso(),
        "run_id": config.run_id,
        "run_dir": str(run_dir),
        "mode": config.mode,
        "source": config.source,
        "dry_run": not config.execute,
        "execute": config.execute,
        "window": {
            "output_write_start": output_start.isoformat(),
            "output_write_end": output_end.isoformat(),
            "lookback_days": config.lookback_days,
        },
        "inputs": {
            "enriched": str(run_dir / "enriched"),
            "required_r3b_validation": str(run_dir / "analysis" / "r3b_validation.json"),
            "required_r3c_validation": str(run_dir / "analysis" / "r3c_family_day_validation.json"),
            "required_r3d_validation": str(run_dir / "analysis" / "r3d_enrichment_validation.json"),
        },
        "output": output.to_dict(),
        "feature_contract": {
            "feature_columns": list(FEATURE_COLUMNS),
            "windows": list(ROLLING_WINDOWS),
            "leakage_policy": "all lag/rolling features are computed after shift(1) within famiglia",
            "rolling_type": "observation_based",
        },
        "ok": ok,
        "issues": list(issues_tuple),
        "warnings": list(warnings_tuple),
        "safety": result.safety,
        "manifest_path": str(manifest_path),
    }

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(_json_safe(manifest), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    return result


def _numeric(df: pd.DataFrame, column: str) -> pd.Series:
    return pd.to_numeric(df[column], errors="coerce").fillna(0)


def _add_rolling_features(enriched: pd.DataFrame) -> pd.DataFrame:
    work = enriched.copy()
    work["data"] = pd.to_datetime(work["data"], errors="coerce")
    work = work.sort_values(["famiglia", "data"], kind="mergesort").reset_index(drop=True)

    for column in ("qty_venduta", "imponibile_netto_tot", "num_articoli"):
        work[column] = _numeric(work, column)

    sidecar = work[["data", "famiglia"]].copy()
    sidecar["data"] = sidecar["data"].dt.strftime("%Y-%m-%d")

    group_key = work["famiglia"]
    grouped = work.groupby("famiglia", sort=False)

    qty_shifted = grouped["qty_venduta"].shift(1)
    imponibile_shifted = grouped["imponibile_netto_tot"].shift(1)
    num_articoli_shifted = grouped["num_articoli"].shift(1)

    sidecar["qty_lag_1_obs"] = qty_shifted
    sidecar["imponibile_lag_1_obs"] = imponibile_shifted
    sidecar["num_articoli_lag_1_obs"] = num_articoli_shifted

    for window in ROLLING_WINDOWS:
        sidecar[f"qty_roll_{window}_obs_mean"] = qty_shifted.groupby(group_key, sort=False).transform(
            lambda s, w=window: s.rolling(w, min_periods=1).mean()
        )
        sidecar[f"qty_roll_{window}_obs_sum"] = qty_shifted.groupby(group_key, sort=False).transform(
            lambda s, w=window: s.rolling(w, min_periods=1).sum()
        )
        sidecar[f"imponibile_roll_{window}_obs_mean"] = imponibile_shifted.groupby(group_key, sort=False).transform(
            lambda s, w=window: s.rolling(w, min_periods=1).mean()
        )
        sidecar[f"num_articoli_roll_{window}_obs_mean"] = num_articoli_shifted.groupby(group_key, sort=False).transform(
            lambda s, w=window: s.rolling(w, min_periods=1).mean()
        )

    return sidecar


def _build_sidecar(run_dir: Path, output_start: date, output_end: date) -> R3D2RollingSidecarOutput:
    issues: list[str] = []
    warnings: list[str] = []

    try:
        enriched = _read_parquet_dataset(run_dir / "enriched")
    except Exception as exc:
        return R3D2RollingSidecarOutput(
            name="rolling_sidecar",
            status="error",
            output_path=str(run_dir / "rolling_sidecar"),
            issues=(f"cannot read enriched: {type(exc).__name__}: {exc}",),
        )

    missing = [c for c in ENRICHED_REQUIRED_COLUMNS if c not in enriched.columns]
    if missing:
        return R3D2RollingSidecarOutput(
            name="rolling_sidecar",
            status="error",
            output_path=str(run_dir / "rolling_sidecar"),
            issues=("enriched missing required columns: " + ",".join(missing),),
        )

    enriched_window = _filter_by_date(enriched, "data", output_start, output_end)
    enriched_window = enriched_window.sort_values(["famiglia", "data"], kind="mergesort").reset_index(drop=True)

    sidecar = _add_rolling_features(enriched_window)

    sidecar["r3d2_output_write_start"] = output_start.isoformat()
    sidecar["r3d2_output_write_end"] = output_end.isoformat()
    sidecar["r3d2_built_at_utc"] = utc_now_iso()

    duplicate_key_count = int(sidecar.duplicated(subset=["data", "famiglia"]).sum())
    if duplicate_key_count > 0:
        issues.append(f"duplicate data+famiglia rows in rolling_sidecar: {duplicate_key_count}")

    if len(sidecar) != len(enriched_window):
        issues.append(f"rolling_sidecar row count changed: enriched={len(enriched_window)}, sidecar={len(sidecar)}")

    family_count = int(sidecar["famiglia"].nunique(dropna=True))
    feature_null_counts = {c: int(sidecar[c].isna().sum()) for c in FEATURE_COLUMNS if c in sidecar.columns}
    feature_non_null_counts = {c: int(sidecar[c].notna().sum()) for c in FEATURE_COLUMNS if c in sidecar.columns}

    missing_features = [c for c in FEATURE_COLUMNS if c not in sidecar.columns]
    if missing_features:
        issues.append("missing rolling feature columns: " + ",".join(missing_features))

    expected_first_row_null_count = family_count
    for column, null_count in feature_null_counts.items():
        if null_count != expected_first_row_null_count:
            warnings.append(
                f"{column} null count differs from family_count: nulls={null_count}, family_count={expected_first_row_null_count}"
            )

    output_dir = run_dir / "rolling_sidecar"
    part_count = _write_partitioned_parquet(sidecar, output_dir)

    return R3D2RollingSidecarOutput(
        name="rolling_sidecar",
        status="ok" if not issues else "error",
        row_count=int(len(sidecar)),
        part_count=int(part_count),
        input_dataset="enriched",
        output_path=str(output_dir),
        feature_count=len([c for c in FEATURE_COLUMNS if c in sidecar.columns]),
        family_count=family_count,
        duplicate_key_count=duplicate_key_count,
        feature_null_counts=feature_null_counts,
        feature_non_null_counts=feature_non_null_counts,
        expected_first_row_null_count=expected_first_row_null_count,
        issues=tuple(issues),
        warnings=tuple(warnings),
    )


def build_r3d2_rolling_sidecar(config: R3D2RollingSidecarConfig) -> R3D2RollingSidecarResult:
    run_dir, output_start, output_end = _validate_config(config)
    manifest_path = run_dir / "metadata" / "r3d2_rolling_sidecar_manifest.json"

    if not config.execute:
        return _write_manifest(
            config=config,
            run_dir=run_dir,
            manifest_path=manifest_path,
            output_start=output_start,
            output_end=output_end,
            output=_planned_output(run_dir),
            issues=[],
            warnings=[],
        )

    issues = _require_validations(run_dir)
    if issues:
        return _write_manifest(
            config=config,
            run_dir=run_dir,
            manifest_path=manifest_path,
            output_start=output_start,
            output_end=output_end,
            output=R3D2RollingSidecarOutput(
                name="rolling_sidecar",
                status="error",
                output_path=str(run_dir / "rolling_sidecar"),
                issues=tuple(issues),
            ),
            issues=issues,
            warnings=[],
        )

    output = _build_sidecar(run_dir, output_start, output_end)
    issues.extend(output.issues)
    warnings = list(output.warnings)

    return _write_manifest(
        config=config,
        run_dir=run_dir,
        manifest_path=manifest_path,
        output_start=output_start,
        output_end=output_end,
        output=output,
        issues=issues,
        warnings=warnings,
    )
