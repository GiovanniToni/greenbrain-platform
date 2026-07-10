"""Parameterized R3A raw extract module for GreenBrain build-global.

This module is intentionally safe by default:
- importing it has no side effects;
- dry-run is the default behavior;
- real DB extraction requires execute=True and a database_url;
- DB connections are forced read-only with default_transaction_read_only=on;
- SQL must remain SELECT-only;
- outputs are confined to the provided run_dir.

R3A extracts the canonical raw parquet inputs for later R3B/R3C stages.
"""

from __future__ import annotations

import json
import traceback
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class DatasetSpec:
    name: str
    schema: str
    table: str
    preferred_date_cols: tuple[str, ...] = ()
    preferred_order_cols: tuple[str, ...] = ()

    @property
    def source_table(self) -> str:
        return f"{self.schema}.{self.table}"


@dataclass(frozen=True)
class SkippedDataset:
    name: str
    reason: str
    source_table: str | None = None
    source_tables: tuple[str, ...] = ()


@dataclass
class R3ARawExtractConfig:
    run_id: str
    run_dir: Path
    database_url: str | None = None
    execute: bool = False
    chunk_size: int = 25_000
    statement_timeout_ms: int = 600_000
    lock_timeout_ms: int = 5_000
    connect_timeout_seconds: int = 20
    compression: str = "zstd"


@dataclass
class R3ADatasetResult:
    name: str
    source_table: str
    status: str
    row_count: int = 0
    part_count: int = 0
    columns: list[str] = field(default_factory=list)
    date_col: str | None = None
    min_date: str | None = None
    max_date: str | None = None
    output_dir: str | None = None
    format: str = "parquet"
    error: dict[str, str] | None = None


@dataclass
class R3ARawExtractResult:
    ok: bool
    run_id: str
    run_dir: str
    manifest_path: str
    dry_run: bool
    datasets: list[R3ADatasetResult]
    skipped: list[dict[str, Any]]
    safety: dict[str, str]
    connection: dict[str, Any] | None = None
    errors: list[str] = field(default_factory=list)


DEFAULT_DATASETS: tuple[DatasetSpec, ...] = (
    DatasetSpec(
        name="sales_family_daily_fact",
        schema="public",
        table="greenhouse_sales_family_daily_fact",
        preferred_date_cols=("data",),
        preferred_order_cols=("data", "famiglia", "fascia_prezzo_iva_inc"),
    ),
    DatasetSpec(
        name="products_normalized",
        schema="public",
        table="greenhouse_products_normalized",
        preferred_order_cols=("famiglia", "fascia_prezzo_iva_inc", "codice_articolo"),
    ),
    DatasetSpec(
        name="weather_actuals",
        schema="gb_weather",
        table="daily_actuals",
        preferred_date_cols=("weather_date", "data", "day"),
        preferred_order_cols=("weather_date", "data", "day", "location_code", "location_id"),
    ),
    DatasetSpec(
        name="weather_forecasts",
        schema="gb_weather",
        table="daily_forecasts",
        preferred_date_cols=("forecast_date", "weather_date", "data", "day"),
        preferred_order_cols=("forecast_date", "weather_date", "data", "day", "location_code", "location_id"),
    ),
    DatasetSpec(
        name="holidays",
        schema="public",
        table="greenhouse_holidays",
        preferred_date_cols=("data", "day"),
        preferred_order_cols=("data", "day"),
    ),
    DatasetSpec(
        name="calendar",
        schema="public",
        table="dim_iso_day",
        preferred_date_cols=("day", "data"),
        preferred_order_cols=("day", "data"),
    ),
)

