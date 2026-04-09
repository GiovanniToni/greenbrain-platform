#!/usr/bin/env python3
"""
validate_engines.py

Validates all forecast engines end-to-end (write_db=False) by:
  1. Selecting 1 sample family per model_code from ml_forecast.family_model_registry_v2,
     joined with family_model_state_v1 and v_family_execution_routing_v1 to prefer
     active, healthy families.
  2. Running the corresponding predict_<engine>() function.
  3. Validating the returned dataframe against the required schema.
  4. Printing a structured validation report.

Usage:
    python jobs/validate_engines.py [--write-db]
"""

import argparse
import os
import sys
from datetime import datetime
from typing import Any

import sqlalchemy as sa
from dotenv import load_dotenv
from sqlalchemy.engine import URL

load_dotenv("/opt/greenbrain-platform/client-runtime/etl/.env.ml.runtime")

REPO_DIR = os.getenv("GH_REPO_DIR", "/opt/greenbrain-platform/apps/ml-worker")
sys.path.insert(0, REPO_DIR)

from jobs.engines.engine_croston import predict_croston  # noqa: E402
from jobs.engines.engine_ets import predict_ets  # noqa: E402
from jobs.engines.engine_naive_zero import predict_naive_zero  # noqa: E402
from jobs.engines.engine_sarima import predict_sarima  # noqa: E402
from jobs.engines.engine_tsb import predict_tsb  # noqa: E402
from jobs.engines.engine_validation import (  # noqa: E402
    REQUIRED_FORECAST_COLUMNS,
    validate_forecast_df,
)

TARGET_MODEL_CODES = ["NAIVE_ZERO", "ETS_DAMPED", "CROSTON_SBA", "TSB", "SARIMA"]

ENGINE_PREDICT_FN = {
    "NAIVE_ZERO":   predict_naive_zero,
    "ETS_DAMPED":   predict_ets,
    "CROSTON_SBA":  predict_croston,
    "TSB":          predict_tsb,
    "SARIMA":       predict_sarima,
}

SAMPLE_QUERY = sa.text("""
    SELECT DISTINCT ON (r.model_code)
        lower(trim(r.family_name))                               AS family_name,
        r.demand_class_final,
        r.model_code,
        coalesce(v.effective_execution_engine, r.model_code)     AS effective_engine,
        coalesce(v.routing_source, 'registry')                   AS routing_source,
        coalesce(v.is_active, true)                              AS is_active,
        coalesce(s.needs_initial_train, false)                   AS needs_initial_train,
        coalesce(s.needs_retrain, false)                         AS needs_retrain,
        s.last_train_at,
        h.health_status
    FROM ml_forecast.family_model_registry_v2 r
    LEFT JOIN ml_forecast.v_family_execution_routing_v1 v
           ON lower(trim(v.family_name)) = lower(trim(r.family_name))
    LEFT JOIN ml_forecast.family_model_state_v1 s
           ON lower(trim(s.family_name)) = lower(trim(r.family_name))
    LEFT JOIN ml_ops.v_registry_health_v1 h
           ON lower(trim(h.family_name)) = lower(trim(r.family_name))
    WHERE r.model_code = ANY(:model_codes)
      AND coalesce(v.is_active, true) = true
    ORDER BY
        r.model_code,
        coalesce(v.is_active, true)              DESC,
        (s.needs_initial_train IS NOT TRUE)       DESC,
        (h.health_status = 'ok')                  DESC,
        r.family_name
""")


def _get_db_engine():
    dburl = os.getenv("DATABASE_URL")
    if dburl:
        return sa.create_engine(dburl, pool_pre_ping=True)

    url = URL.create(
        "postgresql+psycopg",
        username=os.getenv("PG_USER"),
        password=os.getenv("PG_PASSWORD"),
        host=os.getenv("PG_HOST"),
        port=int(os.getenv("PG_PORT", "5432")),
        database=os.getenv("PG_DB", "postgres"),
        query={"sslmode": os.getenv("PG_SSLMODE", "require")},
    )
    return sa.create_engine(url, pool_pre_ping=True)


def _select_samples(db_engine) -> dict[str, dict[str, Any]]:
    try:
        with db_engine.connect() as conn:
            rows = conn.execute(
                SAMPLE_QUERY, {"model_codes": TARGET_MODEL_CODES}
            ).mappings().all()
    except sa.exc.ProgrammingError:
        # v_registry_health_v1 may not exist: retry without it
        fallback_query = sa.text("""
            SELECT DISTINCT ON (r.model_code)
                lower(trim(r.family_name))                               AS family_name,
                r.demand_class_final,
                r.model_code,
                coalesce(v.effective_execution_engine, r.model_code)     AS effective_engine,
                coalesce(v.routing_source, 'registry')                   AS routing_source,
                coalesce(v.is_active, true)                              AS is_active,
                coalesce(s.needs_initial_train, false)                   AS needs_initial_train,
                coalesce(s.needs_retrain, false)                         AS needs_retrain,
                s.last_train_at,
                null::text                                               AS health_status
            FROM ml_forecast.family_model_registry_v2 r
            LEFT JOIN ml_forecast.v_family_execution_routing_v1 v
                   ON lower(trim(v.family_name)) = lower(trim(r.family_name))
            LEFT JOIN ml_forecast.family_model_state_v1 s
                   ON lower(trim(s.family_name)) = lower(trim(r.family_name))
            WHERE r.model_code = ANY(:model_codes)
              AND coalesce(v.is_active, true) = true
            ORDER BY
                r.model_code,
                coalesce(v.is_active, true)         DESC,
                (s.needs_initial_train IS NOT TRUE)  DESC,
                r.family_name
        """)
        with db_engine.connect() as conn:
            rows = conn.execute(
                fallback_query, {"model_codes": TARGET_MODEL_CODES}
            ).mappings().all()

    samples: dict[str, dict[str, Any]] = {}
    for row in rows:
        mc = row["model_code"]
        if mc not in samples:
            samples[mc] = dict(row)
    return samples


