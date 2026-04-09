# Client Runtime Mode

## Stato corrente
Il client-runtime è considerato operativo in modalità:

- local demo / local validation
- ML runtime attivo
- ETL reale cliente non configurato
- nessuna schedulazione automatica attiva

## Cosa è validato
- export parquet locale
- train locale
- predict locale
- scrittura forecast su greenhouse_forecast_results_v2
- logging ml_ops
- t_ops_pipeline_monitor
- storage locale

## Cosa non è ancora validato
- sorgente SQL Server reale cliente
- ETL incrementale reale
- nightly end-to-end reale cliente

## Regola operativa
Fino a configurazione di una sorgente cliente reale:
- train manuale
- predict manuale
- export manuale
- ETL bloccato con safe-stop
- nessun cron automatico
