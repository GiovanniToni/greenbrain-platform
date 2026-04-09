# Wave 7B.2-C Runbook — Dashboard Reorder Suggestions
> Status: PLANNING WAVE — not yet applied
> DDL file: `client-runtime/sql/schema/wave_7b2c_planned.sql`
> Generated: 2026-03-28

---

## Scope

| Endpoint | View | Status before | Expected after |
|----------|------|---------------|----------------|
| `/api/v1/dashboard/reorder-suggestions` | `dashboard__reorder_suggestions_top` | HTTP 500 — relation does not exist | HTTP 200 `{"count":0,"items":[]}` |

**This is the smallest possible micro-wave: 1 view, 0 new tables, 0 functions.**

---

## Dependency analysis

### dashboard.py endpoint (lines 56–78)

Plain SQL query — no RPC:
```sql
SELECT famiglia, fascia_prezzo_iva_inc, categoria_corretta, fascia_corretta,
       pot_sizes_text, qty_giacenza, qty_da_ordinare,
       rischio_stockout_prima_di_arrivo, demand_lead, demand_cycle, in_assortimento
FROM dashboard__reorder_suggestions_top
ORDER BY rischio_stockout_prima_di_arrivo DESC, qty_da_ordinare DESC, qty_giacenza ASC
LIMIT :limit
```

### View dependency chain

```
dashboard__reorder_suggestions_top  (VIEW — this wave)
  └── greenhouse_order_suggestions_enriched_v2  [Wave 7B.2-B ✅]
        ├── greenhouse_order_suggestions_v2      [Wave 7B.2-B ✅]
        └── greenhouse_sales_family_meta_v2      [Wave 7B.2-B ✅]
```

**All dependencies already exist.** Nothing else needed.

### Expected behaviour with empty data

`greenhouse_order_suggestions_enriched_v2` already has a `WHERE qty_da_ordinare >= 1`
clause. With empty backing tables it returns 0 rows.
`dashboard__reorder_suggestions_top` adds a second `WHERE coalesce(qty_da_ordinare,0) > 0`
filter then `LIMIT 200`. Result: 0 rows → HTTP 200 `{"count": 0, "items": []}`.

---

## Object count

| Type | Count | Object |
|------|-------|--------|
| VIEW | 1 | `dashboard__reorder_suggestions_top` |
| **Total** | **1** | |

---

## Read-only inspection commands (run before applying)

```bash
cd /opt/greenbrain-platform

# 1. Confirm planned DDL is correct
wc -l client-runtime/sql/schema/wave_7b2c_planned.sql
grep -c "^CREATE OR REPLACE VIEW" client-runtime/sql/schema/wave_7b2c_planned.sql
# Expected: 1 view

# 2. No forbidden patterns
grep -iE "extension|auth\.|storage\.|WITH SCHEMA|FUNCTION|PROCEDURE" \
  client-runtime/sql/schema/wave_7b2c_planned.sql | grep -v "^\s*--" \
  || echo "CLEAN"

# 3. Confirm prerequisite view already exists in client-runtime postgres
docker exec docker_postgres_1 psql -U greenbrain -d greenbrain -t -c "
  SELECT table_name FROM information_schema.views
  WHERE table_schema='public'
    AND table_name = 'greenhouse_order_suggestions_enriched_v2';
"
# Expected: 1 row

# 4. Confirm target view does NOT yet exist (precondition)
docker exec docker_postgres_1 psql -U greenbrain -d greenbrain -t -c "
  SELECT table_name FROM information_schema.views
  WHERE table_schema='public'
    AND table_name = 'dashboard__reorder_suggestions_top';
"
# Expected: 0 rows

# 5. Confirm the endpoint is currently 500
curl -s -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:8000/api/v1/dashboard/reorder-suggestions?limit=5"
# Expected: 500
```

---

## Step-by-step apply

### Step 1 — Install as init script

```bash
cp /opt/greenbrain-platform/client-runtime/sql/schema/wave_7b2c_planned.sql \
   /opt/greenbrain-platform/client-runtime/sql/init/05_schema_7b2c.sql

ls -lh /opt/greenbrain-platform/client-runtime/sql/init/
# Expected (in order):
#   01_bootstrap.sql
#   02_schema_7b1.sql
#   03_schema_7b2a.sql
#   04_schema_7b2b.sql
#   05_schema_7b2c.sql
```

### Step 2 — Clean boot

```bash
cd /opt/greenbrain-platform/client-runtime/docker

docker-compose -f docker-compose.yml down
docker volume rm docker_postgres_data
docker-compose -f docker-compose.yml up -d
```

### Step 3 — Verify postgres ran all 5 init scripts

```bash
docker logs docker_postgres_1 2>&1 | grep -E "running.*sql|ERROR|FATAL"
# Expected: 5 "running" lines, zero ERROR/FATAL
```

### Step 4 — Verify view created

