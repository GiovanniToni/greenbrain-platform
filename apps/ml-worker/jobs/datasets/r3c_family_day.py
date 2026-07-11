from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
import json
import shutil

import pandas as pd


VALID_MODES = {"full", "incremental_daily"}

FAMILY_PRICEBAND_REQUIRED_COLUMNS = (
    "data",
    "famiglia",
    "fascia_prezzo_iva_inc",
    "qty_venduta",
    "imponibile_netto_tot",
    "num_articoli",
)

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


@dataclass(frozen=True)
class R3CFamilyDayConfig:
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
class R3CFamilyDayOutput:
    name: str
    status: str
    row_count: int = 0
    part_count: int = 0
    input_dataset: str = "family_priceband_day"
    output_path: str = ""
    issues: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class R3CFamilyDayResult:
    run_id: str
    run_dir: str
    mode: str
    dry_run: bool
    ok: bool
    output: R3CFamilyDayOutput
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
            "output": self.output.to_dict(),
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


def _default_as_of_date(config: R3CFamilyDayConfig) -> date:
    return _parse_iso_date(config.as_of_date, "as_of_date") or date.today()


def _window(config: R3CFamilyDayConfig) -> tuple[date, date]:
    as_of = _default_as_of_date(config)
    output_end = _parse_iso_date(config.output_write_end, "output_write_end") or as_of

    if config.mode == "full":
        output_start = _parse_iso_date(config.output_write_start, "output_write_start") or date(2009, 1, 1)
    elif config.mode == "incremental_daily":
        output_start = _parse_iso_date(config.output_write_start, "output_write_start") or (
            output_end - timedelta(days=int(config.lookback_days))
        )
    else:
        raise ValueError(f"unsupported R3C mode: {config.mode!r}")

    if output_start > output_end:
        raise ValueError("output_write_start cannot be after output_write_end")

    return output_start, output_end


def _validate_config(config: R3CFamilyDayConfig) -> tuple[Path, date, date]:
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
        "r3c_execution": "YES" if execute else "NO",
        "parquet_read": "YES_R3B_OUTPUTS_ONLY" if execute else "NO",
        "parquet_write": "YES_R3C_FAMILY_DAY_ONLY" if execute else "NO",
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
    config: R3CFamilyDayConfig,
    run_dir: Path,
    manifest_path: Path,
    output_start: date,
    output_end: date,
    output: R3CFamilyDayOutput,
    issues: Iterable[str],
) -> R3CFamilyDayResult:
    issues_tuple = tuple(issues)
    if config.execute:
        ok = not issues_tuple and output.status == "ok"
    else:
        ok = not issues_tuple and output.status in {"planned", "ok"}

    result = R3CFamilyDayResult(
        run_id=config.run_id,
        run_dir=str(run_dir),
        mode=config.mode,
        dry_run=not config.execute,
        ok=ok,
        output=output,
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
            "output_write_start": output_start.isoformat(),
            "output_write_end": output_end.isoformat(),
            "lookback_days": config.lookback_days,
        },
        "inputs": {
            "family_priceband_day": str(run_dir / "family_priceband_day"),
            "required_validation": str(run_dir / "analysis" / "r3b_validation.json"),
        },
        "output": output.to_dict(),
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


def _planned_output(run_dir: Path) -> R3CFamilyDayOutput:
    return R3CFamilyDayOutput(
        name="family_day",
        status="planned",
        input_dataset="family_priceband_day",
        output_path=str(run_dir / "family_day"),
    )


def _require_valid_r3b(run_dir: Path) -> list[str]:
    issues: list[str] = []
    validation_path = run_dir / "analysis" / "r3b_validation.json"

    if not validation_path.exists():
        return [f"missing required R3B validation report: {validation_path}"]

    try:
        validation = _read_json(validation_path)
    except Exception as exc:
        return [f"cannot read R3B validation report: {type(exc).__name__}: {exc}"]

    if validation.get("ok") is not True:
        issues.append("R3B validation ok is not true")

    if validation.get("issue_count") != 0:
        issues.append(f"R3B validation issue_count is not zero: {validation.get('issue_count')}")

    return issues


