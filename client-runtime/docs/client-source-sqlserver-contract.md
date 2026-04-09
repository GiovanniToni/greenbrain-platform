# GreenBrain Client — Contratto Vista Sorgente SQL Server

## Obiettivo
Definire il contratto minimo che il DB sorgente cliente deve esporre per alimentare l'ETL GreenBrain.

## Principio
GreenBrain non modifica il DB cliente.
Legge da una vista o query read-only standardizzata.

---

## Vista sorgente attesa
Nome logico consigliato:
- `GREENHOUSE_VIEW_STAT`

Il nome reale può variare per cliente, ma deve esporre gli stessi campi logici.

---

## Campi minimi richiesti

| Campo sorgente | Tipo logico | Destinazione GreenBrain |
|---|---|---|
| `Progressivo` | bigint | `greenhouse_sales_raw.progressivo` |
| `CodArt` | varchar | `greenhouse_sales_raw.codart` |
| `DESCRIZIONE` | varchar | `greenhouse_sales_raw.descrizione` |
| `TIPO` | varchar | `greenhouse_sales_raw.tipo` |
| `FASCIA` | varchar | `greenhouse_sales_raw.fascia` |
| `CATEGORIA` | varchar | `greenhouse_sales_raw.categoria` |
| `QUANTITA` | numeric | `greenhouse_sales_raw.quantita` |
| `IMPONIBILENETTO` | numeric | `greenhouse_sales_raw.imponibilenetto` |
| `DATA` | date | `greenhouse_sales_raw.data_movimento` |
| `DISATTIVATO` | smallint/bool | `greenhouse_sales_raw.disattivato` |
| `MOVIM_CASSA` | smallint/bool | `greenhouse_sales_raw.movim_cassa` |

---

## Filtri logici minimi
L'ETL standard importerà almeno:
- `MOVIM_CASSA = 1`
- progressivo > ultimo importato, per la modalità incrementale

---

## Requisiti operativi
- accesso read-only
- stabilità della vista nel tempo
- progressivo affidabile e monotono
- data disponibile e consistente
- codart non nullo quando disponibile
- quantità e imponibile convertibili in numerico

---

## Modalità di utilizzo

### Bulk iniziale
- import storico completo

### Incrementale
- import giornaliero alle 21:00
- filtro su `Progressivo > ultimo_progressivo_importato`

---

## Adattamento per cliente
La vista reale può essere adattata dal team GreenBrain in fase di onboarding,
ma il contratto logico verso GreenBrain deve restare questo.
