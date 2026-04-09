# GreenBrain Client Runtime — Checklist Operativa

## Infrastruttura
- [x] postgres client attivo
- [x] backend client attivo
- [x] frontend client attivo
- [x] health backend OK
- [x] health db OK

## Config
- [x] `client-runtime/env/backend.env` corretto
- [x] `client-runtime/env/frontend.env` corretto
- [x] backend punta a `postgres:5432`
- [x] frontend punta a `http://127.0.0.1:8001`

## Demo mode
- [x] schema minimo applicato
- [x] seed demo applicato
- [x] dense refresh OK
- [x] features refresh OK
- [x] mv_famiglie_catalog refresh OK
- [x] parquet locali generati

## Auth locale
- [x] tabella `greenbrain_users` accessibile
- [x] setup admin OK
- [x] login OK
- [x] `/api/v1/auth/me` OK
- [x] login frontend browser OK

## Dati reali cliente
- [ ] sorgente dati cliente identificata
- [ ] strategia import definita
- [ ] mapping tabelle definito
- [ ] procedura di bootstrap reale definita
- [ ] distinzione demo/reale documentata

## Sicurezza
- [ ] JWT secret non di default
- [ ] password admin demo sostituita in ambienti non demo
- [ ] porte esposte verificate
- [ ] backup DB definito

## Chiusura
- [x] runbook aggiornato
- [x] install guide aggiornata
- [x] checklist salvata


## Architettura target
- [x] DB sorgente cliente definito
- [x] DB GreenBrain cliente definito
- [x] contratto vista sorgente definito
- [x] schema canonico cliente definito
- [x] separazione dev/client documentata

## ETL e pipeline
- [x] ETL bulk iniziale definito
- [x] ETL incrementale serale definito
- [x] tabella ETL runs definita
- [x] staging/upsert definiti
- [x] gestione articoli non classificati definita

## Classificazione prodotti
- [x] struttura completa `greenhouse_products_normalized` definita
- [x] procedura operativa di classificazione iniziale definita
- [x] procedura manutenzione nuovi articoli definita

## ML post-parquet
- [x] trigger predict definito
- [x] trigger train definito
- [x] ordine parquet -> predict/train documentato
- [ ] stato run ML tracciato


## ETL client standard
- [x] script ETL Python standard creato
- [x] merge staging -> raw integrabile via function
- [x] sync raw -> products_normalized integrabile via function
- [ ] registrazione automatica run ETL validata end-to-end
- [ ] test con SQL Server reale cliente eseguito


## Pipeline dati cliente
- [x] funzione raw -> fact definita
- [x] refresh fact -> dense validabile
- [x] refresh dense -> features validabile
- [x] runbook serale 21:00 documentato
- [x] esecuzione end-to-end nightly validata
