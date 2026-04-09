# DB Object Inventory — Wave 7B
> Complete mapping of every backend endpoint to its required DB objects.
> Source: manual inspection of apps/backend/app/api/v1/*.py + sql/schema/current-schema.sql
> Generated: 2026-03-28.

---

## Architecture note

The backend does NOT query raw sales tables directly.
It queries **pre-aggregated analytics tables** (`t_core_analytics__*`, `t_dashboard_*`, `t_core_planner__*`)
through **thin SQL views** (`core_analytics__series_*_lc`, etc.) and **PostgreSQL functions**.

```
Raw sales tables           Pre-aggregated tables           Views / Functions       Backend endpoints
(populated by ML)     →   (refreshed by pipeline)   →    (schema objects)     →  (FastAPI routes)

greenhouse_sales_raw  →   t_core_analytics__series_*  →  core_analytics__series_*_lc  →  /analytics/series
                      →   t_core_analytics__breakdown_* → core_analytics__breakdown_*  →  /analytics/series-breakdown
                      →   t_dashboard_sales_*          →  dashboard__sales_*           →  /dashboard/sales-*
                      →   t_core_planner__*            →  core_planner__*()            →  /planner/*
greenhouse_forecast_* →   (direct table)              →  greenhouse_forecast_*_v2     →  /forecast/*
                                                       →  core_analytics__range_totals_v2() → /analytics/range-totals
```

**For Wave 7B:** create all tables as empty stubs → views compile → endpoints return HTTP 200 with empty data.
No raw data or ML output needed for schema correctness.

---

## Group 1 — Infrastructure (no schema)

Already working in Wave 7A.

| Endpoint | SQL used | Schema needed |
|----------|----------|---------------|
| GET /health | `SELECT 1` | none |
| GET /health/db | `SELECT 1 AS ok` | none |
| GET /api/v1/system/info | none | none |
| GET /api/v1/system/db-info | `SELECT version()`, `SELECT current_database()` | none |

---

## Group 2 — Base schemas

Must exist before any tables in those schemas.

| Schema | Used by |
|--------|---------|
| `public` | exists by default |
| `ml_ops` | ops endpoints |
| `etl` | ops pipeline monitoring |
| `ml_forecast` | ML registry tables |
| `ml_diag` | diagnostic materialized views |

---

## Group 3 — Pre-aggregated analytics tables (direct data sources)

These are the real data sources for the backend. Created empty → views work → endpoints return 200 empty.

### Series tables (4 granularities × 4 entity types = 16 tables)
| Table | Used by views |
|-------|--------------|
| `t_core_analytics__series_daily_famiglia` | `core_analytics__series_daily_famiglia_lc` |
| `t_core_analytics__series_daily_categoria` | `core_analytics__series_daily_categoria_lc` |
| `t_core_analytics__series_daily_fascia` | `core_analytics__series_daily_fascia_lc` |
| `t_core_analytics__series_daily_fascia_prezzo` | `core_analytics__series_daily_fascia_prezzo_lc` |
| `t_core_analytics__series_weekly_*` (×4) | weekly series views |
| `t_core_analytics__series_monthly_*` (×4) | monthly series views |
| `t_core_analytics__series_yearly_*` (×4) | yearly series views |

### Breakdown tables (3 granularities × 3 entity types = 12+ tables, _v2 variants)
| Table | Used by views |
|-------|--------------|
| `t_core_analytics__breakdown_daily_famiglia_fp_v2` | `core_analytics__breakdown_daily_famiglia_fp_v2` |
| `t_core_analytics__breakdown_daily_categoria_fp_v2` | breakdown categoria view |
| `t_core_analytics__breakdown_daily_fascia_fp_v2` | `mv_core_analytics__breakdown_daily_fascia_fp` (mat view) |
| `t_core_analytics__breakdown_{weekly,monthly,yearly}_{famiglia,categoria,fascia}_fp_v2` | (×9 more) |

### Other analytics tables
| Table | Used by |
|-------|---------|
| `t_core_analytics__seasonality_month` | `core_analytics__seasonality_month` view |
| `t_core_analytics__breakdown_yearly_*` (×6) | yearly breakdown views |

### Dashboard tables
| Table | Used by |
|-------|---------|
| `t_dashboard_sales_daily` | `dashboard__sales_daily` view |
| `t_dashboard_sales_weekly` | `dashboard__sales_weekly` view |
| `t_dashboard_sales_monthly` | `dashboard__sales_monthly` view |
| `t_dashboard_sales_yearly` | `dashboard__sales_yearly` view |

### Planner tables
| Table | Used by |
|-------|---------|
| `t_core_planner__assortment_calendar` | `/planner/assortment-calendar-export` direct query |
| `t_core_planner__heat_cells` | `core_planner__get_heatmap_cells()` RPC |
| `t_core_planner__space_budget` | `core_planner__get_space_budget()` RPC |
| `t_core_planner__fact_weekly` | planner RPCs |
| `t_core_planner__params_level` | planner RPCs |
| `t_core_planner__potsize_profile` | planner RPCs |
| `t_core_planner__density` | planner RPCs |
| `t_core_planner__orchestrator_state` | planner RPCs |
| `t_core_planner__refresh_state` | planner RPCs |
| `t_forecast_fam_daily` | planner RPCs |
| `t_ops_pipeline_monitor` | `v_ops_pipeline_status` view |

### Forecast table (direct table, populated by ML)
| Table | Used by |
|-------|---------|
| `greenhouse_forecast_results_v2` | `/forecast/*`, `/analytics/future-windows`, `core_analytics__future_window_stats_v2()` |

### Catalog table
| Table | Used by |
|-------|---------|
| `famiglie_catalog_static` | `/catalog/families` direct query |
| `greenhouse_products_normalized` | catalog RPCs, breakdown views |

### Ops tables (ml_ops schema)
| Table | Used by |
|-------|---------|
| `ml_ops.pipeline_run_log_v1` | `ml_ops.v_pipeline_runs_recent_v1`, `ml_ops.v_daily_pipeline_summary_v1` |
| `ml_ops.family_run_log_v1` | `/ops/family-runs` direct query |

---

## Group 4 — Views (depend on Group 3 tables)

### Series views — thin wrappers with `_lc` suffix (lowercase normalisation)
- `core_analytics__series_{daily,weekly,monthly,yearly}_{famiglia,categoria,fascia,fascia_prezzo}_lc` (16 views)
- Used by: `/analytics/series`, `/analytics/series-bounds`

### Breakdown views
- `core_analytics__breakdown_{daily,weekly,monthly,yearly}_{famiglia,categoria,fascia}_fp_v2` (12 views)
- Used by: `/analytics/series`, `/analytics/series-breakdown`

### Other analytics views
- `core_analytics__series_daily_total` — has columns `famiglia`, `categoria_corretta`, `fascia_corretta`, `qty_venduta_tot`, `qty_forecast_tot`; used by `/analytics/compare-series`
- `core_analytics__components_articles` — columns: `codart`, `articolo_nome`, `pot_size`, `fascia_prezzo_iva_inc`, `prezzo_iva_inclusa`; used by `/analytics/components`
- `core_analytics__seasonality_month` — view on `t_core_analytics__seasonality_month`; used by `/analytics/seasonality`

### Dashboard views
- `dashboard__sales_weekly` — columns: `data, imp_tot`
- `dashboard__sales_monthly` — columns: `data, imp_tot`
- `dashboard__sales_yearly` — columns: `data, imp_tot`
- `dashboard__reorder_suggestions_top` — complex join; used by `/dashboard/reorder-suggestions`

### Planner / order views
- `greenhouse_order_suggestions_enriched_v2` — used by `/planner/order-suggestions`, `/planner/assortment`

### Ops views
- `public.v_ops_pipeline_status` — wraps `t_ops_pipeline_monitor`; used by `/ops/health`
- `ml_ops.v_daily_pipeline_summary_v1` — wraps `ml_ops.pipeline_run_log_v1`; used by `/ops/health`
- `ml_ops.v_pipeline_runs_recent_v1` — wraps `ml_ops.pipeline_run_log_v1`; used by `/ops/pipeline-status`

---

## Group 5 — Functions / RPCs (most complex — plpgsql stored procedures)

| Function | Returns | Used by | Complexity |
|----------|---------|---------|------------|
| `core_analytics__range_totals_v2(entity_type, entity_key, date_from, date_to)` | TABLE | `/analytics/range-totals` | medium |
| `core_analytics__entity_hierarchy_tree_v1(...)` | jsonb | `/analytics/entity-summary` | high |
| `core_analytics__stock_and_reorder_v1(entity_type, entity_key, fascia_prezzo)` | TABLE | `/analytics/stock-and-reorder` | medium |
| `core_analytics__future_window_stats_v2(entity_type, entity_key, anchor_to, windows int[])` | TABLE | `/analytics/future-windows-stats` | medium |
| `core_analytics__search_catalog_rich(term, limit_n)` | TABLE | `/catalog/search` | medium |
| `core_analytics__catalog_children(level, fascia, categoria, famiglia, fascia_prezzo, limit)` | TABLE | `/catalog/children` | medium |
| `core_analytics__list_catalog(entity_type, limit)` | TABLE | `/catalog/list` | medium |
| `dashboard__kpis_v2()` | TABLE | `/dashboard/kpis` | high |
| `core_planner__get_space_budget(mode, level)` | jsonb | `/planner/space-budget` | high |
| `core_planner__get_current_week52()` | jsonb | `/planner/current-week` | low |
| `core_planner__get_assortment_calendar(mode, level)` | jsonb | `/planner/assortment-calendar` | high |
| `core_planner__get_heatmap_nodes(mode)` | jsonb | `/planner/heatmap-nodes` | high |
| `core_planner__get_heatmap_week_ranges(node_ids)` | jsonb | `/planner/heatmap-week-ranges` | high |
| `core_planner__get_heatmap_roll4_ranges(node_ids)` | jsonb | `/planner/heatmap-roll4-ranges` | high |
| `core_planner__get_heatmap_cells(mode, node_ids)` | jsonb | `/planner/heatmap-cells` | high |
| `rpc_heatmap_week_pivot(metric)` | TABLE | `/planner/heatmap-week-pivot` | high |

---

## Group 6 — Tolerant endpoints (already handle missing schema gracefully)

| Endpoint | Table | Behaviour on missing table |
|----------|-------|---------------------------|
| GET /planner/calendar-events | `calendar_events` | Returns `{"count": 0, "items": []}` — `ProgrammingError` caught in code |

---

## Group 7 — Not needed for client-runtime (deferred / out of scope)

| Schema | Reason |
|--------|--------|
| `auth.*` | Supabase auth — not applicable |
| `storage.*` | Supabase storage — not applicable |
| `realtime.*` | Supabase realtime — not applicable |
| `vault.*` | Supabase vault — not applicable |
| `graphql.*` | Supabase GraphQL — not applicable |
| `pgbouncer.*` | Supabase internal — not applicable |
| `ml_diag.*` materialized views | ML diagnostics — not a backend dependency |

---

## Wave 7B scope: what gets done

| Group | Action | Result |
|-------|--------|--------|
| 1 | already working | HTTP 200 |
| 2 | extract + apply CREATE SCHEMA | schemas ready |
| 3 | extract + apply CREATE TABLE | empty stubs ready |
| 4 | extract + apply CREATE VIEW | HTTP 200 empty arrays |
| 5 | extract + apply functions | HTTP 200 empty/null returns |
| 6 | already tolerant | HTTP 200 empty |
| 7 | skip | not applicable |

## Wave 7B known risks

| Risk | Mitigation |
|------|-----------|
| Functions may reference Supabase-specific extensions | Review extracted functions for `auth.`, `vault.`, `pgsodium` references |
| Views may depend on tables not yet created | Apply tables before views; extraction script orders correctly |
| Functions call other functions (dependency order) | `CREATE OR REPLACE FUNCTION` is idempotent; apply all in one pass |
| `uuid_generate_v4()` or similar — needs `uuid-ossp` extension | Add `CREATE EXTENSION IF NOT EXISTS "uuid-ossp"` before DDL |
| `pg_trgm` for full-text search in catalog RPCs | Add `CREATE EXTENSION IF NOT EXISTS pg_trgm` before DDL |
