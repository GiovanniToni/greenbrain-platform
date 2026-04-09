# GreenBrain Platform — Analisi Completa dello Stato del Sistema
> Generato: 2026-04-01. Basato esclusivamente su evidenze reali dal filesystem,
> process list, systemd unit files, pg_cron query, codice sorgente e documentazione interna.
> Fonte primaria: `docs/operations/00-full-system-inventory-0{1,2,3}.md` + ispezione diretta.

---

## SEZIONE 1 — SYSTEM ARCHITECTURE (REALE)

### 1.1 Repository attivi sotto /opt

| Path | Dimensione | Stato | Ruolo reale |
|------|-----------|-------|-------------|
| `/opt/greenhouse` | 18 GB | **ATTIVO — source of truth ML** | Tutti i job Python ML girano da qui via systemd |
| `/opt/greenbrain-platform` | 12 GB | **PARZIALMENTE ATTIVO** | Monorepo in costruzione; shell scripts + 1 job Python attivo |
| `/opt/greenbrain-v2` | 82 MB | **ATTIVO — backend + DB** | FastAPI + PostgreSQL 17 in Docker |
| `/opt/greenbrain` | 369 MB | **ATTIVO — frontend** | React app servita via Docker (Vite dev server) |
| `/opt/digitalocean` | 27 MB | Sistema | Agent DigitalOcean droplet |

---

### 1.2 Strati di esecuzione attivi

#### STRATO 1: Docker (gb_v2_* stack)

| Container | Porta | Sorgente montata | Note |
|-----------|-------|-----------------|------|
| `gb_v2_backend` | 8002 | `/opt/greenbrain-v2/backend` | FastAPI → Supabase |
| `gb_v2_frontend` | 8083 | `/opt/greenbrain/frontend` | React + Vite **dev server** (non produzione) |
| `gb_v2_nginx` | 8082 | `/opt/greenbrain-v2/deploy/` | Reverse proxy |
| `gb_v2_postgres` | 5433 | `/opt/greenbrain-v2/sandbox/postgres17` | PostgreSQL 17 locale (separato da Supabase) |
| `gb_v2_pgadmin` | 5050 | interno | Admin UI |
| `gb_v2_ml` | — | `/opt/greenbrain-v2/ml` | **DEAD PLACEHOLDER** — `sleep infinity` |

> Il backend Docker punta a Supabase come DB principale. Il postgres locale è usato
> solo per lo stack client-runtime in sviluppo.

#### STRATO 2: Systemd (ML jobs — host)

6 timer attivi. 5 su 6 eseguono Python da `/opt/greenhouse/repo` (NON dal monorepo):

| Timer | Orario | Python source effettivo |
|-------|--------|------------------------|
| `gh-parquet-export` | 21:35 | `/opt/greenhouse/repo/jobs/parquet_export/` |
| `gh-refresh-registry` | 00:45 | `/opt/greenbrain-platform/apps/ml-worker/` ← UNICO dal monorepo |
| `gh-train-missing` | 01:10 | `/opt/greenhouse/repo/jobs/` |
| `gh-predict-all` | 01:30 | `/opt/greenhouse/repo/jobs/` |
| `gh-train-biweekly-all` | Dom 1+15 02:00 | `/opt/greenhouse/repo/` (tutto legacy) |
| `gh-train-quarterly` | 1 Gen/Apr/Lug/Ott 02:30 | `/opt/greenhouse/repo/` (tutto legacy) |

#### STRATO 3: pg_cron (ETL + Analytics — Supabase cloud)

13 job attivi. **PROBLEMA CRITICO**: jobs `#30`, `#38`, `#39` schedulati ogni minuto
(`* * * * *`) duplicano funzioni gia schedulate con finestre orarie. A picco (10-12)
`run_greenhouse_daily_pipeline_full` viene invocato 3+ volte simultaneamente.

---

### 1.3 Flusso dati end-to-end (reale)

