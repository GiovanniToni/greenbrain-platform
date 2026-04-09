# GreenBrain Client — ETL / Classification / ML Blueprint

## Flusso completo

### 1. Source
DB cliente locale, di norma SQL Server.

Origine logica:
- vista sorgente cliente equivalente a `GREENHOUSE_VIEW_STAT`
- lettura read-only

### 2. Landing raw
Nel DB GreenBrain locale:
- `greenhouse_sales_raw`

### 3. Product normalization
Nel DB GreenBrain locale:
- `greenhouse_products_normalized`

Compilazione:
- iniziale manuale da parte di operatori GreenBrain
- manutenzione continua sui nuovi codici articolo

### 4. Canonical transforms
- raw → fact
- fact → dense
- dense → forecast features
- features → parquet

### 5. ML
Dopo export parquet:
- predict
- oppure train
- secondo schedulazione o trigger operativo

---

## Schedulazione giornaliera consigliata

### Ore 21:00
ETL incrementale:
- SQL Server sorgente → greenhouse_sales_raw

### Subito dopo
Pipeline dati:
- refresh fact
- refresh dense
- refresh features
- refresh cataloghi/MV

### Subito dopo
ML/data products:
- export parquet
- predict
- train se previsto

---

## Bulk iniziale
Alla prima installazione cliente:
1. connessione al DB sorgente
2. import storico completo in raw
3. classificazione iniziale prodotti
4. build pipeline completa
5. export parquet
6. predict/train iniziale

---

## Principi operativi
- il DB del cliente non si modifica
- GreenBrain usa un DB proprio separato
- il DB GreenBrain è standardizzato
- l'ETL sorgente è adattatore cliente-specifico
- la pipeline GreenBrain interna resta standard

