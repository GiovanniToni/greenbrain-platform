# Runtime V4 Status

## Stato
Runtime locale validato in modalità:

- manual local demo
- demo scheduled ready
- demo full pipeline local validated
- real client runtime prepared but not enabled

## Validato
- install.sh
- update.sh
- validate_client_runtime.sh
- run_smoke_runtime.sh
- run_daily_demo_runtime.sh
- run_daily_demo_full_pipeline.sh
- run_weekly_train_runtime.sh
- refresh fact da raw locali già presenti nel DB
- refresh dense
- refresh features
- refresh catalog
- export runtime
- train runtime
- predict runtime
- ml_ops pipeline/family logs
- t_ops_pipeline_monitor
- forecast writeback

## Non validato
- ETL reale da SQL Server cliente
- caricamento raw da sorgente esterna cliente
- nightly reale cliente end-to-end

## Regola
Il runtime resta non schedulato finché non decidiamo esplicitamente:
- demo schedulata
oppure
- runtime cliente reale
