# GreenBrain Dev -> Client Operational Runbook

## Obiettivo
Promuovere modifiche dal lato dev al client-runtime locale
in modo semplice, ripetibile e sicuro.

## Stato attuale del client-runtime
- modalità: local demo / validation
- ETL reale cliente: non attivo
- scheduler: preparato ma non attivo
- export/train/predict: validati
- ml_ops logging: valido
- forecast writeback: valido

## Regole fisse
- non attivare cron senza decisione esplicita
- non attivare ETL reale con env placeholder
- non sovrascrivere mai client-runtime/etl/.env
- usare sempre package + update + validate
- fare sempre smoke test post-update

## Procedura standard release

### 1. Aggiorna il codice lato dev
Modificare solo i file canonici.

### 2. Aggiorna il manifest
File:
client-runtime/release/runtime_manifest.txt

### 3. Crea package
Comando:
client-runtime/scripts/package_client_runtime.sh

Output:
- PACKAGE_DIR
- PACKAGE_TAR

### 4. Aggiorna release metadata
File:
- client-runtime/release/RELEASE_VERSION
- client-runtime/release/RELEASE_NOTES.md

### 5. Applica update
Comando:
client-runtime/update.sh <package_dir>

### 6. Valida runtime
Script:
client-runtime/scripts/validate_client_runtime.sh

### 7. Esegui smoke test
Script:
apps/ml-worker/run_smoke_runtime.sh

### 8. Verifica DB
Controllare:
- ml_ops.pipeline_run_log_v1
- ml_ops.family_run_log_v1
- public.t_ops_pipeline_monitor
- public.greenhouse_forecast_results_v2

## Smoke test standard
Script:
apps/ml-worker/run_smoke_runtime.sh

Contiene:
- export
- train "rosa"
- predict "rosa"

## Scheduler
Wrapper pronti ma non attivi:
- client-runtime/etl/run_etl_runtime.sh
- apps/ml-worker/run_daily_runtime.sh
- apps/ml-worker/run_weekly_train_runtime.sh

File piano:
runtime-reports/future_cron_example.txt

Stato:
- pronto
- non attivo

## Quando attivare scheduler
Solo se decidiamo esplicitamente una di queste modalità:

### Modalità A
demo schedulata locale

oppure

### Modalità B
cliente reale con sorgente SQL Server valida

Fino ad allora:
- manual run only

## Comandi rapidi utili

### Crea package
/opt/greenbrain-platform/client-runtime/scripts/package_client_runtime.sh

### Applica update
/opt/greenbrain-platform/client-runtime/update.sh /opt/greenbrain-platform/client-runtime/release/current_package

### Valida
/opt/greenbrain-platform/client-runtime/scripts/validate_client_runtime.sh

### Smoke test
/opt/greenbrain-platform/apps/ml-worker/run_smoke_runtime.sh

## Stato finale accettato
Client-runtime pronto come runtime locale validato,
aggiornabile da dev,
non ancora in go-live ETL cliente reale.
