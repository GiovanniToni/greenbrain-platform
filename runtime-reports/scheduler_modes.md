# Scheduler Modes

## Modalità 1 — Demo schedulata locale semplice
Usa:
- /opt/greenbrain-platform/apps/ml-worker/run_daily_demo_runtime.sh
- /opt/greenbrain-platform/apps/ml-worker/run_weekly_train_runtime.sh

Scopo:
- export + predict automatici locali
- nessun ETL reale
- nessun refresh fact/dense/features

## Modalità 2 — Demo full pipeline locale
Usa:
- /opt/greenbrain-platform/apps/ml-worker/run_daily_demo_full_pipeline.sh
- /opt/greenbrain-platform/apps/ml-worker/run_weekly_train_runtime.sh

Scopo:
- refresh DB locale
- export parquet
- predict automatici locali
- nessuna dipendenza da SQL Server cliente

## Modalità 3 — Runtime reale cliente
Usa:
- /opt/greenbrain-platform/apps/ml-worker/run_daily_runtime.sh
- /opt/greenbrain-platform/apps/ml-worker/run_weekly_train_runtime.sh

Scopo:
- ETL reale cliente
- pipeline completa
- richiede sorgente SQL Server valida

## Stato attuale
- nessuna modalità attiva
- tutte preparate
- cron non abilitato
