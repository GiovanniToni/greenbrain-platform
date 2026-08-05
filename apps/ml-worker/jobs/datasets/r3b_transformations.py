from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
import hashlib
import json
import os
import shutil
import uuid

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
    input_run_dir: Path | None = None,
    transaction_id: str | None = None,
    manifest_path: Path,
    source_start: date,
    output_start: date,
    output_end: date,
    outputs: Iterable[R3BOutputResult],
    issues: Iterable[str],
) -> R3BTransformResult:
    outputs_tuple = tuple(outputs)
    issues_tuple = tuple(issues)
    effective_input_root = (
        Path(input_run_dir)
        if input_run_dir is not None
        else run_dir
    )
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
            "raw_extracts_dir": str(effective_input_root / "raw_extracts"),
            "required_raw_datasets": list(REQUIRED_RAW_DATASETS),
        },
        "outputs": [output.to_dict() for output in outputs_tuple],
        "ok": ok,
        "issues": list(issues_tuple),
        "safety": result.safety,
        "manifest_path": str(manifest_path),
        "transaction": (
            {"transaction_id": transaction_id}
            if transaction_id is not None
            else None
        ),
    }

    _atomic_write_json(manifest_path, manifest)

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


def _write_partitioned_parquet(
    df: pd.DataFrame,
    output_dir: Path,
    max_rows_per_file: int = 50_000,
) -> int:
    output_dir = Path(output_dir)
    parent_dir = output_dir.parent

    if output_dir.name not in OUTPUT_DATASETS:
        raise ValueError(
            "refusing unowned R3B output directory: "
            f"{output_dir}"
        )

    if parent_dir.is_symlink():
        raise ValueError(
            "refusing R3B output under symlink parent: "
            f"{parent_dir}"
        )

    parent_dir.mkdir(parents=True, exist_ok=True)

    if parent_dir.is_symlink():
        raise ValueError(
            "R3B output parent became a symlink: "
            f"{parent_dir}"
        )

    if output_dir.is_symlink():
        raise ValueError(
            "refusing symlink R3B output directory: "
            f"{output_dir}"
        )

    if output_dir.exists():
        raise FileExistsError(
            "refusing to overwrite existing R3B output "
            f"directory: {output_dir}"
        )

    output_dir.mkdir(mode=0o700)

    try:
        if df.empty:
            return 0

        part_count = 0
        for start in range(0, len(df), max_rows_per_file):
            part = df.iloc[start : start + max_rows_per_file]
            part_path = output_dir / f"part-{part_count:05d}.parquet"
            part.to_parquet(part_path, index=False)
            part_count += 1

        return part_count
    except Exception:
        if (
            output_dir.exists()
            and not output_dir.is_symlink()
            and output_dir.parent == parent_dir
        ):
            shutil.rmtree(output_dir)
        raise



def _build_family_priceband_day(
    run_dir: Path,
    output_root: Path,
    source_start: date,
    output_start: date,
    output_end: date,
) -> R3BOutputResult:
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
            output_path=str(output_root / "family_priceband_day"),
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

    output_dir = output_root / "family_priceband_day"
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


def _build_weather_wide(
    run_dir: Path,
    output_root: Path,
    output_start: date,
    output_end: date,
) -> R3BOutputResult:
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
            output_path=str(output_root / "weather_wide"),
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

    output_dir = output_root / "weather_wide"
    part_count = _write_partitioned_parquet(weather, output_dir)

    return R3BOutputResult(
        name="weather_wide",
        status="ok",
        row_count=int(len(weather)),
        part_count=int(part_count),
        input_datasets=("weather_actuals", "weather_forecasts", "calendar", "holidays"),
        output_path=str(output_dir),
    )


