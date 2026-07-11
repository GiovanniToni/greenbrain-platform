from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
import json
import shutil

import pandas as pd


VALID_MODES = {"full", "incremental_daily"}

REQUIRED_RAW_DATASETS = (
    "sales_family_daily_fact",
    "products_normalized",
    "weather_actuals",
    "weather_forecasts",
    "holidays",
    "calendar",
)

OUTPUT_DATASETS = (
    "family_priceband_day",
    "weather_wide",
)


@dataclass(frozen=True)
class R3BTransformConfig:
    run_id: str
    run_dir: Path | str
    mode: str = "full"
    as_of_date: str | date | None = None
    output_write_start: str | date | None = None
    output_write_end: str | date | None = None
    source_read_start: str | date | None = None
    lookback_days: int = 40
    execute: bool = False
    source: str = "cloud"


@dataclass(frozen=True)
class R3BOutputResult:
    name: str
    status: str
    row_count: int = 0
    part_count: int = 0
    input_datasets: tuple[str, ...] = field(default_factory=tuple)
    output_path: str = ""
    issues: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class R3BTransformResult:
    run_id: str
    run_dir: str
    mode: str
    dry_run: bool
    ok: bool
    outputs: tuple[R3BOutputResult, ...]
    manifest_path: str
    safety: dict[str, str]
    issues: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "run_dir": self.run_dir,
            "mode": self.mode,
            "dry_run": self.dry_run,
            "ok": self.ok,
            "outputs": [output.to_dict() for output in self.outputs],
            "manifest_path": self.manifest_path,
            "safety": dict(self.safety),
            "issues": list(self.issues),
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


def _default_as_of_date(config: R3BTransformConfig) -> date:
    return _parse_iso_date(config.as_of_date, "as_of_date") or date.today()


def _window(config: R3BTransformConfig) -> tuple[date, date, date]:
    as_of = _default_as_of_date(config)
    output_end = _parse_iso_date(config.output_write_end, "output_write_end") or as_of

    if config.mode == "full":
        output_start = _parse_iso_date(config.output_write_start, "output_write_start") or date(2009, 1, 1)
        source_start = _parse_iso_date(config.source_read_start, "source_read_start") or output_start
    elif config.mode == "incremental_daily":
        output_start = _parse_iso_date(config.output_write_start, "output_write_start") or (
            output_end - timedelta(days=int(config.lookback_days))
        )
        source_start = _parse_iso_date(config.source_read_start, "source_read_start") or (
            output_start - timedelta(days=int(config.lookback_days))
        )
    else:
        raise ValueError(f"unsupported R3B mode: {config.mode!r}")

    if source_start > output_start:
        raise ValueError("source_read_start cannot be after output_write_start")
    if output_start > output_end:
        raise ValueError("output_write_start cannot be after output_write_end")

    return source_start, output_start, output_end


def _validate_config(config: R3BTransformConfig) -> tuple[Path, date, date, date]:
    if not config.run_id:
        raise ValueError("run_id is required")

    if config.mode not in VALID_MODES:
        raise ValueError(f"mode must be one of {sorted(VALID_MODES)}, got {config.mode!r}")

    run_dir = Path(config.run_dir)
    source_start, output_start, output_end = _window(config)

    if config.lookback_days < 0:
        raise ValueError("lookback_days must be >= 0")

    return run_dir, source_start, output_start, output_end


