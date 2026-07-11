from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
import json
import shutil

import pandas as pd


VALID_MODES = {"full", "incremental_daily"}

FAMILY_DAY_REQUIRED_COLUMNS = (
    "data",
    "famiglia",
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
)

WEATHER_REQUIRED_COLUMNS = (
    "date",
    "record_type",
    "location_id",
)

WEATHER_NUMERIC_MEAN_COLUMNS = (
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
    "daylight_duration_seconds",
    "sunshine_duration_seconds",
    "snowfall_sum_cm",
)

WEATHER_FIRST_COLUMNS = (
    "weather_code",
    "iso_year",
    "iso_week",
    "week_start",
    "month_num",
    "is_holiday",
    "holiday_name",
)


@dataclass(frozen=True)
class R3DEnrichmentConfig:
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
class R3DEnrichmentOutput:
    name: str
    status: str
    row_count: int = 0
    part_count: int = 0
    input_datasets: tuple[str, ...] = ("family_day", "weather_wide")
    output_path: str = ""
    missing_weather_rows: int = 0
    duplicate_key_count: int = 0
    weather_day_rows: int = 0
    issues: tuple[str, ...] = field(default_factory=tuple)
    warnings: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class R3DEnrichmentResult:
    run_id: str
    run_dir: str
    mode: str
    dry_run: bool
    ok: bool
    output: R3DEnrichmentOutput
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


def _default_as_of_date(config: R3DEnrichmentConfig) -> date:
    return _parse_iso_date(config.as_of_date, "as_of_date") or date.today()


def _window(config: R3DEnrichmentConfig) -> tuple[date, date]:
    as_of = _default_as_of_date(config)
    output_end = _parse_iso_date(config.output_write_end, "output_write_end") or as_of

    if config.mode == "full":
        output_start = _parse_iso_date(config.output_write_start, "output_write_start") or date(2009, 1, 1)
    elif config.mode == "incremental_daily":
        output_start = _parse_iso_date(config.output_write_start, "output_write_start") or (
            output_end - timedelta(days=int(config.lookback_days))
        )
    else:
        raise ValueError(f"unsupported R3D mode: {config.mode!r}")

    if output_start > output_end:
        raise ValueError("output_write_start cannot be after output_write_end")

    return output_start, output_end


def _validate_config(config: R3DEnrichmentConfig) -> tuple[Path, date, date]:
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
        "r3d_execution": "YES" if execute else "NO",
        "parquet_read": "YES_VALIDATED_R3B_R3C_OUTPUTS_ONLY" if execute else "NO",
        "parquet_write": "YES_R3D_ENRICHED_ONLY" if execute else "NO",
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


def _normalize_date_column(df: pd.DataFrame, column: str) -> pd.DataFrame:
    out = df.copy()
    out[column] = pd.to_datetime(out[column], errors="coerce").dt.strftime("%Y-%m-%d")
    return out


def _filter_by_date(df: pd.DataFrame, column: str, start: date, end: date) -> pd.DataFrame:
    if column not in df.columns:
        raise ValueError(f"missing date column {column!r}")
    dates = pd.to_datetime(df[column], errors="coerce").dt.date
    mask = (dates >= start) & (dates <= end)
    out = df.loc[mask].copy()
    out[column] = pd.to_datetime(out[column], errors="coerce").dt.strftime("%Y-%m-%d")
    return out


def _first_non_null(series: pd.Series) -> Any:
    valid = series.dropna()
    if valid.empty:
        return None
    return valid.iloc[0]


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


def _write_manifest(
    *,
    config: R3DEnrichmentConfig,
    run_dir: Path,
    manifest_path: Path,
    output_start: date,
    output_end: date,
    output: R3DEnrichmentOutput,
    issues: Iterable[str],
    warnings: Iterable[str],
) -> R3DEnrichmentResult:
    issues_tuple = tuple(issues)
    warnings_tuple = tuple(warnings)

    if config.execute:
        ok = not issues_tuple and output.status == "ok"
    else:
        ok = not issues_tuple and output.status in {"planned", "ok"}

    result = R3DEnrichmentResult(
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
            "family_day": str(run_dir / "family_day"),
            "weather_wide": str(run_dir / "weather_wide"),
            "required_r3b_validation": str(run_dir / "analysis" / "r3b_validation.json"),
            "required_r3c_validation": str(run_dir / "analysis" / "r3c_family_day_validation.json"),
        },
        "output": output.to_dict(),
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


def _planned_output(run_dir: Path) -> R3DEnrichmentOutput:
    return R3DEnrichmentOutput(
        name="enriched",
        status="planned",
        input_datasets=("family_day", "weather_wide"),
        output_path=str(run_dir / "enriched"),
    )


def _require_validations(run_dir: Path) -> list[str]:
    issues: list[str] = []

    required = [
        ("R3B", run_dir / "analysis" / "r3b_validation.json"),
        ("R3C family_day", run_dir / "analysis" / "r3c_family_day_validation.json"),
    ]

    for label, path in required:
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


