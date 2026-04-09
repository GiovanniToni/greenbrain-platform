# Freeze Baseline — Wave 0
Generated: 2026-03-27T17:06:55+01:00

---

## SYSTEMD TIMERS

Fri 2026-03-27 21:35:32 CET  4h 28min left        Thu 2026-03-26 21:36:18 CET 19h ago            gh-parquet-export.timer        gh-parquet-export.service
Sat 2026-03-28 00:47:39 CET  7h left              Fri 2026-03-27 00:46:04 CET 16h ago            gh-refresh-registry.timer      gh-refresh-registry.service
Sat 2026-03-28 01:10:18 CET  8h left              Fri 2026-03-27 01:11:38 CET 15h ago            gh-train-missing.timer         gh-train-missing.service
Sat 2026-03-28 01:30:54 CET  8h left              Fri 2026-03-27 01:30:13 CET 15h ago            gh-predict-all.timer           gh-predict-all.service
Wed 2026-04-01 02:33:03 CEST 4 days left          Sun 2026-02-22 21:46:02 CET 1 month 2 days ago gh-train-quarterly.timer       gh-train-quarterly.service
Sun 2026-11-01 02:02:01 CET  7 months 5 days left Sun 2026-03-15 02:04:40 CET 1 week 5 days ago  gh-train-biweekly-all.timer    gh-train-biweekly-all.service

---

## DOCKER STATUS

gb_v2_frontend | Up 19 minutes | 0.0.0.0:8083->8080/tcp, [::]:8083->8080/tcp
gb_v2_backend | Up 6 days | 0.0.0.0:8002->8000/tcp, [::]:8002->8000/tcp
gb_v2_nginx | Up 7 days | 0.0.0.0:8082->80/tcp, [::]:8082->80/tcp
gb_v2_ml | Up 7 days | 
gb_v2_pgadmin | Up 7 days | 443/tcp, 0.0.0.0:5050->80/tcp, [::]:5050->80/tcp
gb_v2_postgres | Up 7 days (healthy) | 0.0.0.0:5433->5432/tcp, [::]:5433->5432/tcp

---

## PG_CRON JOBS

 jobid |       schedule       |                                       command                                       
-------+----------------------+-------------------------------------------------------------------------------------
    11 | */5 10-11 * * *      | set statement_timeout = 0; call public.run_greenhouse_daily_pipeline_full(40,14,2);
    12 | 5 1 * * *            | set statement_timeout = 0; select public.core_planner__nightly_roll4_reset();
    13 | 0 12 * * *           | set statement_timeout=0; select public.core_planner__nightly_roll4_tick(2);
    28 | */15 * * * *         | select public.ops_pipeline_monitor_snapshot();
    29 | */5 19-23 * * *      | set statement_timeout=0; select public.ops_maybe_run_daily_pipeline();
    31 | */10 19-23 * * *     | select public.ops_refresh_pipeline_monitor_snapshot();
    32 | */2 10-12 * * *      | select public.ops_refresh_pipeline_monitor_snapshot();
    34 | */30 0-9,13-23 * * * | select public.ops_refresh_pipeline_monitor_snapshot();
    35 | */5 9-11 * * *       | select public.ops_refresh_pipeline_monitor_snapshot();
    37 | */5 9-11 * * *       | select public.ops_maybe_run_daily_pipeline();
(10 rows)


---

## SYSTEMD SERVICES STATUS

○ gh-refresh-registry.service - Greenhouse - Refresh Family Registry
     Loaded: loaded (/etc/systemd/system/gh-refresh-registry.service; disabled; vendor preset: enabled)
     Active: inactive (dead) since Fri 2026-03-27 12:40:46 CET; 4h 26min ago
TriggeredBy: ● gh-refresh-registry.timer
   Main PID: 955381 (code=exited, status=0/SUCCESS)
        CPU: 284ms

