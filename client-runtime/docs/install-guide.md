# GreenBrain Client Runtime — Installation Guide
> Wave 6 skeleton. Sections marked ⚠️ WAVE 7 are not yet executable.
> Last updated: 2026-03-28.

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Docker | ≥ 24 | Docker Engine or Docker Desktop |
| Docker Compose | ≥ 2.20 | included in Docker Desktop |
| RAM | ≥ 2 GB | for postgres + backend |
| Disk | ≥ 5 GB | for postgres data volume |

No internet access required after initial Docker image pull.

---

## Quick start

### 1. Prepare environment files

```bash
cd /opt/greenbrain-platform/client-runtime

# Backend config
cp env/backend.env.template env/backend.env
# Edit backend.env — set a strong POSTGRES_PASSWORD
nano env/backend.env

# Frontend config
cp env/frontend.env.template env/frontend.env
# Edit frontend.env — set VITE_API_BASE_URL to the machine's address
# Example: VITE_API_BASE_URL=http://192.168.1.100:8000
nano env/frontend.env
```

### 2. Start the stack

```bash
docker-compose -f docker/docker-compose.yml up -d
```

### 3. Verify

```bash
# Backend health
curl http://localhost:8000/health
# Expected: {"status": "ok"}

# Frontend
open http://localhost:8080
```

---

## Frontend auth client-runtime

Il frontend client-runtime usa auth locale via backend:

- `POST /api/v1/auth/setup`
- `POST /api/v1/auth/login`
- `GET /api/v1/auth/me`

Non richiede variabili Supabase.

Per la validazione locale usare:

- backend host: `8001`
- frontend host: `8081`

Credenziali demo:

- email: `admin@greenbrain.local`
- password: `Admin12345!`

Riferimento operativo:

- `client-runtime/docs/client-demo-runbook.md`

---

## ⚠️ WAVE 7 — Schema migration required

A fresh PostgreSQL instance has no schema. Before the backend can serve data, the schema
must be applied. Wave 7 will provide a migration runner.

**Placeholder:**
```bash
# Wave 7 will add this step
# psql -h localhost -U greenbrain -d greenbrain -f sql/schema/customer-schema.sql
```

---

## Data directories

| Path | Contents | Notes |
|------|----------|-------|
| `postgres_data` Docker volume | All PostgreSQL data | Survives container restarts |
| `../../apps/backend` | Backend source code | Mounted read-write |
| `../../apps/frontend` | Frontend source code | Mounted read-write |

---

## Stopping and restarting

```bash
# Stop without removing data
docker-compose -f docker/docker-compose.yml stop

# Restart
docker-compose -f docker/docker-compose.yml start

# Full teardown (removes containers but keeps postgres_data volume)
docker-compose -f docker/docker-compose.yml down

# Full teardown including database (DESTRUCTIVE)
docker-compose -f docker/docker-compose.yml down -v
```

---

## Logs

```bash
# All services
docker-compose -f docker/docker-compose.yml logs -f

# Backend only
docker-compose -f docker/docker-compose.yml logs -f backend

# Postgres only
docker-compose -f docker/docker-compose.yml logs -f postgres
```

---

## Updating

```bash
# Pull latest code
git pull

# Restart services to pick up changes
docker-compose -f docker/docker-compose.yml restart backend frontend
```


## Demo mode locale validato

È disponibile una modalità demo locale per validare il client-runtime anche senza dati reali cliente.

Componenti validati:
- PostgreSQL locale client
- backend client JWT locale
- frontend client su porta 8081
- seed demo sintetico
- dense/features/parquet locali

Riferimento operativo:
- `client-runtime/docs/client-demo-runbook.md`

Porte standard demo client:
- PostgreSQL host: `55432`
- Backend host: `8001`
- Frontend host: `8081`

Credenziali demo:
- email: `admin@greenbrain.local`
- password: `Admin12345!`

Nota:
- questa modalità usa dati sintetici demo
- non usa Supabase
- non rappresenta ancora il dataset reale cliente
