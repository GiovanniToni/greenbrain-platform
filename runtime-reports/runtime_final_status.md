# Runtime Final Status

## Stato generale
GreenBrain client-runtime è operativo in modalità local demo / validation.

## Validato
- package client-runtime
- update dev -> client
- validate_client_runtime.sh
- export runtime
- train runtime
- predict runtime
- scrittura forecast su public.greenhouse_forecast_results_v2
- logging su ml_ops.pipeline_run_log_v1
- logging su ml_ops.family_run_log_v1
- monitor su public.t_ops_pipeline_monitor

## Non attivo
- ETL reale cliente
- scheduler automatico
- cron
- systemd timer attivi

## Regola operativa
- ETL resta in safe-stop con env placeholder
- scheduler resta preparato ma non attivo
- runtime usato in modalità manuale