Mar 27 12:36:16 greenbrain-forecast bash[952780]: REFRESH MATERIALIZED VIEW
Mar 27 12:36:16 greenbrain-forecast bash[952780]: REFRESH MATERIALIZED VIEW
Mar 27 12:36:37 greenbrain-forecast bash[952780]: REFRESH MATERIALIZED VIEW
Mar 27 12:37:54 greenbrain-forecast bash[952780]: REFRESH MATERIALIZED VIEW
Mar 27 12:39:35 greenbrain-forecast bash[952780]: REFRESH MATERIALIZED VIEW
Mar 27 12:40:45 greenbrain-forecast bash[952780]: REFRESH MATERIALIZED VIEW
Mar 27 12:40:45 greenbrain-forecast bash[952778]: OK gh-refresh-ml-diag
Mar 27 12:40:45 greenbrain-forecast bash[955381]: [ENV] loaded base.env + dev.env
Mar 27 12:40:45 greenbrain-forecast bash[955381]: [ENV] DATABASE_URL ready
Mar 27 12:40:46 greenbrain-forecast bash[955383]: OK refresh_registry | families=844

○ gh-train-missing.service - Greenhouse - Train Missing Bundles (batch)
     Loaded: loaded (/etc/systemd/system/gh-train-missing.service; disabled; vendor preset: enabled)
     Active: inactive (dead) since Fri 2026-03-27 12:43:15 CET; 4h 23min ago
TriggeredBy: ● gh-train-missing.timer
   Main PID: 956013 (code=exited, status=0/SUCCESS)
        CPU: 1.873s

Mar 27 12:42:16 greenbrain-forecast bash[956013]: [ENV] loaded base.env + dev.env
Mar 27 12:42:16 greenbrain-forecast bash[956013]: [ENV] DATABASE_URL ready
Mar 27 12:42:16 greenbrain-forecast bash[956023]: START 2026-03-27T11:42:16Z
Mar 27 12:42:18 greenbrain-forecast bash[956026]: DONE train_missing -> /opt/greenhouse/logs/train_missing_20260327_114217.log | trained=0 | ok=0 | bad=0 | rc=0
Mar 27 12:42:18 greenbrain-forecast bash[956057]: END   2026-03-27T11:42:18Z
Mar 27 12:42:18 greenbrain-forecast bash[956059]: [ENV] loaded base.env + dev.env
Mar 27 12:42:18 greenbrain-forecast bash[956059]: [ENV] DATABASE_URL ready
Mar 27 12:43:15 greenbrain-forecast bash[956061]: OK sync_local_artifacts | processed=849

○ gh-predict-all.service - Greenhouse - Predict All Families (daily)
     Loaded: loaded (/etc/systemd/system/gh-predict-all.service; disabled; vendor preset: enabled)
     Active: inactive (dead) since Fri 2026-03-27 14:10:08 CET; 2h 56min ago
TriggeredBy: ● gh-predict-all.timer
    Process: 957804 ExecStart=/bin/bash -lc source /opt/greenhouse/venv/bin/activate && cd /opt/greenbrain-platform/apps/ml-worker && bash jobs/run_predict_all.sh (code=exited, status=0/SUCCESS)
   Main PID: 957804 (code=exited, status=0/SUCCESS)
        CPU: 47min 46.571s

Mar 27 12:49:46 greenbrain-forecast bash[957819]: doy       308904
Mar 27 12:49:46 greenbrain-forecast bash[957819]: global       844
Mar 27 12:49:46 greenbrain-forecast bash[957819]: month      10128
Mar 27 12:49:46 greenbrain-forecast bash[957819]: week       44732
Mar 27 12:49:48 greenbrain-forecast bash[958811]: OK update supabase://ml-snapshots/priors/priors_v1.parquet <- /opt/greenhouse/repo/priors_cache/priors_v1.parquet
Mar 27 12:49:49 greenbrain-forecast bash[958822]: OK download supabase://ml-snapshots/priors/priors_v1.parquet -> /opt/greenhouse/repo/priors_cache/priors_v1.parquet
Mar 27 12:49:50 greenbrain-forecast bash[958825]: PRIORS_END   2026-03-27T11:49:50Z
Mar 27 12:49:50 greenbrain-forecast bash[958830]: START 2026-03-27T11:49:50Z
Mar 27 14:10:08 greenbrain-forecast bash[958833]: DONE predict_all -> /opt/greenhouse/logs/predict_all_20260327_114950.log | ok=844 bad=0 rc=0
Mar 27 14:10:08 greenbrain-forecast bash[990812]: END   2026-03-27T13:10:08Z

