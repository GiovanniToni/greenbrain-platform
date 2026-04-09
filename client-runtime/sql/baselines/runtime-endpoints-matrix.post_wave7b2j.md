# Runtime Endpoint Strategy Matrix

| Endpoint | Status | Type | Data Source | Business Value | Priority | Next Step |
|----------|--------|------|-------------|----------------|----------|----------|
| /analytics/entity-summary | STUB | CORE | none | HIGH | P1 | implement SQL aggregation |
| /analytics/series-breakdown | STUB | CORE | none | HIGH | P1 | connect to core_analytics views |
| /dashboard/reorder-suggestions | REAL / EMPTY-DATA | CORE | partial real | VERY HIGH | P0 | load test data + validate reorder logic |
| /analytics/future-windows-stats | STUB | CORE | none | HIGH | P1 | implement forecast model |
| /dashboard/kpis | STUB | HYBRID | none | MEDIUM | P2 | replace with aggregates |
| /catalog/* | PARTIAL | HYBRID | partial | MEDIUM | P2 | enrich hierarchy |
| /planner/current-week | STUB | SUPPORT | system | LOW | P4 | keep stub |
| /ops/pipeline-status | STUB | SUPPORT | system | LOW | P4 | keep stub |
| /health | REAL | SUPPORT | system | LOW | P4 | done |
| /system/db-info | REAL | SUPPORT | system | LOW | P4 | done |
