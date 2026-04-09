# Runtime Validation Plan

## Goal
Move client-runtime from "endpoint green" to "business-valid output".

## Current status
- health/system endpoints: green
- catalog: partial
- analytics core endpoints: callable
- dashboard reorder-suggestions: REAL / EMPTY-DATA
- planner/ops support endpoints: safe stubs
- live gb_v2 stack untouched
- shadow stack untouched

## Priority order
1. reorder-suggestions
2. compare-series
3. future-windows-stats
4. entity-summary ✅ non-empty tree validated; next: validate quantitative totals
5. dashboard-kpis
6. planner/ops remain stub unless business need emerges

## Minimum local dataset required
### For reorder-suggestions
- greenhouse_stock_raw_upload
- greenhouse_sales_family_daily_fact
- greenhouse_forecast_results_v2

### For compare-series
- greenhouse_forecast_features_dense
- greenhouse_forecast_results_v2

### For future-windows-stats
- t_core_analytics__series_daily_famiglia
- t_core_analytics__series_daily_categoria
- t_core_analytics__series_daily_fascia
- t_core_analytics__series_daily_fascia_prezzo

### For entity-summary
- greenhouse_products_normalized
- core_analytics__components_articles dependency chain

## Validation targets
### reorder-suggestions must answer:
- which family needs reorder
- how much reorder is suggested
- whether stockout risk is flagged correctly

### compare-series must answer:
- actual vs forecast over a date range
- empty output only when no data exists

### future-windows-stats must answer:
- min/max/avg future-window quantities from historical seasonal windows

## Rules
- prefer minimal reversible seed data
- do not touch live stack
- do not touch shadow stack
- validate endpoint output before expanding schema
- distinguish STUB vs REAL vs REAL / EMPTY-DATA

## Next concrete task
Extend the deterministic seed approach to:
1. validate reorder-suggestions with edge cases
   - enough stock
   - zero stock
   - forecast low
   - forecast high
2. validate /api/v1/analytics/compare-series with real non-empty output ✅ single-family done; next: multi-family + multi-fascia
3. classify each runtime endpoint as:
   - STUB
   - REAL / EMPTY-DATA
   - REAL / BUSINESS-VALIDATED
