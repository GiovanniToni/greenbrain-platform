# Demo Full Pipeline Validation

## Scopo
Validare il massimo possibile della pipeline cliente senza SQL Server reale.

## Validato
- refresh fact da dati già presenti nel DB locale
- refresh dense
- refresh features
- refresh catalog
- export parquet
- predict default set
- scrittura forecast
- logging ml_ops
- t_ops_pipeline_monitor

## Non validato
- estrazione ETL reale da SQL Server cliente
- caricamento raw da sorgente esterna reale
- nightly end-to-end reale cliente con sorgente cliente vera

## Conclusione
La demo full pipeline locale è validata end-to-end sul DB locale:
raw già presenti nel DB -> fact -> dense -> features -> export -> predict -> writeback.

L'end-to-end reale ETL cliente resta non validato finché non esiste una sorgente SQL Server vera.