```
EXTERNAL INPUT
  gestionale POS   → greenhouse_sales_raw            (orario sconosciuto)
  weather API      → greenhouse_weather_daily
  stock upload     → greenhouse_stock_raw_upload

PG_CRON Supabase (~10:00-11:55 + 19:00-23:00)
  run_greenhouse_daily_pipeline_full(40, 14, 2)
    → greenhouse_sales_family_daily_fact      ETL aggregation
    → greenhouse_sales_family_daily_dense     zero-fill completo
    → greenhouse_forecast_features_dense      features ML  ← TABELLA CRITICA #1
    → etl.t_etl_runs (status=success)         GATE parquet
    → t_core_analytics__* (48+ tabelle)       analytics aggregati
    → t_dashboard_sales_* (4 tabelle)

SYSTEMD host 21:35 — gh-parquet-export
  check_etl_ready.sh → verifica etl.t_etl_runs SUCCESS
  export_features_dense.py × 17 batch
    legge: greenhouse_forecast_features_dense
    scrive: Supabase Storage ml-snapshots/features_dense/v1/year=Y/slug=S/

SYSTEMD host 00:45 — gh-refresh-registry
  REFRESH 9 ml_diag.mv_*
  refresh_registry.py → ml_forecast.family_model_registry_v1/v2

SYSTEMD host 01:10 — gh-train-missing
  train_missing_batches.py
    per ogni famiglia: train_v4_single_family_tweedie.py
      legge: parquet da Supabase Storage (fallback DB)
      scrive: DO Spaces models_v4/bundle_<slug>_v4.pkl
      scrive: ml_forecast.family_model_state_v1
      scrive: ml_ops.family_run_log_v1

SYSTEMD host 01:30 — gh-predict-all
  build_seasonal_priors.py → priors_v1.parquet → Supabase Storage
  predict_all.py
    per ogni famiglia: predict_v4_single_family_tweedie.py
      legge: parquet features + priors + model .pkl da DO Spaces
      scrive: greenhouse_forecast_results_v2   ← TABELLA CRITICA #2
      scrive: t_forecast_fam_daily
      scrive: ml_ops.family_run_log_v1

PG_CRON Supabase 01:05 + 12:00
  core_planner__nightly_roll4_reset() + core_planner__nightly_roll4_tick(2)
    legge: forecast_results_v2 + forecast_features_dense
    scrive: t_core_planner__* (7 tabelle)

DOCKER porta 8002 — gb_v2_backend (FastAPI)
  /api/v1/analytics  → t_core_analytics__* + MVs + funzioni RPC
  /api/v1/dashboard  → t_dashboard_sales_* + forecast
  /api/v1/catalog    → famiglie_catalog_static + RPC
  /api/v1/planner    → t_core_planner__*
  /api/v1/ops        → ml_ops.v_* views
  /api/v1/forecast   → greenhouse_forecast_results_v2

DOCKER porta 8083 — gb_v2_frontend (React)
  Auth: Supabase JS (supabase-js)
  Dati: apiClient.ts → VITE_API_BASE_URL=http://127.0.0.1:8002
```

---

### 1.4 Stato componenti

| Componente | Stato | Note |
|-----------|-------|------|
| ETL pipeline (pg_cron) | ATTIVO | 3 job duplicati da disabilitare |
| ML training (systemd) | ATTIVO | Da `/opt/greenhouse/repo` (legacy) |
| ML prediction (systemd) | ATTIVO | Da `/opt/greenhouse/repo` (legacy) |
| Parquet export (systemd) | ATTIVO | Path hardcoded a `/opt/greenhouse/repo` |
| FastAPI backend | ATTIVO | Da `/opt/greenbrain-v2/backend` via Docker |
| Frontend React | ATTIVO | Dev server Vite — non build produzione |
| PostgreSQL Supabase | ATTIVO | DB principale |
| PostgreSQL Docker locale | ATTIVO | Separato da Supabase, per client-runtime |
| Monorepo ML worker | PARZIALE | Solo `refresh_registry` gira dal monorepo |
| Storage abstraction | IN PROGRESS | Modulo scritto, non wired al codice running |
| client-runtime schema | IN PROGRESS | Wave 7B.1-7B.2J: ~38/58 endpoint verdi |
| gb_v2_ml container | DEAD | `sleep infinity` — placeholder vuoto |

---

## SEZIONE 2 — SOURCE OF TRUTH ANALYSIS

### 2.1 ML Runtime (Python)

