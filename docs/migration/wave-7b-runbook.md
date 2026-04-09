# Wave 7B Runbook — Client-Runtime Minimal Schema Contract
> Status: PLANNING WAVE — no schema applied yet
> Wave 7B.1 DDL: `client-runtime/sql/schema/wave_7b1_planned.sql`
> Endpoint matrix: `client-runtime/sql/schema/endpoint-matrix.md`
> Generated: 2026-03-28

---

## Context and lessons from the failed extraction attempt

An earlier attempt tried to bulk-extract the full Supabase/dev schema into
`client-runtime/sql/init/`. It was stopped after hitting a chain of dependency
failures:

| Failure | Root cause |
|---------|-----------|
| `WITH SCHEMA extensions` | Supabase puts extensions in a dedicated schema — not standard PostgreSQL |
| Sequence `ALTER TABLE ... ADD GENERATED ALWAYS AS IDENTITY` | Ran before the referenced table existed |
| `ml_diag.mv_family_*` matviews | Unresolvable internal dependencies (`_v` intermediate views not captured) |
| `public.mv_core_analytics__*` matviews | Same issue — reference intermediate views excluded by cross-ref filter |
| Views referencing matviews (`mv_famiglie_catalog`, etc.) | Chain dependency: view → matview → intermediate view → table |
| `public.greenhouse_backfill_jobs` missing in function body | Function extracted without checking all referenced relations |

**Conclusion:** The dev/Supabase schema has a layered dependency graph (table →
matview → intermediate view → `_lc` view) that cannot be bulk-extracted without
a topological dependency resolver. Building one is out of scope for Wave 7B.

**Wave 7B approach:** hand-craft a minimal schema containing only the exact
objects the backend endpoints require, pointing directly at the underlying `t_`
tables — bypassing the intermediate matview chain entirely.

---

## Architecture: dev vs client-runtime view chain

```
=== Dev / Supabase (greenbrain-platform) ===

t_core_analytics__series_daily_famiglia
         ↓
mv_core_analytics__series_daily_famiglia   (MATERIALIZED VIEW — refresh pipeline artifact)
         ↓
core_analytics__series_daily_famiglia      (VIEW — thin alias)
         ↓
core_analytics__series_daily_famiglia_lc   (VIEW — applies lower(entity_key))
         ↓
backend endpoint: /analytics/series

=== Client-runtime (Wave 7B.1) ===

t_core_analytics__series_daily_famiglia
         ↓
core_analytics__series_daily_famiglia_lc   (VIEW — applies lower(entity_key), refs t_ directly)
         ↓
backend endpoint: /analytics/series

Query result is identical. The intermediate layers exist for incremental
refresh performance in the dev pipeline, not for query correctness.
```

---

## Wave 7B.1 — Minimal schema contract

**Goal:** Apply 43 hand-crafted objects (23 tables + 20 views) so that 27
additional backend endpoints return HTTP 200 with empty data instead of HTTP 500.

**Scope:**
- All objects in `public` schema
- No extensions required (pure standard PostgreSQL DDL)
- No RPCs / stored functions
- No cross-schema references
- No matviews
- Single self-contained SQL file: `client-runtime/sql/schema/wave_7b1_planned.sql`

### 7B.1 objects

| Section | Object type | Count | Description |
|---------|-------------|-------|-------------|
| 1 | TABLE | 1 | `famiglie_catalog_static` |
| 2 | TABLE | 1 | `greenhouse_forecast_results_v2` |
| 3 | TABLE | 4 | `t_core_analytics__series_daily_{famiglia,categoria,fascia,fascia_prezzo}` |
| 4 | TABLE | 4 | `t_core_analytics__series_weekly_{...}` (same pattern) |
| 5 | TABLE | 4 | `t_core_analytics__series_monthly_{...}` |
| 6 | TABLE | 4 | `t_core_analytics__series_yearly_{...}` (different schema: entity_key_lc) |
| 7 | TABLE | 3 | `t_dashboard_sales_{weekly,monthly,yearly}` |
| 8 | TABLE | 1 | `t_core_analytics__seasonality_month` |
| 9 | TABLE | 1 | `calendar_events` |
| 10 | VIEW | 4 | `core_analytics__series_daily_{...}_lc` |
| 11 | VIEW | 4 | `core_analytics__series_weekly_{...}_lc` |
| 12 | VIEW | 4 | `core_analytics__series_monthly_{...}_lc` |
| 13 | VIEW | 4 | `core_analytics__series_yearly_{...}_lc` |
| 14 | VIEW | 3 | `dashboard__sales_{weekly,monthly,yearly}` |
| 15 | VIEW | 1 | `core_analytics__seasonality_month` |
| **Total** | | **43** | |

