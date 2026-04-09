# GreenBrain V1 API Inventory

## Already available
- GET /api/v1/system/info
- GET /api/v1/system/db-info
- GET /api/v1/catalog/families
- GET /api/v1/forecast/summary
- GET /api/v1/forecast/sample

## Needed next

### Catalog
- GET /api/v1/catalog/families
- GET /api/v1/catalog/families/{family}/summary
- GET /api/v1/catalog/price-bands

### Forecast
- GET /api/v1/forecast/summary
- GET /api/v1/forecast/sample
- GET /api/v1/forecast/family/{family}
- GET /api/v1/forecast/family/{family}/timeseries
- GET /api/v1/forecast/family/{family}/price-bands

### Sales / analytics
- GET /api/v1/sales/summary
- GET /api/v1/sales/timeseries
- GET /api/v1/sales/family/{family}
- GET /api/v1/analytics/dashboard
- GET /api/v1/analytics/family-ranking

### Planner
- GET /api/v1/planner/weekly
- GET /api/v1/planner/assortment
- GET /api/v1/planner/density
- GET /api/v1/planner/space-budget

### Operations
- GET /api/v1/ops/pipeline-status
- GET /api/v1/ops/health
- POST /api/v1/ops/run-forecast

## Rule
Frontend must call backend APIs only.
Frontend should not directly query Supabase/Postgres in the final product.