def _safety(execute: bool) -> dict[str, str]:
    return {
        "db_read": "NO",
        "db_write": "NO",
        "r3a_execution": "NO",
        "r3b_execution": "YES" if execute else "NO",
        "parquet_read": "YES_RAW_EXTRACTS_ONLY" if execute else "NO",
        "parquet_write": "YES_R3B_OUTPUTS_ONLY" if execute else "NO",
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


def _write_manifest(
    *,
    config: R3BTransformConfig,
    run_dir: Path,
    manifest_path: Path,
    source_start: date,
    output_start: date,
    output_end: date,
    outputs: Iterable[R3BOutputResult],
    issues: Iterable[str],
) -> R3BTransformResult:
    outputs_tuple = tuple(outputs)
    issues_tuple = tuple(issues)
    if config.execute:
        ok = not issues_tuple and all(output.status == "ok" for output in outputs_tuple)
    else:
        ok = not issues_tuple and all(
            output.status in {"ok", "planned"} for output in outputs_tuple
        )

    result = R3BTransformResult(
        run_id=config.run_id,
        run_dir=str(run_dir),
        mode=config.mode,
        dry_run=not config.execute,
        ok=ok,
        outputs=outputs_tuple,
        manifest_path=str(manifest_path),
        safety=_safety(config.execute),
        issues=issues_tuple,
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
            "source_read_start": source_start.isoformat(),
            "output_write_start": output_start.isoformat(),
            "output_write_end": output_end.isoformat(),
            "lookback_days": config.lookback_days,
        },
        "inputs": {
            "raw_extracts_dir": str(run_dir / "raw_extracts"),
            "required_raw_datasets": list(REQUIRED_RAW_DATASETS),
        },
        "outputs": [output.to_dict() for output in outputs_tuple],
        "ok": ok,
        "issues": list(issues_tuple),
        "safety": result.safety,
        "manifest_path": str(manifest_path),
    }

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(_json_safe(manifest), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    return result


def _planned_outputs(run_dir: Path) -> tuple[R3BOutputResult, ...]:
    return (
        R3BOutputResult(
            name="family_priceband_day",
            status="planned",
            input_datasets=("sales_family_daily_fact", "products_normalized"),
            output_path=str(run_dir / "family_priceband_day"),
        ),
        R3BOutputResult(
            name="weather_wide",
            status="planned",
            input_datasets=("weather_actuals", "weather_forecasts", "calendar", "holidays"),
            output_path=str(run_dir / "weather_wide"),
        ),
    )


def _raw_dataset_dir(run_dir: Path, dataset_name: str) -> Path:
    return run_dir / "raw_extracts" / dataset_name


def _require_raw_datasets(run_dir: Path) -> list[str]:
    missing: list[str] = []
    for dataset_name in REQUIRED_RAW_DATASETS:
        dataset_dir = _raw_dataset_dir(run_dir, dataset_name)
        if not dataset_dir.exists() or not any(dataset_dir.rglob("*.parquet")):
            missing.append(dataset_name)
    return missing


def _read_parquet_dataset(run_dir: Path, dataset_name: str) -> pd.DataFrame:
    dataset_dir = _raw_dataset_dir(run_dir, dataset_name)
    if not dataset_dir.exists():
        raise FileNotFoundError(f"missing raw dataset directory: {dataset_dir}")
    parquet_files = sorted(dataset_dir.rglob("*.parquet"))
    if not parquet_files:
        raise FileNotFoundError(f"missing parquet files for raw dataset: {dataset_name}")
    return pd.read_parquet(dataset_dir)


def _coerce_date_column(df: pd.DataFrame, column: str) -> pd.Series:
    return pd.to_datetime(df[column], errors="coerce").dt.date


def _filter_by_date(df: pd.DataFrame, column: str, start: date, end: date) -> pd.DataFrame:
    if column not in df.columns:
        raise ValueError(f"missing date column {column!r}")
    dates = _coerce_date_column(df, column)
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


def _build_family_priceband_day(run_dir: Path, source_start: date, output_start: date, output_end: date) -> R3BOutputResult:
    sales = _read_parquet_dataset(run_dir, "sales_family_daily_fact")
    products = _read_parquet_dataset(run_dir, "products_normalized")

    required_sales = {
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
        "qty_venduta",
        "imponibile_netto_tot",
        "num_articoli",
    }
    missing_sales = sorted(required_sales - set(sales.columns))
    if missing_sales:
        return R3BOutputResult(
            name="family_priceband_day",
            status="error",
            input_datasets=("sales_family_daily_fact", "products_normalized"),
            output_path=str(run_dir / "family_priceband_day"),
            issues=(f"missing sales columns: {','.join(missing_sales)}",),
        )

    sales = _filter_by_date(sales, "data", output_start, output_end)

    product_dims = pd.DataFrame()
    optional_product_cols = [
        "famiglia",
        "fascia_prezzo_iva_inc",
        "categoria_corretta",
        "prezzo_iva_inclusa",
    ]
    if set(["famiglia", "fascia_prezzo_iva_inc"]).issubset(products.columns):
        present = [c for c in optional_product_cols if c in products.columns]
        product_dims = (
            products[present]
            .drop_duplicates(subset=["famiglia", "fascia_prezzo_iva_inc"])
            .copy()
        )

    out = sales.copy()
    if not product_dims.empty:
        out = out.merge(
            product_dims,
            on=["famiglia", "fascia_prezzo_iva_inc"],
            how="left",
            suffixes=("", "_product"),
        )

    out["r3b_source_read_start"] = source_start.isoformat()
    out["r3b_output_write_start"] = output_start.isoformat()
    out["r3b_output_write_end"] = output_end.isoformat()
    out["r3b_built_at_utc"] = utc_now_iso()

    output_dir = run_dir / "family_priceband_day"
    part_count = _write_partitioned_parquet(out, output_dir)

    return R3BOutputResult(
        name="family_priceband_day",
        status="ok",
        row_count=int(len(out)),
        part_count=int(part_count),
        input_datasets=("sales_family_daily_fact", "products_normalized"),
        output_path=str(output_dir),
    )


def _weather_common_columns(df: pd.DataFrame) -> list[str]:
    preferred = [
        "location_id",
        "weather_date",
        "forecast_run_date",
        "forecast_date",
        "forecast_horizon_days",
        "provider",
        "provider_model",
        "weather_code",
        "temperature_2m_max_c",
        "temperature_2m_min_c",
        "temperature_2m_mean_c",
        "apparent_temperature_max_c",
        "apparent_temperature_min_c",
        "apparent_temperature_mean_c",
        "sunrise_local",
        "sunset_local",
        "daylight_duration_seconds",
        "sunshine_duration_seconds",
        "uv_index_max",
        "precipitation_sum_mm",
        "rain_sum_mm",
        "snowfall_sum_cm",
        "precipitation_hours",
        "wind_speed_10m_max_kmh",
    ]
    return [c for c in preferred if c in df.columns]


def _build_weather_wide(run_dir: Path, output_start: date, output_end: date) -> R3BOutputResult:
    actuals = _read_parquet_dataset(run_dir, "weather_actuals")
    forecasts = _read_parquet_dataset(run_dir, "weather_forecasts")
    calendar = _read_parquet_dataset(run_dir, "calendar")
    holidays = _read_parquet_dataset(run_dir, "holidays")

    actual_required = {"location_id", "weather_date", "temperature_2m_max_c", "temperature_2m_min_c", "temperature_2m_mean_c"}
    forecast_required = {"location_id", "forecast_run_date", "forecast_date", "forecast_horizon_days", "temperature_2m_max_c", "temperature_2m_min_c", "temperature_2m_mean_c"}

    missing_actuals = sorted(actual_required - set(actuals.columns))
    missing_forecasts = sorted(forecast_required - set(forecasts.columns))

    issues = []
    if missing_actuals:
        issues.append(f"missing weather_actuals columns: {','.join(missing_actuals)}")
    if missing_forecasts:
        issues.append(f"missing weather_forecasts columns: {','.join(missing_forecasts)}")

    if issues:
        return R3BOutputResult(
            name="weather_wide",
            status="error",
            input_datasets=("weather_actuals", "weather_forecasts", "calendar", "holidays"),
            output_path=str(run_dir / "weather_wide"),
            issues=tuple(issues),
        )

    actuals = _filter_by_date(actuals, "weather_date", output_start, output_end)
    forecasts = _filter_by_date(forecasts, "forecast_date", output_start, output_end)

    actual_cols = _weather_common_columns(actuals)
    forecast_cols = _weather_common_columns(forecasts)

    actual_out = actuals[actual_cols].copy()
    actual_out["date"] = actual_out["weather_date"]
    actual_out["record_type"] = "actual"
    if "forecast_run_date" not in actual_out.columns:
        actual_out["forecast_run_date"] = ""
    if "forecast_date" not in actual_out.columns:
        actual_out["forecast_date"] = actual_out["date"]
    if "forecast_horizon_days" not in actual_out.columns:
        actual_out["forecast_horizon_days"] = 0

    forecast_out = forecasts[forecast_cols].copy()
    forecast_out["date"] = forecast_out["forecast_date"]
    forecast_out["record_type"] = "forecast"
    if "weather_date" not in forecast_out.columns:
        forecast_out["weather_date"] = ""

    all_cols = sorted(set(actual_out.columns) | set(forecast_out.columns))
    weather = pd.concat(
        [
            actual_out.reindex(columns=all_cols),
            forecast_out.reindex(columns=all_cols),
        ],
        ignore_index=True,
    )

    # Add light calendar/holiday context when available.
    if "day" in calendar.columns:
        cal = calendar.copy()
        cal["date"] = pd.to_datetime(cal["day"], errors="coerce").dt.strftime("%Y-%m-%d")
        cal_cols = [c for c in ["date", "iso_year", "iso_week", "week_start", "month_num"] if c in cal.columns]
        weather = weather.merge(cal[cal_cols].drop_duplicates("date"), on="date", how="left")

    if "data" in holidays.columns:
        hol = holidays.copy()
        hol["date"] = pd.to_datetime(hol["data"], errors="coerce").dt.strftime("%Y-%m-%d")
        hol_cols = [c for c in ["date", "is_holiday", "holiday_name"] if c in hol.columns]
        weather = weather.merge(hol[hol_cols].drop_duplicates("date"), on="date", how="left")

    weather["r3b_output_write_start"] = output_start.isoformat()
    weather["r3b_output_write_end"] = output_end.isoformat()
    weather["r3b_built_at_utc"] = utc_now_iso()

    output_dir = run_dir / "weather_wide"
    part_count = _write_partitioned_parquet(weather, output_dir)

    return R3BOutputResult(
        name="weather_wide",
        status="ok",
        row_count=int(len(weather)),
        part_count=int(part_count),
        input_datasets=("weather_actuals", "weather_forecasts", "calendar", "holidays"),
        output_path=str(output_dir),
    )


def build_r3b_transforms(config: R3BTransformConfig) -> R3BTransformResult:
    run_dir, source_start, output_start, output_end = _validate_config(config)
    metadata_dir = run_dir / "metadata"
    manifest_path = metadata_dir / "r3b_transform_manifest.json"

    if not config.execute:
        return _write_manifest(
            config=config,
            run_dir=run_dir,
            manifest_path=manifest_path,
            source_start=source_start,
            output_start=output_start,
            output_end=output_end,
            outputs=_planned_outputs(run_dir),
            issues=[],
        )

    issues: list[str] = []

    raw_root = run_dir / "raw_extracts"
    if not raw_root.exists():
        issues.append(f"missing raw_extracts directory: {raw_root}")

    missing_raw = _require_raw_datasets(run_dir) if raw_root.exists() else list(REQUIRED_RAW_DATASETS)
    if missing_raw:
        issues.append("missing raw datasets: " + ",".join(missing_raw))

    outputs: list[R3BOutputResult] = []

    if not issues:
        family_result = _build_family_priceband_day(run_dir, source_start, output_start, output_end)
        outputs.append(family_result)
        issues.extend(family_result.issues)

        weather_result = _build_weather_wide(run_dir, output_start, output_end)
        outputs.append(weather_result)
        issues.extend(weather_result.issues)
    else:
        outputs = [
            R3BOutputResult(
                name="family_priceband_day",
                status="error",
                input_datasets=("sales_family_daily_fact", "products_normalized"),
                output_path=str(run_dir / "family_priceband_day"),
                issues=tuple(issues),
            ),
            R3BOutputResult(
                name="weather_wide",
                status="error",
                input_datasets=("weather_actuals", "weather_forecasts", "calendar", "holidays"),
                output_path=str(run_dir / "weather_wide"),
                issues=tuple(issues),
            ),
        ]

    return _write_manifest(
        config=config,
        run_dir=run_dir,
        manifest_path=manifest_path,
        source_start=source_start,
        output_start=output_start,
        output_end=output_end,
        outputs=outputs,
        issues=issues,
    )