| Aspetto | Source of Truth REALE | Copia | Stato |
|---------|----------------------|-------|-------|
| Python ML jobs (predict, train, data_access) | `/opt/greenhouse/repo/` | `/opt/greenbrain-platform/apps/ml-worker/` | INCOERENTE |
| Shell entry scripts | monorepo `apps/ml-worker/jobs/` | `/opt/greenhouse/repo/jobs/` | FRAGILE |
| Virtual environment | `/opt/greenhouse/venv/` | nessuna | OK |
| requirements.txt | `/opt/greenhouse/repo/requirements.txt` | 3 file nel monorepo | FRAGILE |
| Storage abstraction | `apps/ml-worker/storage/` | non esiste in legacy | NON WIRED |
| Modelli .pkl | DO Spaces `models_v4/` (master) | `/opt/greenhouse/repo/models_v4/` (cache 1886 file) | OK |
| Parquet features | Supabase Storage (master) | `/opt/greenhouse/repo/parquet_cache/` (cache 18520 file) | OK |

**Divergenze confermate:**

| File | Divergenza |
|------|-----------|
| `jobs/run_predict_all.sh` | Monorepo piu' nuovo ma contiene `cd /opt/greenhouse/repo` |
| `jobs/run_train_missing.sh` | Stesso problema |
| `jobs/parquet_export/export_features_dense.py` | Migrazione storage in progress (`.bak_phase2b`) |
| `jobs/download_priors_from_supabase.py` | Migrazione storage in progress (`.bak_phase2c`) |
| `jobs/upload_priors_to_supabase.py` | Stesso |
| `run_daily_parquet_batches.sh` | `PROJECT_DIR` hardcoded a `/opt/greenhouse/repo/jobs/parquet_export` |

---

### 2.2 CLI Scripts

Due set completi di script `gh-*`:
- Legacy `/opt/greenhouse/bin/` (19 script): usa `source /opt/greenhouse/.env`
- Monorepo `/opt/greenbrain-platform/infra/scripts/bin/` (21 script): usa `load_env.sh`

Entrambi in `$PATH`. Comportamenti divergenti confermati su almeno 3 script.
**Stato: INCOERENTE**

---

### 2.3 SQL Schema

| Aspetto | Source of Truth | Problema |
|---------|----------------|---------|
| Schema live | Supabase PostgreSQL | Nessun migration runner; SQL applicato a mano |
| File schema | `/opt/greenbrain-v2/database/current-schema.sql` | Export snapshot — non in `sql/` del monorepo |
| Migrations | `jobs/migrations/blocco_*.sql` (8 file) | In `jobs/` anziche `sql/migrations/` |
| pg_cron jobs | Solo su Supabase | Non versionati; impossibile ricreare da zero |
| DB locale Docker | `gb_v2_postgres:17` (`greenbrain` DB) | Potenzialmente disallineato da Supabase |

---

### 2.4 Backend (FastAPI)

| Aspetto | Source of Truth | Stato |
|---------|----------------|-------|
| Codice running | `/opt/greenbrain-v2/backend/` (volume Docker) | OK ma fuori monorepo |
| Codice monorepo | `/opt/greenbrain-platform/apps/backend/` | Identico, NON attivo |

I file `.py` sono identici tra i due. Modifiche al monorepo non hanno effetto
sul running finche' Docker non viene riavviato dal path corretto.

---

### 2.5 Frontend (React)

| Aspetto | Source of Truth | Stato |
|---------|----------------|-------|
| `src/` running | `/opt/greenbrain/frontend/src/` | Fuori dal monorepo |
| `src/` monorepo | `/opt/greenbrain-platform/apps/frontend/src/` | Identico ma senza `.env` — non buildabile |
| Auth | Supabase JS (`integrations/supabase/client.ts`) | NON portabile |
| Dati | `apiClient.ts` → FastAPI | Gia' portabile |
| Package manager | bun.lock + bun.lockb + package-lock.json | Conflitto 3 lock file |
| Build mode | Vite dev server (`npm run dev`) | Non e' produzione |

---

### 2.6 Systemd Units

Units attivi: `/etc/systemd/system/gh-*.service|timer` — OK
Copia monorepo: `infra/systemd/current/` (12 unit) — Sincronizzata

---

### 2.7 Environment / Config

Quattro sistemi env separati:

| Sistema | File | Usato da |
|---------|------|---------|
| Legacy | `/opt/greenhouse/.env` | `EnvironmentFile` in `gh-train-biweekly` e `gh-train-quarterly` |
| Monorepo | `infra/env/base.env` + `dev.env`/`client.env` via `load_env.sh` | 4 servizi systemd |
| Docker | `/opt/greenbrain-v2/deploy/.env` | Stack `gb_v2_*` |
| Frontend | `/opt/greenbrain/frontend/.env` | Build frontend |