_R3B_TRANSACTION_PREFIX = ".r3b-transaction-"
_R3B_TRANSACTION_OWNERSHIP = (
    Path("metadata") / "r3b_transaction_ownership.json"
)
_R3B_TRANSACTION_JOURNAL = (
    Path("metadata") / "r3b_transaction_journal.json"
)
_R3B_OUTPUT_OWNERSHIP = ".r3b_output_ownership.json"
_R3B_OFFICIAL_MANIFEST = (
    Path("metadata") / "r3b_transform_manifest.json"
)
_R3B_PROMOTION_PHASES = {
    "promoting_family",
    "family_promoted",
    "promoting_weather",
    "weather_promoted",
    "writing_official_manifest",
}


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(
            lambda: stream.read(1024 * 1024),
            b"",
        ):
            digest.update(block)
    return digest.hexdigest()


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(str(path), os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _atomic_write_json(
    path: Path,
    payload: dict[str, Any],
) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    if path.is_symlink():
        raise ValueError(
            f"refusing JSON write through symlink: {path}"
        )

    temporary = path.with_name(
        f".{path.name}.{uuid.uuid4().hex}.tmp"
    )

    descriptor = os.open(
        str(temporary),
        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
        0o600,
    )

    try:
        with os.fdopen(
            descriptor,
            "w",
            encoding="utf-8",
        ) as stream:
            json.dump(
                _json_safe(payload),
                stream,
                indent=2,
                sort_keys=True,
            )
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())

        os.replace(temporary, path)
        _fsync_directory(path.parent)
    except Exception:
        if temporary.exists() and not temporary.is_symlink():
            temporary.unlink()
        raise


