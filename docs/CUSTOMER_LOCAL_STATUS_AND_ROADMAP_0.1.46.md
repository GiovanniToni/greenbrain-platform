# GreenBrain Customer Local — Status & Roadmap 0.1.46

## Release validata

Release corrente: `customer-local-0.1.46`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.46/customer-local-0.1.46.tar.gz`

Fresh test:
- `/tmp/gb_fresh_0146_full_20260510_233643/package/customer-local-template`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Fresh one-shot install OK
- `install_exit=0`
- Customer env wizard OK
- Runtime provisioning wizard OK
- Backend health wait OK
- Doctor OK
- Smoke package OK
- Provisioning OK
- VERSION/package_version = 0.1.46
- Daily sequence OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con `local_agent_version=0.1.46`
- Extended doctor OK
- Scheduler cron OK
- Update demo runtime OK
- Auto SQL patches OK
- `overlay/logs` host-owned `gh:gh`
- `overlay/logs/ml` host-owned `gh:gh`
- `daily_sequence_latest.log` creato correttamente

## Fix chiave

- `run-local-daily-once.sh` ora corregge ownership di tutta `overlay/logs`, non solo `overlay/logs/ml`.
- Risolto errore fresh install: `ln: failed to create symbolic link ... Permission denied`.

## Stato

`customer-local-0.1.46` è una baseline solida per installer cliente plug-and-play.

## Prossima fase 0.1.47

1. Port availability preflight
2. Doctor più severo su daily/latest logs
3. Validazione finale bundle one-shot
4. Runbook operativo cliente
