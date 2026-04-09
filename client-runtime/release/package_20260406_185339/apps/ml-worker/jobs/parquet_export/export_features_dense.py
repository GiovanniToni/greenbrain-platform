import os
import io
import time
import random
import argparse
from datetime import date, datetime

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import psycopg2

from dotenv import load_dotenv
from storage.backend import get_storage_backend


def normalize_dtypes(df: pd.DataFrame) -> pd.DataFrame:
    if "data" in df.columns:
        df["data"] = pd.to_datetime(df["data"], errors="coerce")

    if "is_holiday" in df.columns:
        df["is_holiday"] = df["is_holiday"].astype("bool")

    for c in ["dow", "week_num", "month_num", "year_num"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0).astype("int16")

    float_cols = [
        "qty_venduta",
        "tmin_c", "tmax_c", "tavg_c", "rain_mm", "sun_hours",
        "qty_lag_1", "qty_lag_2", "qty_lag_3", "qty_lag_7", "qty_lag_10", "qty_lag_14",
        "qty_ma_3", "qty_ma_7", "qty_ma_10", "qty_ma_14", "qty_ma_28",
    ]
    for c in float_cols:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce").astype("float32")

    return df


def fmt_seconds(s: float) -> str:
    s = max(0.0, float(s))
    if s < 60:
        return f"{s:.0f}s"
    if s < 3600:
        return f"{s/60:.1f}m"
    return f"{s/3600:.2f}h"


def is_retryable_error(e: Exception) -> bool:
    msg = repr(e)
    retry_markers = [
        "ReadTimeout", "RemoteProtocolError", "ConnectTimeout", "ConnectError",
        "NetworkError", "TimeoutError", "ServerDisconnectedError",
        "ConnectionResetError", "BrokenPipeError", "SSLError",
        "502", "503", "504", "429", "EOFError",
    ]
    return any(m in msg for m in retry_markers)


def sleep_backoff(attempt: int, base: float = 1.5, cap: float = 30.0) -> None:
    delay = min(cap, base * (2 ** (attempt - 1)))
    delay = delay * (0.75 + random.random() * 0.5)
    time.sleep(delay)


if os.getenv("DATABASE_URL") is None:
    load_dotenv()

DB_HOST = os.environ["PG_HOST"]
DB_PORT = int(os.environ.get("PG_PORT", "5432"))
DB_NAME = os.environ.get("PG_DB", "postgres")
DB_USER = os.environ.get("PG_USER", "postgres")
DB_PASSWORD = os.environ["PG_PASSWORD"]

STORAGE_PREFIX = "features_dense/v1"
PROGRESS_EVERY = int(os.getenv("PROGRESS_EVERY", "10"))
BATCH_SIZE = os.getenv("BATCH_SIZE")
BATCH_OFFSET = os.getenv("BATCH_OFFSET")
BATCH_SIZE = int(BATCH_SIZE) if BATCH_SIZE else None
BATCH_OFFSET = int(BATCH_OFFSET) if BATCH_OFFSET else None
STATEMENT_TIMEOUT_MS = os.getenv("STATEMENT_TIMEOUT_MS")
STATEMENT_TIMEOUT_MS = int(STATEMENT_TIMEOUT_MS) if STATEMENT_TIMEOUT_MS else None
UPLOAD_MAX_RETRIES = int(os.getenv("UPLOAD_MAX_RETRIES", "6"))
UPLOAD_BASE_BACKOFF_SEC = float(os.getenv("UPLOAD_BASE_BACKOFF_SEC", "1.5"))
QUERY_MAX_RETRIES = int(os.getenv("QUERY_MAX_RETRIES", "3"))
COMMIT_EVERY_FILES = int(os.getenv("COMMIT_EVERY_FILES", "50"))


def pg_conn():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        sslmode=os.getenv("PG_SSLMODE", "prefer"),
        connect_timeout=10,
    )


def maybe_set_statement_timeout(cur):
    if STATEMENT_TIMEOUT_MS is not None and STATEMENT_TIMEOUT_MS > 0:
        cur.execute("SET statement_timeout = %s;", (STATEMENT_TIMEOUT_MS,))


def get_last_success_window(cur):
    cur.execute("""
      with last_run as (
        select
          coalesce(
            nullif(payload->>'target_last','')::date,
            ended_at::date,
            started_at::date
          ) as target_last,
          coalesce(
            nullif(payload->>'rebuild_days','')::int,
            90
          ) as rebuild_days
        from public.etl_runs
        where status in ('success', 'ok')
        order by coalesce(ended_at, started_at) desc
        limit 1
      )
      select
        target_last,
        rebuild_days,
        (target_last - (rebuild_days - 1))::date as start_day
      from last_run;
    """)
    row = cur.fetchone()
    if not row or row[0] is None:
        raise RuntimeError("Non trovo un run SUCCESS in public.etl_runs.")
    target_last, rebuild_days, start_day = row
    return start_day, target_last, rebuild_days


