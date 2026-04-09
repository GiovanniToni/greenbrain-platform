# Runtime Current State

## Validated endpoint state

### CORE
- /api/v1/dashboard/reorder-suggestions
  - status: REAL / BUSINESS-VALIDATED
  - note: deterministic edge cases validated

- /api/v1/analytics/future-windows-stats
  - status: REAL / BUSINESS-VALIDATED
  - note: non-empty historical seasonal validation completed

- /api/v1/analytics/compare-series
  - status: REAL / SEMANTICALLY-ACCEPTED
  - note: for entity_type=famiglia, multiple rows per date are accepted when multiple fascia_prezzo exist

- /api/v1/analytics/entity-summary
  - status: REAL / STRUCTURE-VALIDATED
  - note: accepted as tree-only hierarchical endpoint for current phase; quantitative totals deferred

- /api/v1/analytics/series-breakdown
  - status: STUB
  - note: callable and green, but not yet business-validated with meaningful non-empty data

### HYBRID
- /api/v1/dashboard/kpis
  - status: STUB
  - note: safe stub accepted for current phase

- /api/v1/catalog/*
  - status: PARTIAL
  - note: usable, enrichment deferred

### SUPPORT
- /api/v1/planner/current-week
  - status: STUB
  - note: accepted safe stub

- /api/v1/ops/pipeline-status
  - status: STUB
  - note: accepted safe stub

- /health
  - status: REAL

- /health/db
  - status: REAL

- /api/v1/system/db-info
  - status: REAL

## Recommended next target
1. series-breakdown business validation
2. catalog enrichment only if needed by frontend/runtime flows
3. dashboard-kpis replacement only when business KPI semantics are required
