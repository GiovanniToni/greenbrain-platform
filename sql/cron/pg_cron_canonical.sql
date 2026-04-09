-- pg_cron Canonical Job Definitions
-- Source: Supabase cron.job table
-- Active jobs expected after Wave 0: 10
-- Jobs 30, 38, 39 were removed in Wave 0.
-- Apply only against Supabase PostgreSQL.
-- Do NOT apply against local Docker PostgreSQL.

 -- Job 11: greenhouse_daily_full                                                                                                                          +
 SELECT cron.schedule('greenhouse_daily_full', '*/5 10-11 * * *', $$set statement_timeout = 0; call public.run_greenhouse_daily_pipeline_full(40,14,2);$$);+
 
 -- Job 12: planner_roll4_reset_nightly                                                                                                                    +
 SELECT cron.schedule('planner_roll4_reset_nightly', '5 1 * * *', $$set statement_timeout = 0; select public.core_planner__nightly_roll4_reset();$$);      +
 
 -- Job 13: planner_roll4_tick_q15m                                                                                                                        +
 SELECT cron.schedule('planner_roll4_tick_q15m', '0 12 * * *', $$set statement_timeout=0; select public.core_planner__nightly_roll4_tick(2);$$);           +
 
 -- Job 28: ops_monitor_snapshot_q15m                                                                                                                      +
 SELECT cron.schedule('ops_monitor_snapshot_q15m', '*/15 * * * *', $$select public.ops_pipeline_monitor_snapshot();$$);                                    +
 
 -- Job 29: ops_auto_run_after_raw_q5m                                                                                                                     +
 SELECT cron.schedule('ops_auto_run_after_raw_q5m', '*/5 19-23 * * *', $$set statement_timeout=0; select public.ops_maybe_run_daily_pipeline();$$);        +
 
 -- Job 31: ops_pipeline_monitor_q5m                                                                                                                       +
 SELECT cron.schedule('ops_pipeline_monitor_q5m', '*/10 19-23 * * *', $$select public.ops_refresh_pipeline_monitor_snapshot();$$);                         +
 
 -- Job 32: ops_pipeline_monitor_10_12_q2m                                                                                                                 +
 SELECT cron.schedule('ops_pipeline_monitor_10_12_q2m', '*/2 10-12 * * *', $$select public.ops_refresh_pipeline_monitor_snapshot();$$);                    +
 
 -- Job 34: ops_pipeline_monitor_rest_q15m                                                                                                                 +
 SELECT cron.schedule('ops_pipeline_monitor_rest_q15m', '*/30 0-9,13-23 * * *', $$select public.ops_refresh_pipeline_monitor_snapshot();$$);               +
 
 -- Job 35: ops_monitor_5m_10_12_rome                                                                                                                      +
 SELECT cron.schedule('ops_monitor_5m_10_12_rome', '*/5 9-11 * * *', $$select public.ops_refresh_pipeline_monitor_snapshot();$$);                          +
 
 -- Job 37: ops_maybe_run_daily_5m_10_12_rome                                                                                                              +
 SELECT cron.schedule('ops_maybe_run_daily_5m_10_12_rome', '*/5 9-11 * * *', $$select public.ops_maybe_run_daily_pipeline();$$);                           +
 

