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
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not args.dry_run:
        raise SystemExit(
            "STOP: this scaffold only supports --dry-run. "
            "Real R3 execution is intentionally not implemented yet."
        )

    output_root = Path(args.output_root)
    run_id = args.run_id or default_run_id()

    validate_source(args.source)
    validate_mode(args.mode)
    validate_output_root(output_root)
    validate_run_id(run_id)

    run_dir = output_root / run_id
    ensure_run_layout(run_dir)

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
        stages=planned_stages(),
        inputs={
            "phase": "2B dry-run scaffold",
            "note": "Runtime R3 scripts are not executed by this patch.",
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
