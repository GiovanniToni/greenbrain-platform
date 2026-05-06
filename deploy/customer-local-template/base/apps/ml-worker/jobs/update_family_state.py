#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
import psycopg

DATABASE_URL = os.environ["DATABASE_URL"]

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--family", required=True)
    ap.add_argument("--action", required=True, choices=[
        "train_success", "train_failed", "predict_success", "predict_failed"
    ])
    ap.add_argument("--run-id", type=int, default=None)
    ap.add_argument("--model-code", default=None)
    ap.add_argument("--train-max-date", default=None)
    ap.add_argument("--message", default=None)
    args = ap.parse_args()

    sql_map = {
        "train_success": """
            select ml_forecast.mark_family_train_success_v1(%s,%s,%s,now(),%s,%s)
        """,
        "train_failed": """
            select ml_forecast.mark_family_train_failed_v1(%s,%s,%s)
        """,
        "predict_success": """
            select ml_forecast.mark_family_predict_success_v1(%s,%s,%s)
        """,
        "predict_failed": """
            select ml_forecast.mark_family_predict_failed_v1(%s,%s,%s)
        """,
    }

    params_map = {
        "train_success": (
            args.family, args.run_id, args.model_code, args.train_max_date, args.message
        ),
        "train_failed": (
            args.family, args.run_id, args.message
        ),
        "predict_success": (
            args.family, args.run_id, args.message
        ),
        "predict_failed": (
            args.family, args.run_id, args.message
        ),
    }

    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(sql_map[args.action], params_map[args.action])
        conn.commit()

    print(f"OK update_family_state | family={args.family} | action={args.action}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