○ gh-parquet-export.service - Greenhouse - Export features_dense parquet batches
     Loaded: loaded (/etc/systemd/system/gh-parquet-export.service; disabled; vendor preset: enabled)
     Active: inactive (dead) since Fri 2026-03-27 14:25:47 CET; 2h 41min ago
TriggeredBy: ● gh-parquet-export.timer
    Process: 989595 ExecStartPre=/bin/bash -lc cd /opt/greenbrain-platform/apps/ml-worker && bash jobs/parquet_export/check_etl_ready.sh (code=exited, status=0/SUCCESS)
    Process: 989604 ExecStart=/bin/bash -lc source /opt/greenhouse/venv/bin/activate && cd /opt/greenbrain-platform/apps/ml-worker && bash jobs/parquet_export/scripts/run_daily_parquet_batches.sh (code=exited, status=0/SUCCESS)
   Main PID: 989604 (code=exited, status=0/SUCCESS)
        CPU: 49.237s

Mar 27 14:24:59 greenbrain-forecast bash[995586]: [RUN 1093] progress=8/44 (18.2%) files=8 rows=1160 elapsed=10s eta=46s | now famiglia_slug=tigrida year=2026
Mar 27 14:25:10 greenbrain-forecast bash[995586]: [RUN 1093] progress=16/44 (36.4%) files=16 rows=2160 elapsed=21s eta=36s | now famiglia_slug=timo-limone year=2026
Mar 27 14:25:21 greenbrain-forecast bash[995586]: [RUN 1093] progress=25/44 (56.8%) files=25 rows=3194 elapsed=32s eta=24s | now famiglia_slug=valeriana year=2026
Mar 27 14:25:32 greenbrain-forecast bash[995586]: [RUN 1093] progress=33/44 (75.0%) files=33 rows=4634 elapsed=42s eta=14s | now famiglia_slug=wax-flower year=2026
Mar 27 14:25:42 greenbrain-forecast bash[995586]: [RUN 1093] progress=41/44 (93.2%) files=41 rows=6474 elapsed=53s eta=4s | now famiglia_slug=zucca year=2026
Mar 27 14:25:47 greenbrain-forecast bash[995586]: [RUN 1093] progress=44/44 (100.0%) files=44 rows=6754 elapsed=58s eta=0s
Mar 27 14:25:47 greenbrain-forecast bash[995586]: SUCCESS run_id=1093 files=44 rows=6754 families_in_run=44/844 years=1 window=2026-02-14..2026-03-25
Mar 27 14:25:47 greenbrain-forecast bash[995586]: NEXT: export BATCH_OFFSET=850 (done up to ~844/844)
Mar 27 14:25:47 greenbrain-forecast bash[995950]: 2026-03-27T14:25:47+01:00 [BATCH off=800 attempt=1] OK
Mar 27 14:25:47 greenbrain-forecast bash[995953]: 2026-03-27T14:25:47+01:00 SUCCESS all batches completed

---

## ML PIPELINE RUN LOG (LAST 30)

 run_id |     job_type     |  trigger_mode  | status  |          started_at           |          finished_at          | rows_processed |    error_message     