def get_full_window(cur):
    cur.execute("""
      select min(data)::date as min_data, max(data)::date as max_data
      from public.greenhouse_forecast_features_dense;
    """)
    row = cur.fetchone()
    if not row or row[0] is None or row[1] is None:
        raise RuntimeError("Tabella greenhouse_forecast_features_dense vuota o min/max null.")
    return row[0], row[1]


def list_families(cur, limit=None, offset=None):
    sql = """
      select famiglia, famiglia_slug
      from public.v_famiglie_catalog
      order by 1
    """
    params = []
    if limit is not None:
        sql += " limit %s"
        params.append(int(limit))
    if offset is not None:
        sql += " offset %s"
        params.append(int(offset))
    cur.execute(sql, params if params else None)
    return cur.fetchall()


def count_total_families(cur) -> int:
    cur.execute("select count(*) from public.v_famiglie_catalog;")
    return int(cur.fetchone()[0])


def export_family_year(cur, famiglia: str, famiglia_slug: str, year: int, start_day: date, end_day: date) -> pd.DataFrame:
    year_start = date(year, 1, 1)
    year_end = date(year, 12, 31)

    f_from = max(start_day, year_start)
    f_to = min(end_day, year_end)
    if f_from > f_to:
        return pd.DataFrame()

    cur.execute("""
      select
        data,
        lower(trim(famiglia)) as famiglia,
        fascia_prezzo_iva_inc,
        qty_venduta,
        tmin_c, tmax_c, tavg_c, rain_mm, sun_hours,
        is_holiday,
        dow, week_num, month_num, year_num,
        qty_lag_1, qty_lag_2, qty_lag_3, qty_lag_7, qty_lag_10, qty_lag_14,
        qty_ma_3, qty_ma_7, qty_ma_10, qty_ma_14, qty_ma_28
      from public.greenhouse_forecast_features_dense
      where lower(trim(famiglia)) = %s
        and data between %s and %s
      order by data;
    """, (famiglia, f_from, f_to))

    cols = [d.name for d in cur.description]
    rows = cur.fetchall()
    if not rows:
        return pd.DataFrame()
    return pd.DataFrame(rows, columns=cols)


def export_family_year_with_retry(cur, famiglia: str, famiglia_slug: str, year: int, start_day: date, end_day: date) -> pd.DataFrame:
    for attempt in range(1, QUERY_MAX_RETRIES + 1):
        try:
            return export_family_year(cur, famiglia, famiglia_slug, year, start_day, end_day)
        except Exception as e:
            msg = repr(e)
            retryable = ("QueryCanceled" in msg) or ("statement timeout" in msg) or is_retryable_error(e)
            if not retryable or attempt == QUERY_MAX_RETRIES:
                raise
            print(f"[WARN] query retry attempt={attempt}/{QUERY_MAX_RETRIES} famiglia_slug={famiglia_slug} year={year} err={e}", flush=True)
            sleep_backoff(attempt, base=1.0, cap=10.0)
    return pd.DataFrame()


def df_to_parquet_bytes(df: pd.DataFrame) -> bytes:
    table = pa.Table.from_pandas(df, preserve_index=False)
    buf = io.BytesIO()
    pq.write_table(table, buf, compression="zstd", use_dictionary=True)
    return buf.getvalue()


def upload_bytes_with_retry(storage, path: str, b: bytes, run_id: int, famiglia_slug: str, year: int):
    last_err = None
    for attempt in range(1, UPLOAD_MAX_RETRIES + 1):
        try:
            storage.upload_bytes(path, b, content_type="application/octet-stream")
            return
        except Exception as e:
            last_err = e
            retryable = is_retryable_error(e)
            if (not retryable) or (attempt == UPLOAD_MAX_RETRIES):
                break
            print(f"[WARN] upload retry attempt={attempt}/{UPLOAD_MAX_RETRIES} run_id={run_id} year={year} famiglia_slug={famiglia_slug} path={path} err={e}", flush=True)
            try:
                storage = get_storage_backend()
            except Exception:
                pass
            sleep_backoff(attempt, base=UPLOAD_BASE_BACKOFF_SEC, cap=30.0)

    raise RuntimeError(
        f"upload_failed after {UPLOAD_MAX_RETRIES} attempts run_id={run_id} year={year} famiglia_slug={famiglia_slug} path={path} last_err={last_err}"
    )


def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--full-export", action="store_true")
    ap.add_argument("--start-date", dest="start_date", default=None)
    ap.add_argument("--end-date", dest="end_date", default=None)
    return ap.parse_args()


