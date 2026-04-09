# GreenBrain Client — Canonical DB Schema

## Principio
Il DB GreenBrain cliente è separato dal DB sorgente cliente ed è standardizzato.

## Blocchi principali
- auth locale
- raw import
- products normalized
- fact
- dense
- forecast features
- viste / materialized views
- tabelle ops / run tracking / scheduler state
- supporto parquet / ML

## Raw layer
Tabella minima di landing:
- greenhouse_sales_raw

## Product normalization
Tabella canonica:
- greenhouse_products_normalized

## Transform layer
- greenhouse_sales_family_daily_fact
- greenhouse_sales_family_daily_dense
- greenhouse_forecast_features_dense

## Ops layer
- etl_runs
- eventuale staging raw
- export runs/state
- predict/train runs/state

## Principio di allineamento
Lo schema cliente deriva dal modello canonico GreenBrain presente in dev/master,
ridotto inizialmente al subset necessario e poi esteso fino alla copertura completa.
