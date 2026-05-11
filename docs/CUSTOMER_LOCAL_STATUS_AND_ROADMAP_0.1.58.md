# GreenBrain Customer Local — Status & Roadmap 0.1.58

## Release validata

Release corrente: `customer-local-0.1.58`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.58/customer-local-0.1.58.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Update demo runtime OK
- VERSION/package_version = 0.1.58
- Source DB import integrato nella daily sequence come step 0 non bloccante
- Source DB irraggiungibile skippato velocemente
- Skip registrato in `overlay/logs/source-db/import_sales_raw_latest.log`
- Daily sequence completata in circa 8 secondi con placeholder irraggiungibile
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK
- predict_all OK
- Heartbeat centrale healthy con local_agent_version 0.1.58
- Extended doctor OK

## Stato

Il runtime locale è ora robusto anche con Source DB configurato ma non raggiungibile.

## Prossimo step

0.1.59:
- distinguere nel daily log tra Source DB import OK, Source DB skip irraggiungibile e Source DB import failed reale
