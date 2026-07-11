"""Dry-run scaffold for the future `gb dataset build-global` command.

This first patch deliberately does not execute the R3 pipeline. It creates a
versioned run directory containing a manifest and a decision CSV that document
the planned R3A -> R3B -> R3C -> R3D -> R3D2 stages.

Safety guarantees in this version:
- no DB writes;
- no schema changes;
- no training;
- no prediction;
- no forecast staging;
- no publish to greenhouse_forecast_results_v2;
- no Docker/systemd changes;
- no execution of runtime R3 scripts.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import date, datetime
from pathlib import Path

try:
    from .manifest import (
        BuildGlobalManifest,
        BuildGlobalStage,
        ensure_run_layout,
        write_decision_csv,
        write_manifest,
    )
    from .validation import (
        validate_mode,
        validate_output_root,
        validate_run_id,
        validate_source,
    )
    from .r3a_raw_extracts import R3ARawExtractConfig, build_raw_extracts
    from .r3a_validation import validate_materialized_extract, validate_plan_manifest
except ImportError:  # Allows direct execution: python jobs/datasets/build_global.py
    from manifest import (
        BuildGlobalManifest,
        BuildGlobalStage,
        ensure_run_layout,
        write_decision_csv,
        write_manifest,
    )
    from validation import (
        validate_mode,
        validate_output_root,
        validate_run_id,
        validate_source,
    )
    from r3a_raw_extracts import R3ARawExtractConfig, build_raw_extracts
    from r3a_validation import validate_materialized_extract, validate_plan_manifest


DEFAULT_OUTPUT_ROOT = Path("/opt/greenbrain-platform/runtime/ml-datasets/runs")


def default_run_id() -> str:
    return "gb_dataset_build_global_dry_run_" + datetime.now().strftime("%Y%m%d_%H%M%S")


def planned_stages() -> list[BuildGlobalStage]:
    return [
        BuildGlobalStage(
            name="R3A_RAW_EXTRACT",
            status="PLANNED_NOT_EXECUTED",
            source_kind="runtime_promotion_candidate",
            source_reference="r3a2_extract_raw_parquet_robust.py",
            output_reference="raw_extracts/",
            notes="Requires parameterization before real execution.",
        ),
        BuildGlobalStage(
            name="R3B_FAMILY_PRICEBAND_DAY",
            status="PLANNED_NOT_EXECUTED",
            source_kind="runtime_promotion_candidate",
            source_reference="r3b_fixed_build_family_priceband_day_retry.py",
            output_reference="family_priceband_day/",
            notes="Requires parameterized input/output manifests.",
        ),
        BuildGlobalStage(
            name="R3B_WEATHER_WIDE",
            status="PLANNED_NOT_EXECUTED",
            source_kind="runtime_promotion_candidate",
            source_reference="r3b_weather_wide_build.py",
            output_reference="weather_wide/",
            notes="DB-write-looking static hit must be reviewed before real execution.",
        ),
        BuildGlobalStage(
            name="R3C_FAMILY_DAY",
            status="PLANNED_NOT_EXECUTED",
            source_kind="runtime_promotion_candidate",
            source_reference="r3c_build_family_day.py",
            output_reference="family_day/",
            notes="Validated historical output exists; promote only after parameterization.",
        ),
        BuildGlobalStage(
            name="R3D_FEATURE_ENRICHMENT",
            status="PLANNED_NOT_EXECUTED",
            source_kind="runtime_plus_repo_adapter_candidate",
            source_reference="r3d_feature_enrichment_v2_build.py + feature_builder_v2.py",
            output_reference="family_day_enriched/ and family_priceband_day_enriched/",
            notes="Adapter first; avoid deep refactor.",
        ),
        BuildGlobalStage(
            name="R3D2_ROLLING_SIDECAR",
            status="PLANNED_NOT_EXECUTED",
            source_kind="runtime_promotion_candidate",
            source_reference="r3d2_rolling_sidecar_build.py",
            output_reference="rolling_sidecar/",
            notes="Requires hardcoded path/run cleanup.",
        ),
        BuildGlobalStage(
            name="MANIFEST_AND_VALIDATION",
            status="DRY_RUN_WRITTEN",
            source_kind="new_scaffold",
            source_reference="jobs/datasets/manifest.py + jobs/datasets/validation.py",
            output_reference="metadata/build_global_manifest.json and analysis/build_global_decision.csv",
            notes="Only scaffold artifacts are written in this patch.",
        ),
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Dry-run scaffold for GreenBrain build-global dataset command."
    )
    parser.add_argument("--as-of-date", default=date.today().isoformat())
    parser.add_argument("--source", choices=["cloud", "local"], default="cloud")
    parser.add_argument("--mode", choices=["full", "incremental"], default="full")
    parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT))
    parser.add_argument("--run-id", default="")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Required for this scaffold. Real execution is intentionally blocked.",
    )
    parser.add_argument(
        "--execute-r3a-materialized",
        action="store_true",
        help=(
            "Execute the gated R3A materialized DB read-only extraction. "
            "Requires --enable-r3a-materialized, --confirm-db-read-only, "
            "--database-url-env, and an explicit --run-id."
        ),
    )
    parser.add_argument(
        "--enable-r3a-materialized",
        action="store_true",
        help=(
            "Gate flag for future R3A materialized extraction. Without "
            "--execute-r3a-materialized this records intent only and never reads the DB."
        ),
    )
    parser.add_argument(
        "--confirm-db-read-only",
        action="store_true",
        help=(
            "Required confirmation for future R3A materialized extraction. "
            "This patch still does not read the DB."
        ),
    )
    parser.add_argument(
        "--database-url-env",
        default="",
        help=(
            "Name of the environment variable that would contain the DB URL "
            "in a future execution patch. This patch does not read it."
        ),
    )
    return parser.parse_args()


def _valid_env_var_name(value: str) -> bool:
    if not value:
        return False
    if not (value[0].isalpha() or value[0] == "_"):
        return False
    return all(ch.isalnum() or ch == "_" for ch in value)


def materialized_gate_intent(args: argparse.Namespace) -> dict[str, object]:
    execute_requested = bool(args.execute_r3a_materialized)
    enabled = bool(args.enable_r3a_materialized)
    confirmed_read_only = bool(args.confirm_db_read_only)
    database_url_env = str(args.database_url_env or "").strip()

    intent: dict[str, object] = {
        "enabled": enabled,
        "execute_requested": execute_requested,
        "status": "DISABLED",
        "execute": False,
        "db_read": "NO",
        "db_write": "NO",
        "r3a_materialized_execution": "NO",
        "r3a_validator_materialized_execution": "NO",
        "parquet_read": "NO",
        "database_url_env": database_url_env,
        "confirm_db_read_only": confirmed_read_only,
        "reason": "R3A materialized execution is not enabled.",
        "validation_issues": [],
    }

    issues: list[str] = []

    if not enabled:
        if execute_requested:
            issues.append("--execute-r3a-materialized requires --enable-r3a-materialized")
        if confirmed_read_only:
            issues.append("--confirm-db-read-only requires --enable-r3a-materialized")
        if database_url_env:
            issues.append("--database-url-env requires --enable-r3a-materialized")
        if issues:
            intent["status"] = "INVALID_DISABLED_GATE_FLAGS"
            intent["validation_issues"] = issues
            raise SystemExit(
                "STOP: invalid R3A materialized gate flags: " + "; ".join(issues)
            )
        return intent

    if not confirmed_read_only:
        issues.append("--enable-r3a-materialized requires --confirm-db-read-only")

    if not database_url_env:
        issues.append("--enable-r3a-materialized requires --database-url-env")
    elif not _valid_env_var_name(database_url_env):
        issues.append("--database-url-env must be a valid environment variable name")

    if execute_requested and not args.run_id:
        issues.append("--execute-r3a-materialized requires an explicit --run-id")

    if issues:
        intent["status"] = "INVALID_ENABLED_GATE_FLAGS"
        intent["validation_issues"] = issues
        raise SystemExit(
            "STOP: invalid R3A materialized gate flags: " + "; ".join(issues)
        )

    if execute_requested:
        intent["status"] = "MATERIALIZED_EXECUTION_AUTHORIZED"
        intent["execute"] = True
        intent["db_read"] = "YES"
        intent["r3a_materialized_execution"] = "YES"
        intent["r3a_validator_materialized_execution"] = "YES_AFTER_EXTRACT"
        intent["parquet_read"] = "YES_FOR_VALIDATION"
        intent["reason"] = (
            "R3A materialized extraction was explicitly requested, confirmed "
            "as DB read-only, and authorized by the gate."
        )
        return intent

    intent["status"] = "NON_EXECUTING_GATE_ACKNOWLEDGED"
    intent["reason"] = (
        "Future materialized R3A extraction was explicitly requested and "
        "confirmed as read-only, but --execute-r3a-materialized was not supplied; "
        "this run records intent only and never reads the DB."
    )
    return intent


def _database_url_from_env(env_name: str) -> str:
    if not _valid_env_var_name(env_name):
        raise SystemExit("STOP: invalid database URL env var name.")

    value = os.environ.get(env_name)
    if not value:
        raise SystemExit(
            "STOP: database URL environment variable is missing or empty: "
            f"{env_name}"
        )
    return value

def main() -> int:
    args = parse_args()

    if args.dry_run and args.execute_r3a_materialized:
        raise SystemExit(
            "STOP: --dry-run and --execute-r3a-materialized are mutually exclusive."
        )

    if not args.dry_run and not args.execute_r3a_materialized:
        raise SystemExit(
            "STOP: use --dry-run for planning or --execute-r3a-materialized "
            "for the explicitly gated R3A-only materialized execution."
        )

    r3a_materialized_gate = materialized_gate_intent(args)

    output_root = Path(args.output_root)
    run_id = args.run_id or default_run_id()

    validate_source(args.source)
    validate_mode(args.mode)
    validate_output_root(output_root)
    validate_run_id(run_id)

    run_dir = output_root / run_id
    ensure_run_layout(run_dir)

    if args.execute_r3a_materialized:
        database_url = _database_url_from_env(str(args.database_url_env).strip())
        r3a_result = build_raw_extracts(
            R3ARawExtractConfig(
                run_id=run_id,
                run_dir=run_dir,
                database_url=database_url,
                execute=True,
            )
        )
    else:
        r3a_result = build_raw_extracts(
            R3ARawExtractConfig(
                run_id=run_id,
                run_dir=run_dir,
                database_url=None,
                execute=False,
            )
        )

    r3a_manifest_path = Path(r3a_result.manifest_path)
    r3a_dataset_names = [dataset.name for dataset in r3a_result.datasets]
    r3a_safety = dict(r3a_result.safety)

    r3a_plan_validation_result = None
    r3a_plan_validation_path = None
    r3a_materialized_validation_result = None
    r3a_materialized_validation_path = None

    if args.execute_r3a_materialized:
        r3a_materialized_validation_result = validate_materialized_extract(run_dir)
        r3a_materialized_validation_path = (
            run_dir / "analysis" / "r3a_materialized_validation.json"
        )
        r3a_materialized_validation_path.write_text(
            json.dumps(
                r3a_materialized_validation_result.to_dict(),
                indent=2,
                sort_keys=True,
                ensure_ascii=False,
            )
            + chr(10),
            encoding="utf-8",
        )
        if not r3a_materialized_validation_result.ok:
            raise SystemExit(
                "STOP: R3A materialized validation failed. "
                f"See {r3a_materialized_validation_path}"
            )
    else:
        r3a_plan_validation_result = validate_plan_manifest(r3a_manifest_path)
        r3a_plan_validation_path = run_dir / "analysis" / "r3a_plan_validation.json"
        r3a_plan_validation_path.write_text(
            json.dumps(
                r3a_plan_validation_result.to_dict(),
                indent=2,
                sort_keys=True,
                ensure_ascii=False,
            )
            + chr(10),
            encoding="utf-8",
        )
        if not r3a_plan_validation_result.ok:
            raise SystemExit(
                "STOP: R3A plan validation failed. "
                f"See {r3a_plan_validation_path}"
            )

    stages = planned_stages()
    stages[0] = BuildGlobalStage(
        name="R3A_RAW_EXTRACT",
        status="PLANNED_BY_R3A_MODULE",
        source_kind="repo_module_dry_run",
        source_reference="jobs.datasets.r3a_raw_extracts",
        output_reference=str(r3a_manifest_path),
        notes=(
            f"R3A module planned {len(r3a_dataset_names)} datasets with "
            "execute=False; no DB read/write."
        ),
    )

    manifest = BuildGlobalManifest(
        run_id=run_id,
        command="gb dataset build-global",
        dry_run=True,
        source=args.source,
        mode=args.mode,
        as_of_date=args.as_of_date,
        output_root=str(output_root),
        run_dir=str(run_dir),
        safety={
            "db_write": "NO",
            "db_schema_change": "NO",
            "service_change": "NO",
            "timer_change": "NO",
            "docker_change": "NO",
            "training_execution": "NO",
            "prediction_execution": "NO",
            "publish_execution": "NO",
            "legacy_final_write": "NO",
            "r3_pipeline_execution": "NO",
        },
        stages=stages,
        inputs={
            "phase": "2D R3A dry-run integration",
            "note": (
                "R3A repo module is invoked with execute=False; "
                "downstream R3B/R3C/R3D are not executed."
            ),
            "r3a_extract_manifest": str(r3a_manifest_path),
            "r3a_datasets_planned": len(r3a_dataset_names),
            "r3a_dataset_names": r3a_dataset_names,
            "r3a_safety": r3a_safety,
            "r3a_plan_validation": (
                str(r3a_plan_validation_path)
                if r3a_plan_validation_path is not None
                else None
            ),
            "r3a_plan_validation_ok": (
                r3a_plan_validation_result.ok
                if r3a_plan_validation_result is not None
                else None
            ),
            "r3a_plan_validation_issue_count": (
                len(r3a_plan_validation_result.issues)
                if r3a_plan_validation_result is not None
                else None
            ),
            "r3a_plan_validation_safety": (
                dict(r3a_plan_validation_result.safety)
                if r3a_plan_validation_result is not None
                else None
            ),
            "r3a_materialized_validation": (
                str(r3a_materialized_validation_path)
                if r3a_materialized_validation_path is not None
                else None
            ),
            "r3a_materialized_validation_ok": (
                r3a_materialized_validation_result.ok
                if r3a_materialized_validation_result is not None
                else None
            ),
            "r3a_materialized_validation_issue_count": (
                len(r3a_materialized_validation_result.issues)
                if r3a_materialized_validation_result is not None
                else None
            ),
            "r3a_materialized_validation_safety": (
                dict(r3a_materialized_validation_result.safety)
                if r3a_materialized_validation_result is not None
                else None
            ),
            "r3a_materialized_gate": r3a_materialized_gate,
        },
    )

    manifest_path = run_dir / "metadata" / "build_global_manifest.json"
    decision_path = run_dir / "analysis" / "build_global_decision.csv"

    write_manifest(manifest, manifest_path)
    write_decision_csv(decision_path, manifest)

    print("BUILD_GLOBAL_DRY_RUN_PLAN_ONLY")
    print(f"run_id={run_id}")
    print(f"run_dir={run_dir}")
    print(f"manifest={manifest_path}")
    print(f"decision={decision_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