```bash
docker exec docker_postgres_1 psql -U greenbrain -d greenbrain -t -c "
  SELECT table_name FROM information_schema.views
  WHERE table_schema='public'
    AND table_name = 'dashboard__reorder_suggestions_top';
"
# Expected: 1 row

docker exec docker_postgres_1 psql -U greenbrain -d greenbrain -t -c "
  SELECT count(*) FROM public.dashboard__reorder_suggestions_top;
"
# Expected: 0 (empty — no data yet)
```

### Step 5 — Validate target endpoint

```bash
BASE="http://127.0.0.1:8000"

echo "=== target endpoint ==="
curl -s "$BASE/api/v1/dashboard/reorder-suggestions?limit=5"
# Expected: {"count":0,"items":[]}

echo ""
echo "=== HTTP code ==="
curl -s -o /dev/null -w "%{http_code}" \
  "$BASE/api/v1/dashboard/reorder-suggestions?limit=5"
# Expected: 200
```

### Step 6 — Regression checks

```bash
BASE="http://127.0.0.1:8000"

for url in \
  "$BASE/api/v1/analytics/stock-and-reorder?entity_type=famiglia&entity_key=test" \
  "$BASE/api/v1/analytics/range-totals?entity_type=famiglia&entity_key=test&date_from=2025-01-01&date_to=2025-12-31" \
  "$BASE/api/v1/analytics/components?entity_type=famiglia&entity_key=test" \
  "$BASE/api/v1/catalog/search?term=te" \
  "$BASE/api/v1/dashboard/sales-weekly" \
  "$BASE/api/v1/analytics/series?entity_type=famiglia&granularity=day&entity_key=test&date_from=2025-01-01&date_to=2025-12-31"; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  echo "  $CODE  ${url##*/api/v1/}"
done
# Expected: all 200

# Shadow and live stacks untouched
curl -s http://localhost:8001/health | python3 -c "import json,sys; print('shadow:', json.load(sys.stdin)['status'])"
docker ps --filter name=gb_v2 --format "{{.Names}}: {{.Status}}" | head -3
```

---

## Rollback

```bash
cd /opt/greenbrain-platform/client-runtime/docker

docker-compose -f docker-compose.yml down
rm /opt/greenbrain-platform/client-runtime/sql/init/05_schema_7b2c.sql
docker volume rm docker_postgres_data
docker-compose -f docker-compose.yml up -d

# Confirm rollback
curl -s -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:8000/api/v1/dashboard/reorder-suggestions?limit=5"
# Expected: 500 (view gone)
```

No changes to `apps/`, live stack, or shadow stack.

---

## Validation checklist

| # | Check | Expected |
|---|-------|----------|
| 1 | `dashboard__reorder_suggestions_top` view exists | `SELECT count(*) = 0` from it |
| 2 | `/dashboard/reorder-suggestions` | HTTP 200 `{"count":0,"items":[]}` |
| 3 | `/analytics/stock-and-reorder` still 200 | regression |
| 4 | `/analytics/range-totals` still 200 | regression |
| 5 | `/catalog/search` still 200 | regression |
| 6 | `/dashboard/sales-weekly` still 200 | regression |
| 7 | No ERROR in postgres logs | zero |
| 8 | shadow stack ok | `{"status":"ok"}` |
| 9 | live gb_v2 ok | all Up |

---

## What remains deferred after Wave 7B.2-C

| Endpoint | Missing object | Complexity |
|----------|---------------|------------|
| `/api/v1/analytics/entity-summary` | `core_analytics__entity_hierarchy_tree_v1()` | High — large JSONB plpgsql RPC |
| `/api/v1/analytics/series-breakdown` | `core_analytics__breakdown_*_fp_v2` views (12) + breakdown tables (12) | Medium |
| `/api/v1/analytics/compare-series` | `core_analytics__series_daily_total` view | Medium |
| `/api/v1/analytics/future-windows-stats` | `core_analytics__future_window_stats_v2()` | Low-medium — references existing tables |
| `/api/v1/dashboard/kpis` | `dashboard__kpis_v2()` | High — complex multi-table aggregation RPC |
| `/api/v1/planner/*` | `core_planner__*` RPCs + `t_core_planner__*` tables | High |
| `/api/v1/ops/*` | `ml_ops` schema + tables + views | Medium |

**Next logical micro-wave candidates (lowest effort):**
- **7B.2-D**: `future-windows-stats` — `core_analytics__future_window_stats_v2()` references
  `greenhouse_forecast_results_v2` (✅ already exists). Likely 1 function + 0 new tables.
- **7B.2-E**: `compare-series` — `core_analytics__series_daily_total` is a join view;
  needs inspection but probably references existing `_lc` tables.
- **7B.2-F**: `series-breakdown` — 12 breakdown tables + 12 views, same pattern as 7B.1 series.

---

## Cumulative endpoint status after this wave

| Wave | Endpoints green | Total green |
|------|----------------|-------------|
| 7A | 4 + 1 tolerant | 5 |
| 7B.1 | +27 | 32 |
| 7B.2-A | +3 (catalog) | 35 |
| 7B.2-B | +2 (range-totals, stock-and-reorder) | 37 |
| 7B.2-C | +1 (reorder-suggestions) | **38** |
| Deferred | ~20 remaining | — |
