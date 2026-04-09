# Runtime Endpoint Strategy Matrix

| Endpoint | Status | Type | Data Source | Business Value | Priority | Next Step |
|----------|--------|------|-------------|----------------|----------|----------|
| /analytics/entity-summary | REAL / STRUCTURE-VALIDATED | CORE | products + components chain | HIGH | P1 | keep tree-only for now; quantitative totals explicitly deferred |
| /analytics/compare-series | REAL / SEMANTICALLY-ACCEPTED | CORE | forecast_features + forecast_results | HIGH | P1 | keep current behavior: famiglia may expose multiple rows per date when multiple fascia_prezzo exist |
| /analytics/series-breakdown | REAL / BUSINESS-VALIDATED | CORE | breakdown *_fp_v2 tables/views | HIGH | P1 | extend dataset and validate additional business edge cases only if needed |
| /dashboard/reorder-suggestions | REAL / BUSINESS-VALIDATED | CORE | real local chain | VERY HIGH | P0 | extend dataset and validate edge cases |
| /analytics/future-windows-stats | REAL / BUSINESS-VALIDATED | CORE | historical seasonal series tables | HIGH | P1 | extend dataset and validate edge windows |
| /dashboard/kpis | STUB | HYBRID | none | MEDIUM | P2 | replace with aggregates |
| /catalog/* | PARTIAL | HYBRID | partial | MEDIUM | P2 | enrich hierarchy |
| /planner/current-week | STUB | SUPPORT | system | LOW | P4 | keep stub |
| /ops/pipeline-status | STUB | SUPPORT | system | LOW | P4 | keep stub |
| /health | REAL | SUPPORT | system | LOW | P4 | done |
| /system/db-info | REAL | SUPPORT | system | LOW | P4 | done |