--------+------------------+----------------+---------+-------------------------------+-------------------------------+----------------+----------------------
   2046 | predict_daily    | systemd_timer  | success | 2026-03-27 11:49:51.471429+00 | 2026-03-27 13:10:08.384077+00 |            844 | 
   2044 | train_missing    | systemd_timer  | success | 2026-03-27 11:42:18.119341+00 | 2026-03-27 11:42:18.359136+00 |              0 | 
   2043 | refresh_registry | systemd_timer  | success | 2026-03-27 11:40:45.963215+00 | 2026-03-27 11:40:45.963215+00 |            844 | 
   2042 | refresh_registry | shadow_test    | success | 2026-03-27 10:28:24.391551+00 | 2026-03-27 10:28:24.391551+00 |            844 | 
   2041 | predict_daily    | systemd_timer  | success | 2026-03-27 00:33:12.202096+00 | 2026-03-27 01:51:29.707221+00 |            844 | 
   2039 | train_missing    | systemd_timer  | success | 2026-03-27 00:11:39.789625+00 | 2026-03-27 00:11:40.02083+00  |              0 | 
   2038 | refresh_registry | systemd_timer  | success | 2026-03-26 23:52:46.301348+00 | 2026-03-26 23:52:46.301348+00 |            844 | 
   2037 | predict_daily    | shadow_systemd | success | 2026-03-26 18:15:09.975611+00 | 2026-03-26 19:29:21.642167+00 |            844 | 
   2036 | train_missing    | shadow_systemd | success | 2026-03-26 18:11:39.00966+00  | 2026-03-26 18:11:39.252491+00 |              0 | 
   2035 | train_missing    | shadow_systemd | success | 2026-03-26 18:10:59.507184+00 | 2026-03-26 18:10:59.748965+00 |              0 | 
   2034 | predict_daily    | systemd_timer  | failed  | 2026-03-26 17:53:14.682501+00 | 2026-03-26 18:36:59.023745+00 |            484 | terminated by signal
   2031 | train_missing    | systemd_timer  | success | 2026-03-26 17:33:15.482468+00 | 2026-03-26 17:33:15.726483+00 |              0 | 
   2029 | refresh_registry | manual         | success | 2026-03-26 17:05:45.263173+00 | 2026-03-26 17:05:45.263173+00 |            844 | 
   2028 | refresh_registry | manual         | success | 2026-03-26 17:05:41.204898+00 | 2026-03-26 17:05:41.204898+00 |            844 | 
   2027 | refresh_registry | manual         | success | 2026-03-26 17:03:18.570135+00 | 2026-03-26 17:03:18.570135+00 |            844 | 
   2026 | refresh_registry | manual         | success | 2026-03-26 17:03:12.606394+00 | 2026-03-26 17:03:12.606394+00 |            844 | 
   2025 | refresh_registry | manual         | success | 2026-03-26 16:46:19.065865+00 | 2026-03-26 16:46:19.065865+00 |            844 | 
   2023 | predict_daily    | systemd_timer  | success | 2026-03-26 13:03:48.3776+00   | 2026-03-26 14:18:18.641089+00 |            844 | 
   2021 | train_missing    | systemd_timer  | success | 2026-03-26 12:09:49.850931+00 | 2026-03-26 12:09:50.086873+00 |              0 | 
   2019 | refresh_registry | systemd_timer  | success | 2026-03-26 12:01:00.784281+00 | 2026-03-26 12:01:00.784281+00 |            844 | 
   2018 | predict_daily    | systemd_timer  | success | 2026-03-26 00:34:50.181058+00 | 2026-03-26 01:47:06.799494+00 |            844 | 
   2017 | train_missing    | systemd_timer  | success | 2026-03-26 00:10:41.911481+00 | 2026-03-26 00:10:42.167842+00 |              0 | 
   2016 | refresh_registry | manual         | success | 2026-03-25 23:54:08.492251+00 | 2026-03-25 23:54:08.492251+00 |            844 | 
   2015 | refresh_registry | manual         | success | 2026-03-25 07:27:14.389493+00 | 2026-03-25 07:27:14.389493+00 |            844 | 
   2014 | predict_daily    | systemd_timer  | success | 2026-03-25 00:34:56.215359+00 | 2026-03-25 01:50:24.788008+00 |            844 | 
   2013 | train_missing    | systemd_timer  | success | 2026-03-25 00:11:41.797527+00 | 2026-03-25 00:11:42.043367+00 |              0 | 
   2012 | refresh_registry | manual         | success | 2026-03-24 23:45:09.327152+00 | 2026-03-24 23:45:09.327152+00 |            844 | 
   2011 | predict_daily    | systemd_timer  | success | 2026-03-24 00:32:55.208511+00 | 2026-03-24 01:48:09.993136+00 |            844 | 
   2010 | train_missing    | systemd_timer  | success | 2026-03-24 00:11:19.785999+00 | 2026-03-24 00:11:20.051603+00 |              0 | 
   2009 | refresh_registry | manual         | success | 2026-03-23 23:45:59.282173+00 | 2026-03-23 23:45:59.282173+00 |            844 | 
(30 rows)


---

## POST-WAVE-0 SNAPSHOT

Captured: 2026-03-27T17:29:10+01:00

