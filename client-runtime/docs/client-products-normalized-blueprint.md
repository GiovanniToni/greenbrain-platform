# GreenBrain Client — Blueprint greenhouse_products_normalized

## Scopo
Tabella di classificazione manuale iniziale degli articoli del cliente.

## Ruolo
Serve a trasformare i codici articolo grezzi in una classificazione canonica GreenBrain.

---

## Fonte dati
L'elenco articoli nasce da:
- storico presente in `greenhouse_sales_raw`
- nuovi articoli emersi dall'incrementale

---

## Campi logici attesi

### Identificazione articolo
- `codart`
- `descrizione_raw`

### Classificazione canonica
- `famiglia`
- `categoria_corretta`
- `fascia_corretta`
- `fascia_prezzo_iva_inc`

### Supporto modellazione
- `tipo`
- `pot_size`
- `brand` opzionale
- `varieta` opzionale
- `colore` opzionale
- `note_classificazione`

### Stato classificazione
- `is_classified`
- `is_active`
- `classification_status`

### Audit
- `created_at`
- `updated_at`
- `classified_by`
- `classified_at`

---

## Processo operativo
1. import storico raw
2. estrazione elenco articoli unici
3. classificazione manuale da parte operatori GreenBrain
4. salvataggio nella tabella
5. pipeline fact/dense/features usa questa tabella come riferimento canonico

---

## Gestione nuovi articoli
Ogni nuovo articolo non ancora classificato deve:
- emergere in una lista di lavoro
- essere marcato come non classificato
- essere lavorato manualmente
- rientrare poi nella pipeline standard

---

## Principio
La qualità di questa tabella è centrale:
- impatta fact
- impatta dense/features
- impatta parquet
- impatta predict/train ML