def main():
    args = parse_args()
    storage = get_storage_backend()

    with pg_conn() as conn:
        conn.autocommit = False
        with conn.cursor() as cur:
            maybe_set_statement_timeout(cur)

            full_export = args.full_export or str(os.getenv("FULL_EXPORT", "")).strip().lower() in ("1", "true", "yes", "y", "on")

            if args.start_date and args.end_date:
                start_day = datetime.strptime(args.start_date, "%Y-%m-%d").date()
                target_last = datetime.strptime(args.end_date, "%Y-%m-%d").date()
                rebuild_days = (target_last - start_day).days + 1
            elif full_export:
                start_day, target_last = get_full_window(cur)
                rebuild_days = None
            else:
                start_day, target_last, rebuild_days = get_last_success_window(cur)

            years = list(range(start_day.year, target_last.year + 1))

            ONLY_YEAR = os.getenv("ONLY_YEAR")
            if ONLY_YEAR:
                years = [y for y in years if str(y) == str(ONLY_YEAR)]

            families_total = count_total_families(cur)
            families = list_families(cur, limit=BATCH_SIZE, offset=BATCH_OFFSET)

            ONLY_FAMILY_SLUG = os.getenv("ONLY_FAMILY_SLUG")
            if ONLY_FAMILY_SLUG:
                families = [t for t in families if t[1] == ONLY_FAMILY_SLUG]

            cur.execute("""
              insert into public.ops_parquet_export_runs(dataset, status, from_day, to_day, n_families, meta)
              values (%s, 'running', %s, %s, %s,
                      jsonb_build_object(
                          'rebuild_days', %s,
                          'batch_size', %s,
                          'batch_offset', %s,
                          'families_total', %s,
                          'full_export', %s
                      ))
              returning run_id;
            """, (
                "features_dense_ml_clean",
                start_day, target_last,
                len(families),
                rebuild_days,
                BATCH_SIZE, BATCH_OFFSET, families_total, full_export
            ))
            run_id = cur.fetchone()[0]
            conn.commit()

            total_files = 0
            total_rows = 0
            total_steps = max(1, len(families) * len(years))
            done_steps = 0
            t0 = time.time()
            last_print = 0.0
            files_since_commit = 0

            def maybe_print_progress(force=False, current_family=None, current_year=None):
                nonlocal last_print
                now = time.time()
                if (not force) and (now - last_print < PROGRESS_EVERY):
                    return
                last_print = now
                elapsed = now - t0
                pct = (done_steps / total_steps) * 100.0
                rate = done_steps / elapsed if elapsed > 0 else 0.0
                eta = (total_steps - done_steps) / rate if rate > 0 else 0.0
                msg = f"[RUN {run_id}] progress={done_steps}/{total_steps} ({pct:.1f}%) files={total_files} rows={total_rows} elapsed={fmt_seconds(elapsed)} eta={fmt_seconds(eta)}"
                if current_family is not None and current_year is not None:
                    msg += f" | now famiglia_slug={current_family} year={current_year}"
                print(msg, flush=True)

            print(f"START run_id={run_id} | window={start_day}..{target_last}", flush=True)
            maybe_print_progress(force=True)

            try:
                for famiglia, famiglia_slug in families:
                    for y in years:
                        current_family = famiglia_slug
                        current_year = y

                        try:
                            df = export_family_year_with_retry(cur, famiglia, famiglia_slug, y, start_day, target_last)
                        except Exception as e:
                            print(f"[WARN] famiglia_slug={famiglia_slug} year={y} query_failed err={e}", flush=True)
                            done_steps += 1
                            maybe_print_progress(current_family=current_family, current_year=current_year)
                            continue

                        df = normalize_dtypes(df)
                        if not df.empty:
                            b = df_to_parquet_bytes(df)
                            relpath = f"{STORAGE_PREFIX}/year={y}/famiglia_slug={famiglia_slug}/part.parquet"

                            try:
                                upload_bytes_with_retry(storage, relpath, b, run_id, famiglia_slug, y)
                            except Exception as e:
                                print(f"[WARN] upload_failed famiglia_slug={famiglia_slug} year={y} path={relpath} err={e}", flush=True)
                                done_steps += 1
                                maybe_print_progress(current_family=current_family, current_year=current_year)
                                continue

                            total_files += 1
                            total_rows += len(df)
                            files_since_commit += 1

                            if files_since_commit >= COMMIT_EVERY_FILES:
                                try:
                                    conn.commit()
                                except Exception:
                                    conn.rollback()
                                files_since_commit = 0

                        done_steps += 1
                        maybe_print_progress(current_family=current_family, current_year=current_year)

                cur.execute("""
                  update public.ops_parquet_export_runs
                  set ended_at = now(),
                      status = 'success',
                      n_files = %s,
                      n_rows = %s
                  where run_id = %s;
                """, (total_files, total_rows, run_id))

                cur.execute("""
                  update public.ops_parquet_export_state
                  set last_success_run_at = now(),
                      last_success_day = %s
                  where id = 1;
                """, (target_last,))

                conn.commit()

                maybe_print_progress(force=True)
                print(f"SUCCESS run_id={run_id} files={total_files} rows={total_rows}", flush=True)

            except Exception as e:
                conn.rollback()
                cur.execute("""
                    update public.ops_parquet_export_runs
                    set ended_at = now(),
                        status = 'failed',
                        error_message = %s
                    where run_id = %s;
                """, (str(e), run_id))
                conn.commit()
                raise


if __name__ == "__main__":
    main()