### TIMERS
Fri 2026-03-27 21:35:32 CET  4h 6min left         Thu 2026-03-26 21:36:18 CET 19h ago            gh-parquet-export.timer        gh-parquet-export.service
Sat 2026-03-28 00:47:39 CET  7h left              Fri 2026-03-27 00:46:04 CET 16h ago            gh-refresh-registry.timer      gh-refresh-registry.service
Sat 2026-03-28 01:10:18 CET  7h left              Fri 2026-03-27 01:11:38 CET 16h ago            gh-train-missing.timer         gh-train-missing.service
Sat 2026-03-28 01:30:54 CET  8h left              Fri 2026-03-27 01:30:13 CET 15h ago            gh-predict-all.timer           gh-predict-all.service
Wed 2026-04-01 02:33:03 CEST 4 days left          Sun 2026-02-22 21:46:02 CET 1 month 2 days ago gh-train-quarterly.timer       gh-train-quarterly.service
Sun 2026-11-01 02:02:01 CET  7 months 5 days left Sun 2026-03-15 02:04:40 CET 1 week 5 days ago  gh-train-biweekly-all.timer    gh-train-biweekly-all.service

### DOCKER
gb_v2_frontend | Up 41 minutes | 0.0.0.0:8083->8080/tcp, [::]:8083->8080/tcp
gb_v2_backend | Up 6 days | 0.0.0.0:8002->8000/tcp, [::]:8002->8000/tcp
gb_v2_nginx | Up 7 days | 0.0.0.0:8082->80/tcp, [::]:8082->80/tcp
gb_v2_ml | Up 7 days | 
gb_v2_pgadmin | Up 7 days | 443/tcp, 0.0.0.0:5050->80/tcp, [::]:5050->80/tcp
gb_v2_postgres | Up 7 days (healthy) | 0.0.0.0:5433->5432/tcp, [::]:5433->5432/tcp

### PG_CRON
 jobid |       schedule       |                                       command                                       
-------+----------------------+-------------------------------------------------------------------------------------
    11 | */5 10-11 * * *      | set statement_timeout = 0; call public.run_greenhouse_daily_pipeline_full(40,14,2);
    12 | 5 1 * * *            | set statement_timeout = 0; select public.core_planner__nightly_roll4_reset();
    13 | 0 12 * * *           | set statement_timeout=0; select public.core_planner__nightly_roll4_tick(2);
    28 | */15 * * * *         | select public.ops_pipeline_monitor_snapshot();
    29 | */5 19-23 * * *      | set statement_timeout=0; select public.ops_maybe_run_daily_pipeline();
    31 | */10 19-23 * * *     | select public.ops_refresh_pipeline_monitor_snapshot();
    32 | */2 10-12 * * *      | select public.ops_refresh_pipeline_monitor_snapshot();
    34 | */30 0-9,13-23 * * * | select public.ops_refresh_pipeline_monitor_snapshot();
    35 | */5 9-11 * * *       | select public.ops_refresh_pipeline_monitor_snapshot();
    37 | */5 9-11 * * *       | select public.ops_maybe_run_daily_pipeline();
(10 rows)


### WAVE-0 STATUS
- Dangerous pg_cron jobs 30/38/39 removed
- Freeze baseline captured
- Post-Wave-0 snapshot captured
- Credential leak file no longer found by filesystem scan
- Frontend container restarted successfully
- Supabase anon/public key rotation: VERIFY MANUALLY IN DASHBOARD

### WAVE-2 STATUS
- dev.env expanded with legacy ML/runtime variables
- SUPABASE_KEY alias added
- gh-train-biweekly-all.service migrated off EnvironmentFile
- gh-train-quarterly.service migrated off EnvironmentFile
- ExecStartPost for both services now uses monorepo bin path
- interactive shell PATH now resolves gh-* commands to monorepo bin first
- legacy /opt/greenhouse/.env no longer referenced by live service units

### WAVE-3 STATUS
- GH_REPO_DIR now points to /opt/greenbrain-platform/apps/ml-worker
- run_train_missing.sh now resolves REPO_DIR via GH_REPO_DIR
- run_predict_all.sh now resolves REPO_DIR and GIT_SHA via GH_REPO_DIR
- run_daily_parquet_batches.sh now resolves PROJECT_DIR via GH_REPO_DIR
- gh-train-biweekly-all.service WorkingDirectory moved to monorepo
- gh-train-quarterly.service WorkingDirectory moved to monorepo
- gh-train-missing smoke test passed from monorepo path
- gh-predict-all smoke test passed through priors build, storage I/O, and START phase from monorepo path
- parquet export script path verified from monorepo
- /opt/greenhouse/repo temporarily frozen, then unfrozen after parquet export import-path failure
- parquet export import-path fix applied: PYTHONPATH now uses ${PYTHONPATH:-} to avoid unbound-variable failure
- parquet export smoke test passed from monorepo path: env loaded, PROJECT_DIR confirmed, batch started successfully, no storage import error

