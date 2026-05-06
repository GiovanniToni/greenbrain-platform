# GreenBrain — Orchestration Cleanup Decision Matrix

## Canonical runtime

| Area | Canonical |
|---|---|
| RAW → FACT → DENSE → FEATURES → MONITOR | infra/systemd/gh-daily-pipeline.service/timer |
| PARQUET export | infra/systemd/gh-parquet-export.service/timer |
| Registry | infra/systemd/gh-refresh-registry.service/timer |
| Daily train missing | infra/systemd/gh-train-missing.service/timer |
| Daily predict all | infra/systemd/gh-predict-all.service/timer |
| Biweekly full train | infra/systemd/gh-train-biweekly-all.service/timer |
| Quarterly full train | infra/systemd/gh-train-quarterly.service/timer |

## Legacy candidates

| File | Current role | Decision |
|---|---|---|
| apps/ml-worker/run_daily_2100_prepared.sh | Old all-in-one ETL + fact/dense/features + export + predict | Deprecate. Superseded by gh-daily-pipeline + gh-parquet-export + gh-predict-all |
| apps/ml-worker/run_daily_demo_full_pipeline.sh | Demo full flow for selected families | Deprecate or move to docs/examples |
| apps/ml-worker/run_daily_runtime.sh | Old client runtime daily flow, writes ETL tracking manually | Deprecated. Operational references removed from validation/docs |
| apps/ml-worker/run_daily_demo_runtime.sh | Demo export + selected predict | Deprecate or move to docs/examples |
| apps/ml-worker/run_nightly_runtime.sh | Old export + train all + predict all | Deprecate. Replaced by systemd timers |
| apps/ml-worker/run_smoke_runtime.sh | Manual smoke test | Keep as utility |
| apps/ml-worker/run_weekly_train_runtime.sh | Manual weekly train for demo families | Deprecate. Replaced by train-missing / biweekly / quarterly |

## Files to update before deleting legacy scripts

| File | Required update |
|---|---|
| client-runtime/scripts/validate_client_runtime.sh | Validate canonical systemd units and required ML scripts instead of legacy daily scripts |
| client-runtime/docs/dev_client_operational_runbook.md | Replace old runtime commands with canonical systemd runbook |
| client-runtime/docs/quick_update_guide.md | Replace smoke/update references if needed |
| client-runtime/release/runtime_manifest.txt | Replace old demo wrappers with canonical units/scripts |
| client-runtime/release/RELEASE_NOTES.md | Add orchestration cleanup note |

## Cleanup policy

1. Do not delete legacy scripts immediately.
2. Add deprecation headers first.
3. Update validation/docs/manifests.
4. Verify release build still contains canonical runtime.
5. Only then move legacy scripts to `apps/ml-worker/legacy/` or remove them.