def _read_json_file(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise ValueError(
            f"invalid required JSON file: {path}"
        )

    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(
            f"JSON payload must be an object: {path}"
        )
    return payload


def _assert_direct_child(
    parent: Path,
    child: Path,
) -> None:
    parent_resolved = parent.resolve(strict=True)
    child_parent = child.parent.resolve(strict=True)

    if child_parent != parent_resolved:
        raise ValueError(
            "path is not a direct child of the owned root: "
            f"{child}"
        )


def _target_prestate(target: Path) -> dict[str, str]:
    if target.is_symlink():
        raise ValueError(
            f"refusing symlink R3B output target: {target}"
        )

    if not target.exists():
        return {"kind": "absent"}

    if not target.is_dir():
        raise ValueError(
            f"R3B output target is not a directory: {target}"
        )

    if any(target.iterdir()):
        raise FileExistsError(
            "refusing populated R3B output target: "
            f"{target}"
        )

    return {"kind": "empty_dir"}


def _restore_target_prestate(
    target: Path,
    prestate: dict[str, str],
) -> None:
    kind = prestate.get("kind")

    if kind == "absent":
        if target.exists() or target.is_symlink():
            raise RuntimeError(
                "cannot restore absent target state: "
                f"{target}"
            )
        return

    if kind == "empty_dir":
        if target.is_symlink():
            raise RuntimeError(
                "cannot restore empty directory over symlink: "
                f"{target}"
            )

        if not target.exists():
            target.mkdir(mode=0o700)
            _fsync_directory(target.parent)
            return

        if not target.is_dir() or any(target.iterdir()):
            raise RuntimeError(
                "cannot restore empty target directory: "
                f"{target}"
            )
        return

    raise RuntimeError(
        f"unknown target prestate: {prestate}"
    )


def _transaction_paths(
    transaction_root: Path,
) -> tuple[Path, Path]:
    return (
        transaction_root / _R3B_TRANSACTION_OWNERSHIP,
        transaction_root / _R3B_TRANSACTION_JOURNAL,
    )


def _read_transaction_ownership(
    run_dir: Path,
    transaction_root: Path,
) -> dict[str, Any]:
    _assert_direct_child(run_dir, transaction_root)

    if transaction_root.is_symlink():
        raise ValueError(
            "refusing symlink R3B transaction root: "
            f"{transaction_root}"
        )

    ownership_path, _ = _transaction_paths(
        transaction_root
    )
    ownership = _read_json_file(ownership_path)

    if ownership.get("kind") != "r3b_transaction":
        raise ValueError(
            "invalid R3B transaction ownership kind"
        )

    if ownership.get("run_dir") != str(
        run_dir.resolve(strict=True)
    ):
        raise ValueError(
            "R3B transaction ownership run_dir mismatch"
        )

    if ownership.get("transaction_root") != str(
        transaction_root.resolve(strict=True)
    ):
        raise ValueError(
            "R3B transaction ownership root mismatch"
        )

    return ownership


def _read_transaction_journal(
    run_dir: Path,
    transaction_root: Path,
) -> dict[str, Any]:
    ownership = _read_transaction_ownership(
        run_dir,
        transaction_root,
    )
    _, journal_path = _transaction_paths(
        transaction_root
    )
    journal = _read_json_file(journal_path)

    if (
        journal.get("transaction_id")
        != ownership.get("transaction_id")
    ):
        raise ValueError(
            "R3B transaction journal ownership mismatch"
        )

    return journal


def _write_transaction_journal(
    transaction_root: Path,
    journal: dict[str, Any],
    *,
    phase: str,
    error: str | None = None,
) -> dict[str, Any]:
    updated = dict(journal)
    updated["phase"] = phase
    updated["updated_at_utc"] = utc_now_iso()

    if error is not None:
        updated["error"] = error

    _, journal_path = _transaction_paths(
        transaction_root
    )
    _atomic_write_json(journal_path, updated)
    return updated


def _create_transaction_root(
    *,
    config: R3BTransformConfig,
    run_dir: Path,
    prestates: dict[str, dict[str, str]],
) -> tuple[Path, dict[str, Any]]:
    if run_dir.is_symlink():
        raise ValueError(
            f"refusing symlink run directory: {run_dir}"
        )

    run_dir.mkdir(parents=True, exist_ok=True)

    transaction_id = uuid.uuid4().hex
    transaction_root = run_dir / (
        _R3B_TRANSACTION_PREFIX + transaction_id
    )
    _assert_direct_child(run_dir, transaction_root)

    transaction_root.mkdir(mode=0o700)

    ownership_path, journal_path = _transaction_paths(
        transaction_root
    )

    ownership = {
        "schema_version": 1,
        "kind": "r3b_transaction",
        "transaction_id": transaction_id,
        "run_id": config.run_id,
        "run_dir": str(run_dir.resolve(strict=True)),
        "transaction_root": str(
            transaction_root.resolve(strict=True)
        ),
        "module_path": str(Path(__file__).resolve()),
        "module_sha256": _sha256_file(
            Path(__file__).resolve()
        ),
        "created_at_utc": utc_now_iso(),
    }

    journal = {
        "schema_version": 1,
        "transaction_id": transaction_id,
        "run_id": config.run_id,
        "run_dir": ownership["run_dir"],
        "transaction_root": ownership[
            "transaction_root"
        ],
        "phase": "created",
        "prestates": prestates,
        "outputs": {
            name: {
                "staged": str(transaction_root / name),
                "target": str(run_dir / name),
            }
            for name in OUTPUT_DATASETS
        },
        "created_at_utc": utc_now_iso(),
        "updated_at_utc": utc_now_iso(),
    }

    try:
        _atomic_write_json(ownership_path, ownership)
        _atomic_write_json(journal_path, journal)
        _fsync_directory(run_dir)
    except Exception:
        if (
            transaction_root.exists()
            and not transaction_root.is_symlink()
        ):
            shutil.rmtree(transaction_root)
        raise

    return transaction_root, journal


def _write_output_ownership(
    output_dir: Path,
    *,
    transaction_id: str,
    output_name: str,
) -> None:
    if output_dir.name != output_name:
        raise ValueError(
            "R3B output ownership name mismatch"
        )

    marker = output_dir / _R3B_OUTPUT_OWNERSHIP
    _atomic_write_json(
        marker,
        {
            "schema_version": 1,
            "kind": "r3b_output",
            "transaction_id": transaction_id,
            "output_name": output_name,
            "output_dir": str(
                output_dir.resolve(strict=True)
            ),
            "created_at_utc": utc_now_iso(),
        },
    )


def _output_owned_by_transaction(
    output_dir: Path,
    *,
    transaction_id: str,
    output_name: str,
) -> bool:
    if (
        not output_dir.is_dir()
        or output_dir.is_symlink()
    ):
        return False

    marker = output_dir / _R3B_OUTPUT_OWNERSHIP
    if not marker.is_file() or marker.is_symlink():
        return False

    try:
        payload = _read_json_file(marker)
    except Exception:
        return False

    return (
        payload.get("kind") == "r3b_output"
        and payload.get("transaction_id")
        == transaction_id
        and payload.get("output_name")
        == output_name
    )


def _remove_owned_output(
    run_dir: Path,
    output_dir: Path,
    *,
    transaction_id: str,
    output_name: str,
) -> None:
    _assert_direct_child(run_dir, output_dir)

    if not _output_owned_by_transaction(
        output_dir,
        transaction_id=transaction_id,
        output_name=output_name,
    ):
        raise RuntimeError(
            "refusing removal of unowned R3B output: "
            f"{output_dir}"
        )

    shutil.rmtree(output_dir)
    _fsync_directory(run_dir)


def _remove_owned_official_manifest(
    run_dir: Path,
    *,
    transaction_id: str,
) -> None:
    manifest_path = run_dir / _R3B_OFFICIAL_MANIFEST

    if not manifest_path.exists():
        return

    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise RuntimeError(
            "invalid official R3B manifest during rollback"
        )

    payload = _read_json_file(manifest_path)
    transaction = payload.get("transaction") or {}

    if (
        not isinstance(transaction, dict)
        or transaction.get("transaction_id")
        != transaction_id
    ):
        raise RuntimeError(
            "refusing removal of an official R3B manifest "
            "not owned by the active transaction"
        )

    manifest_path.unlink()
    _fsync_directory(manifest_path.parent)


def _cleanup_owned_transaction_root(
    run_dir: Path,
    transaction_root: Path,
) -> None:
    _read_transaction_ownership(
        run_dir,
        transaction_root,
    )
    shutil.rmtree(transaction_root)
    _fsync_directory(run_dir)


def _rollback_promoted_outputs(
    run_dir: Path,
    transaction_root: Path,
    journal: dict[str, Any],
) -> None:
    transaction_id = str(
        journal["transaction_id"]
    )

    journal = _write_transaction_journal(
        transaction_root,
        journal,
        phase="rolling_back",
    )

    try:
        _remove_owned_official_manifest(
            run_dir,
            transaction_id=transaction_id,
        )

        for output_name in reversed(OUTPUT_DATASETS):
            target = run_dir / output_name
            prestate = journal["prestates"][
                output_name
            ]

            if target.is_symlink():
                raise RuntimeError(
                    "R3B rollback target became a symlink: "
                    f"{target}"
                )

            if target.exists():
                if _output_owned_by_transaction(
                    target,
                    transaction_id=transaction_id,
                    output_name=output_name,
                ):
                    _remove_owned_output(
                        run_dir,
                        target,
                        transaction_id=transaction_id,
                        output_name=output_name,
                    )
                elif (
                    target.is_dir()
                    and not any(target.iterdir())
                    and prestate.get("kind")
                    == "empty_dir"
                ):
                    pass
                else:
                    raise RuntimeError(
                        "R3B rollback found an unowned target: "
                        f"{target}"
                    )

            _restore_target_prestate(
                target,
                prestate,
            )

        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="rolled_back",
        )
    except Exception as exc:
        _write_transaction_journal(
            transaction_root,
            journal,
            phase="recovery_required",
            error=f"{type(exc).__name__}: {exc}",
        )
        raise


