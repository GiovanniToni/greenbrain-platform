#!/usr/bin/env bash
set -euo pipefail

GB_BASE="${GB_BASE:-/opt/greenbrain-platform}"
cd "$GB_BASE"

BACKEND_CONTAINER="${WEATHER_BACKEND_CONTAINER:-dev_backend}"

WEATHER_FORECAST_DAYS="${WEATHER_FORECAST_DAYS:-10}"
WEATHER_RECENT_ACTUAL_DAYS="${WEATHER_RECENT_ACTUAL_DAYS:-7}"
WEATHER_INGEST_CURRENT="${WEATHER_INGEST_CURRENT:-1}"
WEATHER_LOCATION_CODES="${WEATHER_LOCATION_CODES:-}"

LOG_DIR="${GB_BASE}/runtime-reports/weather_ingest"
LOCK_DIR="${GB_BASE}/runtime-reports/tmp"
LOCK_FILE="${LOCK_DIR}/weather_daily_ingest.lock"

mkdir -p "$LOG_DIR" "$LOCK_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") weather daily ingest already running, exiting."
  exit 0
fi

STAMP="$(date -u +"%Y%m%d_%H%M%S")"
LOG_FILE="${LOG_DIR}/weather_daily_ingest_${STAMP}.log"
ln -sfn "$(basename "$LOG_FILE")" "${LOG_DIR}/weather_daily_ingest_latest.log"

