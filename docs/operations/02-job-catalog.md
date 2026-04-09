# Job Catalog

## gh-refresh-registry
- type: systemd
- pre-step: gh-refresh-ml-diag
- script: /opt/greenhouse/bin/gh-refresh-registry
- purpose: refresh model registry and family model state
- outputs:
  - ml_forecast.family_model_state_v1
  - ml_ops.pipeline_run_log_v1

## gh-train-missing
- type: systemd
- script: jobs/run_train_missing.sh
- post-step: gh-sync-local-artifacts
- purpose: train missing bundles
- outputs:
  - models_v4 local bundles
  - DO Spaces bundles
  - ml_forecast state tables

## gh-predict-all
- type: systemd
- script: jobs/run_predict_all.sh
- purpose: run daily prediction for all active families
- outputs:
  - greenhouse_forecast_results_v2
  - priors parquet on storage

## gh-parquet-export
- type: systemd
- pre-step: check_etl_ready.sh
- script: jobs/parquet_export/scripts/run_daily_parquet_batches.sh
- purpose: export features_dense parquet to storage
- outputs:
  - bucket ml-snapshots / features_dense/v1
  - ops_parquet_export_runs
  - ops_parquet_export_state