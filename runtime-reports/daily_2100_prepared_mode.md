# Daily 21:00 Prepared Mode

## Stato
Il flusso giornaliero ETL -> data pipeline -> export -> predict è stato preparato,
ma NON è schedulato.

## Script pronto
/opt/greenbrain-platform/apps/ml-worker/run_daily_2100_prepared.sh

## Regola attuale
- nessun cron attivo
- esecuzione solo manuale
- ETL safe-stop se la sorgente è placeholder/demo

## Quando attivarlo
Solo dopo configurazione della sorgente SQL Server reale cliente.
