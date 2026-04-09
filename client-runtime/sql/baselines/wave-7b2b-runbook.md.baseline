# Wave 7B.2-B Runbook — Analytics Functions: range-totals + stock-and-reorder
> Status: PLANNING WAVE — not yet applied
> DDL file: `client-runtime/sql/schema/wave_7b2b_planned.sql`
> Generated: 2026-03-28

---

## Why /api/v1/analytics/components is already HTTP 200

**No action required for this endpoint.**

`analytics.py` lines 384–416 query `core_analytics__components_articles` directly
with plain SQL (no RPC). That view was created in **Wave 7B.2-A**
(`greenhouse_products_normalized` → `core_analytics__components_articles`).

The endpoint was never schema-blocked — it just needed the view that 7B.2-A delivered.

---

## Scope

| Endpoint | RPC | Status before | Expected after |
|----------|-----|---------------|----------------|
| `/api/v1/analytics/range-totals` | `core_analytics__range_totals_v2()` | HTTP 500 | HTTP 200 empty |
| `/api/v1/analytics/stock-and-reorder` | `core_analytics__stock_and_reorder_v1()` | HTTP 500 | HTTP 200 `{stock_qty: null, reorder_qty: 0}` |

---

## Dependency analysis

### range-totals — 1 new object only

`core_analytics__range_totals_v2(text, text, date, date)` — `LANGUAGE plpgsql STABLE`

All backing views already exist from Wave 7B.1:

```
core_analytics__range_totals_v2
  → core_analytics__series_daily_famiglia_lc    [Wave 7B.1 ✅]
  → core_analytics__series_daily_categoria_lc   [Wave 7B.1 ✅]
  → core_analytics__series_daily_fascia_lc      [Wave 7B.1 ✅]
  → core_analytics__series_daily_fascia_prezzo_lc [Wave 7B.1 ✅]
```

**Zero new backing objects — function registration only.**

**ARTICOLO branch:** the function body contains an internal branch for
`entity_type='articolo'` that references `core_analytics__article_sales_daily`.
- The backend calls `_resolve_entity()` before invoking the RPC which raises HTTP 400
  for 'articolo' — the branch is **never reachable from the API**.
- `plpgsql` validates SQL per-branch at execution time, not at `CREATE FUNCTION` time.
  The function registers successfully without `core_analytics__article_sales_daily`.
- `core_analytics__article_sales_daily` is **deferred to a later wave**.

### stock-and-reorder — 9 new objects

Full dependency chain, in creation order:

| Step | Object | Type | Backed by | Status |
|------|--------|------|-----------|--------|
| 1 | `greenhouse_stock_raw_upload` | TABLE | — | **new** |
| 2 | `greenhouse_stock_enriched` | VIEW | `greenhouse_stock_raw_upload` + `greenhouse_products_normalized` ✅ | **new** |
| 3 | `greenhouse_forecast_windows_v2` | VIEW | `greenhouse_forecast_results_v2` ✅ | **new** |
| 4 | `greenhouse_stock_family_latest_v2` | VIEW | `greenhouse_stock_enriched` | **new** |
| 5 | `greenhouse_sales_family_daily_fact` | TABLE | — | **new** |
| 6 | `greenhouse_sales_family_meta_v2` | VIEW | `greenhouse_sales_family_daily_fact` | **new** |
| 7 | `greenhouse_order_suggestions_v2` | VIEW | `greenhouse_forecast_windows_v2` + `greenhouse_stock_family_latest_v2` | **new** |
| 8 | `greenhouse_order_suggestions_enriched_v2` | VIEW | `greenhouse_order_suggestions_v2` + `greenhouse_sales_family_meta_v2` | **new** |
| 9 | `core_analytics__stock_and_reorder_v1` | FUNCTION (plpgsql) | objects 1–8 above | **new** |

Chain terminates at existing objects:
- `greenhouse_forecast_results_v2` — Wave 7B.1 ✅
- `greenhouse_products_normalized` — Wave 7B.2-A ✅

No new extensions. No matviews. No Supabase-specific syntax.

**Expected behaviour with empty tables:**
- `greenhouse_stock_raw_upload` empty → `max(data_rilevazione)` = NULL → `stock_qty = null`
- `greenhouse_order_suggestions_enriched_v2` empty → `sum(qty_da_ordinare)` = NULL → `coalesce(..., 0)` = 0
- Function returns `{stock_qty: null, reorder_qty: 0}` — HTTP 200, not 500.

---

## Total Wave 7B.2-B object count

| Type | Count | Objects |
|------|-------|---------|
| TABLE | 2 | `greenhouse_stock_raw_upload`, `greenhouse_sales_family_daily_fact` |
| VIEW | 6 | `stock_enriched`, `forecast_windows_v2`, `stock_family_latest_v2`, `sales_family_meta_v2`, `order_suggestions_v2`, `order_suggestions_enriched_v2` |
| FUNCTION | 2 | `core_analytics__range_totals_v2`, `core_analytics__stock_and_reorder_v1` |
| **Total** | **10** | |

---

## Read-only inspection commands (run before applying)