Variabile critica con naming duplicato: `SUPABASE_DB_*` (solo `export_features_dense.py`)
vs `PG_*` (tutti gli altri) — crash se l'una manca nell'env dell'altro.

---

### 2.8 Storage

| Storage | Cosa contiene | Stato |
|---------|--------------|-------|
| Supabase PostgreSQL | DB principale | ATTIVO |
| Supabase Storage `ml-snapshots` | Parquet features, priors | ATTIVO |
| DO Spaces `greenbrainmodels` | Model bundles .pkl (1886+) | ATTIVO |
| Docker PostgreSQL locale | Schema client-runtime | ATTIVO (separato) |
| `/opt/greenhouse/repo/parquet_cache/` | Cache locale parquet (18520 file) | Runtime cache |
| `/opt/greenhouse/repo/models_v4/` | Cache locale modelli (1886 file) | Runtime cache |

---

## SEZIONE 3 — DATA & ML PIPELINE

### 3.1 Flusso dati: raw → ETL → features → forecast → analytics → API

```
LAYER 0 — INPUT ESTERNI
  gestionale POS       → greenhouse_sales_raw
  weather API          → greenhouse_weather_daily
  stock upload         → greenhouse_stock_raw_upload
  manuale              → greenhouse_holidays, famiglie_catalog_static

LAYER 1 — ETL (pg_cron, ~10:00)
  run_greenhouse_daily_pipeline_full(40, 14, 2)
    refresh_dense_range_from_fact()
      scrive: greenhouse_sales_family_daily_fact
              greenhouse_series_list_fact
    refresh_dense_range()
      scrive: greenhouse_sales_family_daily_dense   (zero-fill)
    refresh_forecast_features_dense_range()
      scrive: greenhouse_forecast_features_dense    *** TABELLA CRITICA #1 ***
      scrive: etl.t_etl_runs (SUCCESS)              *** GATE PARQUET ***
    refresh_core_analytics_range()
      scrive: t_core_analytics__* (48+ tabelle)
    refresh_dashboard_sales_range()
      scrive: t_dashboard_sales_* (4 tabelle)

LAYER 2 — PARQUET EXPORT (systemd 21:35, gated da ETL)
  export_features_dense.py x 17 batch
    legge: greenhouse_forecast_features_dense
    scrive: Supabase Storage ml-snapshots/features_dense/v1/

LAYER 3 — ML REGISTRY (systemd 00:45)
  refresh_registry.py
    scrive: ml_forecast.family_model_registry_v1/v2

LAYER 4 — ML TRAINING (systemd 01:10 + biweekly + quarterly)
  train_v4_single_family_tweedie.py (per ogni famiglia)
    legge: parquet da Supabase Storage (fallback DB)
    engines: croston, ets, sarima, tsb, seasonal_croston, naive_zero
    scrive: DO Spaces models_v4/bundle_<slug>_v4.pkl
    scrive: ml_forecast.family_model_state_v1

LAYER 5 — ML PREDICTION (systemd 01:30)
  predict_v4_single_family_tweedie.py (per ogni famiglia)
    legge: parquet features + priors + model .pkl da DO Spaces
    scrive: greenhouse_forecast_results_v2    *** TABELLA CRITICA #2 ***
    scrive: t_forecast_fam_daily
    scrive: ml_ops.family_run_log_v1

LAYER 6 — PLANNER (pg_cron 01:05 + 12:00)
  core_planner__nightly_roll4_tick(2)
    legge: forecast_results_v2 + forecast_features_dense
    scrive: t_core_planner__* (7 tabelle)

LAYER 7 — API + FRONTEND (continuo)
  FastAPI :8002 → React :8083
```

---

### 3.2 Tabelle critiche

| Tabella | Critica perche' | Popolata da |
|---------|----------------|-------------|
| `greenhouse_forecast_features_dense` | Input ML + analytics + planner | ETL pg_cron |
| `greenhouse_forecast_results_v2` | Output prediction → API, dashboard, planner | `predict_v4_single_family_tweedie.py` |
| `greenhouse_sales_family_daily_fact` | Base dell'intera catena ETL | `refresh_dense_range_from_fact()` |
| `famiglie_catalog_static` | Catalogo per predizioni e planner | Manuale / migration |
| `etl.t_etl_runs` | Gate per parquet export | ETL pipeline |
| `ml_forecast.family_model_registry_v2` | Routing: quale modello per quale famiglia | `refresh_registry.py` |