def _recover_stale_r3b_transactions(
    run_dir: Path,
) -> None:
    if not run_dir.exists():
        return

    for transaction_root in sorted(
        run_dir.glob(
            _R3B_TRANSACTION_PREFIX + "*"
        )
    ):
        if transaction_root.is_symlink():
            raise RuntimeError(
                "stale R3B transaction path is a symlink: "
                f"{transaction_root}"
            )

        if not transaction_root.is_dir():
            raise RuntimeError(
                "stale R3B transaction path is not a directory: "
                f"{transaction_root}"
            )

        journal = _read_transaction_journal(
            run_dir,
            transaction_root,
        )
        phase = str(journal.get("phase"))

        if phase == "recovery_required":
            raise RuntimeError(
                "R3B stale transaction requires manual "
                f"recovery: {transaction_root}"
            )

        if phase in _R3B_PROMOTION_PHASES:
            _rollback_promoted_outputs(
                run_dir,
                transaction_root,
                journal,
            )
            _cleanup_owned_transaction_root(
                run_dir,
                transaction_root,
            )
            continue

        if phase == "committed":
            manifest_path = (
                run_dir / _R3B_OFFICIAL_MANIFEST
            )
            manifest = _read_json_file(
                manifest_path
            )
            transaction = (
                manifest.get("transaction") or {}
            )

            if (
                not isinstance(transaction, dict)
                or transaction.get("transaction_id")
                != journal.get("transaction_id")
            ):
                raise RuntimeError(
                    "committed R3B transaction has no "
                    "matching official manifest"
                )

            _cleanup_owned_transaction_root(
                run_dir,
                transaction_root,
            )
            continue

        if phase in {
            "created",
            "building",
            "staged",
            "validated",
            "rolled_back",
        }:
            _cleanup_owned_transaction_root(
                run_dir,
                transaction_root,
            )
            continue

        raise RuntimeError(
            "unknown stale R3B transaction phase: "
            f"{phase}"
        )


