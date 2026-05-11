# GreenBrain Customer Local — Status & Roadmap 0.1.63

## Release validata

Release corrente: `customer-local-0.1.63`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.63/customer-local-0.1.63.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Update demo runtime OK
- VERSION/package_version = 0.1.63
- Wizard Source DB integrato in `install.sh`
- Prompt `Configure Source DB now? yes/no [no]` presente
- SQL patches 25/26/27 OK
- Daily sequence OK
- Source DB placeholder gestito come `SOURCE_DB_IMPORT_SKIPPED_UNREACHABLE`
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK
- predict_all OK
- Heartbeat centrale healthy con local_agent_version 0.1.63
- Extended doctor OK

## Stato

Il bundle è più vicino a un processo installazione guidato quasi plug-and-play.

Il test SQL Server reale è intenzionalmente rimandato.

## Prossimo step

0.1.64:
- test fresh install one-shot con risposta `no` al wizard Source DB
- rendere il wizard Source DB più adatto a installazioni non interattive
- aggiungere riepilogo finale installazione
