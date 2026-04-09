# GreenBrain Client — ML Post-Parquet Flow

## Principio
Dopo la generazione dei parquet locali parte il flusso ML cliente.

## Ordine logico
1. ETL sorgente -> raw
2. raw -> fact
3. fact -> dense
4. dense -> features
5. features -> parquet
6. parquet -> predict
7. parquet -> train (se previsto)

## Modalità operative

### Predict
Da eseguire normalmente dopo l'export parquet riuscito.

### Train
Da eseguire:
- on-demand
- oppure schedulato
- oppure dopo cambi strutturali importanti del dataset

## Stato operativo da tracciare
- export parquet run
- predict run
- train run
- timestamp ultimo successo
- errore ultimo run
- path dataset/parquet usato

## Obiettivo
Avere pipeline cliente completa e auditabile:
raw -> fact -> dense -> features -> parquet -> predict/train
