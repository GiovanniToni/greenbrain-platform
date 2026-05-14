# GreenBrain Customer-Local — Analisi Plug & Play
_Generata: 2026-05-09 — Bundle corrente: 0.1.24 — Branch: `feat/customer-ops-supabase-foundation`_

---

## 1. Architettura attuale reale

### 1.1 Dual environment


```
CLOUD (www.greenbrain.it)
  ├── React SPA (Vite, TailwindCSS, shadcn/ui)
  ├── FastAPI (Supabase Postgres via psycopg)
  ├── Supabase Postgres (tabelle operative, auth, ops, cloud-sync)
  ├── Portal cliente (CustomerPortalDashboard: onboarding, download, billing)
  └── Tunnel heartbeat receiver, provisioning token manager

CUSTOMER-LOCAL (<tenant>.greenbrain.it)
  ├── Docker: postgres:16-alpine  (55450:5432)
  ├── Docker: backend FastAPI      (LOCAL_BACKEND_PORT:8000)
  ├── Docker: nginx frontend       (LOCAL_FRONTEND_PORT:80)
  ├── Docker: cloudflared tunnel   (compose separato)
  ├── HOST: Python venv + ml-worker (NON containerizzato)
  ├── HOST: systemd timer units    (gh-daily-pipeline, gh-parquet-export, ...)
  └── HOST: ETL script SQL Server → Postgres locale
```

### 1.2 Flusso di delivery bundle (cloud → cliente)

```
OPS admin crea token di provisioning (cloud API)
  → Cloud genera bundle personalizzato (personalized tar.gz):
      • overlay/env/customer-local.env  ← tenant params + credenziali
      • overlay/provisioning/local-runtime.env  ← PROVISIONING_TOKEN, INSTALLATION_ID
      • JWT_SECRET iniettato
  → Cliente scarica tar.gz dal CustomerPortalDashboard (/api/v1/customer-portal/download-bundle)
  → Cliente estrae e avvia (manualmente)
```

### 1.3 Flusso auth SSO (cloud → locale)

```
1. Cliente: www.greenbrain.it/login (email+password)
2. Cloud: POST /api/v1/auth/sso/start
   ├── Verifica credenziali nel DB cloud
   ├── Legge home_host = "<tenant>.greenbrain.it"
   ├── Emette JWT ticket (2 min, aud=<tenant-host>)
   └── Restituisce redirect_url
3. Browser: redirect a https://<tenant>.greenbrain.it/login?sso=<ticket>
4. Locale: Login.tsx rileva ?sso param, POST /api/v1/auth/sso/exchange
5. Locale: verifica ticket (JWT_SECRET condiviso), emette token locale
6. Browser: GET /api/v1/auth/me (locale) → home_path=/dashboard
7. Browser: navigate("/dashboard") → CustomerRoute → Dashboard locale
```

### 1.4 Routing frontend (stato 0.1.24)

```
App.tsx
  /                    Landing          (public)
  /login               Login            (public)
  /pricing             PricingPage      (public)
  /signup              Signup           (public)

  ProtectedRoute (autenticato)
    AppLayout
      /account         CustomerPortalDashboard  ← tutti gli autenticati
      portal/          redirect → /account

      AdminRoute       (is_admin === true SOLTANTO)
        /ops           CustomerOpsConsolePage
        /dashboard     Dashboard
        /dashboard/reorders  Reorders
        /analytics     Analytics
        /assortment-planner  AssortmentPlanner
        /suppliers     Suppliers
        /customers     Customers
        /customers/:id CustomerDetail
```

**⚠ PROBLEMA P0**: `customer_admin` (`is_admin=false`) non può accedere a `/dashboard`.  
`AdminRoute` usa solo `is_admin` boolean; `user_role` è nel DB ma ignorato dal frontend.

### 1.5 Backend locale (bundle 0.1.24) — routers inclusi

```python
# deploy/customer-local-template/base/backend-src/app/main.py
app.include_router(health_router)        # /health
app.include_router(auth_router)          # /api/v1/auth (login, sso/*, me, setup)
app.include_router(settings_router)      # /api/v1/settings
app.include_router(system_router)        # /api/v1/system
app.include_router(catalog_router)       # /api/v1/catalog
app.include_router(forecast_router)      # /api/v1/forecast
app.include_router(sales_router)         # /api/v1/sales
app.include_router(analytics_router)     # /api/v1/analytics
app.include_router(planner_router)       # /api/v1/planner
app.include_router(ops_router)           # /api/v1/ops
app.include_router(dashboard_router)     # /api/v1/dashboard

# customer_provisioning_router: FILE presente nel bundle ma NON incluso ✓
# cloud-only (customer_ops, delivery, portal, billing, cloud_sync): ASSENTI ✓
```

Il `main.py` locale è pulito. Il file `customer_provisioning.py` esiste nel bundle ma non è montato.

### 1.6 Pipeline ML (stato 0.1.24)

```
HOST LINUX (fuori Docker)
  ├── systemd timers (base/infra/systemd/)
  │     gh-daily-pipeline.timer    → 21:05 (ETL raw→features SQL stored proc)
  │     gh-parquet-export.timer    → (export features_dense parquet)
  │     gh-predict-all.timer       → (previsioni giornaliere)
  │     gh-train-missing.timer     → (training modelli mancanti)
  │     gh-train-biweekly-all.timer→ (training bisettimanale)
  │     gh-train-quarterly.timer   → (training trimestrale)
  ├── bin scripts (base/infra/scripts/bin/) → wrapped in systemd units
  └── ml-worker Python (base/apps/ml-worker/) → richiede venv sull'host

  client-runtime/etl/ → ETL SQL Server → Postgres locale
     .env (credenziali SQL Server)
     greenbrain_client_etl.py
     run_etl_runtime.sh
```

