# Scheduler Plan Not Enabled

## Daily plan
Orario previsto futuro: 21:00

Wrapper:
- /opt/greenbrain-platform/apps/ml-worker/run_daily_runtime.sh

## Weekly train plan
Orario previsto futuro: domenica ore 03:00

Wrapper:
- /opt/greenbrain-platform/apps/ml-worker/run_weekly_train_runtime.sh

## Stato attuale
- nessun cron attivo
- nessun systemd timer attivo
- scheduler solo preparato
- attivazione rinviata a quando sarà deciso esplicitamente

## Regola
Non attivare scheduling automatico finché:
- non decidiamo il set di famiglie da predict
- non decidiamo la politica train
- non esiste una sorgente ETL cliente reale
oppure
- non scegliamo esplicitamente modalità demo schedulata