{
  echo "===== GREENBRAIN WEATHER DAILY INGEST ====="
  echo "started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "GB_BASE=$GB_BASE"
  echo "BACKEND_CONTAINER=$BACKEND_CONTAINER"
  echo "WEATHER_FORECAST_DAYS=$WEATHER_FORECAST_DAYS"
  echo "WEATHER_RECENT_ACTUAL_DAYS=$WEATHER_RECENT_ACTUAL_DAYS"
  echo "WEATHER_INGEST_CURRENT=$WEATHER_INGEST_CURRENT"
  echo "WEATHER_LOCATION_CODES=${WEATHER_LOCATION_CODES:-all_active}"
  echo

  if ! docker inspect "$BACKEND_CONTAINER" >/dev/null 2>&1; then
    echo "ERROR: backend container not found: $BACKEND_CONTAINER"
    exit 20
  fi

  echo "===== BACKEND CONTAINER STATUS ====="
  docker ps --filter "name=${BACKEND_CONTAINER}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo

  echo "===== RUN WEATHER INGEST INSIDE BACKEND ====="
  set +e
  docker exec \
    -e WEATHER_FORECAST_DAYS="$WEATHER_FORECAST_DAYS" \
    -e WEATHER_RECENT_ACTUAL_DAYS="$WEATHER_RECENT_ACTUAL_DAYS" \
    -e WEATHER_INGEST_CURRENT="$WEATHER_INGEST_CURRENT" \
    -e WEATHER_LOCATION_CODES="$WEATHER_LOCATION_CODES" \
    -i "$BACKEND_CONTAINER" python - <<'PY'
from __future__ import annotations

import json
import os
import sys
from typing import Any

from app.db.session import SessionLocal
from app.repositories import weather_repository as repo
from app.services.weather_ingestion_service import (
    MAX_FORECAST_DAYS,
    MAX_RECENT_ACTUAL_DAYS,
    ingest_current_for_location,
    ingest_forecast_for_location,
    ingest_recent_actuals_for_location,
)


def bounded_int(name: str, default: int, minimum: int, maximum: int) -> int:
    raw = os.environ.get(name, str(default))
    try:
        value = int(raw)
    except Exception:
        raise RuntimeError(f"{name}_invalid_integer:{raw}")

    if value < minimum or value > maximum:
        raise RuntimeError(f"{name}_out_of_bounds:{value}:allowed_{minimum}_{maximum}")

    return value


def enabled(name: str, default: str = "1") -> bool:
    raw = os.environ.get(name, default).strip().lower()
    return raw not in {"0", "false", "no", "off", "disabled"}


forecast_days = bounded_int("WEATHER_FORECAST_DAYS", 10, 1, MAX_FORECAST_DAYS)
recent_actual_days = bounded_int("WEATHER_RECENT_ACTUAL_DAYS", 7, 1, MAX_RECENT_ACTUAL_DAYS)
ingest_current = enabled("WEATHER_INGEST_CURRENT", "1")

wanted_codes_raw = os.environ.get("WEATHER_LOCATION_CODES", "").strip()
wanted_codes = {
    item.strip().lower()
    for item in wanted_codes_raw.split(",")
    if item.strip()
}

summary: dict[str, Any] = {
    "status": "running",
    "limits": {
        "max_forecast_days": MAX_FORECAST_DAYS,
        "max_recent_actual_days": MAX_RECENT_ACTUAL_DAYS,
        "parallelism": "disabled",
    },
    "requested": {
        "forecast_days": forecast_days,
        "recent_actual_days": recent_actual_days,
        "ingest_current": ingest_current,
        "location_codes": sorted(wanted_codes) if wanted_codes else "all_active",
    },
    "locations": [],
    "failures": [],
}

db = SessionLocal()

try:
    all_locations = repo.get_active_locations(db)
    locations = [
        loc for loc in all_locations
        if not wanted_codes or loc["location_code"] in wanted_codes
    ]

    if not locations:
        raise RuntimeError("weather_no_matching_active_locations")

    print("WEATHER_DAILY_INGEST_START")
    print("locations=", [loc["location_code"] for loc in locations])
    print("forecast_days=", forecast_days)
    print("recent_actual_days=", recent_actual_days)
    print("ingest_current=", ingest_current)
    print()

    def commit_or_rollback_after_error() -> None:
        try:
            # Services record failed ingestion_runs before raising.
            # Commit preserves that audit when possible.
            db.commit()
        except Exception:
            db.rollback()

    for loc in locations:
        code = loc["location_code"]
        loc_summary: dict[str, Any] = {
            "location_code": code,
            "forecast": None,
            "recent_actuals": None,
            "current": None,
        }

        print(f"===== LOCATION {code} =====")

        try:
            result = ingest_forecast_for_location(
                db,
                location_code=code,
                forecast_days=forecast_days,
            )
            db.commit()
            loc_summary["forecast"] = {
                "status": result["status"],
                "rows_received": result["rows_received"],
                "rows_upserted": result["rows_upserted"],
                "run_id": result["run"]["id"],
                "run_status": result["run"]["status"],
            }
            print("forecast=", loc_summary["forecast"])
        except Exception as exc:
            commit_or_rollback_after_error()
            failure = {
                "location_code": code,
                "step": "forecast",
                "error": str(exc),
            }
            loc_summary["forecast"] = {"status": "failed", "error": str(exc)}
            summary["failures"].append(failure)
            print("forecast_failed=", failure)

        try:
            result = ingest_recent_actuals_for_location(
                db,
                location_code=code,
                days=recent_actual_days,
            )
            db.commit()
            loc_summary["recent_actuals"] = {
                "status": result["status"],
                "date_from": result["date_from"],
                "date_to": result["date_to"],
                "rows_received": result["rows_received"],
                "rows_upserted": result["rows_upserted"],
                "run_id": result["run"]["id"],
                "run_status": result["run"]["status"],
            }
            print("recent_actuals=", loc_summary["recent_actuals"])
        except Exception as exc:
            commit_or_rollback_after_error()
            failure = {
                "location_code": code,
                "step": "recent_actuals",
                "error": str(exc),
            }
            loc_summary["recent_actuals"] = {"status": "failed", "error": str(exc)}
            summary["failures"].append(failure)
            print("recent_actuals_failed=", failure)

        if ingest_current:
            try:
                result = ingest_current_for_location(db, location_code=code)
                db.commit()
                loc_summary["current"] = {
                    "status": result["status"],
                    "rows_upserted": result["rows_upserted"],
                    "run_id": result["run"]["id"],
                    "run_status": result["run"]["status"],
                }
                print("current=", loc_summary["current"])
            except Exception as exc:
                commit_or_rollback_after_error()
                failure = {
                    "location_code": code,
                    "step": "current",
                    "error": str(exc),
                }
                loc_summary["current"] = {"status": "failed", "error": str(exc)}
                summary["failures"].append(failure)
                print("current_failed=", failure)
        else:
            loc_summary["current"] = {"status": "skipped"}

        summary["locations"].append(loc_summary)
        print()

    summary["status"] = "partial" if summary["failures"] else "ok"

    print("===== WEATHER DAILY INGEST SUMMARY =====")
    print(json.dumps(summary, ensure_ascii=False, indent=2, default=str))

    if summary["failures"]:
        print("WEATHER_DAILY_INGEST_PARTIAL")
        sys.exit(2)

    print("WEATHER_DAILY_INGEST_OK")
    sys.exit(0)

finally:
    db.close()
PY
  RC="${PIPESTATUS[0]}"
  set -e

  echo
  echo "===== RESULT ====="
  echo "WEATHER_DAILY_INGEST_RC=$RC"
  echo "finished_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  exit "$RC"
} 2>&1 | tee -a "$LOG_FILE"
