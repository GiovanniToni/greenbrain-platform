# Endpoint → DB Object Matrix
> Wave 7B planning document. Maps every backend endpoint to its exact DB dependencies
> and classifies it into a schema tier.
> Source: manual inspection of all apps/backend/app/api/v1/*.py files + sql/schema/current-schema.sql
> Generated: 2026-03-28

---

## Tier definitions

| Tier | Name | Description | Target wave |
|------|------|-------------|-------------|
| 0 | Bootstrap-safe | No schema needed — SELECT 1 or app-level only | Wave 7A ✅ |
| 1 | Tolerant | Schema missing → returns empty list, not 500 | Wave 7A ✅ |
| 2 | Simple tables + thin views | Single tables or thin wrapper views; no RPCs | **Wave 7B.1** |
| 3 | Simple RPCs | Pure plpgsql functions reading Tier 2 tables | Wave 7B.2 |
| 4 | Complex analytics | Multi-table views, JSONB RPCs, planner RPCs | Wave 7B.2 |
| 5 | ml_ops schema | Separate schema, ML pipeline monitoring | Wave 7B.2 |

---

## Tier 0 — Bootstrap-safe (Wave 7A, already working)

| Endpoint | Method | DB call | Status |
|----------|--------|---------|--------|
| `/health` | GET | `SELECT 1` | ✅ live |
| `/health/db` | GET | `SELECT 1 AS ok` | ✅ live |
| `/api/v1/system/info` | GET | none (app config) | ✅ live |
| `/api/v1/system/db-info` | GET | `SELECT version()` · `SELECT current_database()` | ✅ live |

---

## Tier 1 — Tolerant (Wave 7A, already safe)

| Endpoint | Method | DB object | Why tolerant |
|----------|--------|-----------|--------------|
| `/api/v1/planner/calendar-events` | GET | `calendar_events` table | `ProgrammingError` caught explicitly; returns `{"count":0,"items":[]}` |

**Note:** `/api/v1/ops/health` also partially tolerant — each probe is try/catched independently.
Returns `{"status":"degraded"}` on missing schema, not HTTP 500.

---

## Tier 2 — Simple tables + thin views (Wave 7B.1 target)

All objects in this tier are:
- Standard PostgreSQL tables with simple column types
- Thin `SELECT ... FROM <single_table>` views with no joins or subqueries
- **Zero RPCs, zero matviews, zero cross-schema references**
- Column definitions sourced directly from `sql/schema/current-schema.sql`

### 2a. Direct table queries

| Endpoint | Method | DB object(s) | Table columns (key) |
|----------|--------|--------------|---------------------|
| `/api/v1/catalog/families` | GET | `famiglie_catalog_static` | `famiglia TEXT, famiglia_slug TEXT` |
| `/api/v1/forecast/summary` | GET | `greenhouse_forecast_results_v2` | `data DATE, famiglia TEXT, fascia_prezzo_iva_inc TEXT, qty_forecast NUMERIC(12,3)` |
| `/api/v1/forecast/series` | GET | `greenhouse_forecast_results_v2` | same |
| `/api/v1/forecast/sample` | GET | `greenhouse_forecast_results_v2` | same |
| `/api/v1/analytics/future-windows` | GET | `greenhouse_forecast_results_v2` | same |

### 2b. Views → analytics series tables (daily)

The `_lc` views wrap `t_core_analytics__series_daily_*` tables.
**All 4 entity daily tables share the same 8-column schema.**

| Endpoint | Method | View | Backing table |
|----------|--------|------|---------------|
| `/api/v1/analytics/series?granularity=day&entity_type=famiglia` | GET | `core_analytics__series_daily_famiglia_lc` | `t_core_analytics__series_daily_famiglia` |
| `/api/v1/analytics/series?granularity=day&entity_type=categoria` | GET | `core_analytics__series_daily_categoria_lc` | `t_core_analytics__series_daily_categoria` |
| `/api/v1/analytics/series?granularity=day&entity_type=fascia` | GET | `core_analytics__series_daily_fascia_lc` | `t_core_analytics__series_daily_fascia` |
| `/api/v1/analytics/series?granularity=day&entity_type=fascia_prezzo` | GET | `core_analytics__series_daily_fascia_prezzo_lc` | `t_core_analytics__series_daily_fascia_prezzo` |
| `/api/v1/analytics/series-bounds?granularity=day` | GET | same 4 views | same 4 tables |
| `/api/v1/sales/summary` | GET | `core_analytics__series_daily_famiglia_lc` | `t_core_analytics__series_daily_famiglia` |

Daily table schema: `(data DATE, entity_key TEXT, qty_venduta_tot NUMERIC, imponibile_netto_tot NUMERIC, qty_forecast_tot NUMERIC, is_holiday BOOLEAN, holiday_name TEXT, dow INTEGER)`

### 2c. Views → analytics series tables (weekly)

All 4 entity weekly tables share the same 5-column schema (no holiday/dow).

| Endpoint | Method | View | Backing table |
|----------|--------|------|---------------|
| `/api/v1/analytics/series?granularity=week&entity_type=famiglia` | GET | `core_analytics__series_weekly_famiglia_lc` | `t_core_analytics__series_weekly_famiglia` |
| `/api/v1/analytics/series?granularity=week&entity_type=categoria` | GET | `core_analytics__series_weekly_categoria_lc` | `t_core_analytics__series_weekly_categoria` |
| `/api/v1/analytics/series?granularity=week&entity_type=fascia` | GET | `core_analytics__series_weekly_fascia_lc` | `t_core_analytics__series_weekly_fascia` |
| `/api/v1/analytics/series?granularity=week&entity_type=fascia_prezzo` | GET | `core_analytics__series_weekly_fascia_prezzo_lc` | `t_core_analytics__series_weekly_fascia_prezzo` |
| `/api/v1/analytics/series-bounds?granularity=week` | GET | same 4 views | same 4 tables |

Weekly table schema: `(period_start DATE, entity_key TEXT, qty_venduta_tot NUMERIC, imponibile_netto_tot NUMERIC, qty_forecast_tot NUMERIC)`
View: `SELECT period_start AS data, lower(btrim(entity_key)) AS entity_key_lc, ...`

### 2d. Views → analytics series tables (monthly, same pattern as weekly)

| Entity | View | Backing table |
|--------|------|---------------|
| famiglia | `core_analytics__series_monthly_famiglia_lc` | `t_core_analytics__series_monthly_famiglia` |
| categoria | `core_analytics__series_monthly_categoria_lc` | `t_core_analytics__series_monthly_categoria` |
| fascia | `core_analytics__series_monthly_fascia_lc` | `t_core_analytics__series_monthly_fascia` |
| fascia_prezzo | `core_analytics__series_monthly_fascia_prezzo_lc` | `t_core_analytics__series_monthly_fascia_prezzo` |

### 2e. Views → analytics series tables (yearly, slightly different schema)

Yearly tables store `entity_key_lc` (already lowercased) with stricter numeric types.
View does NOT apply `lower()` — just passes through.

| Entity | View | Backing table |
|--------|------|---------------|
| famiglia | `core_analytics__series_yearly_famiglia_lc` | `t_core_analytics__series_yearly_famiglia` |
| categoria | `core_analytics__series_yearly_categoria_lc` | `t_core_analytics__series_yearly_categoria` |
| fascia | `core_analytics__series_yearly_fascia_lc` | `t_core_analytics__series_yearly_fascia` |
| fascia_prezzo | `core_analytics__series_yearly_fascia_prezzo_lc` | `t_core_analytics__series_yearly_fascia_prezzo` |

Yearly table schema: `(period_start DATE, entity_key_lc TEXT NOT NULL, qty_venduta_tot NUMERIC(12,3) NOT NULL DEFAULT 0, imponibile_netto_tot NUMERIC(12,2) NOT NULL DEFAULT 0, qty_forecast_tot NUMERIC(12,3))`

### 2f. Views → dashboard sales tables

| Endpoint | Method | View | Backing table |
|----------|--------|------|---------------|
| `/api/v1/dashboard/sales-weekly` | GET | `dashboard__sales_weekly` | `t_dashboard_sales_weekly` |
| `/api/v1/dashboard/sales-monthly` | GET | `dashboard__sales_monthly` | `t_dashboard_sales_monthly` |
| `/api/v1/dashboard/sales-yearly` | GET | `dashboard__sales_yearly` | `t_dashboard_sales_yearly` |

Dashboard table schema: `(period_start DATE NOT NULL, qty_tot NUMERIC(18,3) NOT NULL DEFAULT 0, imp_tot NUMERIC(18,2) NOT NULL DEFAULT 0)`
View: `SELECT period_start AS data, qty_tot, imp_tot`

### 2g. View → seasonality table

| Endpoint | Method | View | Backing table |
|----------|--------|------|---------------|
| `/api/v1/analytics/seasonality` | GET | `core_analytics__seasonality_month` | `t_core_analytics__seasonality_month` |

Seasonality table schema: `(entity_type TEXT NOT NULL, entity_key_lc TEXT NOT NULL, month_num INTEGER NOT NULL, avg_qty_per_day NUMERIC(12,3) DEFAULT 0, sum_qty NUMERIC(14,3) DEFAULT 0, avg_rev_per_day NUMERIC(12,2) DEFAULT 0, sum_rev NUMERIC(14,2) DEFAULT 0, n_days INTEGER DEFAULT 0)`

---

## Tier 3 — Simple RPCs (Wave 7B.2)

| Endpoint | Method | Function | Backing objects |
|----------|--------|----------|-----------------|
| `/api/v1/planner/current-week` | GET | `core_planner__get_current_week52()` | pure date math (no table read) |
| `/api/v1/analytics/range-totals` | GET | `core_analytics__range_totals_v2(entity_type, entity_key, date_from, date_to)` | analytics series tables |
| `/api/v1/analytics/future-windows-stats` | GET | `core_analytics__future_window_stats_v2(...)` | `greenhouse_forecast_results_v2` |
| `/api/v1/catalog/search` | GET | `core_analytics__search_catalog_rich(term, limit_n)` | catalog/product tables |
| `/api/v1/catalog/children` | GET | `core_analytics__catalog_children(...)` | catalog tables |
| `/api/v1/catalog/list` | GET | `core_analytics__list_catalog(entity_type, limit)` | catalog tables |

---

## Tier 4 — Complex analytics (Wave 7B.2)

| Endpoint | Method | DB objects | Complexity |
|----------|--------|------------|------------|
| `/api/v1/analytics/series-breakdown` | GET | `core_analytics__breakdown_{gran}_{entity}_fp_v2` (12 views) + 12 breakdown tables | medium — many tables |
| `/api/v1/analytics/compare-series` | GET | `core_analytics__series_daily_total` (complex join view) | medium |
| `/api/v1/analytics/components` | GET | `core_analytics__components_articles` (join view) | medium |
| `/api/v1/analytics/entity-summary` | GET | `core_analytics__entity_hierarchy_tree_v1()` (JSONB RPC) | high |
| `/api/v1/analytics/stock-and-reorder` | GET | `core_analytics__stock_and_reorder_v1()` RPC | medium |
| `/api/v1/dashboard/kpis` | GET | `dashboard__kpis_v2()` RPC (multi-table agg) | high |
| `/api/v1/dashboard/reorder-suggestions` | GET | `dashboard__reorder_suggestions_top` (join view) | medium |
| `/api/v1/planner/order-suggestions` | GET | `greenhouse_order_suggestions_enriched_v2` (join view) | medium |
| `/api/v1/planner/assortment` | GET | same | medium |
| `/api/v1/planner/space-budget` | GET | `core_planner__get_space_budget()` RPC | high |
| `/api/v1/planner/assortment-calendar` | GET | `core_planner__get_assortment_calendar()` RPC | high |
| `/api/v1/planner/assortment-calendar-export` | GET | `t_core_planner__assortment_calendar` (direct table) | medium |
| `/api/v1/planner/heatmap-nodes` | GET | `core_planner__get_heatmap_nodes()` RPC | high |
| `POST /api/v1/planner/heatmap-week-ranges` | POST | `core_planner__get_heatmap_week_ranges()` RPC | high |
| `POST /api/v1/planner/heatmap-roll4-ranges` | POST | `core_planner__get_heatmap_roll4_ranges()` RPC | high |
| `POST /api/v1/planner/heatmap-cells` | POST | `core_planner__get_heatmap_cells()` RPC | high |
| `/api/v1/planner/heatmap-week-pivot` | GET | `rpc_heatmap_week_pivot(metric)` RPC | high |

---

## Tier 5 — ml_ops schema (Wave 7B.2)

| Endpoint | Method | DB objects | Notes |
|----------|--------|------------|-------|
| `/api/v1/ops/health` | GET | `public.v_ops_pipeline_status`, `ml_ops.v_daily_pipeline_summary_v1`, `greenhouse_forecast_results_v2` | Returns degraded (not 500) on missing schema |
| `/api/v1/ops/pipeline-status` | GET | `ml_ops.v_pipeline_runs_recent_v1` (view) | Returns 500 on missing |
| `/api/v1/ops/family-runs` | GET | `ml_ops.family_run_log_v1` (table, direct query) | Returns 500 on missing |

ml_ops tables needed: `ml_ops.pipeline_run_log_v1`, `ml_ops.family_run_log_v1`
ml_ops views needed: `ml_ops.v_pipeline_runs_recent_v1`, `ml_ops.v_daily_pipeline_summary_v1`
public view needed: `public.v_ops_pipeline_status` (wraps `t_ops_pipeline_monitor` table)

---

## Summary counts

| Tier | Endpoints affected | Wave |
|------|--------------------|------|
| 0 | 4 | 7A ✅ |
| 1 | 1 (+ops/health partial) | 7A ✅ |
| 2 | **27** | **7B.1** |
| 3 | 6 | 7B.2 |
| 4 | 17 | 7B.2 |
| 5 | 3 | 7B.2 |
| **Total** | **58** | |

**Wave 7B.1 achieves 27/58 endpoints (47%) returning HTTP 200 with empty data.**

---

## Wave 7B.1 object count (minimal contract)

| Object type | Count | Notes |
|-------------|-------|-------|
| Tables | 23 | all in `public` schema, no extensions needed |
| Views | 20 | thin wrappers only, hand-crafted to bypass intermediate view chains |
| RPCs | 0 | none |
| Schemas | 1 | `public` only (exists by default) |
| Extensions | 0 | none |
| **Total** | **43** | |

## Wave 7B.2 additional objects (full contract)

| Object type | Count | Notes |
|-------------|-------|-------|
| Additional tables | ~15 | breakdown tables, planner tables, ml_ops tables, ops table |
| Additional views | ~20 | breakdown views, complex join views, ml_ops views, ops view |
| RPCs / Functions | ~25 | core_analytics__, dashboard__, core_planner__ functions |
| Schemas | 1 | `ml_ops` |
| **Total additional** | **~61** | |

---

## Permanently excluded (not applicable to client-runtime)

| Object group | Reason |
|---|---|
| `auth.*` schema | Supabase auth — no client-runtime equivalent |
| `storage.*` schema | Supabase storage — not applicable |
| `realtime.*` schema | Supabase realtime — not applicable |
| `vault.*` schema | Supabase vault — not applicable |
| `graphql.*` schema | Supabase GraphQL — not applicable |
| `ml_diag.*` schema | ML diagnostics only — no backend endpoint uses it |
| `mv_core_analytics__*` matviews | Refresh-pipeline artifacts — not in query path |
| `mv_famiglie_catalog` matview | Catalog cache — not in query path |
| All RLS policies | Row-level security — Supabase-only pattern |
| pg_cron jobs | Refresh scheduler — deferred to operations runbook |
| `etl.*` schema | ETL pipeline — deferred to data population planning |
| `ml_forecast.*` schema | ML model registry — deferred to ML pipeline planning |