**⚠ CRITICO**: ML pipeline NON è containerizzata. Non c'è un servizio `ml-worker` nel `docker-compose.local.yml`. Richiede:
- Python 3.x installato sull'host
- `python -m venv .venv && pip install -r requirements.txt` manuale
- systemd (Linux only, non funziona su Windows/macOS)

---

## 2. Cosa è già pronto ✅

| Componente | Stato | Note |
|---|---|---|
| Bundle structure (template/base/overlay) | ✅ STABILE | overlay-manifest.yml protegge i segreti durante gli aggiornamenti |
| Backend locale `main.py` pulito | ✅ CORRETTO | Solo router operativi, nessun router cloud-only incluso |
| DB schema locale 24 SQL init waves | ✅ IDEMPOTENTE | Eseguito da Docker Postgres entrypoint automaticamente |
| Auth SSO cloud→locale | ✅ FUNZIONANTE | JWT_SECRET condiviso, ticket 2 min, sso/exchange sul locale |
| Auth locale `/me` arricchito | ✅ MIGLIORATO | `platform_enabled`, `runtime_health`, `user_role`, `require_internal_admin`/`require_platform_access` |
| Release pipeline | ✅ AUTOMATICA | `promote_dev_to_customer_template.sh` + `build_customer_local_release.sh` |
| Versioning 0.1.24 | ✅ COERENTE | VERSION=0.1.24, manifest=0.1.24 (fixed da 0.1.18) |
| `update_customer_local_from_bundle.sh` | ✅ ROBUSTO | Backup, rsync base, preserve overlay, restart, health check |
| Dockerfile backend | ✅ PRODUCTION | Non-root user, healthcheck, multi-layer build |
| Cloudflare tunnel docker-compose | ✅ SEPARATO | `base/tunnel/docker-compose.tunnel.yml` autonomo |
| Runtime heartbeat endpoint (cloud) | ✅ OPERATIVO | `/api/v1/customer-runtime/heartbeat` riceve da `cliente_reale` |
| Provisioning token system (cloud) | ✅ IMPLEMENTATO | Crea/revoca/verifica token `gbp_*`, 14 giorni default |
| `overlay-manifest.yml` + `base-manifest.yml` | ✅ DOCUMENTATO | Definiscono cosa preservare e cosa gestisce il template |
| `customer_provisioning.py` in bundle | ✅ SAFE | File presente ma non incluso in `main.py` locale |
| Docker postgres init SQL | ✅ AUTOMATICO | 24 file SQL caricati da `/docker-entrypoint-initdb.d/` |
| ML-worker code nel bundle | ✅ PRESENTE | `base/apps/ml-worker/` completo con jobs, engines, parquet_export |
| Scheduler systemd nel bundle | ✅ PRESENTE | `base/infra/systemd/` con 7 timer+service |
| Ops monitoring views | ✅ PRESENTI | `v_ops_daily_sequence_health_latest`, etc. in SQL init |

---

## 3. Cosa è fragile ⚠️

### 3.1 PATHS ASSOLUTI DEV HARDCODED — P0 ML pipeline

**Tutti** gli script ML nel bundle referenziano `/opt/greenbrain-platform/` come path assoluto. Su macchina cliente questo path non esiste.

File colpiti:
```
base/apps/ml-worker/run_nightly_runtime.sh
  cd /opt/greenbrain-platform/apps/ml-worker      ← HARDCODED DEV PATH
  source .venv/bin/activate                        ← venv non esiste sul cliente
  source ../../client-runtime/etl/.env.ml.runtime ← path dev relativo

base/apps/ml-worker/run_predict_all_runtime.sh    ← stesso problema
base/apps/ml-worker/run_export_runtime.sh         ← stesso problema
base/infra/scripts/bin/gh-*  (tutti i 14 script)
  cd /opt/greenbrain-platform/apps/ml-worker
  source /opt/greenbrain-platform/apps/ml-worker/.venv/bin/activate

base/infra/systemd/*.service
  WorkingDirectory=/opt/greenbrain-platform        ← DEV PATH
  Environment=APP_ENV=dev                          ← SBAGLIATO per cliente
  source /opt/greenbrain-platform/infra/scripts/load_env.sh ← DEV PATH

base/infra/scripts/load_env.sh
  BASE="/opt/greenbrain-platform/infra/env"        ← DEV PATH hardcoded
  
base/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh
  source /opt/greenbrain-platform/infra/scripts/load_env.sh ← DEV PATH
  LOG_DIR="/opt/greenbrain-platform/runtime-reports/parquet_export"
```

### 3.2 Volume mount relativo backend — P1

Nel `docker-compose.local.yml`:
```yaml
backend:
  volumes:
    - ../../releases/customer-local:/opt/greenbrain-platform/releases/customer-local:ro
```
Questo assume che l'istanza sia in `deploy/customer-local-instances/<slug>/`.
Su macchina cliente il path `../../releases/customer-local` relativo all'install dir non ha senso.
Il bundle download è un tar.gz estratto in una cartella arbitraria.

### 3.3 Frontend `AdminRoute` blocca `customer_admin` — P0

`ProtectedRoute.tsx`: `AdminRoute` richiede `user.is_admin === true`.  
`customer_admin` ha `is_admin=false` → redirect a `/account`.  
`user_role` è presente nel DB e in `/me` response ma non viene letto dal frontend.

### 3.4 Variabili d'ambiente ML non nel overlay system — P1

Il ML-worker richiede:
- `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD` per il Postgres locale
- `STORAGE_BACKEND`, `LOCAL_STORAGE_ROOT`, `PARQUET_CACHE_DIR` per i modelli
- `SQLSERVER_*` per il DB sorgente cliente

Questi si trovano in `client-runtime/etl/.env.ml.runtime` e `client-runtime/etl/.env` sul server dev, ma **non hanno un equivalente nel bundle overlay**.