### WAVE-3 COMPLETION
- All jobs now execute from monorepo path via GH_REPO_DIR
- Systemd units updated to monorepo WorkingDirectory
- Predict pipeline validated (priors build + storage I/O + start predict)
- Parquet export validated end-to-end (real batch execution, progress observed)
- PYTHONPATH issue resolved with safe default (${PYTHONPATH:-}) under set -u
- Legacy repo /opt/greenhouse/repo set to read-only after full validation

### SHADOW VALIDATION STATUS
- frontend shadow running on http://localhost:5174
- backend shadow running on http://localhost:8001
- shadow backend now points to Supabase dev/master DB via DATABASE_URL
- analytics entity-summary fixed:
  - RPC JSONB wrapper unwrapped in backend
  - invalid tree nodes sanitised
  - frontend no longer forces p_top_n=0
- "Mostra dettagli" in Analytics now works correctly in shadow
- shadow environment remains isolated from live gb_v2 stack

### WAVE-6 REFINEMENT
- client-runtime docker-compose now starts only postgres + backend by default
- frontend is gated behind profile `wave7-frontend`
- architecture boundary is now enforced by compose, not only by comments

### WAVE-6 / 7A BOOTSTRAP STATUS
- client-runtime postgres now starts cleanly without shell-exported vars
- client-runtime backend now starts cleanly against local PostgreSQL
- compose interpolation issue fixed by removing postgres environment duplication
- client-runtime backend health endpoints validated:
  - /docs = 200
  - /health = ok
  - /health/db = connected
- live gb_v2 stack untouched
- shadow stack untouched
- frontend remains deferred behind wave7-frontend profile

### WAVE-7A VALIDATION
- backend Docker image builds from apps/backend/Dockerfile
- client-runtime postgres boots locally and becomes healthy
- client-runtime backend boots locally and becomes healthy
- validated endpoints:
  - /health = ok
  - /health/db = connected
  - /api/v1/system/db-info = ok
- business endpoints are reachable but still depend on schema not yet applied
- live gb_v2 stack untouched
- shadow stack untouched

### WAVE-7B.1 VALIDATION
- client-runtime postgres applied 01_bootstrap.sql and 02_schema_7b1.sql successfully
- Wave 7B.1 minimal local schema created successfully:
  - 23 tables
  - 20 views
- validated Tier 2 endpoints now return HTTP 200 with empty payloads instead of UndefinedTable 500
- backend bootstrap remains healthy:
  - /health = ok
  - /health/db = connected
  - /api/v1/system/db-info = ok
- live gb_v2 stack untouched
- shadow stack untouched
- frontend still deferred behind wave7-frontend profile

### WAVE-7B.2-A VALIDATION
- client-runtime catalog micro-wave applied successfully via 03_schema_7b2a.sql
- validated catalog endpoints:
  - /api/v1/catalog/search = 200
  - /api/v1/catalog/children = 200
  - /api/v1/catalog/list = 200
- catalog runtime objects created locally:
  - greenhouse_products_normalized
  - core_analytics__components_articles
  - mv_core_analytics__catalog_entities (as VIEW in client-runtime)
  - core_analytics__catalog
  - core_analytics__search_catalog_rich()
  - core_analytics__catalog_children()
  - core_analytics__list_catalog()
- live gb_v2 stack untouched
- shadow stack untouched

### STATUS AFTER WAVE-7B.2-A
- Wave 6 structural separation complete
- Wave 7A backend bootstrap complete
- Wave 7B.1 minimal Tier 2 schema applied
- Wave 7B.2-A catalog micro-wave applied
- validated endpoints:
  - /api/v1/catalog/search = 200
  - /api/v1/catalog/children = 200
  - /api/v1/catalog/list = 200
- baselines saved under client-runtime/sql/baselines