```bash
SCHEMA="sql/schema/current-schema.sql"
cd /opt/greenbrain-platform

# 1. Confirm planned DDL exists and has correct object counts
wc -l client-runtime/sql/schema/wave_7b2b_planned.sql
grep -c "^CREATE TABLE"                    client-runtime/sql/schema/wave_7b2b_planned.sql
grep -c "^CREATE OR REPLACE VIEW"          client-runtime/sql/schema/wave_7b2b_planned.sql
grep -c "^CREATE OR REPLACE FUNCTION"      client-runtime/sql/schema/wave_7b2b_planned.sql
# Expected: 2 tables, 6 views, 2 functions

# 2. Confirm no forbidden patterns
grep -iE "extension|auth\.|storage\.|WITH SCHEMA|OWNED BY" \
  client-runtime/sql/schema/wave_7b2b_planned.sql | grep -v "^--" | grep -v "^\s*--" \
  || echo "CLEAN"

# 3. Confirm all prerequisite objects already exist in client-runtime postgres
docker exec docker_postgres_1 psql -U greenbrain -d greenbrain -t -c "
  SELECT tablename FROM information_schema.tables
  WHERE table_schema='public'
    AND tablename IN ('greenhouse_forecast_results_v2','greenhouse_products_normalized');
"
# Expected: both rows present

docker exec docker_postgres_1 psql -U greenbrain -d greenbrain -t -c "
  SELECT viewname FROM information_schema.views
  WHERE table_schema='public'
    AND viewname LIKE 'core_analytics__series_daily_%_lc';
"
# Expected: 4 rows (famiglia, categoria, fascia, fascia_prezzo)

# 4. Confirm the two target RPCs do NOT yet exist (precondition)
docker exec docker_postgres_1 psql -U greenbrain -d greenbrain -t -c "
  SELECT proname FROM pg_proc
  JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
  WHERE nspname='public'
    AND proname IN ('core_analytics__range_totals_v2','core_analytics__stock_and_reorder_v1');
"
# Expected: 0 rows (not yet created)

# 5. Review the planned DDL (no apply yet)
head -60 client-runtime/sql/schema/wave_7b2b_planned.sql
```

---

## Step-by-step apply

### Step 1 — Install as init script

```bash
cp /opt/greenbrain-platform/client-runtime/sql/schema/wave_7b2b_planned.sql \
   /opt/greenbrain-platform/client-runtime/sql/init/04_schema_7b2b.sql

ls -lh /opt/greenbrain-platform/client-runtime/sql/init/
# Expected (in order):
#   01_bootstrap.sql
#   02_schema_7b1.sql
#   03_schema_7b2a.sql
#   04_schema_7b2b.sql
```

### Step 2 — Clean boot

```bash
cd /opt/greenbrain-platform/client-runtime/docker

docker-compose -f docker-compose.yml down
docker volume rm docker_postgres_data
docker-compose -f docker-compose.yml up -d
```

### Step 3 — Verify postgres ran all init scripts

```bash
docker logs docker_postgres_1 2>&1 | grep -E "running.*sql|ERROR|FATAL"
# Expected: 4 "running" lines, zero ERROR/FATAL
```

### Step 4 — Verify new objects created

```bash
docker exec docker_postgres_1 psql -U greenbrain -d greenbrain -t -c "
SELECT
  (SELECT count(*) FROM information_schema.tables
   WHERE table_schema='public'
     AND tablename IN (
       'greenhouse_stock_raw_upload',
       'greenhouse_sales_family_daily_fact'
     )) AS new_tables,
  (SELECT count(*) FROM information_schema.views
   WHERE table_schema='public'
     AND viewname IN (
       'greenhouse_stock_enriched',
       'greenhouse_forecast_windows_v2',
       'greenhouse_stock_family_latest_v2',
       'greenhouse_sales_family_meta_v2',
       'greenhouse_order_suggestions_v2',
       'greenhouse_order_suggestions_enriched_v2'
     )) AS new_views,
  (SELECT count(*) FROM pg_proc
   JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
   WHERE nspname='public'
     AND proname IN (
       'core_analytics__range_totals_v2',
       'core_analytics__stock_and_reorder_v1'
     )) AS new_functions;
"
# Expected: new_tables=2, new_views=6, new_functions=2
```

### Step 5 — Validate target endpoints

```bash
BASE="http://127.0.0.1:8000"

echo "=== range-totals (should be 200 empty) ==="
curl -s "$BASE/api/v1/analytics/range-totals?entity_type=famiglia&entity_key=test&date_from=2025-01-01&date_to=2025-12-31"
# Expected: {} (empty row) or {"qty_tot":0,"imp_tot":0,"days":0,...}

echo "=== stock-and-reorder (should be 200 with null+0) ==="
curl -s "$BASE/api/v1/analytics/stock-and-reorder?entity_type=famiglia&entity_key=test"
# Expected: {"stock_qty":null,"reorder_qty":0}

echo "=== components still 200 (regression check) ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/api/v1/analytics/components?entity_type=famiglia&entity_key=test")
echo "components: $CODE"
# Expected: 200

echo "=== Tier 2 endpoints still 200 (regression check) ==="
for url in \
  "$BASE/api/v1/catalog/families?limit=5" \
  "$BASE/api/v1/analytics/series?entity_type=famiglia&granularity=day&entity_key=test&date_from=2025-01-01&date_to=2025-12-31" \
  "$BASE/api/v1/dashboard/sales-weekly" \
  "$BASE/api/v1/catalog/search?term=te" \
  "$BASE/api/v1/catalog/list?entity_type=famiglia"; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  echo "  $CODE  ${url##*/api/v1/}"
done
# Expected: all 200
```