### 3.5 File uncommitted nel dev repo — P2

9 file modificati o untracked non committati:
- `apps/backend/app/main.py` — aggiunge `customer_runtime_router` + `allow_origin_regex`
- `apps/frontend/src/lib/apiClient.ts` — refactor RUNTIME_API_PREFIXES, memoryToken
- `apps/frontend/src/lib/customerPortalApi.ts` — setta runtimeBaseUrl automaticamente
- `apps/frontend/src/pages/Login.tsx` — SSO flow
- `apps/backend/app/services/customer_portal_service.py` — modifiche
- `apps/backend/app/repositories/customer_portal_repository.py` — modifiche
- `apps/backend/app/services/customer_delivery_service.py` — modifiche
- `apps/backend/app/services/customer_runtime_service.py` — UNTRACKED (nuovo)
- `apps/backend/app/repositories/customer_runtime_repository.py` — UNTRACKED (nuovo)

**Il bundle 0.1.24 è stato costruito PRIMA di queste modifiche.** La build 0.1.24 è al commit `16919ae` — divergenza.

### 3.6 DB cloud — riga spuria `greenbrain_runtime_connections`

```
tenant_code='2' | runtime_health=healthy | installation_id=11ef6c95-...
```
Residuo di quando `2@gmail.com` aveva `tenant_code='2'`. Da eliminare.

### 3.7 `customer_provisioning_repository.py` usa Supabase sul locale — P2

Il file `base/backend-src/app/repositories/customer_provisioning_repository.py` chiama `get_supabase_client()`. Sul runtime locale le variabili `SUPABASE_URL` / `SUPABASE_KEY` non sono configurate → il modulo fallisce se importato. Non è incluso in `main.py` locale ma viene comunque importato indirettamente da `customer_provisioning_service.py` al caricamento del modulo.

---

## 4. Cosa manca per plug & play ❌

### 4.1 Installer per il cliente — ASSENTE

In 0.1.24: **`install.sh` è vuoto** (exit 2, nessun output). Il cliente non ha un entry point.

Il flusso attuale richiede all'operatore:
1. Estrarre tar.gz manualmente
2. Copiare e compilare `env/customer-local.env.example`
3. Copiare e configurare `overlay/tunnel/cloudflared/config.yml` e `cloudflared.env`
4. Eseguire `docker compose up -d`
5. Installare Python + venv + pip
6. Configurare systemd manualmente

Nessuno di questi passi è guidato o verificato automaticamente.

### 4.2 `provision-local.sh` — ASSENTE da 0.1.24

In 0.1.18 era presente. Generava `INSTALLATION_ID`, configurava `overlay/provisioning/local-runtime.env`, copiava valori da `customer-local.env`. In 0.1.24 **mancante completamente**.

### 4.3 `doctor-local.sh` / `runtime-status.sh` — ASSENTI da 0.1.24

In 0.1.18 erano presenti. In 0.1.24 i soli script in `base/scripts/` sono:
```
start-local.sh     (6 righe: docker compose up -d)
stop-local.sh      (6 righe: docker compose down)
pre-update-backup.sh
post-update-check.sh
tunnel-*.sh
```
Nessun doctor, nessun health check per il cliente.

### 4.4 `runtime-heartbeat.sh` — ASSENTE da 0.1.24

Il cloud riceve heartbeat da `cliente_reale` (ultimo: 2026-05-08 22:37). Ma non c'è lo script nel bundle che lo invia. Il meccanismo funziona solo perché sul server dev esiste un cron/timer separato.

### 4.5 ML-worker NON containerizzato — GAP CRITICO

Il `docker-compose.local.yml` ha solo: `postgres`, `backend`, `frontend`.  
**Nessun container per ml-worker.** La pipeline ML richiede:
- Python 3.x sull'host
- `python -m venv .venv && pip install -r requirements.txt`
- systemd funzionante (Linux only)
- Utente `gh` con `GROUP=gh` (come nei service units)
- Variabili d'ambiente configurate in `/opt/greenbrain-platform/infra/env/`

Questo è **incompatibile con Windows e macOS** e con qualsiasi cliente che non abbia Linux gestito.

### 4.6 Configurazione SQL Server — NESSUNA GUIDA

Il bundle non include:
- File `overlay/config/source-db.env` o equivalente
- Script per testare la connessione SQL Server
- Documentazione del contratto schema SQL Server (`client-source-sqlserver-contract.md` esiste nel dev ma non nel bundle)

Il cliente deve sapere hostname, porta, database, credenziali del proprio SQL Server **prima** dell'installazione e devo inserirli a mano in file di testo.

### 4.7 Tunnel Cloudflare — CONFIGURAZIONE COMPLETAMENTE MANUALE

Per configurare il tunnel il cliente deve:
1. Avere un account Cloudflare
2. Creare un tunnel via Cloudflare Dashboard
3. Ottenere il `TUNNEL_ID` (UUID)
4. Scaricare il file `<TUNNEL_ID>.json` (credentials)
5. Copiarlo in `overlay/tunnel/cloudflared/`
6. Compilare `config.yml` con il dominio e l'UUID
7. Compilare `cloudflared.env`

Nessun passaggio è automatizzato. Non c'è documentazione cliente-friendly nel bundle.

### 4.8 PROVISIONING_TOKEN nel bundle generato — SPEZZATO

Il `_build_personalized_bundle()` in `customer_delivery_service.py` inietta il token in `overlay/provisioning/local-runtime.env`. Ma in 0.1.24 **`overlay/provisioning/` non esiste più** nel bundle — la struttura è cambiata.

Il token viene ancora creato lato cloud ma **non arriva nel bundle** che il cliente scarica. Il `register_runtime` richiede il token come `Authorization: Bearer <token>` ma il cliente non ha modo automatico di eseguire il POST di registrazione.

### 4.9 `update.sh` lato cliente — ASSENTE