SKIPPED_DATASETS: tuple[SkippedDataset, ...] = (
    SkippedDataset(
        name="sales_raw_article_detail",
        source_table="public.greenhouse_sales_raw",
        reason="Skipped to avoid extracting 4M+ raw article rows before defining article-detail contract.",
    ),
    SkippedDataset(
        name="dense_legacy_tables",
        source_tables=(
            "public.greenhouse_sales_family_daily_dense",
            "public.greenhouse_forecast_features_dense",
        ),
        reason="Dense legacy tables are intentionally not extracted.",
    ),
)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def qident(value: str) -> str:
    if "\x00" in value:
        raise ValueError("identifier contains NUL byte")
    return '"' + value.replace('"', '""') + '"'


def qtable(schema: str, table: str) -> str:
    return f"{qident(schema)}.{qident(table)}"


def json_safe(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, (dict, list, tuple)):
        return json.dumps(value, ensure_ascii=False, default=str)
    return str(value)


def row_to_jsonable(row: Any) -> dict[str, Any]:
    return {k: json_safe(v) for k, v in dict(row).items()}


def skipped_to_manifest() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for item in SKIPPED_DATASETS:
        row: dict[str, Any] = {"name": item.name, "reason": item.reason}
        if item.source_table:
            row["source_table"] = item.source_table
        if item.source_tables:
            row["source_tables"] = list(item.source_tables)
        rows.append(row)
    return rows


def safety_block(execute: bool) -> dict[str, str]:
    return {
        "training_execution": "NO",
        "model_fit": "NO",
        "predict_execution": "NO",
        "db_read": "YES" if execute else "NO",
        "db_write": "NO",
        "production_model_write": "NO",
        "cloud_upload": "NO",
        "commit": "NO",
        "r3a_execution": "YES" if execute else "NO",
    }


def ensure_run_layout(run_dir: Path) -> None:
    (run_dir / "raw_extracts").mkdir(parents=True, exist_ok=True)
    (run_dir / "metadata").mkdir(parents=True, exist_ok=True)
    (run_dir / "logs").mkdir(parents=True, exist_ok=True)


def manifest_dict(result: R3ARawExtractResult) -> dict[str, Any]:
    return {
        "ok": result.ok,
        "run_id": result.run_id,
        "created_at_utc": utc_now_iso(),
        "container_out_dir": result.run_dir,
        "manifest_path": result.manifest_path,
        "dry_run": result.dry_run,
        "datasets": [asdict(ds) for ds in result.datasets],
        "skipped": result.skipped,
        "safety": result.safety,
        "connection": result.connection,
        "errors": result.errors,
    }