### 7B.1 endpoint outcome

| Before 7B.1 | After 7B.1 |
|-------------|-----------|
| HTTP 500 — UndefinedTable | HTTP 200 — `{"count": 0, "items": []}` |

Endpoints that change from 500 → 200 empty:
- `/api/v1/catalog/families`
- `/api/v1/forecast/summary`, `/forecast/series`, `/forecast/sample`
- `/api/v1/analytics/future-windows`
- `/api/v1/analytics/series` (all granularities × all entity types)
- `/api/v1/analytics/series-bounds`
- `/api/v1/analytics/seasonality`
- `/api/v1/sales/summary`
- `/api/v1/dashboard/sales-weekly`, `/sales-monthly`, `/sales-yearly`

---

## Wave 7B.1 — Step-by-step apply commands

All commands are read-only analysis or apply the planned DDL. No live stack touched.

### Step 0 — Verify current state (read-only)

```bash
# Confirm init/ is still at Wave 7A baseline
ls /opt/greenbrain-platform/client-runtime/sql/init/
# Expected: only 01_bootstrap.sql

# Confirm planned DDL file exists
wc -l /opt/greenbrain-platform/client-runtime/sql/schema/wave_7b1_planned.sql
# Expected: ~320 lines

# Confirm Wave 7A stack is down (user stopped it)
docker ps --filter name=docker_backend --filter name=docker_postgres \
  --format "{{.Names}}: {{.Status}}"
# Expected: no output (containers stopped)
```

### Step 1 — Review the planned DDL before applying (read-only)

```bash
# Count objects in planned DDL
grep -c "^CREATE TABLE"      /opt/greenbrain-platform/client-runtime/sql/schema/wave_7b1_planned.sql
grep -c "^CREATE OR REPLACE" /opt/greenbrain-platform/client-runtime/sql/schema/wave_7b1_planned.sql
# Expected: 23 tables, 20 views

# Check for any extensions, cross-schema refs, or Supabase patterns
grep -iE "extension|auth\.|storage\.|WITH SCHEMA|OWNED BY" \
  /opt/greenbrain-platform/client-runtime/sql/schema/wave_7b1_planned.sql
# Expected: no output (zero forbidden patterns)

# Check for RPC / function definitions
grep "^CREATE.*FUNCTION\|^CREATE.*PROCEDURE" \
  /opt/greenbrain-platform/client-runtime/sql/schema/wave_7b1_planned.sql
# Expected: no output
```

### Step 2 — Install as init script

```bash
cp /opt/greenbrain-platform/client-runtime/sql/schema/wave_7b1_planned.sql \
   /opt/greenbrain-platform/client-runtime/sql/init/02_schema_7b1.sql

ls -lh /opt/greenbrain-platform/client-runtime/sql/init/
# Expected:
#   01_bootstrap.sql   (~900 bytes)
#   02_schema_7b1.sql  (~15 KB)
```

### Step 3 — Clean boot with schema

```bash
cd /opt/greenbrain-platform/client-runtime/docker

# Down + remove data volume (init scripts only run on empty volume)
docker-compose -f docker-compose.yml down
docker volume rm docker_postgres_data

# Up
docker-compose -f docker-compose.yml up -d
```

### Step 4 — Wait for healthchecks