def _validate_staged_r3b_outputs(
    transaction_root: Path,
) -> None:
    try:
        from .r3b_validation import (
            R3BValidationConfig,
            validate_r3b_outputs,
        )
    except ImportError:
        from r3b_validation import (
            R3BValidationConfig,
            validate_r3b_outputs,
        )

    validation = validate_r3b_outputs(
        R3BValidationConfig(
            run_dir=transaction_root,
            write_report=False,
            strict_row_count_baseline=False,
        )
    )

    if not validation.ok:
        raise RuntimeError(
            "staged R3B validation failed: "
            + "; ".join(validation.issues)
        )


def _relocate_output_result(
    result: R3BOutputResult,
    run_dir: Path,
) -> R3BOutputResult:
    return R3BOutputResult(
        name=result.name,
        status=result.status,
        row_count=result.row_count,
        part_count=result.part_count,
        input_datasets=result.input_datasets,
        output_path=str(run_dir / result.name),
        issues=result.issues,
    )


def _failure_result_without_manifest(
    *,
    config: R3BTransformConfig,
    run_dir: Path,
    manifest_path: Path,
    outputs: list[R3BOutputResult],
    issues: list[str],
) -> R3BTransformResult:
    return R3BTransformResult(
        run_id=config.run_id,
        run_dir=str(run_dir),
        mode=config.mode,
        dry_run=False,
        ok=False,
        outputs=tuple(outputs),
        manifest_path=str(manifest_path),
        safety=_safety(True),
        issues=tuple(issues),
    )


