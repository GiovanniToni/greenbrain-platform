#!/usr/bin/env python3
from __future__ import annotations

import os
import socket
import sys
from contextlib import contextmanager

import psycopg

DATABASE_URL = os.environ["DATABASE_URL"]
JOB_TYPE = "refresh_registry"
TRIGGER_MODE = os.getenv("RUN_TRIGGER_SOURCE", "manual")


@contextmanager
def get_conn():
    with psycopg.connect(DATABASE_URL) as conn:
        conn.autocommit = False
        yield conn


def main() -> int:
    with get_conn() as conn:
        run_id = None
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    insert into ml_ops.pipeline_run_log_v1 (
                        job_type, trigger_mode, host_name, status, notes
                    )
                    values (%s, %s, %s, 'running', %s)
                    returning run_id
                    """,
                    (
                        JOB_TYPE,
                        TRIGGER_MODE,
                        socket.gethostname(),
                        'refresh classification + registry + artifact-state sync',
                    ),
                )
                run_id = cur.fetchone()[0]

                cur.execute("select ml_forecast.log_classification_changes_v1();")
                cur.execute("select ml_forecast.sync_family_model_state_from_registry_v1();")
                cur.execute("select ml_forecast.sync_family_model_state_from_artifacts_v1();")

                cur.execute(
                    """
                    update ml_forecast.family_model_state_v1
                    set registry_last_refreshed_at = now(),
                        last_seen_at = now(),
                        needs_predict = true
                    """
                )

                cur.execute(
                    """
                    select count(*)
                    from ml_forecast.family_model_registry_v2
                    """
                )
                n_families = cur.fetchone()[0]

                cur.execute(
                    """
                    update ml_ops.pipeline_run_log_v1
                    set finished_at = now(),
                        status = 'success',
                        rows_processed = %s,
                        notes = %s
                    where run_id = %s
                    """,
                    (n_families, f"registry refreshed successfully | families={n_families}", run_id),
                )

            conn.commit()
            print(f"OK refresh_registry | families={n_families}")
            return 0

        except Exception as e:
            conn.rollback()
            try:
                with psycopg.connect(DATABASE_URL) as conn2:
                    with conn2.cursor() as cur2:
                        if run_id is not None:
                            cur2.execute(
                                """
                                update ml_ops.pipeline_run_log_v1
                                set finished_at = now(),
                                    status = 'failed',
                                    error_message = %s
                                where run_id = %s
                                """,
                                (str(e), run_id),
                            )
                    conn2.commit()
            except Exception:
                pass

            print(f"ERROR refresh_registry: {e}", file=sys.stderr)
            return 1


if __name__ == "__main__":
    raise SystemExit(main())
