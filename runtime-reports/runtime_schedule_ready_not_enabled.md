# Runtime Schedule Prepared But Not Enabled

## Stato
I wrapper operativi sono preparati ma NON schedulati.

## Wrapper pronti
- /opt/greenbrain-platform/client-runtime/etl/run_etl_runtime.sh
- /opt/greenbrain-platform/apps/ml-worker/run_daily_runtime.sh
- /opt/greenbrain-platform/apps/ml-worker/run_weekly_train_runtime.sh

## Regola corrente
- nessun cron attivo
- ETL bloccato in safe-stop se la sorgente è placeholder
- daily wrapper pronto per futura attivazione alle 21:00
- weekly train wrapper pronto per futura attivazione

## Modalità attuale
- export manuale
- train manuale
- predict manuale
- scheduler non abilitato