def _prepare_weather_day_actual(
    weather_wide: pd.DataFrame,
    output_start: date,
    output_end: date,
) -> pd.DataFrame:
    missing = [c for c in WEATHER_REQUIRED_COLUMNS if c not in weather_wide.columns]
    if missing:
        raise ValueError("weather_wide missing required columns: " + ",".join(missing))

    weather = _filter_by_date(weather_wide, "date", output_start, output_end)
    weather["record_type"] = weather["record_type"].astype(str)

    actual = weather[weather["record_type"] == "actual"].copy()
    if actual.empty:
        raise ValueError("weather_wide has no record_type=actual rows in requested window")

    for column in WEATHER_NUMERIC_MEAN_COLUMNS:
        if column in actual.columns:
            actual[column] = pd.to_numeric(actual[column], errors="coerce")

    named_aggs: dict[str, tuple[str, Any]] = {}

    for column in WEATHER_NUMERIC_MEAN_COLUMNS:
        if column in actual.columns:
            named_aggs[column] = (column, "mean")

    for column in WEATHER_FIRST_COLUMNS:
        if column in actual.columns:
            named_aggs[column] = (column, _first_non_null)

    weather_day = actual.groupby("date", dropna=False).agg(**named_aggs).reset_index()

    location_count = actual.groupby("date", dropna=False)["location_id"].nunique(dropna=True).reset_index()
    location_count = location_count.rename(columns={"location_id": "weather_location_count"})

    row_count = actual.groupby("date", dropna=False).size().reset_index(name="weather_actual_rows_per_date")

    weather_day = weather_day.merge(location_count, on="date", how="left")
    weather_day = weather_day.merge(row_count, on="date", how="left")

    weather_day["weather_date"] = weather_day["date"]
    weather_day["weather_record_type"] = "actual"
    weather_day["weather_day_source"] = "actual_date_level_aggregate"

    return weather_day


def _build_enriched(run_dir: Path, output_start: date, output_end: date) -> R3DEnrichmentOutput:
    issues: list[str] = []
    warnings: list[str] = []

    try:
        family_day = _read_parquet_dataset(run_dir / "family_day")
    except Exception as exc:
        return R3DEnrichmentOutput(
            name="enriched",
            status="error",
            output_path=str(run_dir / "enriched"),
            issues=(f"cannot read family_day: {type(exc).__name__}: {exc}",),
        )

    try:
        weather_wide = _read_parquet_dataset(run_dir / "weather_wide")
    except Exception as exc:
        return R3DEnrichmentOutput(
            name="enriched",
            status="error",
            output_path=str(run_dir / "enriched"),
            issues=(f"cannot read weather_wide: {type(exc).__name__}: {exc}",),
        )

    missing_family = [c for c in FAMILY_DAY_REQUIRED_COLUMNS if c not in family_day.columns]
    if missing_family:
        return R3DEnrichmentOutput(
            name="enriched",
            status="error",
            output_path=str(run_dir / "enriched"),
            issues=("family_day missing required columns: " + ",".join(missing_family),),
        )

    family = _filter_by_date(family_day, "data", output_start, output_end)
    family = family.sort_values(["data", "famiglia"], kind="mergesort").reset_index(drop=True)

    try:
        weather_day = _prepare_weather_day_actual(weather_wide, output_start, output_end)
    except Exception as exc:
        return R3DEnrichmentOutput(
            name="enriched",
            status="error",
            output_path=str(run_dir / "enriched"),
            issues=(f"cannot prepare weather_day_actual: {type(exc).__name__}: {exc}",),
        )

    enriched = family.merge(
        weather_day,
        left_on="data",
        right_on="date",
        how="left",
        suffixes=("", "_weather"),
        indicator=True,
    )

    missing_weather_rows = int((enriched["_merge"] == "left_only").sum())
    if missing_weather_rows > 0:
        warnings.append(f"family_day rows without actual weather date match: {missing_weather_rows}")

    if len(enriched) != len(family):
        issues.append(f"enriched row count changed: family_day={len(family)}, enriched={len(enriched)}")

    duplicate_key_count = int(enriched.duplicated(subset=["data", "famiglia"]).sum())
    if duplicate_key_count > 0:
        issues.append(f"duplicate data+famiglia rows in enriched: {duplicate_key_count}")

    enriched["weather_match_status"] = enriched["_merge"].map(
        {
            "both": "matched",
            "left_only": "missing_actual_weather",
            "right_only": "unexpected_right_only",
        }
    ).astype(str)

    enriched = enriched.drop(columns=["_merge", "date"], errors="ignore")

    enriched["r3d_output_write_start"] = output_start.isoformat()
    enriched["r3d_output_write_end"] = output_end.isoformat()
    enriched["r3d_built_at_utc"] = utc_now_iso()

    output_dir = run_dir / "enriched"
    part_count = _write_partitioned_parquet(enriched, output_dir)

    return R3DEnrichmentOutput(
        name="enriched",
        status="ok" if not issues else "error",
        row_count=int(len(enriched)),
        part_count=int(part_count),
        input_datasets=("family_day", "weather_wide"),
        output_path=str(output_dir),
        missing_weather_rows=missing_weather_rows,
        duplicate_key_count=duplicate_key_count,
        weather_day_rows=int(len(weather_day)),
        issues=tuple(issues),
        warnings=tuple(warnings),
    )


def build_r3d_enrichment(config: R3DEnrichmentConfig) -> R3DEnrichmentResult:
    run_dir, output_start, output_end = _validate_config(config)
    manifest_path = run_dir / "metadata" / "r3d_enrichment_manifest.json"

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
            output=R3DEnrichmentOutput(
                name="enriched",
                status="error",
                output_path=str(run_dir / "enriched"),
                issues=tuple(issues),
            ),
            issues=issues,
            warnings=[],
        )

    output = _build_enriched(run_dir, output_start, output_end)
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
