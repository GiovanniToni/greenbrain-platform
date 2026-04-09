# GreenBrain Client Runtime Release

## Version
2026.04.06-runtime-ml-local-v4

## Included
- runtime ML locale validato
- export/train/predict validati
- ml_ops bridge coerente
- family/pipeline logs coerenti
- t_ops_pipeline_monitor coerente
- parquet export runtime
- package/update flow dev -> client
- cleanup riferimenti legacy principali
- systemd unit files riallineati
- validate_client_runtime.sh rafforzato
- install.sh hardening
- update.sh hardening
- modalità demo schedulata pronta
- wrapper run_daily_demo_runtime.sh
- wrapper run_daily_demo_full_pipeline.sh
- demo full pipeline locale validata:
  raw locali nel DB -> fact -> dense -> features -> export -> predict -> writeback

## Excluded
- sorgente SQL Server reale cliente
- ETL incrementale reale cliente
- cron attivi
- scheduler abilitato

## Mode
- local demo / validation
- manual export/train/predict
- demo scheduler ready but not enabled
- demo full pipeline ready but not enabled
- ETL safe-stop con env placeholder
- real runtime scheduler prepared but not enabled
