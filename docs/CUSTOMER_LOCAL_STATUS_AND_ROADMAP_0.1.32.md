# GreenBrain Customer Local — Status & Roadmap 0.1.32

## Stato validato

Release corrente: `customer-local-0.1.32`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.32/customer-local-0.1.32.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

Validazioni completate:
- VERSION = 0.1.32
- package_version = 0.1.32
- update da bundle OK
- auto-apply SQL patches OK
- backend healthy
- frontend healthy
- Postgres locale running
- scheduler running
- smoke package OK
- doctor extended OK
- daily sequence manuale OK
- pipeline raw -> fact -> dense -> features OK
- train_missing locale OK, rc=0
- predict_all locale OK, rc=0
- heartbeat centrale healthy con local_agent_version 0.1.32

## Componenti ora presenti

### Runtime locale
- Postgres locale
- Backend locale
- Frontend locale
- Scheduler cron locale
- ml-worker Docker locale

### Orchestrazione locale
- `base/orchestration/lib/common.sh`
- `base/orchestration/jobs/pipeline/run_daily_pipeline.sh`
- `base/orchestration/jobs/ml/run_train_missing_local.sh`
- `base/orchestration/jobs/ml/run_predict_all_local.sh`
- `base/orchestration/jobs/runtime/run_daily_sequence.sh`

### Script operativi
- `base/scripts/smoke-local-package.sh`
- `base/scripts/apply-local-sql-patches.sh`
- `base/scripts/doctor-local-extended.sh`
- `base/scripts/runtime-heartbeat.sh`
- `base/scripts/setup-source-db.sh`

### SQL patches
- `25_features_dense_unique_constraint.sql`
- `26_ml_runtime_local_compat.sql`

## Risultato raggiunto

La release 0.1.32 è il primo bundle customer-local con:
- update install automatico
- SQL patches automatiche durante update
- ML worker locale containerizzato
- orchestrazione locale completa
- smoke test pacchetto
- doctor esteso
- daily sequence validata con heartbeat healthy

## Mancanze verso plug-and-play reale

1. ETL reale da SQL Server cliente verso Postgres locale.
2. Gestione credenziali SQL Server sicura e guidata.
3. Classificazione iniziale articoli in `greenhouse_products_normalized`.
4. Popolamento reale dati RAW cliente.
5. Training ML con famiglie reali e modelli generati.
6. Predict reale con output forecast non vuoto.
7. Scheduler daily sequence verificato da cron reale alle 21:05.
8. Gestione backup/restore completa lato cliente.
9. Log rotation e retention.
10. Installer più guidato per utente non tecnico.
11. Test fresh install completo con DB nuovo e dati seed/minimi.
12. Hardening sicurezza tunnel/remote access.
13. Documentazione cliente finale.

## Prossima fase consigliata

### 0.1.33
Obiettivo: rendere il runtime più verificabile automaticamente.

Task:
- aggiungere `doctor-local-extended` al flusso post-update opzionale
- aggiungere comando `run-local-daily-once.sh`
- aggiungere controllo esplicito ultimo heartbeat/versione
- aggiungere controllo ultimo log ML
- aggiungere test scheduler cron installato

### 0.1.34
Obiettivo: ETL SQL Server reale.

Task:
- completare setup source DB
- aggiungere test connessione SQL Server
- creare job ETL manuale
- salvare stato ultimo sync
- collegare ETL alla daily sequence

### 0.1.35
Obiettivo: dati reali e forecast reale.

Task:
- importare RAW cliente
- classificare articoli
- generare fact/dense/features reali
- train_missing con trained > 0
- predict_all con ok > 0