def write_extract_manifest(result: R3ARawExtractResult) -> None:
    path = Path(result.manifest_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(manifest_dict(result), indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def planned_result(config: R3ARawExtractConfig) -> R3ARawExtractResult:
    run_dir = Path(config.run_dir)
    manifest_path = run_dir / "metadata" / "extract_manifest.json"

    datasets = [
        R3ADatasetResult(
            name=spec.name,
            source_table=spec.source_table,
            status="planned",
            output_dir=str(run_dir / "raw_extracts" / spec.name),
        )
        for spec in DEFAULT_DATASETS
    ]

    return R3ARawExtractResult(
        ok=True,
        run_id=config.run_id,
        run_dir=str(run_dir),
        manifest_path=str(manifest_path),
        dry_run=True,
        datasets=datasets,
        skipped=skipped_to_manifest(),
        safety=safety_block(execute=False),
    )


def build_raw_extracts(config: R3ARawExtractConfig) -> R3ARawExtractResult:
    """Build R3A raw parquet extracts.

    Dry-run mode writes only a planned manifest. Real execution is available
    only when config.execute=True and config.database_url is provided.
    """

    run_dir = Path(config.run_dir)
    ensure_run_layout(run_dir)

    if not config.execute:
        result = planned_result(config)
        write_extract_manifest(result)
        return result

    if not config.database_url:
        result = R3ARawExtractResult(
            ok=False,
            run_id=config.run_id,
            run_dir=str(run_dir),
            manifest_path=str(run_dir / "metadata" / "extract_manifest.json"),
            dry_run=False,
            datasets=[],
            skipped=skipped_to_manifest(),
            safety=safety_block(execute=True),
            errors=["database_url is required when execute=True"],
        )
        write_extract_manifest(result)
        return result

    # Imports are intentionally inside the execution branch so dry-run/imports
    # do not require DB/parquet runtime dependencies.
    import psycopg
    import pyarrow as pa
    import pyarrow.parquet as pq
    from psycopg.rows import dict_row

    manifest_path = run_dir / "metadata" / "extract_manifest.json"
    result = R3ARawExtractResult(
        ok=True,
        run_id=config.run_id,
        run_dir=str(run_dir),
        manifest_path=str(manifest_path),
        dry_run=False,
        datasets=[],
        skipped=skipped_to_manifest(),
        safety=safety_block(execute=True),
    )

    conn = psycopg.connect(
        config.database_url,
        options=(
            "-c default_transaction_read_only=on "
            f"-c statement_timeout={int(config.statement_timeout_ms)} "
            f"-c lock_timeout={int(config.lock_timeout_ms)}"
        ),
        connect_timeout=int(config.connect_timeout_seconds),
        row_factory=dict_row,
    )

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                  current_database() AS current_database,
                  current_user AS current_user,
                  now() AS audit_time,
                  current_setting('server_version') AS server_version
                """
            )
            result.connection = row_to_jsonable(cur.fetchone())

        for spec in DEFAULT_DATASETS:
            ds_dir = run_dir / "raw_extracts" / spec.name
            ds_dir.mkdir(parents=True, exist_ok=True)

            dataset_result = R3ADatasetResult(
                name=spec.name,
                source_table=spec.source_table,
                status="ok",
                output_dir=str(ds_dir),
            )

            try:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        SELECT column_name
                        FROM information_schema.columns
                        WHERE table_schema = %s
                          AND table_name = %s
                        ORDER BY ordinal_position
                        """,
                        (spec.schema, spec.table),
                    )
                    columns = [r["column_name"] for r in cur.fetchall()]

                if not columns:
                    raise RuntimeError(f"No columns found for {spec.source_table}")

                dataset_result.columns = columns

                date_col = next((c for c in spec.preferred_date_cols if c in columns), None)
                dataset_result.date_col = date_col

                order_cols = [c for c in spec.preferred_order_cols if c in columns]
                order_sql = ""
                if order_cols:
                    order_sql = " ORDER BY " + ", ".join(qident(c) for c in order_cols)

                select_sql = f"SELECT * FROM {qtable(spec.schema, spec.table)}{order_sql}"

                part_count = 0
                row_count = 0
                min_date: str | None = None
                max_date: str | None = None

                with conn.cursor() as cur:
                    cur.execute(select_sql)

                    while True:
                        rows = cur.fetchmany(int(config.chunk_size))
                        if not rows:
                            break

                        json_rows = [row_to_jsonable(r) for r in rows]

                        if date_col:
                            for rr in json_rows:
                                value = rr.get(date_col)
                                if value is not None:
                                    text_value = str(value)
                                    min_date = text_value if min_date is None or text_value < min_date else min_date
                                    max_date = text_value if max_date is None or text_value > max_date else max_date

                        arrow_table = pa.Table.from_pylist(json_rows)
                        part_path = ds_dir / f"part-{part_count:05d}.parquet"
                        pq.write_table(arrow_table, part_path, compression=config.compression)

                        row_count += len(json_rows)
                        part_count += 1

                conn.rollback()

                dataset_result.row_count = row_count
                dataset_result.part_count = part_count
                dataset_result.min_date = min_date
                dataset_result.max_date = max_date

            except Exception as exc:
                conn.rollback()
                dataset_result.status = "error"
                dataset_result.error = {
                    "type": type(exc).__name__,
                    "message": str(exc),
                    "traceback": traceback.format_exc()[-4000:],
                }
                result.ok = False

            result.datasets.append(dataset_result)
            write_extract_manifest(result)

    finally:
        conn.close()

    write_extract_manifest(result)
    return result
