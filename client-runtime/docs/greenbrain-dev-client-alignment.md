# GreenBrain Platform — Allineamento Dev / Client

## Obiettivo
Avere due ambienti coerenti ma separati:

- **dev/master**
  - ambiente interno GreenBrain
  - collegato a Supabase
  - usato per sviluppo, test, tuning, analisi, ML, evoluzione schema

- **client-runtime**
  - ambiente locale cliente
  - senza dipendenza da Supabase
  - DB GreenBrain locale standard
  - frontend/backend/auth locali
  - ETL da DB sorgente cliente
  - pipeline locale fino a parquet + predict/train ML

---

## Stato attuale — DEV

### Cosa c'è
- schema GreenBrain già esistente e ricco
- tabelle, viste, materialized view, funzioni, pipeline analytics
- logica dense/features già funzionante
- parquet export già funzionante
- ML worker già presente
- ambiente dati storico su Supabase / dev

### Ruolo
- ambiente canonico di sviluppo
- fonte del modello dati standard GreenBrain
- riferimento per tabelle, vincoli, viste, MV, funzioni e pipeline

---

## Stato attuale — CLIENT

### Cosa c'è già validato
- postgres client locale
- backend client locale
- frontend client locale
- auth JWT locale backend
- schema minimo per dense/features/parquet
- seed demo sintetico
- export parquet locale validato
- login frontend/backend validato

### Limiti attuali
- dati demo sintetici, non dati reali cliente
- schema client ancora minimo, non ancora full canonical schema
- ETL sorgente cliente → DB GreenBrain non ancora standardizzato
- classificazione prodotti ancora da formalizzare nel flusso cliente
- predict/train ML post-parquet ancora da innestare nel flusso client

---

## Modello target — CLIENT

### 1. DB sorgente cliente
- tipicamente SQL Server locale
- contiene dati operativi del cliente
- GreenBrain legge da vista/query sorgente standardizzata
- accesso preferibilmente read-only

### 2. DB GreenBrain cliente
Database locale separato e standard GreenBrain.

Contiene:
- raw sales importate dal sorgente
- tabella classificazione articoli (`greenhouse_products_normalized`)
- tabelle fact
- tabelle dense
- tabelle forecast features
- viste / MV / funzioni / ops
- auth locale
- settings locali
- pipeline ML/parquet

### 3. ETL GreenBrain
Processo Python standard:
- bulk iniziale storico
- incrementale giornaliero
- import raw nel DB GreenBrain locale
- log esecuzioni ETL
- gestione retry
- rilevazione articoli nuovi da classificare

### 4. Classificazione articoli
- effettuata inizialmente a mano dagli operatori GreenBrain
- basata sulla sales raw storica
- output nella tabella `greenhouse_products_normalized`
- manutenzione successiva sui nuovi articoli emersi dall'incrementale

### 5. Pipeline applicativa
Sequenza logica:
1. sorgente cliente → raw
2. raw + products_normalized → fact
3. fact → dense
4. dense → features
5. features → parquet
6. parquet → predict / train ML
7. aggiornamento viste / dashboard / planner / analytics

---

## Separazione dev vs client

### DEV
- resta l'ambiente di sviluppo principale
- può usare Supabase
- può contenere dati storici di ricerca/sviluppo
- può evolvere più rapidamente

### CLIENT
- deve essere stabile
- deve essere installabile
- deve essere standard
- non deve dipendere da Supabase
- deve usare DB locale GreenBrain + sorgente cliente locale

---

## Componenti da standardizzare lato client

### Database
- schema canonico GreenBrain cliente
- tabelle raw
- tabella products_normalized
- tabelle fact/dense/features
- viste/MV/funzioni necessarie
- tabelle ops/log/scheduler state

### ETL
- config per SQL Server sorgente
- config per Postgres GreenBrain target
- modalità bulk iniziale
- modalità incrementale giornaliera
- log run
- staging/upsert
- elenco articoli non classificati

### ML pipeline
- export parquet locale
- predict post-export
- train quando richiesto / schedulato
- registry / state tracking locale

### Frontend / Backend
- auth locale già validata
- API locali già avviabili
- documentazione install/runbook/checklist già avviata

---

## Decisioni già prese

- il DB GreenBrain cliente sarà separato dal DB sorgente cliente
- il DB GreenBrain cliente sarà standard per tutti i clienti
- i dati giornalieri verranno sincronizzati dal sorgente al GreenBrain DB ogni sera alle 21:00
- il modello canonico GreenBrain cliente deriva dallo schema GreenBrain dev
- la classificazione prodotti iniziale sarà manuale da parte del team GreenBrain
- dopo i parquet partiranno predict o train ML
- client-runtime e dev/master restano separati e coerenti

---

## Gap ancora aperti

### Dati reali cliente
- definire connessione standard al DB sorgente cliente
- definire contratto minimo della vista sorgente
- definire bootstrap iniziale storico
- definire mapping completo raw → normalized/fact

### Schema cliente completo
- passare da schema minimo validato a schema canonico cliente completo
- includere tutte le parti necessarie per analytics/planner/forecast/ops

### ETL production-grade
- sostituire append semplice con pipeline più robusta
- aggiungere tabella ETL runs
- aggiungere staging / merge
- aggiungere monitoraggio articoli non classificati

### ML orchestration
- definire quando scatta predict
- definire quando scatta train
- definire dipendenze tra parquet export e job ML

---

## Ordine consigliato di implementazione

1. definizione schema canonico DB GreenBrain cliente
2. definizione contratto vista sorgente cliente
3. definizione ETL standard bulk + incrementale
4. definizione flusso classificazione prodotti
5. innesto pipeline completa raw → fact → dense → features
6. aggancio parquet → predict/train ML
7. hardening sicurezza / installazione / go-live