```bash
# Poll until both healthy (up to 90s for schema init)
for i in $(seq 1 18); do
  STATUS=$(docker-compose -f docker-compose.yml ps 2>/dev/null)
  echo "$STATUS"
  echo "$STATUS" | grep -q "unhealthy" && { sleep 5; continue; }
  echo "$STATUS" | grep -qE "starting|health: starting" && { sleep 5; continue; }
  break
done
```

### Step 5 — Validate postgres ran both init scripts

```bash
docker logs docker_postgres_1 2>&1 \
  | grep -E "running.*sql|ERROR|FATAL"
# Expected:
#   running /docker-entrypoint-initdb.d/01_bootstrap.sql
#   running /docker-entrypoint-initdb.d/02_schema_7b1.sql
#   (no ERROR lines)
```

### Step 6 — Validate bootstrap marker

```bash
docker exec docker_postgres_1 \
  psql -U greenbrain -d greenbrain \
  -c "SELECT wave, applied_at FROM _runtime_bootstrap;"
# Expected: 1 row: wave='wave-7a', applied at boot time
```

### Step 7 — Validate schema object counts

```bash
docker exec docker_postgres_1 \
  psql -U greenbrain -d greenbrain -t -c "
    SELECT
      (SELECT count(*) FROM information_schema.tables
       WHERE table_schema='public' AND table_type='BASE TABLE') AS tables,
      (SELECT count(*) FROM information_schema.views
       WHERE table_schema='public') AS views;
"
# Expected: tables ≥ 23, views ≥ 20
```

### Step 8 — Validate endpoints (27 should now return 200)

```bash
BASE="http://127.0.0.1:8000"

echo "=== Tier 0 (unchanged) ==="
curl -s "$BASE/health" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])"
curl -s "$BASE/health/db" | python3 -c "import json,sys; print(json.load(sys.stdin)['database'])"

echo "=== Tier 2 — now 200 ==="
for url in \
  "$BASE/api/v1/catalog/families?limit=5" \
  "$BASE/api/v1/forecast/summary" \
  "$BASE/api/v1/forecast/sample?limit=1" \
  "$BASE/api/v1/analytics/future-windows" \
  "$BASE/api/v1/analytics/series?entity_type=famiglia&granularity=day&entity_key=test&date_from=2025-01-01&date_to=2025-12-31" \
  "$BASE/api/v1/analytics/series?entity_type=famiglia&granularity=week&entity_key=test&date_from=2025-01-01&date_to=2025-12-31" \
  "$BASE/api/v1/analytics/series?entity_type=famiglia&granularity=month&entity_key=test&date_from=2025-01-01&date_to=2025-12-31" \
  "$BASE/api/v1/analytics/series?entity_type=famiglia&granularity=year&entity_key=test&date_from=2020-01-01&date_to=2025-12-31" \
  "$BASE/api/v1/analytics/seasonality?entity_type=famiglia&entity_key=test" \
  "$BASE/api/v1/dashboard/sales-weekly" \
  "$BASE/api/v1/dashboard/sales-monthly" \
  "$BASE/api/v1/dashboard/sales-yearly" \
  "$BASE/api/v1/sales/summary?date_from=2025-01-01&date_to=2025-12-31"; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    echo "  $CODE  ${url##*/api/v1/}"
done
# Expected: all 200

echo "=== Still 500 (deferred to 7B.2) ==="
for url in \
  "$BASE/api/v1/analytics/entity-summary?p_entity_type=famiglia&p_entity_key=test&p_date_from=2025-01-01&p_date_to=2025-12-31" \
  "$BASE/api/v1/analytics/range-totals?entity_type=famiglia&entity_key=test&date_from=2025-01-01&date_to=2025-12-31" \
  "$BASE/api/v1/dashboard/kpis" \
  "$BASE/api/v1/ops/pipeline-status"; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    echo "  $CODE  ${url##*/api/v1/}  ← expected 500 (schema deferred)"
done
```

### Step 9 — Stack isolation check