def _slugify(family_name: str) -> str:
    return family_name.strip().lower().replace(" ", "-")


def _validate_one(model_code: str, row: dict[str, Any], write_db: bool) -> dict[str, Any]:
    family_name = row["family_name"]
    family_slug = _slugify(family_name)
    predict_fn = ENGINE_PREDICT_FN.get(model_code)

    result: dict[str, Any] = {
        "model_code":        model_code,
        "family_name":       family_name,
        "family_slug":       family_slug,
        "demand_class":      row.get("demand_class_final"),
        "effective_engine":  row.get("effective_engine"),
        "routing_source":    row.get("routing_source"),
        "health_status":     row.get("health_status"),
        "last_train_at":     row.get("last_train_at"),
        "needs_retrain":     row.get("needs_retrain"),
        "status":            None,
        "rows":              None,
        "columns":           None,
        "error":             None,
    }

    if predict_fn is None:
        result["status"] = "SKIP"
        result["error"] = f"No predict function mapped for model_code={model_code}"
        return result

    try:
        df = predict_fn(family_name, family_slug, write_db=write_db)
        validate_forecast_df(df)
        result["status"] = "OK"
        result["rows"] = len(df)
        result["columns"] = sorted(df.columns.tolist())
    except FileNotFoundError as exc:
        result["status"] = "NO_BUNDLE"
        result["error"] = str(exc)
    except ValueError as exc:
        result["status"] = "SCHEMA_ERROR"
        result["error"] = str(exc)
    except Exception as exc:
        result["status"] = "FAIL"
        result["error"] = f"{type(exc).__name__}: {exc}"

    return result


def _print_report(
    samples: dict[str, dict[str, Any]],
    results: list[dict[str, Any]],
    write_db: bool,
) -> int:
    W = 100
    now = datetime.utcnow().isoformat() + "Z"

    print("=" * W)
    print(f"  FORECAST ENGINE VALIDATION REPORT  |  {now}  |  write_db={write_db}")
    print("=" * W)

    print(f"\n{'SAMPLE SELECTION':}")
    print(f"  Source: ml_forecast.family_model_registry_v2")
    print(f"  Joined: family_model_state_v1 | v_family_execution_routing_v1 | ml_ops.v_registry_health_v1")
    print(f"  Selection: 1 active family per model_code, ordered by health and train status\n")

    hdr = f"{'MODEL_CODE':<16} {'FAMILY':<28} {'CLASS':<14} {'EFF_ENGINE':<22} {'ROUTING':<18}"
    print(hdr)
    print("-" * W)
    for mc in TARGET_MODEL_CODES:
        if mc in samples:
            s = samples[mc]
            print(
                f"{mc:<16} "
                f"{s['family_name']:<28} "
                f"{(s.get('demand_class_final') or '-'):<14} "
                f"{(s.get('effective_engine') or '-'):<22} "
                f"{(s.get('routing_source') or '-'):<18}"
            )
        else:
            print(f"{mc:<16} {'(not found in registry)':<28}")

    print()
    print("=" * W)
    hdr2 = f"{'MODEL_CODE':<16} {'FAMILY':<28} {'STATUS':<14} {'ROWS':<6} DETAIL"
    print(hdr2)
    print("-" * W)

    failures = 0
    for r in results:
        status = r["status"]
        rows_s = str(r["rows"]) if r["rows"] is not None else "-"
        if status == "OK":
            detail = f"cols={r['columns']}"
        else:
            detail = r["error"] or "-"
            failures += 1
        print(
            f"{r['model_code']:<16} "
            f"{r['family_name']:<28} "
            f"{status:<14} "
            f"{rows_s:<6} "
            f"{detail}"
        )

    print("-" * W)
    ok_count = sum(1 for r in results if r["status"] == "OK")
    missing = [mc for mc in TARGET_MODEL_CODES if mc not in samples]
    print(f"RESULT: {ok_count}/{len(results)} OK | {failures} issues | write_db={write_db}")
    if missing:
        print(f"WARNING: no active family found in registry for model_codes: {missing}")

    print("=" * W)
    return 1 if failures > 0 else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Validate all forecast engines end-to-end")
    ap.add_argument(
        "--write-db",
        action="store_true",
        default=False,
        help="Write forecasts to DB (default: dry-run, no write)",
    )
    args = ap.parse_args()

    db_engine = _get_db_engine()
    try:
        samples = _select_samples(db_engine)
    finally:
        db_engine.dispose()

    if not samples:
        print(
            "ERROR: ml_forecast.family_model_registry_v2 returned no rows "
            f"for model_codes={TARGET_MODEL_CODES}",
            file=sys.stderr,
        )
        return 1

    results = []
    for mc in TARGET_MODEL_CODES:
        if mc in samples:
            results.append(_validate_one(mc, samples[mc], write_db=args.write_db))
        else:
            results.append(
                {
                    "model_code":       mc,
                    "family_name":      "-",
                    "family_slug":      "-",
                    "demand_class":     None,
                    "effective_engine": None,
                    "routing_source":   None,
                    "health_status":    None,
                    "last_train_at":    None,
                    "needs_retrain":    None,
                    "status":           "NOT_IN_REGISTRY",
                    "rows":             None,
                    "columns":          None,
                    "error":            f"no active family found for model_code={mc}",
                }
            )

    return _print_report(samples, results, write_db=args.write_db)


if __name__ == "__main__":
    raise SystemExit(main())