Non esiste uno script cliente per aggiornare il runtime alla versione successiva. Il `update_customer_local_from_bundle.sh` è un tool operator-side che richiede accesso al server cloud e al server locale.

### 4.10 Windows/macOS support — STUB

`install.ps1`, `start.ps1`, `stop.ps1` sono stub vuoti o assenti nel bundle 0.1.24. Il runtime è di fatto solo Linux.

### 4.11 `platform_enabled` non usato dal frontend — GAP

Il backend locale `/me` restituisce `platform_enabled=True` per `customer_admin`. Il frontend (`AuthUser` interface, `ProtectedRoute.tsx`) non usa questo campo. Il routing non ne tiene conto.

---

## 5. Gap dev-cloud vs customer-local

| Aspetto | Dev Cloud | Customer-Local | Gap |
|---|---|---|---|
| Env system | `infra/env/base.env + dev.env` | `overlay/env/customer-local.env` | Sistema completamente diverso; script ML hardcoded su dev |
| Python venv | `apps/ml-worker/.venv/` (installato) | NON presente nel bundle | Cliente deve creare e installare |
| ETL config | `client-runtime/etl/.env` (reale) | NON nel bundle | Cliente deve creare equivalente |
| Supabase | `SUPABASE_URL/KEY` configurati | NON configurati | `customer_provisioning_repository.py` fallirebbe |
| ML scheduler | systemd (su dev Linux) | systemd units nel bundle ma paths dev | Paths hardcoded su `/opt/greenbrain-platform/` |
| load_env.sh | Legge da `/opt/greenbrain-platform/infra/env/` | Stesso hardcoded | Fallirebbe su cliente |
| Storage modelli | `/opt/greenbrain/storage/`, `/opt/greenbrain/models_v4/` | Path dev hardcoded | Non esistono su cliente |
| Backend volume | Relativo a dir dev `../../releases/` | Same path in docker-compose | Fallisce su installazione cliente arbitraria |
| Heartbeat | Script su cron dev | Script mancante nel bundle | Heartbeat funziona solo per cliente_reale (ha il dev server) |
| Routing frontend | `AdminRoute` → `/dashboard` per admin | Stesso codice → blocca customer_admin | P0 fix richiesto |
| Logging | `runtime-reports/` su dev | Path hardcoded, directory non garantita | Fallisce su cliente |

---

## 6. Piano operativo — Fasi A/B/C/D

### FASE A — Fix P0 bloccanti (1–2 giorni)
**Obiettivo**: il cliente `2@gmail.com` può accedere a `/dashboard` sul suo runtime locale.

**A1** — `apps/frontend/src/components/auth/ProtectedRoute.tsx`
```typescript
// Aggiungere CustomerRoute
export function CustomerRoute() {
  const { user, loading } = useAuth();
  if (loading) return <LoadingScreen />;
  if (!user) return <Navigate to="/login" replace />;
  const hasAccess = user.is_admin ||
    ['customer_admin', 'customer_user', 'tenant_admin', 'greenbrain_admin', 'super_admin']
      .includes(user.user_role ?? '');
  if (!hasAccess) return <Navigate to="/account" replace />;
  return <Outlet />;
}

export function InternalAdminRoute() {
  const { user, loading } = useAuth();
  if (loading) return <LoadingScreen />;
  if (!user) return <Navigate to="/login" replace />;
  const isInternal = ['super_admin', 'greenbrain_admin'].includes(user.user_role ?? '')
    || (user.is_admin && !user.tenant_code);
  if (!isInternal) return <Navigate to="/account" replace />;
  return <Outlet />;
}
```

**A2** — `apps/frontend/src/App.tsx`
```tsx
// Separare CustomerRoute da InternalAdminRoute
<Route element={<CustomerRoute />}>
  <Route path="/dashboard" element={<Dashboard />} />
  <Route path="/dashboard/reorders" element={<Reorders />} />
  <Route path="/analytics" element={<Analytics />} />
  <Route path="/assortment-planner" element={<AssortmentPlanner />} />
  <Route path="/suppliers" element={<Suppliers />} />
</Route>
<Route element={<InternalAdminRoute />}>
  <Route path="/ops" element={<CustomerOpsConsolePage />} />
  <Route path="/customers" element={<Customers />} />
  <Route path="/customers/:customerId" element={<CustomerDetail />} />
</Route>
```

**A3** — `apps/frontend/src/components/layout/Sidebar.tsx`
```typescript
// Console Ops solo a internal admin
const isInternalAdmin = ['super_admin', 'greenbrain_admin'].includes(user?.user_role ?? '')
  || (user?.is_admin && !user?.tenant_code);
```

**A4** — `apps/frontend/src/hooks/useAuth.tsx`
```typescript
// Aggiungere platform_enabled all'interface
export interface AuthUser {
  // ... existing
  platform_enabled?: boolean;
  runtime_health?: string | null;
  runtime_public_backend_url?: string | null;
}
```

**A5** — `apps/frontend/src/lib/apiClient.ts`
```typescript
// Rimuovere /api/v1/ops/ da RUNTIME_API_PREFIXES (ops è cloud-only)
const RUNTIME_API_PREFIXES = [
  "/api/v1/dashboard/",
  "/api/v1/analytics/",
  "/api/v1/forecast/",
  "/api/v1/catalog/",
  "/api/v1/sales/",
  "/api/v1/planner/",
  // "/api/v1/ops/",   ← RIMUOVERE
  "/api/v1/settings/",
];
```

