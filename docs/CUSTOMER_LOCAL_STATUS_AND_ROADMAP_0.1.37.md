# GreenBrain Customer Local — Status & Roadmap 0.1.37

## Release validata

Release corrente: `customer-local-0.1.37`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.37/customer-local-0.1.37.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

Fresh test:
- `/tmp/gb_fresh_0137_20260510_171200/package/customer-local-template`

## Validazioni completate

- Fresh smoke OK
- Heartbeat fresh install: skip pulito se non provisioned
- Update demo runtime OK
- Auto SQL patches OK
- VERSION/package_version = 0.1.37
- Backend/frontend healthy
- Scheduler OK
- `run-local-daily-once.sh` OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con `local_agent_version=0.1.37`
- Extended doctor OK
- Log ML host-owned `gh:gh`

## Componenti inclusi

- Postgres locale
- Backend locale
- Frontend locale
- Scheduler cron locale
- ml-worker locale
- Orchestrazione locale
- Auto SQL patch runner
- Smoke package
- Extended doctor
- Daily wrapper
- Heartbeat fresh-safe

## Prossima fase

Obiettivo: passare da runtime demo validato a customer-local plug-and-play reale.

Priorità:
1. Hardening installer/provisioning reale
2. Setup guidato cliente/tenant
3. Connessione DB sorgente cliente
4. ETL reale SQL Server -> GreenBrain local
5. Diagnostica post-install unica
6. Runbook operativo finale
7. Test installazione completamente pulita da zero