---

### 3.3 Dipendenze cloud esterne

| Servizio | Usato da | Sostituibile lato cliente? |
|---------|---------|--------------------------|
| Supabase PostgreSQL | Tutto (DB principale) | Si — PostgreSQL locale |
| Supabase Storage (parquet) | Parquet export + ML worker | Si — `LocalStorageBackend` gia' scritto |
| DO Spaces (model bundles) | Train/predict | Si — `LocalStorageBackend` o S3 compatibile |
| Supabase Auth | Frontend login | No — da sostituire con FastAPI JWT |
| pg_cron Supabase | ETL + planner scheduling | No — serve cron esterno o pgAgent |

---

### 3.4 Cosa manca per pipeline riproducibile lato cliente

1. **ETL SQL**: `run_greenhouse_daily_pipeline_full()` e tutte le funzioni ETL non
   sono nel client-runtime schema. Il DB cliente non si popola mai da raw data.
2. **Scheduler locale**: systemd units hardcoded a `/opt/greenhouse/`. Non funzionano
   su server cliente senza modifica.
3. **Storage abstraction non wired**: `storage/backend.py` e' scritto ma i 4 file
   che devono usarlo (`data_access_v1.py`, `export_features_dense.py`, priors scripts)
   usano ancora Supabase Storage hardcoded.
4. **Import dati esterno**: meccanismo import dal gestionale POS non documentato
   nel monorepo.

---

## SEZIONE 4 — RUNTIME CLIENT-LOCAL

### 4.1 Database

| Voce | Stato | Difficolta' | Note |
|------|-------|------------|------|
| PostgreSQL 17 container | READY | Bassa | Docker image disponibile |
| Schema bootstrap | READY | Bassa | `01_bootstrap.sql` funzionante |
| Schema Wave 7B.1-7B.2J | READY | Bassa | 12 init file applicati |
| ~38/58 endpoint HTTP 200 | PARZIALE | — | Wave fino a 7B.2J |
| ETL functions SQL | MANCANTE | Alta | 8+ funzioni plpgsql + schema `etl` |
| pg_cron equivalente | MANCANTE | Alta | Supabase pg_cron → cron esterno |
| Planner functions | MANCANTE | Alta | 10+ funzioni `core_planner__*` |
| `ml_diag` schema + MVs | MANCANTE | Media | 9 matviews diagnostiche |
| `ml_forecast` schema | MANCANTE | Alta | Registry, routing views |
| `etl` schema | MANCANTE | Media | `t_etl_runs`, `t_etl_steps` |
| Seed `famiglie_catalog_static` | MANCANTE | Bassa | File SQL seed non incluso |
| Migration runner | MANCANTE | Media | Nessun Alembic/Flyway |

---

### 4.2 Backend

| Voce | Stato | Difficolta' | Note |
|------|-------|------------|------|
| FastAPI app source (`apps/backend/`) | READY | Bassa | 100% runtime-portable (POSTGRES_* env vars) |
| env template (`backend.env.template`) | READY | Bassa | In `client-runtime/env/` |
| docker-compose local stack | READY | Bassa | `client-runtime/docker/docker-compose.yml` |
| Dockerfile produzione | MANCANTE | Bassa | Solo bozza in `apps/backend/` |
| ~20 endpoint ancora HTTP 500 | MANCANTE | Media-Alta | entity-summary, kpis, planner, ops |

---

### 4.3 Frontend

| Voce | Stato | Difficolta' | Note |
|------|-------|------------|------|
| `src/` portabile (data hooks via `apiClient.ts`) | READY | Bassa | Tutti i data hook gia' via FastAPI |
| Auth Supabase (`integrations/supabase/`) | BLOCCA | Alta | Sostituzione completa con FastAPI JWT |
| `useGardenCenterSettings` hook | NON PORTABILE | Media | Usa `supabase.from()` direttamente |
| Build produzione (`npm run build`) | MANCANTE | Bassa | Dev server attuale |
| Dockerfile produzione | MANCANTE | Bassa | Non scritto |