### WAVE-7B.2-B VALIDATION
- client-runtime analytics micro-wave applied successfully via 04_schema_7b2b.sql
- validated endpoints:
  - /api/v1/analytics/range-totals = 200
  - /api/v1/analytics/stock-and-reorder = 200
- /api/v1/analytics/components remains 200
- local runtime objects added:
  - greenhouse_stock_raw_upload
  - greenhouse_sales_family_daily_fact
  - greenhouse_stock_enriched
  - greenhouse_forecast_windows_v2
  - greenhouse_stock_family_latest_v2
  - greenhouse_sales_family_meta_v2
  - greenhouse_order_suggestions_v2
  - greenhouse_order_suggestions_enriched_v2
  - core_analytics__range_totals_v2()
  - core_analytics__stock_and_reorder_v1()
- live gb_v2 stack untouched
- shadow stack untouched

### WAVE-7B.2-C VALIDATION
- client-runtime dashboard micro-wave applied successfully via 05_schema_7b2c.sql
- validated endpoint:
  - /api/v1/dashboard/reorder-suggestions = 200
- local runtime object added:
  - dashboard__reorder_suggestions_top
- regression checks remained green:
  - /health = 200
  - /health/db = 200
  - /api/v1/system/db-info = 200
  - /api/v1/catalog/search = 200
  - /api/v1/catalog/children = 200
  - /api/v1/catalog/list = 200
  - /api/v1/analytics/range-totals = 200
  - /api/v1/analytics/stock-and-reorder = 200
- live gb_v2 stack untouched
- shadow stack untouched

### WAVE-7B.2-D VALIDATION
- client-runtime future-windows-stats micro-wave applied successfully via 06_schema_7b2d.sql
- validated endpoint:
  - /api/v1/analytics/future-windows-stats = 200
- local runtime objects added:
  - mv_core_analytics__series_daily_categoria
  - mv_core_analytics__series_daily_fascia
  - mv_core_analytics__series_daily_fascia_prezzo
  - core_analytics__future_window_stats_v2()
- regression checks remained green
- live gb_v2 stack untouched
- shadow stack untouched

### WAVE-7B.2-E VALIDATION
- client-runtime compare-series micro-wave applied successfully via 07_schema_7b2e.sql
- validated endpoint:
  - /api/v1/analytics/compare-series = 200
- local runtime objects added:
  - greenhouse_forecast_features_dense
  - core_analytics__series_daily
  - core_analytics__series_daily_total
- regression checks remained green
- live gb_v2 stack untouched
- shadow stack untouched

### WAVE-7B.2-F VALIDATION
- client-runtime series-breakdown micro-wave applied successfully via 08_schema_7b2f.sql
- validated endpoint:
  - /api/v1/analytics/series-breakdown = 200
- local runtime objects added:
  - 12 t_core_analytics__breakdown_*_fp_v2 tables
  - 12 core_analytics__breakdown_*_fp_v2 views
- regression checks remained green
- live gb_v2 stack untouched
- shadow stack untouched

### WAVE-7B.2-G VALIDATION
- client-runtime entity-summary micro-wave applied successfully via 09_schema_7b2g.sql
- validated endpoint:
  - /api/v1/analytics/entity-summary = 200
- local runtime object added:
  - core_analytics__entity_hierarchy_tree_v1()
- regression checks remained green
- live gb_v2 stack untouched
- shadow stack untouched

### WAVE-7B.2-H VALIDATION
- client-runtime dashboard-kpis micro-wave applied successfully via 10_schema_7b2h.sql
- validated endpoint:
  - /api/v1/dashboard/kpis = 200
- local runtime object added:
  - dashboard__kpis_v2()
- implemented as local safe stub to preserve backend contract without full dashboard-sales dependency chain
- regression checks remained green
- live gb_v2 stack untouched
- shadow stack untouched

### WAVE-7B.2-I VALIDATION
- client-runtime ops pipeline-status micro-wave applied successfully via 11_schema_7b2i.sql
- validated endpoint:
  - /api/v1/ops/pipeline-status = 200
- local runtime object added:
  - ml_ops.v_pipeline_runs_recent_v1
- implemented as local safe stub under ml_ops schema to preserve backend contract without ML pipeline dependency chain
- regression checks remained green
- live gb_v2 stack untouched
- shadow stack untouched
