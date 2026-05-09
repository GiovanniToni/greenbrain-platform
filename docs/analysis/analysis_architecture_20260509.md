# GreenBrain — Analisi Architetturale Completa
_Generata: 2026-05-09 — branch `feat/customer-ops-supabase-foundation` — commit HEAD `13b1f3a`_

---

## Contesto architetturale verificato

| Layer | Componente | Stato |
|---|---|---|
| Cloud frontend | React SPA su `www.greenbrain.it` | ✅ operativo |
| Cloud backend | FastAPI `apps/backend` su `www.greenbrain.it` | ✅ operativo |
| Cloud DB | Supabase/Postgres cloud (`public.*`, `etl.*`) | ✅ operativo |
| Runtime locale | Docker Compose su `cliente-reale.greenbrain.it` | ✅ heartbeat healthy |
| Bundle corrente | `releases/customer-local/0.1.18/` | ✅ esiste |
| Scheduler locale | Container `gb_customer_scheduler` (Alpine cron 20:45) | ✅ in bundle |
| Tunnel | Cloudflare Tunnel → `cliente-reale.greenbrain.it` | ✅ heartbeat dal runtime |

---

## A. Diagnosi precisa dei problemi attuali

### P0 — `2@gmail.com` non può accedere a `/dashboard` sul runtime locale [BLOCCANTE]

**Causa root**: Il routing `AdminRoute` in `App.tsx` protegge `/dashboard`, `/analytics`, `/assortment-planner`, `/suppliers`, `/dashboard/reorders` richiendendo `user.is_admin === true`. Ma `2@gmail.com` ha `is_admin=false` nel DB (`user_role=customer_admin`).

**Flusso rotto**:
1. Login su `www.greenbrain.it` → SSO → redirect a `cliente-reale.greenbrain.it/login?sso=<ticket>`
2. SSO exchange sul backend locale → JWT emesso
3. `GET /api/v1/auth/me` restituisce `is_admin=false`, `home_path=/dashboard`
4. `redirectAfterLogin()` usa `targetPath = home_path = "/dashboard"`
5. `AdminRoute` controlla `user.is_admin === false` → **redirect forzato a `/account`**
6. Il cliente vede solo "Area cliente" (onboarding), non i dati operativi

**DB confermato** (`greenbrain_users`):
```
2@gmail.com | is_admin=false | user_role=customer_admin | home_host=cliente-reale.greenbrain.it | home_path=/dashboard
```

**Impatto**: Il runtime locale `0.1.18` è installato e `healthy` ma il cliente non può usarlo.

---

### P0 — `user_role` ignorato ovunque [ARCHITETTURALE]

Il campo `user_role` esiste in `greenbrain_users` con valori `super_admin`, `greenbrain_admin`, `customer_admin`, `customer_user`, `tenant_admin`, ma:
- **Non viene controllato** in `AdminRoute` né in `ProtectedRoute`
- **Non viene controllato** in nessun `require_admin` backend
- **Non viene usato** per distinguere "admin interno GreenBrain" da "admin del cliente sul runtime"

Il codice usa solo `is_admin` (bool) come unico switch, rendendo impossibile il modello multi-ruolo richiesto.

---

### P1 — `/ops` esposto sul runtime locale agli admin interni [SICUREZZA / UX]

In `App.tsx` la route `/ops` è dietro `AdminRoute` (richiede `is_admin=true`). Se un admin interno di GreenBrain fa SSO sul runtime locale (`cliente-reale.greenbrain.it`), vede la Console Ops che chiama:
- `RUNTIME_API_PREFIXES` → `/api/v1/ops/` viene instradato al **backend locale del cliente**
- Il backend locale include `ops_router` (endpoint operativi) e `customer_ops_router` (gestione clienti)

Il backend del cliente **non dovrebbe esporre** endpoint di gestione clienti (`/api/v1/customer-ops/`, `/api/v1/customer-delivery/`, `/api/v1/customer-billing/`).

---

### P1 — Backend locale include router cloud-only [SICUREZZA]