**A6** — Git commit 9 file uncommitted
```bash
git add apps/backend/app/main.py \
        apps/backend/app/services/customer_runtime_service.py \
        apps/backend/app/repositories/customer_runtime_repository.py \
        apps/backend/app/services/customer_delivery_service.py \
        apps/backend/app/services/customer_portal_service.py \
        apps/backend/app/repositories/customer_portal_repository.py \
        apps/frontend/src/lib/apiClient.ts \
        apps/frontend/src/lib/customerPortalApi.ts \
        apps/frontend/src/pages/Login.tsx
git commit -m "feat(auth+routing): CustomerRoute, InternalAdminRoute, RUNTIME_API_PREFIXES, SSO cleanup"
```

**A7** — DB cloud: rimuovi riga spuria
```sql
DELETE FROM greenbrain_runtime_connections WHERE tenant_code = '2';
```

---

### FASE B — Bundle 0.1.25: installer funzionante + ML paths (1 settimana)
**Obiettivo**: cliente può installare e avviare senza supporto tecnico su Linux.

**B1** — `deploy/customer-local-template/install.sh` (da scrivere)
```bash
#!/usr/bin/env bash
# 1. Preflight: docker, docker compose, porta libera
# 2. Crea overlay/env/ da example se non esiste
# 3. Genera PASSWORD e JWT_SECRET casuali e li inserisce nell'env
# 4. Chiede interattivamente TENANT_CODE e TUNNEL_PUBLIC_HOST
# 5. Crea overlay/provisioning/local-runtime.env (con INSTALLATION_ID generato)
# 6. Crea overlay/tunnel/cloudflared/ da example
# 7. docker compose config validate
# 8. Stampa riepilogo e next steps
```

**B2** — `deploy/customer-local-template/base/scripts/provision-local.sh` (ripristinare da 0.1.18)
```bash
# Genera INSTALLATION_ID se mancante
# Sincronizza TENANT_CODE, TUNNEL_PUBLIC_HOST tra customer-local.env e local-runtime.env
# Preparazione per il bind cloud
```

**B3** — `deploy/customer-local-template/base/scripts/doctor-local.sh` (da scrivere)
```bash
# Verifica docker running
# Verifica containers healthy
# Verifica backend /health risponde
# Verifica DB connessione (greenbrain_users esiste)
# Verifica tunnel config se abilitato
# Stampa versione e INSTALLATION_ID
# Output: OK / WARNING / FAIL con consigli
```

**B4** — `deploy/customer-local-template/base/scripts/runtime-heartbeat.sh` (da scrivere)
```bash
# Legge TENANT_CODE, INSTALLATION_ID, HEARTBEAT_URL da local-runtime.env
# POST a cloud /api/v1/customer-runtime/heartbeat con payload runtime status
# Log risultato in overlay/logs/heartbeat.log
```

**B5** — Fix paths ML scripts (parametrici)

Tutti i 14 script `base/infra/scripts/bin/gh-*` e `base/apps/ml-worker/run_*.sh`:
```bash
# PRIMA (hardcoded dev):
cd /opt/greenbrain-platform/apps/ml-worker
source /opt/greenbrain-platform/apps/ml-worker/.venv/bin/activate

# DOPO (parametrico):
GB_BASE="${GB_BASE:-/opt/greenbrain-platform}"
cd "$GB_BASE/apps/ml-worker"
source "$GB_BASE/apps/ml-worker/.venv/bin/activate"
```

**B6** — Fix `base/infra/scripts/load_env.sh`
```bash
# PRIMA:
BASE="/opt/greenbrain-platform/infra/env"
# DOPO:
GB_BASE="${GB_BASE:-/opt/greenbrain-platform}"
BASE="$GB_BASE/infra/env"
```

**B7** — Fix systemd units (parametrici + APP_ENV corretto)
```ini
# PRIMA:
Environment=APP_ENV=dev
WorkingDirectory=/opt/greenbrain-platform
ExecStart=/bin/bash -lc 'source /opt/greenbrain-platform/infra/scripts/load_env.sh ...'

# DOPO:
Environment=APP_ENV=client-local
Environment=GB_BASE=/opt/greenbrain-platform  # ovveride via env in install
WorkingDirectory=%E{GB_BASE}
ExecStart=/bin/bash -lc 'source ${GB_BASE}/infra/scripts/load_env.sh ...'
```
_Alternativa più robusta: script wrapper che legge GB_BASE da `/etc/greenbrain.conf`._

**B8** — Fix volume mount backend in `docker-compose.local.yml`
```yaml
# PRIMA (relativo, funziona solo su dev):
volumes:
  - ../../releases/customer-local:/opt/greenbrain-platform/releases/customer-local:ro

# DOPO (assoluto, o meglio: non necessario sul locale se il bundle scarica direttamente):
# OPZIONE A: volume non necessario (il backend locale non serve bundle delivery)
# OPZIONE B: path configurabile via env
volumes:
  - ${RELEASES_DIR:-/dev/null}:/opt/greenbrain-platform/releases/customer-local:ro
```

Il backend locale non ha il router `customer_delivery` → non serve il volume `releases/`.

**B9** — `deploy/customer-local-template/overlay/env/customer-local.env.example`  
Aggiungere sezione ML-worker env:
```bash
# ML-Worker (runtime locale)
GB_BASE=/opt/greenbrain-platform  # root dell'installazione
ML_STORAGE_ROOT=/opt/greenbrain/storage
ML_MODELS_DIR=/opt/greenbrain/models_v4
ML_PARQUET_CACHE=/opt/greenbrain/storage/parquet_cache

# SQL Server sorgente dati cliente
SQLSERVER_SERVER=CHANGE_ME_SQLSERVER_HOST
SQLSERVER_DB=CHANGE_ME_SQLSERVER_DB
SQLSERVER_USER=CHANGE_ME_SQLSERVER_USER
SQLSERVER_PASSWORD=CHANGE_ME_SQLSERVER_PASSWORD
SQLSERVER_PORT=1433
```

