# GreenBrain Customer Local — Status & Roadmap 0.1.48

## Release validata

Release corrente: `customer-local-0.1.48`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.48/customer-local-0.1.48.tar.gz`

Fresh test:
- `/tmp/gb_fresh_0148_full_20260510_235914/package/customer-local-template`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Fresh one-shot install OK
- Update demo runtime OK
- VERSION/package_version = 0.1.48
- Preflight intelligente OK
- Porte GreenBrain esistenti rilevate come warning, non errore
- Auto SQL patches OK
- Provisioning OK
- Backend/frontend healthy
- Scheduler cron OK
- run-local-daily-once OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con local_agent_version 0.1.48
- Extended doctor OK
- overlay/logs host-owned gh:gh
- overlay/logs/ml host-owned gh:gh
- daily_sequence_latest.log creato correttamente

## Stato strategico

La base customer-local è ora quasi plug-and-play:
- installer guidato
- wizard env cliente
- wizard runtime/provisioning
- preflight
- health wait
- update script
- SQL patches automatiche
- daily locale
- ML worker locale
- heartbeat centrale
- doctor esteso

## Prossima fase 0.1.49

Avviare scaffold connector gestionale cliente:
1. `source-db.env.example`
2. wizard `generate-source-db-env.sh`
3. `test-source-db-connection.sh`
4. integrazione minima nel doctor
5. nessun import distruttivo ancora