`base/backend-src/app/main.py` nel bundle 0.1.18 include:
```python
customer_ops_router        # gestione clienti (solo cloud)
customer_delivery_router   # generazione bundle (solo cloud)
customer_portal_router     # profilo onboarding (solo cloud)
customer_billing_router    # Stripe (solo cloud)
cloud_sync_router          # sync cloud (solo cloud)
```

Sul runtime locale questi router puntano a un DB locale senza dati cloud → errori o dati vuoti. Espandono anche la superficie di attacco del backend locale.

---

### P1 — Conflitto `home_path` default per utenti senza runtime [LOGICA]

In `db/users.py`, `create_user()`:
```python
"home_path": home_path or ("/ops" if is_admin else "/account"),
```

I test utenti (`a@gmail.com`, `z@gmail.com`, ...) hanno `home_host=www.greenbrain.it`, `home_path=/account`. Questo è corretto per l'area onboarding cloud.

Ma `2@gmail.com` ha `home_path=/dashboard` impostato manualmente durante il provisioning del runtime. Il problema è che `/dashboard` è bloccato da `AdminRoute`. Quando il runtime sarà accessibile, il cliente non potrà usarlo.

---

### P2 — Duplicato in `greenbrain_runtime_connections` [DB]

Esistono due righe con lo stesso `installation_id`:
```
tenant_code=cliente_reale | healthy | 2026-05-08 22:37 | installation_id=11ef6c95-...
tenant_code=2             | healthy | 2026-05-07 13:41 | installation_id=11ef6c95-...
```

La riga `tenant_code=2` è un residuo di quando l'utente aveva `tenant_code='2'`. La `customer_portal_service.py` fa `get_runtime_connection_by_tenant_code(tenant_code)` con `tenant_code='cliente_reale'` → trova la riga corretta. Ma la riga spuria `tenant_code=2` può confondere le query di monitoraggio.

---

### P2 — `release-manifest.yml` nel bundle 0.1.18 dice `0.1.16` [VERSIONING]

```yaml
# customer-local-template/release-manifest.yml in 0.1.18
package_version: 0.1.16   # ← sbagliato
```

`VERSION` dice `0.1.18`, ma il manifest non è stato aggiornato. Il `build_customer_local_release.sh` verifica la coerenza → se eseguito per `0.1.18` **fallirebbe** (ma il bundle esiste già, quindi il problema è emerso durante una build manuale).

---

### P2 — Modifiche non committate su file critici [GIT DRIFT]

| File | Stato | Impatto |
|---|---|---|
| `apps/backend/app/main.py` | M (uncommitted) | aggiunge `customer_runtime_router` + `allow_origin_regex` |
| `apps/frontend/src/lib/apiClient.ts` | M (uncommitted) | refactor RUNTIME_API_PREFIXES, memoryToken, getRuntimeBaseUrl |
| `apps/frontend/src/lib/customerPortalApi.ts` | M (uncommitted) | `getCustomerPortalMe` setta automaticamente runtimeBaseUrl |
| `apps/frontend/src/pages/Login.tsx` | M (uncommitted) | SSO flow |
| `apps/backend/app/services/customer_portal_service.py` | M | — |
| `apps/backend/app/repositories/customer_portal_repository.py` | M | — |
| `apps/backend/app/services/customer_delivery_service.py` | M | — |
| `apps/backend/app/services/customer_runtime_service.py` | ?? untracked | nuovo servizio runtime (importante) |
| `apps/backend/app/repositories/customer_runtime_repository.py` | ?? untracked | nuovo repository runtime (importante) |

**Il bundle 0.1.18 è stato costruito PRIMA di queste modifiche** → divergenza tra bundle pubblicato e codice dev.

---

### P3 — `VITE_API_BASE_URL` e routing `apiClient.ts` [CONFIGURAZIONE]

