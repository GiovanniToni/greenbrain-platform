# Live Schedules

## Systemd timers
- gh-refresh-registry.timer → 00:45
- gh-train-missing.timer → 01:10
- gh-predict-all.timer → 01:30
- gh-parquet-export.timer → 21:35 local time
- gh-train-biweekly-all.timer → Sun on 1st/15th at 02:00
- gh-train-quarterly.timer → Jan/Apr/Jul/Oct 1 at 02:30

## pg_cron
Vedi file:
- docs/operations/pg_cron_jobs.txt

## Notes
- parquet export parte con gate ETL (`check_etl_ready.sh`)
- refresh ml_diag parte come pre-step di refresh_registry
- sync_local_artifacts parte come post-step dei train jobs