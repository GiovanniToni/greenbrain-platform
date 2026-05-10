# GreenBrain Customer Local — Status & Roadmap 0.1.34

## Release validata

Release corrente: `customer-local-0.1.34`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.34/customer-local-0.1.34.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Fresh package smoke test OK
- Update da bundle OK
- Auto-apply SQL patches OK
- VERSION = 0.1.34
- package_version = 0.1.34
- Backend healthy
- Frontend healthy
- Postgres locale running
- Scheduler running
- `run-local-daily-once.sh` OK
- Daily sequence OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con `local_agent_version=0.1.34`
- Extended doctor OK
- Cron scheduler OK:
  - heartbeat ogni 5 minuti
  - daily alle 21:05 tramite `run-local-daily-once.sh`
- Log ML scritti come utente host `gh:gh`, non più root

## Miglioramenti inclusi in 0.1.34

- ml-worker eseguito come utente host tramite `LOCAL_UID:LOCAL_GID`
- preflight ownership in `run-local-daily-once.sh`
- scheduler cron usa wrapper operativo, non comando raw Docker
- doctor esteso rileva `run-local-daily-once`
- log ML e symlink latest scrivibili dal runtime host
- auto SQL patches durante update bundle
- smoke test package incluso

## Stato attuale

La 0.1.34 è il bundle customer-local più stabile finora: installabile, aggiornabile, diagnosticabile e operativo su runtime demo.

## Cosa manca per obiettivo finale plug-and-play

1. Fresh install reale da zero, non solo smoke.
2. Wizard/provisioning cliente più guidato.
3. Setup SQL Server sorgente reale.
4. ETL incrementale reale da gestionale cliente.
5. Classificazione manuale iniziale prodotti/famiglie.
6. Dataset reale sufficiente per training ML.
7. Test scheduler notturno reale alle 21:05.
8. Hardening backup/restore.
9. Documentazione cliente finale.
10. Procedura di deploy multi-cliente ripetibile.

## Prossima release suggerita

`customer-local-0.1.35`

Obiettivo:
- test fresh install completo;
- validazione scheduler reale;
- miglioramento installer/provisioning;
- doctor ancora più severo su ultimo heartbeat/log;
- checklist operativa cliente.
