#!/usr/bin/env python3
from __future__ import annotations

import os
import socket
from typing import Optional

import psycopg

DATABASE_URL = os.environ["DATABASE_URL"]


def _connect():
    return psycopg.connect(DATABASE_URL)


def start_pipeline_run(
    job_type: str,
    trigger_mode: str,
    notes: str | None = None,
    git_sha: str | None = None,
    env_snapshot: dict | None = None,
) -> str:
    import json as _json
    env_json = _json.dumps(env_snapshot) if env_snapshot is not None else None
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into ml_ops.pipeline_run_log_v1 (
                    job_type, trigger_mode, host_name, status, started_at, notes,
                    git_sha, env_snapshot
                )
                values (%s, %s, %s, 'running', now(), %s, %s, %s::jsonb)
                returning run_id
                """,
                (job_type, trigger_mode, socket.gethostname(), notes, git_sha, env_json),
            )
            return str(cur.fetchone()[0])


def finish_pipeline_run(
    run_id: str,
    status: str,
    rows_processed: int | None = None,
    error_message: str | None = None,
    notes: str | None = None,
):
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                update ml_ops.pipeline_run_log_v1
                set finished_at = now(),
                    duration_min = round(extract(epoch from (now() - started_at)) / 60.0, 2),
                    status = %s,
                    rows_processed = coalesce(%s, rows_processed),
                    error_message = coalesce(%s, error_message),
                    notes = coalesce(%s, notes)
                where run_id = %s
                """,
                (status, rows_processed, error_message, notes, run_id),
            )

            cur.execute(
                """
                insert into public.t_ops_pipeline_monitor (ok)
                values (%s)
                """,
                (status == "ok",),
            )


def start_family_run(
    pipeline_run_id: str | None,
    job_type: str,
    family_name: str,
    demand_class_final: str | None = None,
    model_code: str | None = None,
) -> str:
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into ml_ops.family_run_log_v1 (
                    pipeline_run_id,
                    job_type,
                    family_name,
                    demand_class_final,
                    model_code,
                    status,
                    started_at
                )
                values (%s, %s, %s, %s, %s, 'running', now())
                returning family_run_id
                """,
                (pipeline_run_id, job_type, family_name, demand_class_final, model_code),
            )
            return str(cur.fetchone()[0])


def finish_family_run(
    family_run_id: str,
    status: str,
    rows_written: int | None = None,
    artifact_path: str | None = None,
    error_message: str | None = None,
    error_trace: str | None = None,
):
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                update ml_ops.family_run_log_v1
                set finished_at = now(),
                    status = %s,
                    rows_written = coalesce(%s, rows_written),
                    artifact_path = coalesce(%s, artifact_path),
                    error_message = coalesce(%s, error_message),
                    error_trace   = coalesce(%s, error_trace)
                where family_run_id = %s
                """,
                (status, rows_written, artifact_path, error_message, error_trace, family_run_id),
            )


def mark_train_success(
    family_name: str,
    pipeline_run_id: str | None = None,
    model_code: str | None = None,
    train_max_date: str | None = None,
    notes: str | None = None,
):
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                update ml_ops.family_run_log_v1
                set status = 'ok',
                    finished_at = coalesce(finished_at, now()),
                    model_code = coalesce(%s, model_code),
                    artifact_path = coalesce(artifact_path, %s),
                    error_message = null,
                    error_trace = null
                where family_name = %s
                  and (%s is null or pipeline_run_id = %s)
                  and job_type in ('train', 'train_family', 'train_batch')
                  and status = 'running'
                """,
                (model_code, train_max_date, family_name, pipeline_run_id, pipeline_run_id),
            )


def mark_train_failed(
    family_name: str,
    pipeline_run_id: str | None = None,
    error_message: str | None = None,
):
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                update ml_ops.family_run_log_v1
                set status = 'failed',
                    finished_at = coalesce(finished_at, now()),
                    error_message = coalesce(%s, error_message)
                where family_name = %s
                  and (%s is null or pipeline_run_id = %s)
                  and job_type in ('train', 'train_family', 'train_batch')
                  and status = 'running'
                """,
                (error_message, family_name, pipeline_run_id, pipeline_run_id),
            )


def mark_predict_success(
    family_name: str,
    pipeline_run_id: str | None = None,
    notes: str | None = None,
):
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                update ml_ops.family_run_log_v1
                set status = 'ok',
                    finished_at = coalesce(finished_at, now()),
                    error_message = null,
                    error_trace = null
                where family_name = %s
                  and (%s is null or pipeline_run_id = %s)
                  and job_type in ('predict', 'predict_family', 'predict_daily')
                  and status = 'running'
                """,
                (family_name, pipeline_run_id, pipeline_run_id),
            )


def mark_predict_failed(
    family_name: str,
    pipeline_run_id: str | None = None,
    error_message: str | None = None,
):
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                update ml_ops.family_run_log_v1
                set status = 'failed',
                    finished_at = coalesce(finished_at, now()),
                    error_message = coalesce(%s, error_message)
                where family_name = %s
                  and (%s is null or pipeline_run_id = %s)
                  and job_type in ('predict', 'predict_family', 'predict_daily')
                  and status = 'running'
                """,
                (error_message, family_name, pipeline_run_id, pipeline_run_id),
            )


def check_job_enabled(job_type: str, default: bool = True) -> bool:
    try:
        with _connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT is_enabled FROM ml_ops.job_schedule_config_v1 WHERE job_type = %s",
                    (job_type,),
                )
                row = cur.fetchone()
                if row is None:
                    return default
                return bool(row[0])
    except Exception:
        return default
