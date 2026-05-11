# GreenBrain Customer Local — Status & Roadmap 0.1.59

## Release validata

Release corrente: `customer-local-0.1.59`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.59/customer-local-0.1.59.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Update demo runtime OK
- VERSION/package_version = 0.1.59
- Source DB import integrato nello step 0 della daily sequence
- Esiti Source DB distinti:
  - `SOURCE_DB_IMPORT_OK`
  - `SOURCE_DB_IMPORT_SKIPPED_UNREACHABLE`
  - `SOURCE_DB_IMPORT_FAILED_NON_BLOCKING`
- Placeholder SQL Server irraggiungibile gestito correttamente come skip
- Daily sequence completata in circa 8 secondi
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK
- predict_all OK
- Heartbeat centrale healthy con local_agent_version 0.1.59
- Extended doctor OK

## Stato

Customer-local è robusto con Source DB:
- non configurato
- configurato ma irraggiungibile
- pronto per test con SQL Server reale

## Prossimo step

0.1.60:
- preparare test con Source DB reale
- validare import incrementale `GREENHOUSE_VIEW_STAT`
- verificare popolamento `source_import.sales_raw`
- decidere quando collegare `source_import.sales_raw` alla pipeline fact locale
