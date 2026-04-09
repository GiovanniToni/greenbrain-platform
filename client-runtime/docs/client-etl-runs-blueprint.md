# GreenBrain Client — Blueprint etl_runs

## Scopo
Tracciare in modo robusto ogni esecuzione ETL verso il DB GreenBrain cliente.

## Obiettivi
- audit
- retry controllati
- visibilità errori
- supporto bulk e incrementale
- supporto monitoraggio operativo

---

## Tipi run
- `bulk_initial`
- `incremental_daily`
- `manual_repair`
- `backfill`

---

## Campi logici attesi
- `run_id`
- `job_name`
- `run_type`
- `status`
- `started_at`
- `ended_at`
- `source_system`
- `source_object`
- `from_progressivo`
- `to_progressivo`
- `from_day`
- `to_day`
- `rows_extracted`
- `rows_loaded`
- `rows_skipped`
- `error_message`
- `meta_json`

---

## Stati run
- `running`
- `success`
- `failed`
- `partial_success`

---

## Utilità operativa
Permette di sapere:
- ultimo progressivo importato
- ultima finestra dati caricata
- numero righe elaborate
- errore dell'ultimo run
- storico esecuzioni cliente

---

## Collegamenti consigliati
- tabella staging ETL
- job scheduler
- monitor operativo backend
- elenco articoli non classificati