def _promote_staged_output_pair(
    *,
    run_dir: Path,
    transaction_root: Path,
    journal: dict[str, Any],
) -> dict[str, Any]:
    transaction_id = str(
        journal["transaction_id"]
    )

    for output_name in OUTPUT_DATASETS:
        staged = transaction_root / output_name
        if not staged.is_dir() or staged.is_symlink():
            raise RuntimeError(
                "missing or invalid staged R3B output: "
                f"{staged}"
            )

        _write_output_ownership(
            staged,
            transaction_id=transaction_id,
            output_name=output_name,
        )

    family_target = run_dir / "family_priceband_day"
    weather_target = run_dir / "weather_wide"

    try:
        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="promoting_family",
        )

        if family_target.exists():
            family_target.rmdir()

        os.replace(
            transaction_root / "family_priceband_day",
            family_target,
        )
        _fsync_directory(run_dir)

        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="family_promoted",
        )

        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="promoting_weather",
        )

        if weather_target.exists():
            weather_target.rmdir()

        os.replace(
            transaction_root / "weather_wide",
            weather_target,
        )
        _fsync_directory(run_dir)

        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="weather_promoted",
        )

        return journal
    except Exception:
        _rollback_promoted_outputs(
            run_dir,
            transaction_root,
            journal,
        )
        raise


