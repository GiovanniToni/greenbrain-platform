# GreenBrain V1 Data Core

## Core tables/views for V1

### Catalog
- public.famiglie_catalog_static

### Forecast
- public.greenhouse_forecast_results_v2
- public.greenhouse_forecast_features_dense

### Sales
- public.greenhouse_sales_raw
- public.greenhouse_sales_family_daily_fact
- public.greenhouse_sales_family_daily_dense

### Products
- public.greenhouse_products_normalized

### Calendar / support
- public.dim_iso_day
- public.greenhouse_holidays
- public.greenhouse_weather_daily
- public.greenhouse_weekday_strength
- public.greenhouse_weekday_strength_family

### Planner
- public.t_core_planner__assortment_calendar
- public.t_core_planner__density
- public.t_core_planner__fact_weekly
- public.t_core_planner__space_budget

### Dashboard / analytics
- public.t_dashboard_sales_daily
- public.t_dashboard_sales_weekly
- public.t_dashboard_sales_monthly
- public.t_dashboard_sales_yearly
- public.t_forecast_fam_daily

### Ops
- public.t_ops_pipeline_monitor
- ml_ops schema objects
- ml_forecast schema objects

## Rule
Only promote to V1 what is needed by frontend/backend/ML runtime.
Do not migrate complexity into V1 unless actively used.
