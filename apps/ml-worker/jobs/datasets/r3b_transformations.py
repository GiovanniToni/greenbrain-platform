"""R3B transformation planning helpers.

R3B is the first transformation layer after R3A raw extracts.

This module is intentionally safe by default:
- importing it has no side effects;
- dry-run/plan-only is the only implemented behavior;
- it does not read DB;
- it does not write DB;
- it does not read parquet;
- it does not write parquet;
- real materialization is intentionally deferred.

Planned R3B outputs:
- family_priceband_day/
- weather_wide/
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any


DEFAULT_FULL_START_DATE = "2009-01-01"
DEFAULT_LOOKBACK_DAYS = 40
DEFAULT_MAX_ROLLING_DEPENDENCY_DAYS = 56

VALID_MODES = frozenset({"full", "incremental", "incremental_daily", "backfill"})

R3B_OUTPUT_NAMES = ("family_priceband_day", "weather_wide")

R3A_REQUIRED_INPUTS = (
    "sales_family_daily_fact",
    "products_normalized",
    "weather_actuals",
    "weather_forecasts",
    "holidays",
    "calendar",
)


@dataclass(frozen=True)
class R3BTransformConfig:
    run_id: str
    run_dir: Path
    mode: str = "full"
    start_date: str = DEFAULT_FULL_START_DATE
    end_date: str = field(default_factory=lambda: date.today().isoformat())
    lookback_days: int = DEFAULT_LOOKBACK_DAYS
    max_rolling_dependency_days: int = DEFAULT_MAX_ROLLING_DEPENDENCY_DAYS
    source_read_start: str | None = None
    execute: bool = False
    write_manifest: bool = True


@dataclass(frozen=True)
class R3BPlannedOutput:
    name: str
    output_dir: str
    status: str
    grain: str
    input_datasets: tuple[str, ...]
    partitioning: tuple[str, ...]
    planned_column_groups: tuple[str, ...]
    notes: str


@dataclass(frozen=True)
class R3BTransformResult:
    run_id: str
    run_dir: str
    manifest_path: str | None
    ok: bool
    dry_run: bool
    execute: bool
    stage: str
    mode: str
    window: dict[str, Any]
    outputs: tuple[R3BPlannedOutput, ...]
    safety: dict[str, str]
    issues: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "run_dir": self.run_dir,
            "manifest_path": self.manifest_path,
            "ok": self.ok,
            "dry_run": self.dry_run,
            "execute": self.execute,
            "stage": self.stage,
            "mode": self.mode,
            "window": self.window,
            "outputs": [asdict(output) for output in self.outputs],
            "safety": self.safety,
            "issues": list(self.issues),
        }


def _parse_iso_date(value: str, field_name: str) -> date:
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError as exc:
        raise ValueError(f"{field_name} must be YYYY-MM-DD, got {value!r}") from exc


def _default_source_read_start(config: R3BTransformConfig) -> str:
    start = _parse_iso_date(config.start_date, "start_date")
    if config.mode == "full":
        return config.start_date
    return (start - timedelta(days=config.max_rolling_dependency_days)).isoformat()


def _validate_config(config: R3BTransformConfig) -> tuple[str, ...]:
    issues: list[str] = []

    if not config.run_id:
        issues.append("run_id is required")

    if config.mode not in VALID_MODES:
        issues.append(f"mode must be one of {sorted(VALID_MODES)}, got {config.mode!r}")

    if config.lookback_days <= 0:
        issues.append("lookback_days must be > 0")

    if config.max_rolling_dependency_days < 0:
        issues.append("max_rolling_dependency_days must be >= 0")

    try:
        start = _parse_iso_date(config.start_date, "start_date")
        end = _parse_iso_date(config.end_date, "end_date")
        if start > end:
            issues.append("start_date must be <= end_date")
    except ValueError as exc:
        issues.append(str(exc))

    if config.source_read_start is not None:
        try:
            source_start = _parse_iso_date(config.source_read_start, "source_read_start")
            start = _parse_iso_date(config.start_date, "start_date")
            if source_start > start:
                issues.append("source_read_start must be <= start_date")
        except ValueError as exc:
            issues.append(str(exc))

    if config.execute:
        issues.append(
            "execute=True is intentionally not implemented for R3B yet; "
            "this module is plan-only in this phase"
        )

    return tuple(issues)


def _planned_outputs(run_dir: Path) -> tuple[R3BPlannedOutput, ...]:
    return (
        R3BPlannedOutput(
            name="family_priceband_day",
            output_dir=str(run_dir / "family_priceband_day"),
            status="planned",
            grain="day|family|priceband",
            input_datasets=(
                "sales_family_daily_fact",
                "products_normalized",
                "holidays",
                "calendar",
            ),
            partitioning=("year_month",),
            planned_column_groups=(
                "sales_daily_metrics",
                "family_attributes",
                "priceband_attributes",
                "calendar_keys",
                "holiday_flags",
            ),
            notes=(
                "Base family/priceband/day analytical table planned from R3A raw extracts. "
                "Dry-run only: no parquet read/write."
            ),
        ),
        R3BPlannedOutput(
            name="weather_wide",
            output_dir=str(run_dir / "weather_wide"),
            status="planned",
            grain="day|location",
            input_datasets=("weather_actuals", "weather_forecasts", "calendar"),
            partitioning=("year_month",),
            planned_column_groups=(
                "actual_weather_daily",
                "forecast_weather_horizons",
                "forecast_actual_alignment",
                "weather_quality_flags",
            ),
            notes=(
                "Weather wide feature block planned from weather actuals/forecasts. "
                "Dry-run only: no parquet read/write."
            ),
        ),
    )


def build_r3b_transforms(config: R3BTransformConfig) -> R3BTransformResult:
    """Plan R3B transformations.

    In this phase, only execute=False is supported.
    The function writes metadata/r3b_transform_manifest.json when requested.
    It never reads DB, never writes DB, never reads parquet, and never writes parquet.
    """

    run_dir = Path(config.run_dir)
    manifest_path = run_dir / "metadata" / "r3b_transform_manifest.json"

    issues = _validate_config(config)
    source_read_start = config.source_read_start or _default_source_read_start(config)

    safety = {
        "db_read": "NO",
        "db_write": "NO",
        "r3a_execution": "NO",
        "r3b_execution": "NO",
        "parquet_read": "NO",
        "parquet_write": "NO",
        "pipeline_execution": "NO",
    }

    result = R3BTransformResult(
        run_id=config.run_id,
        run_dir=str(run_dir),
        manifest_path=str(manifest_path) if config.write_manifest else None,
        ok=not issues,
        dry_run=True,
        execute=False,
        stage="R3B",
        mode=config.mode,
        window={
            "start_date": config.start_date,
            "end_date": config.end_date,
            "lookback_days": config.lookback_days,
            "max_rolling_dependency_days": config.max_rolling_dependency_days,
            "source_read_start": source_read_start,
            "output_write_start": config.start_date,
            "output_write_end": config.end_date,
        },
        outputs=_planned_outputs(run_dir),
        safety=safety,
        issues=issues,
    )

    if config.write_manifest:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(result.to_dict(), indent=2, sort_keys=True, ensure_ascii=False)
            + "\n",
            encoding="utf-8",
        )

    if issues:
        raise SystemExit(
            "STOP: invalid R3B transform config: " + "; ".join(issues)
        )

    return result