**B10** — Aggiungere heartbeat scheduler al docker-compose (leggero)
```yaml
# Alternativa al systemd: cron minimalista nel container Alpine
  heartbeat:
    image: alpine:3.20
    container_name: greenbrain_local_heartbeat
    restart: unless-stopped
    env_file:
      - ./overlay/env/customer-local.env
    volumes:
      - ./overlay/provisioning:/workspace/provisioning:ro
      - ./overlay/logs:/workspace/logs
      - ./base/scripts:/workspace/scripts:ro
    command: >
      sh -c "echo '*/5 * * * * /workspace/scripts/runtime-heartbeat.sh >> /workspace/logs/heartbeat.log 2>&1' | crontab - && crond -f -l 8"
```

---

### FASE C — Bundle 0.1.26: SQL Server guidato + ML containerizzato (2–3 settimane)
**Obiettivo**: installazione completamente guidata su Linux. Zero prerequisiti Python sull'host.

**C1** — `deploy/customer-local-template/base/scripts/setup-source-db.sh`
```bash
# Wizard interattivo:
# 1. Chiede host SQL Server, porta, database, utente, password
# 2. Testa connessione con mssql-tools (Docker oneshot)
# 3. Se OK: scrive overlay/config/source-db.sqlserver.env
# 4. Elenca tabelle trovate e chiede conferma contratto schema
# 5. Esegue mapping base automatico verso mapping.env
```

**C2** — `deploy/customer-local-template/base/scripts/tunnel-setup.sh`
```bash
# Guida utente:
# 1. Verifica cloudflared disponibile (via Docker)
# 2. Genera istruzioni passo-passo per creare tunnel su Cloudflare Dashboard
# 3. Chiede TUNNEL_ID, copia JSON credentials da input utente
# 4. Popola overlay/tunnel/cloudflared/ automaticamente
# 5. Test dry-run tunnel
```

**C3** — Containerizzare ML-worker

Aggiungere servizio `ml-worker` al `docker-compose.local.yml`:
```yaml
  ml-worker:
    build:
      context: ./base/apps/ml-worker
      dockerfile: Dockerfile.runtime  # da creare
    container_name: greenbrain_local_ml
    restart: "no"
    env_file:
      - ./overlay/env/customer-local.env
    volumes:
      - ${ML_STORAGE_ROOT:-/opt/greenbrain/storage}:/opt/greenbrain/storage
      - ${ML_MODELS_DIR:-/opt/greenbrain/models_v4}:/opt/greenbrain/models_v4
    profiles:
      - ml  # avviato separatamente: docker compose --profile ml up ml-worker
```

`Dockerfile.runtime`:
```dockerfile
FROM python:3.11-slim
RUN apt-get update && apt-get install -y gcc libpq-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV GB_BASE=/app
CMD ["python", "-m", "jobs.predict_all"]
```

**C4** — Scheduler container per ML cron
```yaml
  scheduler:
    image: alpine:3.20
    container_name: greenbrain_local_scheduler
    restart: unless-stopped
    env_file:
      - ./overlay/env/customer-local.env
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./overlay/logs:/workspace/logs
    command: >
      sh -c "apk add --no-cache docker-cli &&
             echo '05 21 * * * docker exec greenbrain_local_ml python -m jobs.run_daily_pipeline >> /workspace/logs/daily.log 2>&1' | crontab - &&
             crond -f -l 8"
```

**C5** — Frontend: `platform_enabled` routing

```typescript
// Login.tsx: dopo SSO, usa platform_enabled per redirect
const defaultPath = user.platform_enabled ? "/dashboard" : "/account";
// ignorare home_path se l'utente è su un dominio diverso (sicurezza)
```

**C6** — Documentazione cliente (PDF/HTML) nel bundle
```
base/docs/
  INSTALLAZIONE-LINUX.md   (step numerati, senza jargon tecnico)
  INSTALLAZIONE-WINDOWS.md (basato su Docker Desktop)
  CONFIGURAZIONE-SQLSERVER.md
  CONFIGURAZIONE-TUNNEL.md
  AGGIORNAMENTO.md
```

---

### FASE D — Bundle 0.1.27+: OTA update + Windows (1–2 mesi)
**Obiettivo**: self-service completo. Nessuna interazione operatore richiesta post-installazione.

**D1** — `base/scripts/update.sh` lato cliente
```bash
# 1. GET cloud /api/v1/customer-runtime/latest-version?tenant=<code>
# 2. Scarica bundle firmato (URL S3/signed)
# 3. Estrai in /tmp, verifica checksum
# 4. pre-update-backup.sh
# 5. rsync base/, preserva overlay/
# 6. Restart containers
# 7. Health check
# 8. POST heartbeat con nuova versione
```

**D2** — Windows installer completo (`install.ps1`)
```powershell
# 1. Check Docker Desktop running
# 2. Interactive wizard (TENANT_CODE, TUNNEL_PUBLIC_HOST, SQL Server)
# 3. Genera secrets (Get-Random)
# 4. Scrive overlay/env/customer-local.env
# 5. docker compose up -d
# 6. Apre browser su localhost:8088
```

**D3** — Auto-update OTA
- Endpoint cloud `GET /api/v1/customer-runtime/update-available?tenant=<code>&version=<current>`
- Bundle update package (delta, non full) con solo i file `base/` cambiati
- Il scheduler container chiama l'endpoint ogni notte, lancia update se disponibile

**D4** — Multi-instance support
- Più installazioni per stesso tenant (es. sede diversa)
- `INSTALLATION_ID` distinto per ogni macchina
- Monitoring centralizzato sul cloud con lista installazioni per tenant

---

## 7. Lista file da modificare

### Fase A (P0 — fix immediato, senza toccare bundle)