def build_r3b_transforms(
    config: R3BTransformConfig,
) -> R3BTransformResult:
    (
        run_dir,
        source_start,
        output_start,
        output_end,
    ) = _validate_config(config)

    metadata_dir = run_dir / "metadata"
    manifest_path = (
        metadata_dir
        / "r3b_transform_manifest.json"
    )

    if not config.execute:
        return _write_manifest(
            config=config,
            run_dir=run_dir,
            input_run_dir=run_dir,
            transaction_id=None,
            manifest_path=manifest_path,
            source_start=source_start,
            output_start=output_start,
            output_end=output_end,
            outputs=_planned_outputs(run_dir),
            issues=[],
        )

    _recover_stale_r3b_transactions(run_dir)

    if manifest_path.is_symlink():
        raise ValueError(
            "refusing symlink official R3B manifest"
        )

    if manifest_path.exists():
        raise FileExistsError(
            "refusing to overwrite an existing official "
            f"R3B manifest: {manifest_path}"
        )

    issues: list[str] = []
    raw_root = run_dir / "raw_extracts"

    if not raw_root.exists():
        issues.append(
            f"missing raw_extracts directory: {raw_root}"
        )

    missing_raw = (
        _require_raw_datasets(run_dir)
        if raw_root.exists()
        else list(REQUIRED_RAW_DATASETS)
    )

    if missing_raw:
        issues.append(
            "missing raw datasets: "
            + ",".join(missing_raw)
        )

    if issues:
        outputs = [
            R3BOutputResult(
                name="family_priceband_day",
                status="error",
                input_datasets=(
                    "sales_family_daily_fact",
                    "products_normalized",
                ),
                output_path=str(
                    run_dir / "family_priceband_day"
                ),
                issues=tuple(issues),
            ),
            R3BOutputResult(
                name="weather_wide",
                status="error",
                input_datasets=(
                    "weather_actuals",
                    "weather_forecasts",
                    "calendar",
                    "holidays",
                ),
                output_path=str(
                    run_dir / "weather_wide"
                ),
                issues=tuple(issues),
            ),
        ]

        return _failure_result_without_manifest(
            config=config,
            run_dir=run_dir,
            manifest_path=manifest_path,
            outputs=outputs,
            issues=issues,
        )

    prestates = {
        output_name: _target_prestate(
            run_dir / output_name
        )
        for output_name in OUTPUT_DATASETS
    }

    transaction_root, journal = (
        _create_transaction_root(
            config=config,
            run_dir=run_dir,
            prestates=prestates,
        )
    )

    staged_outputs: list[R3BOutputResult] = []

    try:
        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="building",
        )

        family_result = (
            _build_family_priceband_day(
                run_dir,
                transaction_root,
                source_start,
                output_start,
                output_end,
            )
        )
        staged_outputs.append(family_result)

        weather_result = _build_weather_wide(
            run_dir,
            transaction_root,
            output_start,
            output_end,
        )
        staged_outputs.append(weather_result)

        stage_issues = [
            issue
            for output in staged_outputs
            for issue in output.issues
        ]

        if (
            stage_issues
            or any(
                output.status != "ok"
                for output in staged_outputs
            )
        ):
            raise RuntimeError(
                "R3B staged build failed: "
                + "; ".join(stage_issues)
            )

        staged_manifest_path = (
            transaction_root
            / "metadata"
            / "r3b_transform_manifest.json"
        )

        staged_result = _write_manifest(
            config=config,
            run_dir=transaction_root,
            input_run_dir=run_dir,
            transaction_id=str(
                journal["transaction_id"]
            ),
            manifest_path=staged_manifest_path,
            source_start=source_start,
            output_start=output_start,
            output_end=output_end,
            outputs=staged_outputs,
            issues=[],
        )

        if not staged_result.ok:
            raise RuntimeError(
                "R3B staged manifest is not valid"
            )

        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="staged",
        )

        _validate_staged_r3b_outputs(
            transaction_root
        )

        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="validated",
        )

        journal = _promote_staged_output_pair(
            run_dir=run_dir,
            transaction_root=transaction_root,
            journal=journal,
        )

        official_outputs = [
            _relocate_output_result(
                output,
                run_dir,
            )
            for output in staged_outputs
        ]

        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="writing_official_manifest",
        )

        result = _write_manifest(
            config=config,
            run_dir=run_dir,
            input_run_dir=run_dir,
            transaction_id=str(
                journal["transaction_id"]
            ),
            manifest_path=manifest_path,
            source_start=source_start,
            output_start=output_start,
            output_end=output_end,
            outputs=official_outputs,
            issues=[],
        )

        if not result.ok:
            raise RuntimeError(
                "official R3B manifest is not valid"
            )

        journal = _write_transaction_journal(
            transaction_root,
            journal,
            phase="committed",
        )

        _cleanup_owned_transaction_root(
            run_dir,
            transaction_root,
        )

        return result
    except Exception as exc:
        try:
            if transaction_root.exists():
                current = _read_transaction_journal(
                    run_dir,
                    transaction_root,
                )
                phase = str(current.get("phase"))

                if phase in _R3B_PROMOTION_PHASES:
                    _rollback_promoted_outputs(
                        run_dir,
                        transaction_root,
                        current,
                    )
                    current = _read_transaction_journal(
                        run_dir,
                        transaction_root,
                    )
                    phase = str(current.get("phase"))

                if phase == "recovery_required":
                    raise RuntimeError(
                        "R3B transaction rollback requires "
                        "manual recovery"
                    )

                _cleanup_owned_transaction_root(
                    run_dir,
                    transaction_root,
                )
        except Exception as recovery_exc:
            raise RuntimeError(
                "R3B transaction failed and automatic "
                "recovery did not complete: "
                f"{type(recovery_exc).__name__}: "
                f"{recovery_exc}"
            ) from exc

        failure_issues = [
            f"{type(exc).__name__}: {exc}"
        ]

        failure_outputs = (
            [
                _relocate_output_result(
                    output,
                    run_dir,
                )
                for output in staged_outputs
            ]
            if staged_outputs
            else [
                R3BOutputResult(
                    name="family_priceband_day",
                    status="error",
                    input_datasets=(
                        "sales_family_daily_fact",
                        "products_normalized",
                    ),
                    output_path=str(
                        run_dir
                        / "family_priceband_day"
                    ),
                    issues=tuple(
                        failure_issues
                    ),
                ),
                R3BOutputResult(
                    name="weather_wide",
                    status="error",
                    input_datasets=(
                        "weather_actuals",
                        "weather_forecasts",
                        "calendar",
                        "holidays",
                    ),
                    output_path=str(
                        run_dir / "weather_wide"
                    ),
                    issues=tuple(
                        failure_issues
                    ),
                ),
            ]
        )

        return _failure_result_without_manifest(
            config=config,
            run_dir=run_dir,
            manifest_path=manifest_path,
            outputs=failure_outputs,
            issues=failure_issues,
        )
