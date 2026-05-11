# GreenBrain Customer Local — Status & Roadmap 0.1.49

## Release validata

Release corrente: `customer-local-0.1.49`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.49/customer-local-0.1.49.tar.gz`

Fresh test:
- `/tmp/gb_fresh_0149_full_20260511_081506/package/customer-local-template`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Fresh one-shot install OK
- Update demo runtime OK
- VERSION/package_version = 0.1.49
- Preflight intelligente OK
- Auto SQL patches OK
- Provisioning OK
- Backend/frontend healthy
- Scheduler cron OK
- run-local-daily-once OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con local_agent_version 0.1.49
- Extended doctor OK
- Source DB scaffold incluso
- source-db.env.example incluso nel bundle
- Source DB doctor check incluso

## Nota Source DB

Il test connessione Source DB fallisce correttamente con il placeholder:
- `192.168.1.10:1433`

Questo è atteso finché non viene configurato un gestionale reale raggiungibile.

## Prossimo step

0.1.50:
- creare primo scaffold import SQL Server -> raw locale
- aggiungere script `run-source-db-import-once.sh`
- aggiungere log import
- integrare check nel doctor