```bash
# Shadow stack untouched
curl -s http://localhost:8001/health | python3 -c "import json,sys; print('shadow:', json.load(sys.stdin)['status'])"

# Live gb_v2 stack untouched
docker ps --filter name=gb_v2 --format "{{.Names}}: {{.Status}}"
# Expected: all Up
```

---

## Wave 7B.1 — Rollback

Wave 7B.1 is fully reversible.

```bash
# 1. Stop client-runtime stack
cd /opt/greenbrain-platform/client-runtime/docker
docker-compose -f docker-compose.yml down

# 2. Remove schema init file
rm /opt/greenbrain-platform/client-runtime/sql/init/02_schema_7b1.sql

# 3. Remove data volume
docker volume rm docker_postgres_data 2>/dev/null

# 4. Return to Wave 7A state (no schema)
docker-compose -f docker-compose.yml up -d

# 5. Verify Wave 7A health endpoints still work
curl -s http://127.0.0.1:8000/health
# Expected: {"status":"ok"}
```

No changes to `apps/`, live stack, or shadow stack. All rollback is local to
`client-runtime/sql/init/` and the postgres data volume.

---

## Wave 7B.2 — Additional objects (planned, not yet implemented)

Wave 7B.2 extends the schema to cover Tiers 3–5.

### 7B.2 scope

| Group | Objects | Endpoints unlocked |
|-------|---------|-------------------|
| Analytics breakdown tables + views | 12 tables + 12 views | `/analytics/series-breakdown` |
| Analytics RPC functions | ~8 functions | `/analytics/range-totals`, `/analytics/entity-summary`, `/analytics/compare-series`, `/analytics/components`, `/analytics/stock-and-reorder`, `/analytics/future-windows-stats` |
| Catalog RPC functions | 3 functions | `/catalog/search`, `/catalog/children`, `/catalog/list` |
| Dashboard RPC + complex views | 1 function + 2 views | `/dashboard/kpis`, `/dashboard/reorder-suggestions` |
| Planner tables + RPC functions | ~10 tables + ~10 functions | `/planner/*` |
| ml_ops schema + tables + views | 1 schema + 2 tables + 3 views | `/ops/*` |

### 7B.2 approach (to be planned separately)

Wave 7B.2 will be a separate planning cycle. **Do not attempt to bulk-extract
these from the snapshot.** The correct approach is:

1. **Analytics RPCs** — Extract function bodies individually using targeted grep.
   Review each function body for Supabase-specific patterns before applying.
   Use `CREATE OR REPLACE FUNCTION ... LANGUAGE sql` (most are pure SQL, not plpgsql).

2. **Breakdown tables/views** — Follow the same hand-crafted pattern as 7B.1.
   The breakdown tables have additional columns (`fascia_prezzo_iva_inc`) but
   follow the same `t_core_analytics__breakdown_*_fp_v2` → view pattern.

3. **Planner RPCs** — Most complex group. `core_planner__*` functions are long
   plpgsql procedures. Extract and test individually. Note: `core_planner__get_current_week52()`
   is pure date math and the easiest starting point.

4. **ml_ops schema** — Simple: CREATE SCHEMA ml_ops, 2 base tables, 3 thin views.
   All `ml_ops.*` objects are simple enough to hand-craft.

### 7B.2 extraction commands (read-only analysis)

```bash
SCHEMA="sql/schema/current-schema.sql"

# Count RPCs by group
grep "^CREATE.*FUNCTION public\.core_analytics__" "$SCHEMA" | wc -l
grep "^CREATE.*FUNCTION public\.core_planner__" "$SCHEMA" | wc -l
grep "^CREATE.*FUNCTION public\.dashboard__" "$SCHEMA" | wc -l

# Extract a single function for review (example: core_analytics__range_totals_v2)
python3 -c "
import re
content = open('$SCHEMA').read()
blocks = re.split(r'\n(?=--\n-- Name: )', content)
for b in blocks:
    if 'core_analytics__range_totals_v2' in b and 'FUNCTION' in b:
        print(b[:3000])
        break
"

# List breakdown tables
grep "^CREATE TABLE public\.t_core_analytics__breakdown" "$SCHEMA" | awk '{print \$3}'

# Check core_planner__get_current_week52 complexity
python3 -c "
import re
content = open('$SCHEMA').read()
blocks = re.split(r'\n(?=--\n-- Name: )', content)
for b in blocks:
    if 'core_planner__get_current_week52' in b and 'FUNCTION' in b:
        print(b[:2000])
        break
"
```