Il comportamento di `apiOrigin()` in `apiClient.ts`:
- **Auth/portal API** → `window.location.origin` (corretto: segue l'host corrente)
- **Operational API** (dashboard, analytics...) → `runtimeBase` se settato, altrimenti `window.location.origin`

Il `runtimeBase` viene settato da `getCustomerPortalMe()` solo se `runtime_public_backend_url` è presente nel profilo cliente. Se non è settato (cloud-only login), le chiamate operational vanno al cloud backend → corretto. Se è settato, vanno al runtime locale → corretto.

**Problema**: `runtimeBase` è in `localStorage`. Se l'utente si sposta da cloud a runtime locale (SSO), il `runtimeBase` rimane dall'ultima sessione. Non viene resettato al logout.

---

### P3 — `check_etl_ready.sh` nel bundle 0.1.18 [PARQUET EXPORT]

Il bundle 0.1.18 include `base/orchestration/jobs/parquet/check_etl_ready.sh` con la versione corretta (fix applicati in sessione precedente: dev bypass + 48h window + lag fix). Questo è corretto.

---

## B. Lista dei file da correggere

### PRIORITÀ P0 (bloccanti)

| # | File | Correzione richiesta |
|---|---|---|
| 1 | `apps/frontend/src/components/auth/ProtectedRoute.tsx` | Aggiungere `CustomerRoute` che usa `user_role` invece di solo `is_admin` |
| 2 | `apps/frontend/src/App.tsx` | Spostare `/dashboard`, `/analytics`, `/assortment-planner`, `/suppliers`, `/reorders` da `AdminRoute` a nuova `CustomerRoute` (accessibile anche a `customer_admin` e `customer_user`) |
| 3 | `apps/backend/app/db/users.py` | `create_user()`: default `home_path` per `customer_admin` deve essere `/dashboard` (già così) ma il routing frontend deve permetterlo |
| 4 | `apps/frontend/src/pages/Login.tsx` | `redirectAfterLogin`: il `defaultPath` per utenti non-admin ma con ruolo customer deve essere `/dashboard` sul runtime locale |

### PRIORITÀ P1

| # | File | Correzione richiesta |
|---|---|---|
| 5 | `apps/frontend/src/App.tsx` | `/ops` deve usare `InternalAdminRoute` (verifica `user_role` in `['super_admin','greenbrain_admin']`) |
| 6 | `apps/frontend/src/components/layout/Sidebar.tsx` | Voce "Console Ops" visibile solo se `user_role` è internal admin, non solo `is_admin` |
| 7 | `apps/backend/app/api/v1/auth.py` | `require_admin` usare `user_role` come criterio secondario |
| 8 | `deploy/customer-local-template/base/backend-src/app/main.py` (bundle) | Rimuovere `customer_ops_router`, `customer_delivery_router`, `customer_portal_router`, `customer_billing_router`, `cloud_sync_router` dal bundle locale |
| 9 | `deploy/customer-local-template/release-manifest.yml` | Aggiornare `package_version: 0.1.18` |

### PRIORITÀ P2

| # | File | Correzione richiesta |
|---|---|---|
| 10 | `apps/frontend/src/lib/apiClient.ts` | Commit le modifiche uncommitted; rimuovere `/api/v1/ops/` da RUNTIME_API_PREFIXES (ops è cloud-only) |
| 11 | `apps/backend/app/main.py` | Commit le modifiche uncommitted |
| 12 | `apps/frontend/src/lib/customerPortalApi.ts` | Commit; aggiungere `clearRuntimeBaseUrl()` al logout |
| 13 | `apps/frontend/src/hooks/useAuth.tsx` | `logout()`: chiamare `clearStoredToken()` che già rimuove anche `RUNTIME_BASE_KEY` ✓ |
| 14 | DB cloud | `DELETE FROM greenbrain_runtime_connections WHERE tenant_code = '2'` (riga spuria) |
| 15 | DB cloud | Verifica e unifica i test-utenti con `home_host` corretto |

### PRIORITÀ P3

| # | File | Correzione richiesta |
|---|---|---|
| 16 | `apps/backend/app/services/customer_runtime_service.py` | Commit (untracked) |
| 17 | `apps/backend/app/repositories/customer_runtime_repository.py` | Commit (untracked) |
| 18 | `apps/backend/app/services/customer_delivery_service.py` | Commit modifiche |
| 19 | `apps/backend/app/services/customer_portal_service.py` | Commit modifiche |
| 20 | Bundle rebuild | Rebuild 0.1.19 o patch 0.1.18 con main.py corretto |

---

## C. Modello ruoli consigliato

### Ruoli da usare (campo `user_role`)

| Ruolo | Dove esiste | Accesso |
|---|---|---|
| `super_admin` | Solo DB cloud | Tutto: /ops, /customers, /dashboard (dev), Console Ops completa |
| `greenbrain_admin` | Solo DB cloud | Come super_admin meno gestione utenti interni |
| `customer_admin` | DB cloud + DB locale runtime | /account (cloud), /dashboard + /analytics + /planner + /suppliers (locale) |
| `customer_user` | Solo DB locale runtime | /dashboard + /analytics (read-only) — futuro |
| `tenant_admin` | DB locale runtime legacy | deprecato → mappare a `customer_admin` |

### Regole di visibilità UI

```
is_internal_admin(user) := user.user_role in ['super_admin', 'greenbrain_admin']
is_customer_access(user) := user.user_role in ['customer_admin', 'customer_user', 'tenant_admin']
  OR user.is_admin === true  (backward compat cloud dev)
```

### Route protette (nuovo schema)

```
/ops, /customers, /customers/:id   →  InternalAdminRoute (solo internal_admin)
/dashboard, /analytics, /planner,
/suppliers, /reorders              →  CustomerRoute (customer_admin + customer_user + internal_admin)
/account                           →  ProtectedRoute (tutti gli autenticati)
```

**Key insight**: `/dashboard` e le pagine operative vanno rese accessibili ai `customer_admin` sul runtime locale. Sul cloud (`www.greenbrain.it`) questi route possono chiamare il DB cloud (per dev/testing) o essere nascosti se `runtimeBase` non è settato.

---

## D. Flusso login corretto end-to-end

### Caso 1: Admin interno (`admin@greenbrain.it`)

```
www.greenbrain.it/login
  → POST /api/v1/auth/sso/start
      home_host = www.greenbrain.it = currentHost → SSO ticket non usato (stesso host)
      OPPURE: sso/start 400 per home_host == cloud → catch → login standard
  → POST /api/v1/auth/login → token
  → GET /api/v1/auth/me → {is_admin:true, user_role:"super_admin", home_path:"/ops"}
  → navigate("/ops")
  → InternalAdminRoute → PASSA → Console Ops
```

### Caso 2: Cliente con runtime (`2@gmail.com`)

```
www.greenbrain.it/login
  → POST /api/v1/auth/sso/start (cloud DB)
      home_host = "cliente-reale.greenbrain.it" ≠ currentHost → SSO ticket emesso
  → window.location.href = "https://cliente-reale.greenbrain.it/login?sso=<ticket>"

cliente-reale.greenbrain.it/login?sso=<ticket>
  → useEffect: sso param rilevato, isCentralHost=false → POST /api/v1/auth/sso/exchange
      locale backend verifica ticket, emette JWT locale
  → GET /api/v1/auth/me (locale) → {is_admin:false, user_role:"customer_admin", home_path:"/dashboard"}
  → navigate("/dashboard")
  → CustomerRoute → PASSA → Dashboard locale con dati locali
  
  [apiClient] runtimeBase = cliente-reale.greenbrain.it (window.location.origin)
  → tutte le chiamate dashboard/analytics/forecast → locale ✓
```

### Caso 3: Cliente senza runtime (`a@gmail.com`)

```
www.greenbrain.it/login
  → POST /api/v1/auth/sso/start
      home_host = "www.greenbrain.it" = currentHost → NO redirect (stessa origin)
  → POST /api/v1/auth/login → token cloud
  → GET /api/v1/auth/me → {is_admin:false, user_role:"customer_admin", home_path:"/account"}
  → navigate("/account")
  → ProtectedRoute → CustomerPortalDashboard → area onboarding ✓
```

### Caso 4: Cliente che apre direttamente il runtime locale

```
cliente-reale.greenbrain.it  (nessun sso param)
  → useEffect token: localStorage ha token locale valido → /me OK
  → già autenticato, navigate("/dashboard") ✓
  
  Se token scaduto:
  → /login su cliente-reale.greenbrain.it
  → isCentralHost = false → window.location.href = "https://www.greenbrain.it/login"
  → Caso 2 si ripete ✓
```

---

## E. Piano patch minimo (senza rompere runtime locale)

### Step 1 — Fix routing frontend (3 file, ~30 righe)

**`ProtectedRoute.tsx`**: aggiungere `CustomerRoute`
```typescript
export function CustomerRoute() {
  const { user, loading } = useAuth();
  if (loading) return <LoadingScreen />;
  if (!user) return <Navigate to="/login" replace />;
  // customer_admin, customer_user, tenant_admin possono accedere; gli admin anche
  const allowed = user.is_admin ||
    ['customer_admin', 'customer_user', 'tenant_admin', 'greenbrain_admin', 'super_admin']
      .includes(user.user_role ?? '');
  if (!allowed) return <Navigate to="/account" replace />;
  return <Outlet />;
}

export function InternalAdminRoute() {
  const { user, loading } = useAuth();
  if (loading) return <LoadingScreen />;
  if (!user) return <Navigate to="/login" replace />;
  const isInternal = ['super_admin', 'greenbrain_admin'].includes(user.user_role ?? '')
    || (user.is_admin && !user.tenant_code);  // backward compat: admin senza tenant = interno
  if (!isInternal) return <Navigate to="/account" replace />;
  return <Outlet />;
}
```

**`App.tsx`**: separare le route
```tsx
<Route element={<ProtectedRoute />}>
  <Route element={<AppLayout />}>
    <Route path="/account" element={<CustomerPortalDashboard />} />

    {/* Operative: cliente admin locale + admin interno */}
    <Route element={<CustomerRoute />}>
      <Route path="/dashboard" element={<Dashboard />} />
      <Route path="/dashboard/reorders" element={<Reorders />} />
      <Route path="/analytics" element={<Analytics />} />
      <Route path="/assortment-planner" element={<AssortmentPlanner />} />
      <Route path="/suppliers" element={<Suppliers />} />
    </Route>

    {/* Solo admin interni GreenBrain */}
    <Route element={<InternalAdminRoute />}>
      <Route path="/ops" element={<CustomerOpsConsolePage />} />
      <Route path="/customers" element={<Customers />} />
      <Route path="/customers/:customerId" element={<CustomerDetail />} />
    </Route>
  </Route>
</Route>
```

**`Sidebar.tsx`**: mostrare Console Ops solo a internal admin
```typescript
const isInternalAdmin = user?.is_admin &&
  (!user.tenant_code || ['super_admin','greenbrain_admin'].includes(user.user_role ?? ''));
```

### Step 2 — Fix DB cloud (2 query, nessun file)

```sql
-- Rimuovi riga spuria
DELETE FROM greenbrain_runtime_connections WHERE tenant_code = '2';

-- Correggi home_path di 2@gmail.com (già corretto, /dashboard, ma ora il routing lo accetterà)
-- Non serve modifica: il routing fix in Step 1 sblocca l'accesso
```

### Step 3 — Commit uncommitted files

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
git commit -m "feat(auth+routing): customer role routing + runtime API dispatch + SSO fixes"
```

### Step 4 — Fix bundle backend (main.py locale)

Nel `deploy/customer-local-template/base/backend-src/app/main.py`:
- Rimuovere: `customer_ops_router`, `customer_delivery_router`, `customer_portal_router`, `customer_billing_router`, `cloud_sync_router`
- Mantenere: `auth`, `dashboard`, `analytics`, `catalog`, `sales`, `forecast`, `planner`, `ops` (monitoring), `settings`, `system`, `health`, `customer_runtime` (heartbeat)

### Step 5 — Fix release-manifest.yml (1 riga)

```yaml
package_version: 0.1.18  # era 0.1.16
```

### Step 6 — Rebuild bundle 0.1.18 (o bump a 0.1.19)

```bash
rm -rf releases/customer-local/0.1.18/
bash tools/release/build_customer_local_release.sh 0.1.18
```

**Stima effort totale**: ~2-3 ore. Nessuna migrazione DB necessaria. Nessun restart dei servizi cloud. Il runtime locale 0.1.18 già installato continua a funzionare (il fix è solo frontend+routing).

---

## F. Piano evolutivo bundle customer-local plug-and-play

### Fase 1 — Completare 0.1.18 (ora)

- [x] Scheduler containerizzato (cron 20:45 Europe/Rome Alpine Docker) ✓
- [x] `install-local.sh` + `start.sh` + `stop.sh` + `doctor-local.sh` ✓
- [x] Tunnel Cloudflare configurabile ✓
- [x] Provisioning token e heartbeat cloud ✓
- [ ] Fix routing frontend (Step 1 sopra)
- [ ] Fix backend locale main.py (Step 4 sopra)
- [ ] Fix release-manifest.yml (Step 5 sopra)

### Fase 2 — Bundle 0.1.19: setup guidato (1-2 settimane)

**Obiettivo**: il cliente apre il bundle, esegue un singolo comando, compila un file `.env`, avvia Docker.

```
install-local.sh
  ├── preflight: Docker, RAM, porta 8008 libera
  ├── crea overlay/env/customer-local.env da example
  ├── crea overlay/provisioning/local-runtime.env da example  
  ├── se PROVISIONING_TOKEN presente → POST /api/v1/customer-runtime/register
  ├── docker compose up -d
  └── doctor-local.sh → health check

provision-local.sh (attuale + cloud bind)
  ├── genera INSTALLATION_ID se mancante
  ├── legge PROVISIONING_TOKEN da local-runtime.env
  └── POST cloud /api/v1/customer-runtime/register  ← automatico (oggi è manuale)
```

**Da aggiungere al bundle**:
- `setup-source-db.sh` guidato: chiede host SQL Server, testa connessione, scrive `source-db.sqlserver.env`
- `bind-cloud.sh`: esegue il POST di provisioning al cloud con token
- `update-local.sh`: scarica nuovo bundle, backup, restart

### Fase 3 — Bundle 0.1.20: Windows/macOS portability (2-4 settimane)

- `install.ps1` + `start.ps1` + `stop.ps1` + `doctor.ps1` (già presenti in 0.1.18 ma vuoti/stub)
- `install.bat` per Windows senza PowerShell
- Documentazione PDF installazione utente finale
- Wizard GUI web-based in Docker (un container aggiuntivo solo durante il setup)

### Fase 4 — Multi-tenant e aggiornamenti OTA (1-2 mesi)

- `update-local.sh` + endpoint cloud `GET /api/v1/customer-runtime/latest-version`
- Il bundle si aggiorna automaticamente se `AUTO_UPDATE=true` in env
- Il cloud può push nuovi bundle tramite URL firmato
- Log di aggiornamento centralizzati

### Fase 5 — Separazione cloud-backend da local-backend (architetturale)

Due `main.py` distinti:
```
apps/backend/app/main_cloud.py   # tutti i router cloud
apps/backend/app/main_local.py   # solo router operativi: auth, dashboard, analytics, catalog, sales, forecast, planner, ops, settings, system, health, customer_runtime
```

Il bundle usa `main_local.py`. Il cloud usa `main_cloud.py`. Dockerfile diversi.

---

## Stato DB cloud — utenti rilevanti

| Email | is_admin | user_role | home_host | home_path | Note |
|---|---|---|---|---|---|
| `admin@greenbrain.it` | ✅ true | `super_admin` | www.greenbrain.it | /ops | Admin interno OK |
| `2@gmail.com` | ❌ false | `customer_admin` | cliente-reale.greenbrain.it | /dashboard | **BLOCCATO da AdminRoute** |
| `a@gmail.com` .. `11@gmail.com` | ❌ false | `customer_admin` | www.greenbrain.it | /account | Test utenti, nessun runtime |
| `admin@cliente1.local` | ❌ false | `tenant_admin` | cliente1.greenbrain.it | /dashboard | Utente legacy locale |

## Stato runtime `cliente_reale`

| Metrica | Valore |
|---|---|
| `runtime_health` | `healthy` |
| `last_heartbeat_at` | 2026-05-08 22:37:16 UTC |
| `public_backend_url` | https://cliente-reale.greenbrain.it |
| `installed_release_version` | 0.1.18 |
| `onboarding_status` | `data_validated` |
| `assigned_release_version` | 0.1.18 |
| Riga spuria da rimuovere | `tenant_code='2'` in `greenbrain_runtime_connections` |

---

_Analisi completata. Nessuna modifica applicata. In attesa di conferma prima di procedere con le patch._