### Step 6 — Stack isolation check

```bash
curl -s http://localhost:8001/health | python3 -c "import json,sys; print('shadow:', json.load(sys.stdin)['status'])"
docker ps --filter name=gb_v2 --format "{{.Names}}: {{.Status}}" | head -6
# Expected: shadow ok, all gb_v2 Up
```

---

## Rollback

Wave 7B.2-B is fully reversible — all changes are in the init file and data volume.

```bash
cd /opt/greenbrain-platform/client-runtime/docker

# 1. Stop stack
docker-compose -f docker-compose.yml down

# 2. Remove init file
rm /opt/greenbrain-platform/client-runtime/sql/init/04_schema_7b2b.sql

# 3. Remove data volume
docker volume rm docker_postgres_data

# 4. Restart with previous wave files only
docker-compose -f docker-compose.yml up -d

# 5. Confirm rollback
curl -s http://127.0.0.1:8000/health
# Expected: {"status":"ok"}

docker exec docker_postgres_1 psql -U greenbrain -d greenbrain -t -c "
  SELECT count(*) FROM pg_proc
  JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
  WHERE nspname='public'
    AND proname IN ('core_analytics__range_totals_v2','core_analytics__stock_and_reorder_v1');
"
# Expected: 0 (functions gone)
```

No changes to `apps/`, live stack, or shadow stack.

---

## Validation checklist

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | New tables exist | psql tables query above | `new_tables=2` |
| 2 | New views exist | psql views query above | `new_views=6` |
| 3 | New functions exist | psql functions query above | `new_functions=2` |
| 4 | range-totals | `curl .../analytics/range-totals?...` | HTTP 200 |
| 5 | stock-and-reorder | `curl .../analytics/stock-and-reorder?...` | HTTP 200 `{stock_qty:null,reorder_qty:0}` |
| 6 | components still 200 | `curl .../analytics/components?...` | HTTP 200 (regression) |
| 7 | catalog/* still 200 | `curl .../catalog/search?term=te` etc | HTTP 200 (regression) |
| 8 | Tier 2 series still 200 | `curl .../analytics/series?...` | HTTP 200 (regression) |
| 9 | No ERROR in postgres logs | `docker logs ... \| grep ERROR` | zero |
| 10 | shadow stack ok | `curl http://localhost:8001/health` | `{"status":"ok"}` |
| 11 | live gb_v2 ok | `docker ps --filter name=gb_v2` | all Up |

---

## What remains deferred after Wave 7B.2-B

| Endpoint | Missing object | Notes |
|----------|---------------|-------|
| `/api/v1/analytics/entity-summary` | `core_analytics__entity_hierarchy_tree_v1()` | Complex JSONB plpgsql RPC, large function |
| `/api/v1/analytics/series-breakdown` | `core_analytics__breakdown_*_fp_v2` views + 12 breakdown tables | Medium — same pattern as series but with fascia_prezzo dimension |
| `/api/v1/analytics/compare-series` | `core_analytics__series_daily_total` view | Join of daily fact + hierarchy |
| `/api/v1/analytics/future-windows-stats` | `core_analytics__future_window_stats_v2()` | References `greenhouse_forecast_results_v2` ✅ — moderate complexity |
| `/api/v1/analytics/range-totals` (articolo branch) | `core_analytics__article_sales_daily` | API blocks 'articolo' — deferred |
| `/api/v1/dashboard/kpis` | `dashboard__kpis_v2()` | Complex multi-table aggregation RPC |
| `/api/v1/dashboard/reorder-suggestions` | `dashboard__reorder_suggestions_top` view | References `greenhouse_order_suggestions_enriched_v2` ✅ — potentially quick |
| `/api/v1/planner/*` | `core_planner__*` RPCs + `t_core_planner__*` tables | Complex planner schema |
| `/api/v1/ops/*` | `ml_ops` schema + tables | Separate ml_ops schema |

**Note on `/api/v1/dashboard/reorder-suggestions`:** this view references
`greenhouse_order_suggestions_enriched_v2` which is now created by this wave.
It may require only the view + the dashboard RPC — candidate for a very small Wave 7B.2-C.

---

## Cumulative endpoint status after this wave

| Wave | Endpoints green | Total green |
|------|----------------|-------------|
| 7A | 4 (health + system) + 1 tolerant | 5 |
| 7B.1 | +27 (series, forecast, dashboard sales, seasonality, catalog/families) | 32 |
| 7B.2-A | +3 (catalog/search, catalog/children, catalog/list) | 35 |
| 7B.2-B | +2 (range-totals, stock-and-reorder) | **37** |
| Deferred | 21 remaining | — |