Il frontend e' il componente piu' bloccante: senza sostituzione auth Supabase
non puo' funzionare presso un cliente.

---

### 4.4 ML (Training + Inference)

| Voce | Stato | Difficolta' | Note |
|------|-------|------------|------|
| Training code | NON PORTABILE | Alta | Hardcoded `/opt/greenhouse/` + Supabase Storage |
| Inference code | NON PORTABILE | Alta | Hardcoded paths + DO Spaces |
| Storage abstraction | IN PROGRESS | Media | Modulo scritto, non wired |
| `data_access_v1.py` migrazione | IN PROGRESS | Media | `.bak_phase2b` presente |
| Virtual environment | NON PORTABILE | Media | Tied a `/opt/greenhouse/venv/` |
| `requirements.txt` canonico | MANCANTE | Bassa | 4 file concorrenti |

---

### 4.5 Scheduler

| Voce | Stato | Difficolta' | Note |
|------|-------|------------|------|
| ETL automation | MANCANTE | Alta | pg_cron → cron locale |
| ML job automation | MANCANTE | Alta | Systemd units hardcoded a `/opt/greenhouse/` |
| Systemd unit templates portabili | MANCANTE | Media | Units non parametrizzabili |

---

## SEZIONE 5 — GAP ANALYSIS (CRITICA)

### 5.1 Dev-Cloud

