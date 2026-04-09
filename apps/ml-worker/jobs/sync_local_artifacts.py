#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import socket
from pathlib import Path

import psycopg

DATABASE_URL = os.environ["DATABASE_URL"]
REPO_DIR = Path(os.getenv("REPO_DIR", "/opt/greenbrain-platform/apps/ml-worker"))
MODEL_DIR = Path(os.getenv("MODEL_DIR_V4", str(REPO_DIR / "models_v4")))
JOB_TYPE = "sync_local_artifacts"
TRIGGER_MODE = os.getenv("RUN_TRIGGER_SOURCE", "manual")

BUNDLE_RE = re.compile(r"^bundle_(.+)_v4\.pkl$")


def slug_to_family(slug: str) -> str:
    return slug.replace("-", " ").strip().lower()


def main() -> int:
    if not MODEL_DIR.exists():
        print(f"ERROR: model dir not found: {MODEL_DIR}")
        return 1

    files = sorted(p for p in MODEL_DIR.iterdir() if p.is_file() and p.name.startswith("bundle_") and p.name.endswith("_v4.pkl"))

    with psycopg.connect(DATABASE_URL) as conn:
        conn.autocommit = False

        with conn.cursor() as cur:
            cur.execute(
                """
                insert into ml_ops.pipeline_run_log_v1 (
                    job_type, trigger_mode, host_name, status, notes
                )
                values (%s, %s, %s, 'running', %s)
                returning run_id
                """,
                (JOB_TYPE, TRIGGER_MODE, socket.gethostname(), f"sync local artifacts from {MODEL_DIR}"),
            )
            run_id = cur.fetchone()[0]

        processed = 0

        try:
            with conn.cursor() as cur:
                for fp in files:
                    m = BUNDLE_RE.match(fp.name)
                    if not m:
                        continue

                    slug = m.group(1)
                    family_name = slug_to_family(slug)

                    cur.execute(
                        """
                        select model_code
                        from ml_forecast.family_model_registry_v2
                        where family_name = %s
                        """,
                        (family_name,),
                    )
                    row = cur.fetchone()
                    model_code = row[0] if row else "UNKNOWN"

                    size_bytes = fp.stat().st_size

                    cur.execute(
                        """
                        update ml_forecast.model_artifact_registry_v1
                        set is_active = false,
                            updated_at = now()
                        where family_name = %s
                          and bundle_version = 'v4'
                          and is_active = true
                        """,
                        (family_name,),
                    )

                    cur.execute(
                        """
                        insert into ml_forecast.model_artifact_registry_v1 (
                            family_name,
                            family_slug,
                            model_code,
                            execution_engine,
                            bundle_version,
                            artifact_path,
                            artifact_store,
                            artifact_size_bytes,
                            is_active,
                            created_at,
                            updated_at
                        )
                        values (
                            %s, %s, %s, 'V4_TWEEDIE_BUNDLE', 'v4',
                            %s, 'local_fs', %s, true, now(), now()
                        )
                        """,
                        (family_name, slug, model_code, str(fp), size_bytes),
                    )

                    processed += 1

                cur.execute(
                    """
                    update ml_forecast.family_model_state_v1 s
                    set needs_initial_train = case when a.family_name is not null then false else true end,
                        needs_retrain = case when a.family_name is not null then false else true end
                    from (
                        select distinct family_name
                        from ml_forecast.model_artifact_registry_v1
                        where is_active = true
                    ) a
                    where s.family_name = a.family_name
                    """
                )

                cur.execute(
                    """
                    update ml_forecast.family_model_state_v1 s
                    set needs_initial_train = true,
                        needs_retrain = true
                    where not exists (
                        select 1
                        from ml_forecast.model_artifact_registry_v1 a
                        where a.family_name = s.family_name
                          and a.is_active = true
                    )
                    """
                )

                cur.execute(
                    """
                    update ml_ops.pipeline_run_log_v1
                    set finished_at = now(),
                        status = 'success',
                        rows_processed = %s,
                        notes = %s
                    where run_id = %s
                    """,
                    (processed, f"synced {processed} local artifacts", run_id),
                )

            conn.commit()
            print(f"OK sync_local_artifacts | processed={processed}")
            return 0

        except Exception as e:
            conn.rollback()
            with conn.cursor() as cur:
                cur.execute(
                    """
                    update ml_ops.pipeline_run_log_v1
                    set finished_at = now(),
                        status = 'failed',
                        error_message = %s
                    where run_id = %s
                    """,
                    (str(e), run_id),
                )
            conn.commit()
            print(f"ERROR sync_local_artifacts: {e}")
            return 1


if __name__ == "__main__":
    raise SystemExit(main())
