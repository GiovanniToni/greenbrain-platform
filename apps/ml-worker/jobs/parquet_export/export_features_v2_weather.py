"""Export weather-enriched ML parquet dataset v2.

Local-only exporter for Feature Builder V2.

Default output path:
    apps/ml-worker/parquet_cache/features_ml/v2_weather/data_year=YYYY/famiglia_slug=<slug>/part.parquet

Safety:
    - reads DB sources only
    - no DB writes
    - no upload
    - no training/prediction side effects
    - no daily orchestration side effects

This intentionally does NOT replace export_features_dense.py.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from datetime import date, datetime
from pathlib import Path
from typing import Any

import pandas as pd
import psycopg2
from dotenv import load_dotenv


ML_WORKER_ROOT = Path(__file__).resolve().parents[2]
if str(ML_WORKER_ROOT) not in sys.path:
    sys.path.insert(0, str(ML_WORKER_ROOT))

from features.feature_builder_v2 import (  # noqa: E402
    V2_STORAGE_PREFIX,
    expected_v1_columns,
    slugify,
    build_family_year_v2_weather_frame,
    write_family_year_v2_weather_parquet,
)


DEFAULT_OUTPUT_ROOT = ML_WORKER_ROOT / "parquet_cache" / V2_STORAGE_PREFIX


def _load_env() -> None:
    if not os.getenv("PG_HOST") and not os.getenv("DATABASE_URL"):
        load_dotenv()


def pg_conn():
    _load_env()

    if os.getenv("DATABASE_URL"):
        return psycopg2.connect(os.environ["DATABASE_URL"], connect_timeout=10)

    required = ["PG_HOST", "PG_PASSWORD"]
    missing = [k for k in required if not os.getenv(k)]
    if missing:
        raise RuntimeError(f"Missing required DB env vars: {missing}")

    return psycopg2.connect(
        host=os.environ["PG_HOST"],
        port=int(os.environ.get("PG_PORT", "5432")),
        dbname=os.environ.get("PG_DB", "postgres"),
        user=os.environ.get("PG_USER", "postgres"),
        password=os.environ["PG_PASSWORD"],
        sslmode=os.getenv("PG_SSLMODE", "prefer"),
        connect_timeout=10,
    )


def normalize_family_name(value: str) -> str:
    return " ".join(str(value or "").strip().split()).lower()


def fetch_df(conn, sql: str, params: tuple[Any, ...] | None = None) -> pd.DataFrame:
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        rows = cur.fetchall()
        cols = [d.name for d in cur.description]
    return pd.DataFrame(rows, columns=cols)


def fetch_scalar(conn, sql: str, params: tuple[Any, ...] | None = None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        row = cur.fetchone()
    return row[0] if row else None


def resolve_target_window(conn, year: int, end_date: str | None) -> tuple[pd.Timestamp, pd.Timestamp, pd.Timestamp]:
    target_from = pd.Timestamp(date(int(year), 1, 1))
    year_end = pd.Timestamp(date(int(year), 12, 31))

    if end_date:
        requested_end = pd.Timestamp(end_date)
    else:
        max_fact_date = fetch_scalar(
            conn,
            "SELECT MAX(data)::date FROM public.greenhouse_sales_family_daily_fact;",
        )
        if max_fact_date is None:
            raise RuntimeError("greenhouse_sales_family_daily_fact has no max(data)")
        requested_end = pd.Timestamp(max_fact_date)

    target_to = min(year_end, requested_end)
    return target_from, target_to, year_end


def list_families(conn, family: str | None, family_slug: str | None, limit: int | None, offset: int | None) -> list[dict[str, str]]:
    if family:
        fam_norm = normalize_family_name(family)

        df = fetch_df(
            conn,
            """
            SELECT
              lower(trim(famiglia)) AS famiglia,
              famiglia_slug
            FROM public.v_famiglie_catalog
            WHERE lower(trim(famiglia)) = %s
            ORDER BY 1
            LIMIT 1;
            """,
            (fam_norm,),
        )

        if df.empty:
            return [{
                "famiglia": fam_norm,
                "famiglia_slug": family_slug or slugify(fam_norm),
            }]

        row = df.iloc[0].to_dict()
        return [{
            "famiglia": normalize_family_name(row["famiglia"]),
            "famiglia_slug": str(family_slug or row.get("famiglia_slug") or slugify(row["famiglia"])),
        }]

    sql = """
        SELECT
          lower(trim(famiglia)) AS famiglia,
          famiglia_slug
        FROM public.v_famiglie_catalog
        ORDER BY 1
    """
    params: list[Any] = []

    if limit is not None:
        sql += " LIMIT %s"
        params.append(int(limit))

    if offset is not None:
        sql += " OFFSET %s"
        params.append(int(offset))

    df = fetch_df(conn, sql, tuple(params))
    families = []
    for row in df.to_dict("records"):
        fam = normalize_family_name(row["famiglia"])
        families.append({
            "famiglia": fam,
            "famiglia_slug": str(row.get("famiglia_slug") or slugify(fam)),
        })
    return families


def load_calendar(conn, warmup_start: pd.Timestamp, target_to: pd.Timestamp) -> pd.DataFrame:
    df = fetch_df(
        conn,
        """
        SELECT *
        FROM public.greenhouse_calendar_features_daily
        WHERE data BETWEEN %s AND %s
        ORDER BY data;
        """,
        (warmup_start.date(), target_to.date()),
    )
    if not df.empty:
        df["data"] = pd.to_datetime(df["data"])
    return df


def load_weather(conn, warmup_start: pd.Timestamp, target_to: pd.Timestamp) -> pd.DataFrame:
    df = fetch_df(
        conn,
        """
        SELECT *
        FROM public.greenhouse_weather_ml_features_daily
        WHERE data BETWEEN %s AND %s
        ORDER BY data;
        """,
        (warmup_start.date(), target_to.date()),
    )
    if not df.empty:
        df["data"] = pd.to_datetime(df["data"])
    return df


def load_facts_for_family(conn, famiglia: str, warmup_start: pd.Timestamp, target_to: pd.Timestamp) -> pd.DataFrame:
    df = fetch_df(
        conn,
        """
        SELECT
          data,
          lower(trim(famiglia)) AS famiglia,
          fascia_prezzo_iva_inc,
          qty_venduta
        FROM public.greenhouse_sales_family_daily_fact
        WHERE lower(trim(famiglia)) = %s
          AND data BETWEEN %s AND %s
        ORDER BY data, fascia_prezzo_iva_inc;
        """,
        (normalize_family_name(famiglia), warmup_start.date(), target_to.date()),
    )

    if df.empty:
        return pd.DataFrame(columns=["data", "famiglia", "fascia_prezzo_iva_inc", "qty_venduta"])

    df["data"] = pd.to_datetime(df["data"])
    return df


def load_fasce_for_family(conn, famiglia: str) -> list[str]:
    df = fetch_df(
        conn,
        """
        SELECT DISTINCT fascia_prezzo_iva_inc
        FROM public.greenhouse_sales_family_daily_fact
        WHERE lower(trim(famiglia)) = %s
          AND fascia_prezzo_iva_inc IS NOT NULL
        ORDER BY fascia_prezzo_iva_inc;
        """,
        (normalize_family_name(famiglia),),
    )

    return sorted(df["fascia_prezzo_iva_inc"].dropna().astype(str).unique().tolist()) if not df.empty else []


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Export local weather-enriched ML parquet dataset v2.")

    ap.add_argument("--year", type=int, required=True, help="Target data year, e.g. 2026.")
    ap.add_argument("--family", default=None, help="Optional exact famiglia name.")
    ap.add_argument("--family-slug", default=None, help="Optional slug override when --family is used.")
    ap.add_argument("--limit-families", type=int, default=None, help="Limit number of families from catalog.")
    ap.add_argument("--offset-families", type=int, default=None, help="Offset families from catalog.")
    ap.add_argument("--end-date", default=None, help="Optional target end date YYYY-MM-DD. Defaults to min(year-end, max fact date).")
    ap.add_argument("--warmup-days", type=int, default=60, help="Warmup days before Jan 1 for lag/rolling calculations.")
    ap.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT), help="Output root. The exporter appends data_year=YYYY/famiglia_slug=<slug>/part.parquet.")
    ap.add_argument("--no-debug-metadata", action="store_true", help="Exclude debug metadata columns from output.")
    ap.add_argument("--progress-every", type=int, default=10)
    ap.add_argument("--fail-on-empty-fasce", action="store_true", help="Fail if a selected family has no known fasce.")

    return ap.parse_args()


def main() -> int:
    args = parse_args()

    output_root = Path(args.output_root)
    include_debug_metadata = not bool(args.no_debug_metadata)

    print("EXPORT_V2_WEATHER_START", flush=True)
    print(f"year={args.year}", flush=True)
    print(f"family={args.family}", flush=True)
    print(f"limit_families={args.limit_families}", flush=True)
    print(f"offset_families={args.offset_families}", flush=True)
    print(f"output_root={output_root}", flush=True)
    print(f"include_debug_metadata={include_debug_metadata}", flush=True)
    print("db_writes=NO", flush=True)
    print("upload=NO", flush=True)

    started = time.perf_counter()

    conn = pg_conn()
    try:
        target_from, target_to, year_end = resolve_target_window(conn, args.year, args.end_date)
        warmup_start = target_from - pd.Timedelta(days=int(args.warmup_days))

        print(f"target_from={target_from.date()}", flush=True)
        print(f"target_to={target_to.date()}", flush=True)
        print(f"warmup_start={warmup_start.date()}", flush=True)

        families = list_families(
            conn,
            family=args.family,
            family_slug=args.family_slug,
            limit=args.limit_families,
            offset=args.offset_families,
        )

        if not families:
            raise RuntimeError("No families selected for export")

        print(f"selected_family_count={len(families)}", flush=True)

        calendar = load_calendar(conn, warmup_start, target_to)
        weather = load_weather(conn, warmup_start, target_to)

        print(f"calendar_rows={len(calendar)}", flush=True)
        print(f"weather_rows={len(weather)}", flush=True)

        if calendar.empty:
            raise RuntimeError("Calendar features source returned zero rows")
        if weather.empty:
            raise RuntimeError("Weather ML features source returned zero rows")

        expected = expected_v1_columns()
        results = []

        for idx, item in enumerate(families, start=1):
            fam = item["famiglia"]
            fam_slug = item["famiglia_slug"] or slugify(fam)

            t0 = time.perf_counter()
            facts = load_facts_for_family(conn, fam, warmup_start, target_to)
            fasce = load_fasce_for_family(conn, fam)

            if not fasce:
                msg = f"no fasce found for famiglia={fam!r}"
                if args.fail_on_empty_fasce:
                    raise RuntimeError(msg)
                print(f"[WARN] {msg}; skipping", flush=True)
                continue

            frame = build_family_year_v2_weather_frame(
                facts=facts,
                calendar=calendar,
                weather=weather,
                famiglia=fam,
                year=args.year,
                fasce=fasce,
                target_from=target_from,
                target_to=target_to,
                warmup_days=args.warmup_days,
                include_debug_metadata=include_debug_metadata,
            )

            out_file = write_family_year_v2_weather_parquet(
                frame,
                output_root=output_root,
                year=args.year,
                famiglia_slug=fam_slug,
            )

            elapsed = time.perf_counter() - t0

            result = {
                "famiglia": fam,
                "famiglia_slug": fam_slug,
                "facts_rows": int(len(facts)),
                "fasce_count": int(len(fasce)),
                "rows": int(len(frame)),
                "cols": int(len(frame.columns)),
                "first_25_match_expected_v1": list(frame.columns[:25]) == expected,
                "out_file": str(out_file),
                "size_bytes": int(out_file.stat().st_size),
                "elapsed_seconds": float(elapsed),
            }
            results.append(result)

            if idx == 1 or idx % max(1, int(args.progress_every)) == 0 or idx == len(families):
                print(f"PROGRESS {idx}/{len(families)} result={result}", flush=True)

        total_elapsed = time.perf_counter() - started

        total_rows = sum(r["rows"] for r in results)
        total_size = sum(r["size_bytes"] for r in results)
        ok_first25 = all(r["first_25_match_expected_v1"] for r in results)

        print("EXPORT_V2_WEATHER_SUMMARY", flush=True)
        print({
            "requested_families": len(families),
            "exported_families": len(results),
            "total_rows": int(total_rows),
            "total_size_bytes": int(total_size),
            "elapsed_seconds": float(total_elapsed),
            "all_first25_ok": bool(ok_first25),
            "output_root": str(output_root),
        }, flush=True)

        if not results:
            raise RuntimeError("No parquet files exported")

        if not ok_first25:
            raise RuntimeError("At least one exported frame does not preserve first 25 v1 columns")

        print("EXPORT_V2_WEATHER_OK", flush=True)
        return 0

    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
