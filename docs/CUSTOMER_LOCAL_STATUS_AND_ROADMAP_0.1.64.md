# GreenBrain Customer Local — Status & Roadmap 0.1.64

## Release validata

Release corrente: `customer-local-0.1.64`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.64/customer-local-0.1.64.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Update demo runtime OK
- Fresh one-shot install OK con `GREENBRAIN_CONFIGURE_SOURCE_DB=no`
- VERSION/package_version = 0.1.64
- Source DB non configurato gestito come `SOURCE_DB_IMPORT_NOT_CONFIGURED`
- Install summary presente
- `install_exit=0`
- Daily sequence OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK
- predict_all OK
- Heartbeat centrale healthy con local_agent_version 0.1.64
- Extended doctor OK

## Stato

Il bundle supporta installazione guidata quasi plug-and-play anche senza Source DB configurato.

Il test SQL Server reale resta rimandato.

## Prossimo step

0.1.65:
- aggiungere un comando unico post-install di verifica
- migliorare riepilogo operativo finale
- preparare runbook cliente minimale
