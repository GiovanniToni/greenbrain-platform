# Runtime V3 Status

## Stato
Runtime locale validato in modalità:
- manual local demo
- demo scheduled ready
- real client runtime prepared but not enabled

## Validato
- install.sh
- update.sh
- validate_client_runtime.sh
- run_smoke_runtime.sh
- run_daily_demo_runtime.sh
- run_weekly_train_runtime.sh
- export runtime
- train runtime
- predict runtime
- ml_ops pipeline/family logs
- t_ops_pipeline_monitor
- forecast writeback

## Non attivo
- cron
- systemd timers
- ETL reale cliente
- nightly reale cliente

## Regola
Il runtime resta non schedulato finché non decidiamo esplicitamente:
- demo schedulata
oppure
- runtime cliente reale
