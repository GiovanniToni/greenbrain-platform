# GreenBrain Client Runtime — Roadmap Implementativa

## Fase 0 — già validato
- [x] postgres client locale
- [x] backend client locale
- [x] frontend client locale
- [x] auth JWT locale
- [x] schema minimo dense/features/parquet
- [x] seed demo sintetico
- [x] parquet export locale
- [x] login frontend demo

## Fase 1 — modello canonico DB cliente
- [ ] inventario schema dev da portare lato client
- [ ] definizione subset minimo obbligatorio
- [ ] definizione schema canonico cliente
- [ ] strategia migrazione/bootstrapping schema cliente

## Fase 2 — sorgente cliente
- [ ] definire contratto vista/query sorgente SQL Server
- [ ] definire campi minimi obbligatori
- [ ] definire regole di mapping raw
- [ ] definire connessione read-only standard

## Fase 3 — ETL standard
- [ ] ETL bulk iniziale storico
- [ ] ETL incrementale giornaliero ore 21:00
- [ ] tabella `etl_runs`
- [ ] staging table
- [ ] merge/upsert robusto
- [ ] gestione errori e retry
- [ ] lista articoli nuovi non classificati

## Fase 4 — classificazione articoli
- [ ] modello standard `greenhouse_products_normalized`
- [ ] procedura operativa di classificazione iniziale
- [ ] procedura gestione nuovi articoli
- [ ] campi audit operatore/classificazione

## Fase 5 — pipeline GreenBrain completa
- [ ] raw → fact
- [ ] fact → dense
- [ ] dense → features
- [ ] features → cataloghi / MV / viste
- [ ] validazione planner / analytics / dashboard

## Fase 6 — ML
- [ ] parquet export post features
- [ ] predict post parquet
- [ ] train schedulato / on-demand
- [ ] tracking run ML
- [ ] registry/state locale

## Fase 7 — hardening go-live
- [ ] JWT secret reale
- [ ] password admin non demo
- [ ] backup DB
- [ ] monitoraggio job
- [ ] install guide finale
- [ ] runbook go-live
- [ ] checklist operativa finale