| Gap | Classificazione | Dettaglio |
|-----|----------------|-----------|
| 3 pg_cron jobs ogni minuto (#30, #38, #39) | CRITICAL | ETL invocato 3+ volte/minuto a picco |
| 2 set CLI scripts in PATH comportamento diverso | CRITICAL | Operatore non sa quale script viene eseguito |
| Credenziali live in source tree | CRITICAL | Password DB + JWT + DO Spaces key in chiaro in repo |
| `gh-audit` fallisce su `ml_monitor_db.py` mancante | CRITICAL | Tool operativo rotto su ogni run |
| Frontend gira Vite dev server in produzione | CRITICAL | Non e' un server produzione |
| ML Python (5/6 job) gira da legacy repo | HIGH | Edit al monorepo non hanno effetto sui job running |
| 2 env systems paralleli | HIGH | 2 servizi ancora su `/opt/greenhouse/.env` |
| `run_daily_parquet_batches.sh` hardcoded legacy path | HIGH | Migrazione storage invisibile al job running |
| `export_features_dense.py` usa `SUPABASE_DB_*` | HIGH | Crash se variabili mancano in env pulito |
| Storage abstraction non wired (4 file) | HIGH | Blocca progressione verso client-local |
| SQL schema non versionato nel monorepo | HIGH | Impossibile ricreare DB da zero |
| Migration runner assente | MEDIUM | SQL applicato a mano, nessuna history |
| pg_cron non versionato | MEDIUM | Impossibile ricreare scheduling da zero |
| `useGardenCenterSettings` ancora su Supabase SDK | MEDIUM | Unica anomalia nel data plane del frontend |
| Build produzione frontend mancante | MEDIUM | Dev server non appropriato |
| `gb_v2_ml` container morto | MEDIUM | Placeholder `sleep infinity` nel docker-compose |

---

### 5.2 Client-Local

| Gap | Classificazione | Dettaglio |
|-----|----------------|-----------|
| Auth frontend (Supabase JS) non sostituita | CRITICAL | Blocca completamente il login |
| ETL SQL functions non portate nel client-runtime | CRITICAL | Senza ETL il DB non si popola mai |
| ML pipeline non portabile | CRITICAL | Training e inference impossibili su server cliente |
| Scheduler non portabile | CRITICAL | Automazione pipeline impossibile |
| ~20 endpoint API ancora HTTP 500 | HIGH | entity-summary, kpis, planner, ops, breakdown |
| Storage abstraction non wired | HIGH | ML su client impossibile senza LocalBackend |
| Seed data non inclusi | HIGH | DB parte completamente vuoto |
| Dockerfile produzione backend mancante | HIGH | Nessuna build image per il cliente |
| Dockerfile produzione frontend mancante | HIGH | Stesso |
| `requirements.txt` ML non canonico | MEDIUM | Environment ML non riproducibile |
| Migration runner non esiste | MEDIUM | Schema aggiornamenti futuri non gestibili |
| `ml_forecast` schema non portato | MEDIUM | Routing modelli assente |
| `etl` schema non portato | MEDIUM | Gate parquet export non funziona |
| Installer (`install.sh`) non esiste | MEDIUM | Installazione cliente interamente manuale |
| Planner functions non portate | LOW | Funzionalita' planner assente |
| `ml_ops` schema non portato | LOW | Monitoring ML assente |

---

### 5.3 Riepilogo per componente

| Componente | Dev-Cloud | Client-Local |
|-----------|-----------|-------------|
| ETL pipeline | Funziona, 3 duplicati critici | Non esiste |
| ML training | Funziona, da legacy repo | Non portabile |
| ML inference | Funziona, da legacy repo | Non portabile |
| Backend FastAPI | Funziona, schema parziale | Portabile, schema incompleto |
| Frontend | Dev server, auth da rifare | Blocco auth |
| Database schema | Supabase master, no migration | Parziale (38/58 endpoint) |
| Scheduler | Funziona con duplicati | Non portabile |
| Storage | Supabase+DO funziona | LocalBackend non wired |
| CLI operativo | 2 set ambigui in PATH | N/A |

---

## SEZIONE 6 — EXECUTION ROADMAP (OPERATIVA)

### FASE 1 — Stabilizzazione produzione (1 settimana)
**Obiettivo**: eliminare rischi attivi. Nessuna dipendenza reciproca — eseguibili in parallelo.

| # | Task | Rischio se rimandato |
|---|------|---------------------|
| 1.1 | Disabilita pg_cron jobs 30, 38, 39 | ETL multi-invocato, carico DB |
| 1.2 | Elimina file con credenziali + ruota chiave JWT + DO Spaces secret | Security breach |
| 1.3 | Rimuovi `/opt/greenhouse/bin/` dal PATH | Operatore invoca script sbagliato |
| 1.4 | Risolvi `gh-audit` ml_monitor_db (rimuovi check o crea stub) | Tool rotto su ogni run |
| 1.5 | Sostituisci Vite dev server con `npm run build` + nginx | Frontend instabile |

```sql
-- 1.1: da eseguire su Supabase
SELECT cron.unschedule(30);
SELECT cron.unschedule(38);
SELECT cron.unschedule(39);
```

---

### FASE 2 — Consolidamento monorepo ML (2-3 settimane)
**Obiettivo**: monorepo diventa unico source of truth per il codice Python ML.

| # | Task | Dipende da |
|---|------|-----------|
| 2.1 | Wiring storage abstraction in 4 file (data_access, export_features, priors upload/download) | — |
| 2.2 | Unifica variabili DB (`SUPABASE_DB_*` → `PG_*` in export_features_dense.py) | Parte di 2.1 |
| 2.3 | Fix `run_daily_parquet_batches.sh`: usa `GH_REPO_DIR` invece di path hardcoded | 2.1 |
| 2.4 | Fix `run_predict_all.sh` e `run_train_missing.sh`: rimuovi `cd /opt/greenhouse/repo` | — |
| 2.5 | Fix `gh-train-biweekly` e `gh-train-quarterly`: usa `load_env.sh` | — |
| 2.6 | Crea venv nel monorepo (o symlink controllato) | 2.1–2.5 |
| 2.7 | Consolida requirements.txt in file canonico unico | — |
| 2.8 | Rimuovi tutti i `.bak_*` (17 file) + cleanup `__pycache__` | 2.1–2.5 |

---

### FASE 3 — Config unificata + SQL versionato (1-2 settimane)
**Obiettivo**: unico sistema di configurazione, schema versionato, pg_cron riproducibile.

| # | Task | Dipende da |
|---|------|-----------|
| 3.1 | Popola `sql/` nel monorepo: copia `current-schema.sql`, sposta 8 migration da `jobs/migrations/` a `sql/migrations/` | Fase 2 |
| 3.2 | Scrivi `sql/cron/pg_cron_canonical.sql` con i 10 job corretti (senza 30/38/39) | 3.1 |
| 3.3 | Unifica env system: elimina tutte le referenze a `/opt/greenhouse/.env`; `load_env.sh` unico | Fase 2 |
| 3.4 | Scrivi `sql/seed/famiglie_catalog_seed.sql` | 3.1 |
| 3.5 | Verifica e documenta il volume Docker frontend (discrepanza mount confermata) | — |

---

### FASE 4 — Pipeline riproducibile per client-local (3-4 settimane)
**Obiettivo**: ETL + ML funzionanti su server cliente.

| # | Task | Dipende da |
|---|------|-----------|
| 4.1 | Porta ETL SQL functions nel client-runtime schema | Fase 3 |
| 4.2 | Porta `etl` schema (`t_etl_runs`, `t_etl_steps`) | 4.1 |
| 4.3 | Implementa scheduler cliente: wrapper cron + bash (sostituisce pg_cron) | 4.1 + 4.2 |
| 4.4 | Crea systemd unit templates parametrizzabili per train/predict/parquet | Fase 2 + 4.3 |
| 4.5 | Porta `ml_forecast` schema (registry, routing views) | Fase 3 |
| 4.6 | Porta `ml_ops` schema (run log, views) | 4.5 |
| 4.7 | Porta planner functions (`core_planner__*`) | Fase 3 |
| 4.8 | Test pipeline ML end-to-end con LocalStorageBackend su server pulito | 2.1 + 4.5 |

---

### FASE 5 — Client runtime installabile (2-3 settimane)
**Obiettivo**: pacchetto completo installabile, frontend senza Supabase.

| # | Task | Dipende da |
|---|------|-----------|
| 5.1 | Sostituisci Supabase auth con FastAPI JWT (login + me endpoint) | Tutte le fasi |
| 5.2 | Porta `useGardenCenterSettings` da `supabase.from()` a FastAPI | 5.1 |
| 5.3 | Scrivi Dockerfile produzione backend | — |
| 5.4 | Scrivi Dockerfile produzione frontend (build + nginx) | 5.1 |
| 5.5 | Scrivi `client-runtime/packaging/install.sh` completo | Tutto sopra |
| 5.6 | Scrivi migration runner (script SQL ordinato o Alembic minimal) | 4.1–4.7 |
| 5.7 | Test end-to-end su macchina pulita | Tutto sopra |
| 5.8 | Completa `docs/client-runtime/install-guide.md` | 5.7 |

---

### Diagramma dipendenze

```
FASE 1 (nessuna dipendenza — eseguibile subito)
  |
  +-> FASE 2 (consolidamento ML monorepo)
        |
        +-> FASE 3 (config + SQL versioning)
              |
              +-> FASE 4 (ETL + scheduler + ML portabili)
              |     |
              |     +-> FASE 5 (auth + Dockerfiles + installer)
              |
              +-> FASE 5 (solo Dockerfiles, indipendente da FASE 4)
```

### Timeline stimata

| Fase | Durata | Effort |
|------|--------|--------|
| 1 — Stabilizzazione | 1 settimana | DevOps / quick fixes |
| 2 — ML monorepo | 2-3 settimane | Python / storage wiring |
| 3 — Config + SQL | 1-2 settimane | SQL / config |
| 4 — Pipeline riproducibile | 3-4 settimane | SQL porting + ETL + scheduler |
| 5 — Client installabile | 2-3 settimane | Auth frontend + packaging |
| **Totale** | **9-13 settimane** | |

---

## APPENDICE — Riferimenti operativi

### Storage backends disponibili (non ancora wired)

```
apps/ml-worker/storage/
  backend.py           <- factory: STORAGE_BACKEND=supabase|local|s3
  local_backend.py     <- LocalStorageBackend: legge/scrive da LOCAL_STORAGE_ROOT
  s3_backend.py        <- S3StorageBackend: compatibile MinIO/S3
  supabase_backend.py  <- SupabaseStorageBackend (produzione attuale)
```

Wiring richiesto in: `data_access_v1.py`, `export_features_dense.py`,
`upload_priors_to_supabase.py`, `download_priors_from_supabase.py`.

### Endpoint client-runtime: stato corrente

- ~38/58 endpoint HTTP 200 (dopo Wave 7B.1–7B.2J)
- Ancora HTTP 500: `entity-summary`, `compare-series`, `series-breakdown`,
  `future-windows-stats`, `kpis`, `planner/*`, `ops/*`

### File con credenziali da rimuovere subito

```
/opt/greenhouse/repo/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json
/opt/greenbrain-platform/apps/ml-worker/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json
/opt/greenbrain-platform/docs/operations/env-live.txt
```

Contengono in chiaro: password Supabase DB, JWT service role key, DO Spaces secret.
