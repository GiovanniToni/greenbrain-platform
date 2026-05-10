# GreenBrain Customer Local — Status & Roadmap 0.1.41

## Release validata

Release corrente: `customer-local-0.1.41`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.41/customer-local-0.1.41.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Update demo runtime OK
- VERSION/package_version = 0.1.41
- Auto SQL patches OK
- Smoke package OK
- Provisioning validation OK
- Customer env wizard incluso
- Runtime provisioning wizard incluso
- run-local-daily-once OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con local_agent_version 0.1.41
- Extended doctor OK
- Scheduler cron OK
- Log ML host-owned gh:gh

## Miglioramenti inclusi

- Wizard per `overlay/env/customer-local.env`
- Wizard per `overlay/provisioning/local-runtime.env`
- Installer più guidato
- Bundle più vicino a installazione plug-and-play cliente

## Prossima fase

1. Test fresh completo da bundle 0.1.41
2. Consolidare installer one-shot
3. Aggiungere validazione porte occupate
4. Aggiungere check Docker/Compose più diagnostico
5. Preparare runbook operatore cliente