| File | Modifica |
|---|---|
| `apps/frontend/src/components/auth/ProtectedRoute.tsx` | Aggiungere `CustomerRoute` e `InternalAdminRoute` |
| `apps/frontend/src/App.tsx` | Separare route operative (CustomerRoute) da route admin interne (InternalAdminRoute) |
| `apps/frontend/src/components/layout/Sidebar.tsx` | Console Ops visibile solo a internal admin |
| `apps/frontend/src/hooks/useAuth.tsx` | Aggiungere `platform_enabled`, `runtime_health` a `AuthUser` |
| `apps/frontend/src/lib/apiClient.ts` | Rimuovere `/api/v1/ops/` da RUNTIME_API_PREFIXES; committare |
| `apps/frontend/src/lib/customerPortalApi.ts` | Committare (già modificato) |
| `apps/frontend/src/pages/Login.tsx` | Committare (già modificato) |
| `apps/backend/app/main.py` | Committare (già modificato) |
| `apps/backend/app/services/customer_runtime_service.py` | Committare (untracked) |
| `apps/backend/app/repositories/customer_runtime_repository.py` | Committare (untracked) |
| `apps/backend/app/services/customer_delivery_service.py` | Committare |
| `apps/backend/app/services/customer_portal_service.py` | Committare |
| `apps/backend/app/repositories/customer_portal_repository.py` | Committare |

### Fase B (bundle 0.1.25)

| File | Modifica |
|---|---|
| `deploy/customer-local-template/install.sh` | Scrivere da zero |
| `deploy/customer-local-template/base/scripts/provision-local.sh` | Ripristinare da 0.1.18 + aggiornare |
| `deploy/customer-local-template/base/scripts/doctor-local.sh` | Scrivere da zero |
| `deploy/customer-local-template/base/scripts/runtime-heartbeat.sh` | Scrivere da zero |
| `deploy/customer-local-template/base/apps/ml-worker/run_nightly_runtime.sh` | Parametrizzare paths |
| `deploy/customer-local-template/base/apps/ml-worker/run_predict_all_runtime.sh` | Parametrizzare paths |
| `deploy/customer-local-template/base/apps/ml-worker/run_export_runtime.sh` | Parametrizzare paths |
| `deploy/customer-local-template/base/infra/scripts/load_env.sh` | Parametrizzare BASE |
| `deploy/customer-local-template/base/infra/scripts/bin/gh-*` (14 file) | Parametrizzare paths |
| `deploy/customer-local-template/base/infra/systemd/*.service` (7 file) | Parametrizzare paths + APP_ENV=client-local |
| `deploy/customer-local-template/base/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh` | Parametrizzare paths |
| `deploy/customer-local-template/docker-compose.local.yml` | Rimuovere volume `releases/` dal backend; aggiungere heartbeat container |
| `deploy/customer-local-template/env/customer-local.env.example` | Aggiungere sezione ML-worker env + SQL Server |
| `deploy/customer-local-template/overlay/env/customer-local.env` (template) | Stesso |
| `deploy/customer-local-template/VERSION` | Bump a 0.1.25 |
| `deploy/customer-local-template/release-manifest.yml` | Bump a 0.1.25 |
| `apps/frontend/src/pages/Login.tsx` | Usare `platform_enabled` per redirect post-SSO |

---

## 8. Comandi sicuri di verifica

```bash
# Stato attuale bundle vs dev
diff <(tar -tzf /opt/greenbrain-platform/releases/customer-local/0.1.24/customer-local-0.1.24.tar.gz 2>/dev/null | sort) \
     <(find /opt/greenbrain-platform/deploy/customer-local-template -type f | sed 's|.*/deploy/customer-local-template/||' | sort) 2>/dev/null | head -30

# Conta path hardcoded nel bundle template
grep -rn "/opt/greenbrain-platform\|\.venv/bin" \
  /opt/greenbrain-platform/deploy/customer-local-template/base/ \
  --include="*.sh" 2>/dev/null | wc -l

# Verifica routers inclusi nel main.py locale
grep "include_router" /opt/greenbrain-platform/deploy/customer-local-template/base/backend-src/app/main.py

# Verifica routing frontend (AdminRoute vs CustomerRoute)
grep -n "AdminRoute\|CustomerRoute\|InternalAdmin" /opt/greenbrain-platform/apps/frontend/src/App.tsx

# Verifica user_role in greenbrain_users cloud
# (readonly, sicuro)
cd /opt/greenbrain-platform && APP_ENV=dev source infra/scripts/load_env.sh 2>/dev/null && \
  PGPASSWORD="$PG_PASSWORD" psql "host=$PG_HOST port=$PG_PORT dbname=$PG_DB user=$PG_USER sslmode=require" \
  -c "SELECT email, is_admin, user_role, home_host, home_path FROM greenbrain_users ORDER BY created_at;" 2>/dev/null | grep -v "^\[ENV\]"

# Verifica heartbeat runtime_connections
cd /opt/greenbrain-platform && APP_ENV=dev source infra/scripts/load_env.sh 2>/dev/null && \
  PGPASSWORD="$PG_PASSWORD" psql "host=$PG_HOST port=$PG_PORT dbname=$PG_DB user=$PG_USER sslmode=require" \
  -c "SELECT tenant_code, runtime_health, last_heartbeat_at FROM greenbrain_runtime_connections ORDER BY last_heartbeat_at DESC NULLS LAST;" 2>/dev/null | grep -v "^\[ENV\]"

# Verifica versioning template
echo "VERSION:$(cat /opt/greenbrain-platform/deploy/customer-local-template/VERSION)" && \
  grep "package_version" /opt/greenbrain-platform/deploy/customer-local-template/release-manifest.yml

# Verifica uncommitted
cd /opt/greenbrain-platform && git status --short | head -20

# Verifica container locale cliente_reale (se accessibile)
# SAFE: solo lettura stato
curl -fs https://cliente-reale.greenbrain.it/health 2>/dev/null | python3 -m json.tool

# Verifica bundle 0.1.24 ha install.sh
tar -xOf /opt/greenbrain-platform/releases/customer-local/0.1.24/customer-local-0.1.24.tar.gz \
  package/customer-local-template/install.sh 2>/dev/null | wc -l

# Verifica script ML hanno path hardcoded nel bundle 0.1.24
tar -xOf /opt/greenbrain-platform/releases/customer-local/0.1.24/customer-local-0.1.24.tar.gz \
  package/customer-local-template/base/apps/ml-worker/run_nightly_runtime.sh 2>/dev/null | grep "opt/greenbrain"

# Lista tutti i file presenti in deploy/template ma assenti nel bundle 0.1.24
comm -23 \
  <(find /opt/greenbrain-platform/deploy/customer-local-template -type f -not -path '*/__pycache__/*' -not -name '*.pyc' | sed 's|.*/deploy/customer-local-template/||' | sort) \
  <(tar -tzf /opt/greenbrain-platform/releases/customer-local/0.1.24/customer-local-0.1.24.tar.gz 2>/dev/null | sed 's|^package/customer-local-template/||' | grep -v "/$" | sort) 2>/dev/null | head -40
```