def _read_family_priceband(run_dir: Path) -> pd.DataFrame:
    family_dir = run_dir / "family_priceband_day"
    if not family_dir.exists():
        raise FileNotFoundError(f"missing family_priceband_day directory: {family_dir}")
    parquet_files = sorted(family_dir.rglob("*.parquet"))
    if not parquet_files:
        raise FileNotFoundError(f"missing family_priceband_day parquet files: {family_dir}")
    return pd.read_parquet(family_dir)


def _filter_by_date(df: pd.DataFrame, column: str, start: date, end: date) -> pd.DataFrame:
    if column not in df.columns:
        raise ValueError(f"missing date column {column!r}")
    dates = pd.to_datetime(df[column], errors="coerce").dt.date
    mask = (dates >= start) & (dates <= end)
    out = df.loc[mask].copy()
    out[column] = pd.to_datetime(out[column], errors="coerce").dt.strftime("%Y-%m-%d")
    return out


def _build_family_day(run_dir: Path, output_start: date, output_end: date) -> R3CFamilyDayOutput:
    issues: list[str] = []

    try:
        family_priceband = _read_family_priceband(run_dir)
    except Exception as exc:
        return R3CFamilyDayOutput(
            name="family_day",
            status="error",
            output_path=str(run_dir / "family_day"),
            issues=(f"cannot read family_priceband_day: {type(exc).__name__}: {exc}",),
        )

    missing = [c for c in FAMILY_PRICEBAND_REQUIRED_COLUMNS if c not in family_priceband.columns]
    if missing:
        return R3CFamilyDayOutput(
            name="family_day",
            status="error",
            output_path=str(run_dir / "family_day"),
            issues=("missing family_priceband_day columns: " + ",".join(missing),),
        )

    df = _filter_by_date(family_priceband, "data", output_start, output_end)

    for col in ("qty_venduta", "imponibile_netto_tot", "num_articoli"):
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)

    grouped = (
        df.groupby(["data", "famiglia"], dropna=False)
        .agg(
            qty_venduta=("qty_venduta", "sum"),
            imponibile_netto_tot=("imponibile_netto_tot", "sum"),
            num_articoli=("num_articoli", "sum"),
            priceband_count=("fascia_prezzo_iva_inc", "nunique"),
            source_priceband_rows=("fascia_prezzo_iva_inc", "size"),
        )
        .reset_index()
        .sort_values(["data", "famiglia"], kind="mergesort")
        .reset_index(drop=True)
    )

    denominator = pd.to_numeric(grouped["num_articoli"], errors="coerce")
    numerator = pd.to_numeric(grouped["imponibile_netto_tot"], errors="coerce")
    grouped["avg_price_per_item"] = (numerator / denominator).where(denominator != 0)

    grouped["r3c_output_write_start"] = output_start.isoformat()
    grouped["r3c_output_write_end"] = output_end.isoformat()
    grouped["r3c_built_at_utc"] = utc_now_iso()

    output_dir = run_dir / "family_day"
    part_count = _write_partitioned_parquet(grouped, output_dir)

    return R3CFamilyDayOutput(
        name="family_day",
        status="ok",
        row_count=int(len(grouped)),
        part_count=int(part_count),
        input_dataset="family_priceband_day",
        output_path=str(output_dir),
        issues=tuple(issues),
    )


def build_r3c_family_day(config: R3CFamilyDayConfig) -> R3CFamilyDayResult:
    run_dir, output_start, output_end = _validate_config(config)
    manifest_path = run_dir / "metadata" / "r3c_family_day_manifest.json"

    if not config.execute:
        return _write_manifest(
            config=config,
            run_dir=run_dir,
            manifest_path=manifest_path,
            output_start=output_start,
            output_end=output_end,
            output=_planned_output(run_dir),
            issues=[],
        )

    issues = _require_valid_r3b(run_dir)
    if issues:
        return _write_manifest(
            config=config,
            run_dir=run_dir,
            manifest_path=manifest_path,
            output_start=output_start,
            output_end=output_end,
            output=R3CFamilyDayOutput(
                name="family_day",
                status="error",
                output_path=str(run_dir / "family_day"),
                issues=tuple(issues),
            ),
            issues=issues,
        )

    output = _build_family_day(run_dir, output_start, output_end)
    issues.extend(output.issues)

    return _write_manifest(
        config=config,
        run_dir=run_dir,
        manifest_path=manifest_path,
        output_start=output_start,
        output_end=output_end,
        output=output,
        issues=issues,
    )
