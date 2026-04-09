# GreenBrain Client — ETL Operational Runbook

## Scopo
Runbook operativo per:
- bulk iniziale storico
- incrementale giornaliero alle 21:00
- gestione staging/raw
- logging in etl_runs
- alimentazione lista articoli da classificare

## Flusso standard
1. lettura da SQL Server sorgente read-only
2. caricamento in greenhouse_sales_raw_staging
3. merge staging -> greenhouse_sales_raw
4. registrazione run in etl_runs
5. aggiornamento greenhouse_products_normalized per nuovi codart
6. classificazione manuale articoli nuovi
7. pipeline GreenBrain successiva:
   - raw -> fact
   - fact -> dense
   - dense -> features
   - features -> parquet
   - parquet -> predict/train

## Modalità supportate
- bulk_initial
- incremental_daily
- manual_repair
- backfill

## Controlli minimi
- esistenza righe in staging
- corretto merge su raw
- run etl registrata
- nuovi codart rilevati
- vista v_products_unclassified aggiornata

## Scheduling target
- ETL incrementale giornaliero: 21:00
- a seguire:
  - refresh pipeline dati
  - parquet export
  - predict o train ML