---

## Validation checklist

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Wave 7A still intact | `ls client-runtime/sql/init/` | `01_bootstrap.sql` + `02_schema_7b1.sql` |
| 2 | No extensions in DDL | `grep -i extension client-runtime/sql/init/02_schema_7b1.sql` | no output |
| 3 | No cross-schema refs | `grep -E "auth\.|storage\.|extensions\." client-runtime/sql/init/02_schema_7b1.sql` | no output |
| 4 | Table count | psql: `SELECT count(*) FROM information_schema.tables WHERE table_schema='public'` | ≥ 23 |
| 5 | View count | psql: `SELECT count(*) FROM information_schema.views WHERE table_schema='public'` | ≥ 20 |
| 6 | /catalog/families | `curl -s .../api/v1/catalog/families \| python3 -c "..."` | HTTP 200 |
| 7 | /forecast/summary | `curl -s .../api/v1/forecast/summary` | HTTP 200 |
| 8 | /analytics/series (day) | `curl -s "...series?entity_type=famiglia&granularity=day..."` | HTTP 200 |
| 9 | /dashboard/sales-weekly | `curl -s .../api/v1/dashboard/sales-weekly` | HTTP 200 |
| 10 | /analytics/seasonality | `curl -s "...seasonality?entity_type=famiglia&entity_key=x"` | HTTP 200 |
| 11 | /dashboard/kpis still 500 | `curl -s -o /dev/null -w "%{http_code}" .../dashboard/kpis` | 500 (expected) |
| 12 | shadow stack ok | `curl -s http://localhost:8001/health` | `{"status":"ok"}` |
| 13 | live gb_v2 ok | `docker ps --filter name=gb_v2` | all Up |

---

## What remains permanently deferred (not Wave 7B at all)

| Item | Reason | Decision needed |
|------|--------|-----------------|
| `auth.*` schema | Supabase auth — replaced by different auth layer at customer site | Frontend wave |
| `storage.*` | Supabase storage — not used by backend API | Product decision |
| `ml_diag.*` matviews | ML diagnostics — no backend endpoint uses them | Never port |
| `mv_core_analytics__*` matviews | Refresh-pipeline artifacts — not in query path | Never port |
| pg_cron refresh jobs | Customer site needs an equivalent scheduler | Ops decision |
| `etl.*` schema | ETL pipeline — separate deployment decision | Data pipeline wave |
| `ml_forecast.*` schema | ML model registry — separate from runtime schema | ML wave |
| `greenhouse_backfill_jobs` table | Used only by backfill functions — not queried by API | Never port |

---

## Files produced in this planning wave

| File | Purpose |
|------|---------|
| `client-runtime/sql/schema/endpoint-matrix.md` | Complete endpoint → DB object mapping with tier classification |
| `client-runtime/sql/schema/object-inventory.md` | Architecture and object group documentation |
| `client-runtime/sql/schema/wave_7b1_planned.sql` | Hand-crafted 43-object minimal DDL (ready to apply) |
| `client-runtime/sql/extract/extract-schema.py` | Extraction script (improved with cross-ref filter, for reference/Wave 7B.2 use) |
| `client-runtime/sql/schema/extraction-report.txt` | What the extractor kept vs skipped from the full snapshot |
| `docs/migration/wave-7b-runbook.md` | This file |

Wave 7B.1 apply step: `cp wave_7b1_planned.sql client-runtime/sql/init/02_schema_7b1.sql`
Wave 7B.1 is ready. Gated on deliberate decision to proceed.
