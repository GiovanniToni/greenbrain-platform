# GreenBrain Customer Local — Status & Roadmap 0.1.50

## Release validata

Release corrente: `customer-local-0.1.50`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.50/customer-local-0.1.50.tar.gz`

Fresh test:
- `/tmp/gb_fresh_0150_full_20260511_085311/package/customer-local-template`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Fresh one-shot install OK
- Update demo runtime OK
- VERSION/package_version = 0.1.50
- Auto SQL patches 25/26/27 OK
- Tabella `source_import.sales_raw` creata correttamente
- Import Source DB skip pulito se `source-db.env` non configurato
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con local_agent_version 0.1.50
- Extended doctor OK
- Source DB config non configurato gestito correttamente

## Nuovo scaffold Source DB

Aggiunti:
- `source_import.sales_raw`
- `base/apps/source-db-importer/import_sales_raw.py`
- `base/scripts/import-source-db-once.sh`
- `env/source-db.env.example`

## Prossimo step

0.1.51:
- test Source DB configurato ma irraggiungibile
- log dedicati import Source DB
- doctor check su ultimo import
- nessuna integrazione nella daily sequence finché non validiamo una connessione reale