---

## 9. Target release 0.1.25 e 0.1.26

### Release 0.1.25 — "Installer funzionante"

**Prerequisiti completati (da Fase A):**
- `CustomerRoute` + `InternalAdminRoute` in produzione
- 9 file committati
- DB cloud: riga spuria eliminata

**Contenuto 0.1.25:**
- `install.sh` funzionante (wizard bash)
- `provision-local.sh` ripristinato
- `doctor-local.sh` nuovo
- `runtime-heartbeat.sh` nuovo + container heartbeat in docker-compose
- ML paths parametrizzati con `GB_BASE`
- `load_env.sh` parametrizzato
- systemd units con `APP_ENV=client-local` e paths parametrici
- Volume `releases/` rimosso da docker-compose backend locale
- `customer-local.env.example` con sezione ML e SQL Server

**Processo di release:**
```bash
cd /opt/greenbrain-platform

# Step 1: bump versione + sync dev → template
bash tools/release/promote_dev_to_customer_template.sh 0.1.25

# Step 2: build bundle
bash tools/release/build_customer_local_release.sh 0.1.25

# Verifica
ls releases/customer-local/0.1.25/
tar -tzf releases/customer-local/0.1.25/customer-local-0.1.25.tar.gz | grep install.sh
```

**Rischi 0.1.25:** ZERO rotture per cliente_reale esistente (upgrade via `update_customer_local_from_bundle.sh` preserva overlay).

---

### Release 0.1.26 — "Plug & Play completo Linux"

**Prerequisiti completati (da Fase B):**

**Contenuto 0.1.26:**
- `setup-source-db.sh` wizard interattivo SQL Server
- `tunnel-setup.sh` guida Cloudflare
- ML-worker containerizzato (`Dockerfile.runtime` + servizio docker-compose)
- Scheduler container Docker (sostituisce systemd su Linux senza root)
- `update.sh` lato cliente basico
- Documentazione cliente in `base/docs/`
- `platform_enabled` usato nel frontend per routing intelligente
- Fix `apps/frontend`: `Login.tsx` usa `platform_enabled` per redirect

**Test target:**
```
Scenario: cliente nuovo
1. Scarica bundle 0.1.26 dal portal (bundle personalizzato con token pre-iniettato)
2. tar -xzf customer-local-0.1.26-<tenant>-<stamp>.tar.gz
3. cd customer-local-template && bash install.sh
4. → install.sh genera secrets, chiede TUNNEL_PUBLIC_HOST
5. bash base/scripts/doctor-local.sh → OK
6. Apre http://localhost:8088 → Login → SSO → /dashboard ✓
7. SQL Server: bash base/scripts/setup-source-db.sh → wizard completo
8. Tunnel: bash base/scripts/tunnel-setup.sh → guida Cloudflare
9. docker compose -f base/tunnel/docker-compose.tunnel.yml up -d → tunnel up
10. Dashboard accessibile da https://<tenant>.greenbrain.it ✓
```

---

## 10. Rischi da non rompere

| Rischio | Mitigazione |
|---|---|
| **Auth SSO** — JWT_SECRET condiviso cloud↔locale | JWT_SECRET è iniettato nel bundle dal cloud al momento della generazione. Non modificare il meccanismo di iniezione in `customer_delivery_service.py`. |
| **CustomerPortalDashboard** — onboarding, download, billing | Le Fase A toccano solo frontend routing. Il `CustomerPortalDashboard` rimane sulla route `/account` → `ProtectedRoute` → invariato. |
| **Runtime locale `cliente_reale`** — heartbeat, tunnel, dati | Il runtime 0.1.18 installato su `cliente_reale` non viene toccato da nessuna Fase. Il `update_customer_local_from_bundle.sh` preserva l'overlay. Aggiornare solo su richiesta esplicita. |
| **Dati DB locale** | Il volume `greenbrain_local_postgres_data` è docker named volume → persiste tra restart e aggiornamenti. Il `docker compose up -d --build` non rimuove i volumi. |
| **Tunnel esistente** | Il tunnel Cloudflare è configurato in `overlay/tunnel/cloudflared/` che è preservato da `overlay-manifest.yml`. Nessuna modifica a base-manifest o overlay-manifest rompe questo. |
| **`require_admin` backward compat** | `require_internal_admin` in auth.py ha già backward compat per `is_admin=true AND tenant_code=null`. Non modificare questa logica. |
| **`/api/v1/ops/` routing** | Rimuoverlo da RUNTIME_API_PREFIXES fa sì che le chiamate ops vadano al cloud backend. Sul locale non c'è ops router (è in `main.py` locale ma come `ops_router` di monitoring, non di gestione). Verificare prima con `curl`. |

---

_Fine analisi. Nessun file modificato. Tutte le modifiche sono proposte, in attesa di conferma._
