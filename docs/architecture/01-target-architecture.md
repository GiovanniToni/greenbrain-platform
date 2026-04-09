# Target Architecture

## Goal
Consolidare il progetto in due blocchi chiari:

1. greenbrain-platform
   - sorgente principale sviluppata e mantenuta centralmente
   - frontend
   - backend
   - ml-worker
   - sql
   - infra
   - docs

2. greenbrain-client-runtime
   - pacchetto reinstallabile per cliente
   - db locale
   - backend locale
   - ml-worker locale
   - frontend locale
   - schedulazioni locali
   - env locali
   - procedure di update

## Runtime model
### Centrale
- sviluppo e versionamento codice
- eventuale registry/versioning rilasci
- documentazione
- strumenti di packaging

### Cliente
- ingest locale da gestionale cliente
- raw locale postgres
- ETL locale
- parquet locale o storage compatibile S3
- train locale
- predict locale
- planner locale
- frontend/backend locali

## Principle
Tutto ciò che riguarda i dati del cliente e il forecasting deve poter girare completamente in locale.