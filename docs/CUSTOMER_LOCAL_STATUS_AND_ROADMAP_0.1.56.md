# GreenBrain Customer Local — Status & Roadmap 0.1.56

## Release validata

Release corrente: `customer-local-0.1.56`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.56/customer-local-0.1.56.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Update demo runtime OK
- VERSION/package_version = 0.1.56
- Safe env examples sync OK
- `env/source-db.env.example` presente dopo update
- Auto SQL patches 25/26/27 OK
- `source_import.sales_raw` presente
- Source DB import configurato con placeholder
- ODBC Driver 18 rilevato e usato
- Fallimento atteso: `Login timeout expired` su `192.168.1.10:1433`
- Fallimento Source DB non blocca runtime
- run-local-daily-once OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con local_agent_version 0.1.56
- Extended doctor OK

## Stato Source DB

Il runtime è pronto lato driver/importer/logging.

Resta da validare con un gestionale reale raggiungibile:
- host SQL Server reale
- database reale
- utente readonly
- vista compatibile, es. `GREENHOUSE_VIEW_STAT`
- colonne minime: Progressivo, CodArt, DESCRIZIONE, TIPO, FASCIA, CATEGORIA, QUANTITA, IMPONIBILENETTO, DATA, DISATTIVATO, MOVIM_CASSA

## Prossimo step

0.1.57:
- integrare `import-source-db-once.sh` nella daily sequence
- import Source DB opzionale e non bloccante
- loggare chiaramente success/failure
- mantenere runtime healthy anche se gestionale non raggiungibile
