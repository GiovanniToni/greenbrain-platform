# GreenBrain Client — Nightly 21:00 Runbook

## Scopo
Runbook operativo serale standard del client-runtime.

## Ordine di esecuzione alle 21:00
1. ETL SQL Server -> staging
2. merge staging -> raw
3. sync raw -> greenhouse_products_normalized
4. classificazione nuovi articoli se presenti
5. refresh raw -> fact
6. refresh fact -> dense
7. refresh dense -> features
8. refresh cataloghi / MV
9. export parquet
10. predict
11. train se previsto

## Sequenza tecnica

### Step 1
Lanciare:
- `client-runtime/etl/greenbrain_client_etl.py`

### Step 2
Verificare articoli non classificati:
- `public.v_products_unclassified`

### Step 3
Dopo classificazione articoli:
- `select public.refresh_fact_from_raw(...)`
- `select public.refresh_dense_range_from_fact(...)`
- `select public.refresh_forecast_features_dense_range(...)`
- `refresh materialized view public.mv_famiglie_catalog`

### Step 4
Export parquet:
- `jobs/parquet_export/export_features_dense.py`

### Step 5
ML:
- predict normalmente dopo parquet riuscito
- train solo se previsto o richiesto

## Principio
La pipeline cliente completa è:

SQL Server source
-> greenhouse_sales_raw_staging
-> greenhouse_sales_raw
-> greenhouse_products_normalized
-> greenhouse_sales_family_daily_fact
-> greenhouse_sales_family_daily_dense
-> greenhouse_forecast_features_dense
-> parquet
-> predict/train
