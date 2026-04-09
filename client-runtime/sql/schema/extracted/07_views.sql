-- GreenBrain Client Runtime — Views
-- Extracted from Supabase/local schema snapshot (sql/schema/current-schema.sql)
-- Wave 7B — DO NOT hand-edit; re-run extract-schema.py to regenerate
--
-- Apply order: 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
-- (tables before views, views before functions)
--
--
-- Name: greenhouse_forecast_windows_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_forecast_windows_v2 AS
 SELECT famiglia,
    fascia_prezzo_iva_inc,
    sum(
        CASE
            WHEN ((data >= (CURRENT_DATE + '1 day'::interval)) AND (data <= (CURRENT_DATE + '3 days'::interval))) THEN qty_forecast
            ELSE (0)::numeric
        END) AS qty_forecast_1_3,
    sum(
        CASE
            WHEN ((data >= (CURRENT_DATE + '4 days'::interval)) AND (data <= (CURRENT_DATE + '10 days'::interval))) THEN qty_forecast
            ELSE (0)::numeric
        END) AS qty_forecast_4_10
   FROM public.greenhouse_forecast_results_v2
  GROUP BY famiglia, fascia_prezzo_iva_inc;

--
-- Name: greenhouse_stock_enriched; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_stock_enriched AS
 SELECT s.data_rilevazione,
    s.codart,
    s.descrizione AS descrizione_stock,
    s.qty_giacenza,
    p.famiglia,
    p.fascia_prezzo_iva_inc,
    p.pot_size,
    p.fascia_corretta,
    p.categoria_corretta
   FROM (public.greenhouse_stock_raw_upload s
     LEFT JOIN public.greenhouse_products_normalized p ON ((s.codart = (p.codart)::text)));

--
-- Name: greenhouse_stock_family_latest_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_stock_family_latest_v2 AS
 WITH latest_date AS (
         SELECT max(s.data_rilevazione) AS data_rilevazione
           FROM public.greenhouse_stock_raw_upload s
        )
 SELECT e.data_rilevazione,
    e.famiglia,
    e.fascia_prezzo_iva_inc,
    sum(e.qty_giacenza) AS qty_giacenza
   FROM (public.greenhouse_stock_enriched e
     JOIN latest_date ld ON ((e.data_rilevazione = ld.data_rilevazione)))
  WHERE ((e.famiglia IS NOT NULL) AND (e.fascia_prezzo_iva_inc IS NOT NULL))
  GROUP BY e.data_rilevazione, e.famiglia, e.fascia_prezzo_iva_inc
  ORDER BY e.famiglia, e.fascia_prezzo_iva_inc;

--
-- Name: greenhouse_order_suggestions_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_order_suggestions_v2 AS
 WITH stock AS (
         SELECT greenhouse_stock_family_latest_v2.data_rilevazione,
            greenhouse_stock_family_latest_v2.famiglia,
            greenhouse_stock_family_latest_v2.fascia_prezzo_iva_inc,
            greenhouse_stock_family_latest_v2.qty_giacenza
           FROM public.greenhouse_stock_family_latest_v2
        ), params AS (
         SELECT 1.5 AS safety_factor
        )
 SELECT f.famiglia,
    f.fascia_prezzo_iva_inc,
    f.qty_forecast_1_3 AS demand_lead,
    f.qty_forecast_4_10 AS demand_cycle,
        CASE
            WHEN (s.famiglia IS NULL) THEN false
            ELSE true
        END AS in_assortimento,
    COALESCE(s.qty_giacenza, (0)::numeric) AS qty_giacenza,
    (COALESCE(s.qty_giacenza, (0)::numeric) - f.qty_forecast_1_3) AS stock_after_lead_raw,
    GREATEST((0)::numeric, (COALESCE(s.qty_giacenza, (0)::numeric) - f.qty_forecast_1_3)) AS stock_after_lead,
    (f.qty_forecast_4_10 * p.safety_factor) AS required_on_arrival,
    GREATEST((0)::numeric, ((f.qty_forecast_4_10 * p.safety_factor) - GREATEST((0)::numeric, (COALESCE(s.qty_giacenza, (0)::numeric) - f.qty_forecast_1_3)))) AS qty_da_ordinare,
        CASE
            WHEN (COALESCE(s.qty_giacenza, (0)::numeric) < f.qty_forecast_1_3) THEN true
            ELSE false
        END AS rischio_stockout_prima_di_arrivo
   FROM ((public.greenhouse_forecast_windows_v2 f
     LEFT JOIN stock s ON (((f.famiglia = (s.famiglia)::text) AND (f.fascia_prezzo_iva_inc = (s.fascia_prezzo_iva_inc)::text))))
     CROSS JOIN params p)
  ORDER BY f.famiglia, f.fascia_prezzo_iva_inc;

--
-- Name: greenhouse_sales_family_meta_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_sales_family_meta_v2 AS
 SELECT famiglia,
    fascia_prezzo_iva_inc,
    min(fascia_corretta) AS fascia_corretta,
    min(categoria_corretta) AS categoria_corretta,
    string_agg(DISTINCT ps, ','::text ORDER BY ps) AS pot_sizes_text,
    jsonb_agg(DISTINCT ps) AS pot_sizes_json
   FROM ( SELECT greenhouse_sales_family_daily_fact.famiglia,
            greenhouse_sales_family_daily_fact.fascia_prezzo_iva_inc,
            greenhouse_sales_family_daily_fact.fascia_corretta,
            greenhouse_sales_family_daily_fact.categoria_corretta,
            jsonb_array_elements_text(greenhouse_sales_family_daily_fact.pot_sizes_json) AS ps
           FROM public.greenhouse_sales_family_daily_fact) x
  GROUP BY famiglia, fascia_prezzo_iva_inc;

--
-- Name: greenhouse_order_suggestions_enriched_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_order_suggestions_enriched_v2 AS
 SELECT o.famiglia,
    o.fascia_prezzo_iva_inc,
    o.demand_lead,
    o.demand_cycle,
    o.in_assortimento,
    o.qty_giacenza,
    o.stock_after_lead_raw,
    o.stock_after_lead,
    o.required_on_arrival,
    o.qty_da_ordinare,
    o.rischio_stockout_prima_di_arrivo,
    m.fascia_corretta,
    m.categoria_corretta,
    m.pot_sizes_text,
    m.pot_sizes_json
   FROM (public.greenhouse_order_suggestions_v2 o
     LEFT JOIN public.greenhouse_sales_family_meta_v2 m ON (((o.famiglia = m.famiglia) AND (o.fascia_prezzo_iva_inc = m.fascia_prezzo_iva_inc))))
  WHERE (o.qty_da_ordinare >= (1)::numeric)
  ORDER BY o.famiglia, o.fascia_prezzo_iva_inc;

--
-- Name: v_family_execution_routing_v1; Type: VIEW; Schema: ml_forecast; Owner: -
--

CREATE VIEW ml_forecast.v_family_execution_routing_v1 AS
 SELECT r.family_name,
    r.business_tier,
    r.demand_class_final,
    r.model_code,
    r.execution_engine AS registry_execution_engine,
    r.bundle_version AS registry_bundle_version,
    s.is_active,
    s.needs_initial_train,
    s.needs_retrain,
    s.needs_predict,
    s.last_train_at,
    s.last_predict_at,
    s.last_train_status,
    s.last_predict_status,
    m.target_execution_engine,
    m.current_execution_engine,
        CASE
            WHEN (e.is_active = true) THEN m.current_execution_engine
            ELSE 'V4_TWEEDIE_BUNDLE'::text
        END AS effective_execution_engine,
        CASE
            WHEN (e.is_active = true) THEN 'engine_map_current'::text
            ELSE 'fallback_v4'::text
        END AS routing_source
   FROM (((ml_forecast.family_model_registry_v2 r
     LEFT JOIN ml_forecast.family_model_state_v1 s ON ((s.family_name = r.family_name)))
     LEFT JOIN ml_forecast.model_engine_map_v1 m ON ((m.model_code = r.model_code)))
     LEFT JOIN ml_forecast.execution_engine_catalog_v1 e ON ((e.execution_engine = m.current_execution_engine)));

--
-- Name: v_family_execution_routing_v2; Type: VIEW; Schema: ml_forecast; Owner: -
--

CREATE VIEW ml_forecast.v_family_execution_routing_v2 AS
 WITH base AS (
         SELECT r.family_name,
            r.business_tier,
            r.demand_class_final,
            a.model_code AS assignment_model_code,
            r.model_code AS registry_model_code,
            COALESCE(a.model_code, r.model_code, 'V4_TWEEDIE_BUNDLE'::text) AS effective_model_code,
                CASE
                    WHEN (a.model_code IS NOT NULL) THEN 'manual_assignment'::text
                    WHEN (r.model_code IS NOT NULL) THEN 'class_map'::text
                    ELSE 'fallback_v4'::text
                END AS routing_source,
            COALESCE(a.is_locked, false) AS is_locked,
            a.assigned_by,
            r.execution_engine AS registry_execution_engine,
            r.bundle_version AS registry_bundle_version,
            s.is_active,
            s.needs_initial_train,
            s.needs_retrain,
            s.needs_predict,
            s.last_train_at,
            s.last_predict_at,
            s.last_train_status,
            s.last_predict_status
           FROM ((ml_forecast.family_model_registry_v2 r
             LEFT JOIN ml_forecast.family_model_state_v1 s ON ((s.family_name = r.family_name)))
             LEFT JOIN ml_forecast.family_model_assignment_v1 a ON ((a.family_name = r.family_name)))
        )
 SELECT b.family_name,
    b.business_tier,
    b.demand_class_final,
    b.effective_model_code,
    b.effective_model_code AS model_code,
    b.assignment_model_code,
    b.registry_model_code,
    b.routing_source,
    b.is_locked,
    b.assigned_by,
    m.current_execution_engine,
    m.target_execution_engine,
        CASE
            WHEN (ec.is_active = true) THEN m.current_execution_engine
            ELSE 'V4_TWEEDIE_BUNDLE'::text
        END AS effective_execution_engine,
    b.registry_execution_engine,
    b.registry_bundle_version,
    b.is_active,
    b.needs_initial_train,
    b.needs_retrain,
    b.needs_predict,
    b.last_train_at,
    b.last_predict_at,
    b.last_train_status,
    b.last_predict_status
   FROM ((base b
     LEFT JOIN ml_forecast.model_engine_map_v1 m ON ((m.model_code = b.effective_model_code)))
     LEFT JOIN ml_forecast.execution_engine_catalog_v1 ec ON ((ec.execution_engine = m.current_execution_engine)));

--
-- Name: v_family_model_registry_v1; Type: VIEW; Schema: ml_forecast; Owner: -
--

CREATE VIEW ml_forecast.v_family_model_registry_v1 AS
 SELECT family_name,
    business_tier,
    value_total,
    qty_total,
    demand_class_final,
    model_code,
    model_name,
    model_family,
    is_seasonal,
    is_intermittent,
    default_horizon_days,
    update_frequency,
    seasonal_strength,
    burst_strength,
    weeks_active_ratio,
    months_active_ratio,
    zero_rate,
    avg_pos_run_len_max_v6,
    top3_months_share_max_v6,
    top10_days_share_max_v6,
    top4_weeks_share_max_v6,
    max_week_share,
    max_month_share,
    months_to_80_min_v6,
    adi_v7,
    registry_created_at
   FROM ml_forecast.family_model_registry_v1
  ORDER BY value_total DESC, family_name;

--
-- Name: v_family_rollout_status_v1; Type: VIEW; Schema: ml_forecast; Owner: -
--

CREATE VIEW ml_forecast.v_family_rollout_status_v1 AS
 SELECT r.family_name,
    r.business_tier,
    r.demand_class_final,
    r.model_code,
    r.execution_engine AS registry_execution_engine,
    r.bundle_version AS registry_bundle_version,
    m.target_execution_engine,
    m.current_execution_engine,
    m.rollout_stage,
    x.effective_execution_engine,
    x.routing_source,
    s.is_active,
    s.last_train_at,
    s.last_train_status,
    s.last_predict_at,
    s.last_predict_status,
    s.needs_initial_train,
    s.needs_retrain,
    s.needs_predict,
        CASE
            WHEN (a.family_name IS NOT NULL) THEN true
            ELSE false
        END AS has_active_artifact
   FROM ((((ml_forecast.family_model_registry_v2 r
     LEFT JOIN ml_forecast.family_model_state_v1 s ON ((s.family_name = r.family_name)))
     LEFT JOIN ml_forecast.model_engine_map_v1 m ON ((m.model_code = r.model_code)))
     LEFT JOIN ml_forecast.v_family_execution_routing_v1 x ON ((x.family_name = r.family_name)))
     LEFT JOIN ( SELECT DISTINCT model_artifact_registry_v1.family_name
           FROM ml_forecast.model_artifact_registry_v1
          WHERE (model_artifact_registry_v1.is_active = true)) a ON ((a.family_name = r.family_name)));

--
-- Name: v_assignment_status_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_assignment_status_v1 AS
 SELECT a.family_name,
    s.demand_class_final,
    a.model_code AS assigned_model_code,
    cm.model_code AS class_default_model,
        CASE
            WHEN (cm.model_code IS NULL) THEN 'no_class_default'::text
            WHEN (a.model_code = cm.model_code) THEN 'aligned'::text
            ELSE 'overridden'::text
        END AS alignment_status,
    a.is_locked,
    a.assigned_by,
    a.assigned_at,
    a.assignment_reason
   FROM ((ml_forecast.family_model_assignment_v1 a
     LEFT JOIN ml_forecast.family_model_state_v1 s ON ((s.family_name = a.family_name)))
     LEFT JOIN ml_forecast.class_model_map_v1 cm ON ((cm.demand_class_final = s.demand_class_final)))
  ORDER BY
        CASE
            WHEN a.is_locked THEN 0
            ELSE 1
        END,
        CASE
            WHEN (cm.model_code IS NULL) THEN 2
            WHEN (a.model_code = cm.model_code) THEN 1
            ELSE 0
        END, a.family_name;

--
-- Name: v_benchmark_best_model_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_benchmark_best_model_v1 AS
 WITH latest_run AS (
         SELECT DISTINCT ON (b.family_name) b.family_name,
            b.model_code AS best_model_code,
            b.wmape AS best_wmape,
            b.mae AS best_mae,
            b.run_id,
            r.started_at AS benchmarked_at,
            b.holdout_days
           FROM (ml_forecast.family_model_benchmark_v1 b
             JOIN ml_forecast.family_benchmark_run_v1 r ON ((r.run_id = b.run_id)))
          WHERE ((b.is_best = true) AND (r.status = 'done'::text))
          ORDER BY b.family_name, r.started_at DESC
        ), assigned_perf AS (
         SELECT b.family_name,
            b.model_code,
            b.wmape AS assigned_wmape,
            b.run_id
           FROM ml_forecast.family_model_benchmark_v1 b
          WHERE (EXISTS ( SELECT 1
                   FROM ml_forecast.family_model_assignment_v1 a_1
                  WHERE ((a_1.family_name = b.family_name) AND (a_1.model_code = b.model_code))))
        )
 SELECT lr.family_name,
    lr.best_model_code,
    lr.best_wmape,
    lr.best_mae,
    lr.benchmarked_at,
    lr.holdout_days,
    a.model_code AS assigned_model_code,
    ap.assigned_wmape,
        CASE
            WHEN (ap.assigned_wmape > (0)::numeric) THEN round((((ap.assigned_wmape - lr.best_wmape) / ap.assigned_wmape) * 100.0), 2)
            ELSE NULL::numeric
        END AS improvement_vs_assigned_pct,
    lr.run_id
   FROM ((latest_run lr
     LEFT JOIN ml_forecast.family_model_assignment_v1 a ON ((a.family_name = lr.family_name)))
     LEFT JOIN assigned_perf ap ON (((ap.family_name = lr.family_name) AND (ap.run_id = lr.run_id))));

--
-- Name: v_benchmark_suggestions_status_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_benchmark_suggestions_status_v1 AS
 WITH latest_sug AS (
         SELECT DISTINCT ON (s.family_name) s.suggestion_id,
            s.family_name,
            s.model_code AS suggested_model_code,
            s.competitor_model_code AS current_model_code,
            s.error_metric,
            s.error_value AS suggested_wmape,
            s.competitor_error_value AS current_wmape,
            s.improvement_pct,
            s.suggestion_strength,
            s.suppression_reason,
            s.is_best,
            s.is_applied,
            s.benchmark_run_id,
            s.suggested_at
           FROM ml_forecast.family_model_suggestion_benchmark_v1 s
          WHERE (s.is_applied = false)
          ORDER BY s.family_name, s.suggested_at DESC
        ), bm_quality AS (
         SELECT DISTINCT ON (b.family_name) b.family_name,
            b.holdout_sum_actual,
            b.holdout_nonzero_days,
            b.training_nonzero_days,
            b.training_sum_actual
           FROM (ml_forecast.family_model_benchmark_v1 b
             JOIN ml_forecast.family_benchmark_run_v1 r ON ((r.run_id = b.run_id)))
          WHERE ((b.is_best = true) AND (r.status = 'done'::text))
          ORDER BY b.family_name, b.competed_at DESC
        )
 SELECT ls.family_name,
    ls.suggested_model_code,
    ls.current_model_code,
    ls.suggested_wmape,
    ls.current_wmape,
    ls.improvement_pct,
    ls.suggestion_strength,
    ls.suppression_reason,
    ls.is_best,
    bq.holdout_sum_actual,
    bq.holdout_nonzero_days,
    bq.training_nonzero_days,
    bq.training_sum_actual,
    a.is_locked,
    ls.suggested_at,
    ls.suggestion_id,
    ls.benchmark_run_id,
        CASE
            WHEN (ls.suppression_reason IS NULL) THEN ls.suggestion_strength
            WHEN (ls.suppression_reason ~~ 'suppressed_%'::text) THEN ls.suggestion_strength
            ELSE
            CASE
                WHEN (ls.improvement_pct >= 10.0) THEN 'strong'::text
                WHEN (ls.improvement_pct >= 3.0) THEN 'moderate'::text
                WHEN (ls.improvement_pct >= 0.0) THEN 'weak'::text
                ELSE 'regression'::text
            END
        END AS suggestion_strength_raw,
        CASE
            WHEN (ls.suppression_reason ~~ 'suppressed_%'::text) THEN NULL::text
            ELSE ls.suggestion_strength
        END AS suggestion_strength_effective,
        CASE
            WHEN (ls.suppression_reason ~~ 'suppressed_%'::text) THEN 'suppressed'::text
            WHEN (ls.suppression_reason IS NOT NULL) THEN 'downgraded'::text
            ELSE 'clean'::text
        END AS decision_status
   FROM ((latest_sug ls
     LEFT JOIN ml_forecast.family_model_assignment_v1 a ON ((a.family_name = ls.family_name)))
     LEFT JOIN bm_quality bq ON ((bq.family_name = ls.family_name)))
  ORDER BY ls.improvement_pct DESC NULLS LAST, ls.family_name;

--
-- Name: v_benchmark_admin_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_benchmark_admin_v1 AS
 SELECT s.family_name,
    s.demand_class_final,
    a.model_code AS assigned_model_code,
    a.is_locked,
    bm.best_model_code,
    bm.best_wmape,
    bm.assigned_wmape,
    bm.improvement_vs_assigned_pct,
    bm.benchmarked_at,
    sug.suggested_model_code,
    sug.suggestion_strength,
    sug.suggestion_strength_raw,
    sug.suggestion_strength_effective,
    sug.suppression_reason,
    sug.decision_status,
    sug.improvement_pct AS suggestion_improvement_pct,
    sug.holdout_sum_actual,
    sug.holdout_nonzero_days,
    sug.training_nonzero_days,
        CASE
            WHEN (sug.suggestion_id IS NOT NULL) THEN true
            ELSE false
        END AS has_open_suggestion,
        CASE
            WHEN (sug.suppression_reason IS NOT NULL) THEN true
            ELSE false
        END AS is_downgraded,
        CASE
            WHEN ((sug.suggestion_id IS NOT NULL) AND (sug.suppression_reason IS NULL)) THEN 'clean'::text
            WHEN ((sug.suggestion_id IS NOT NULL) AND (sug.suppression_reason ~~ 'suppressed_%'::text)) THEN 'suppressed'::text
            WHEN ((sug.suggestion_id IS NOT NULL) AND (sug.suppression_reason IS NOT NULL)) THEN 'downgraded'::text
            WHEN ((bm.best_model_code IS NOT NULL) AND (sug.suggestion_id IS NULL) AND (bm.best_model_code = a.model_code)) THEN 'already_optimal'::text
            WHEN ((bm.best_model_code IS NOT NULL) AND (sug.suggestion_id IS NULL)) THEN 'suppressed_or_no_change'::text
            ELSE 'no_benchmark'::text
        END AS suggestion_status,
    s.last_train_at,
    s.last_predict_at
   FROM (((ml_forecast.family_model_state_v1 s
     LEFT JOIN ml_forecast.family_model_assignment_v1 a ON ((a.family_name = s.family_name)))
     LEFT JOIN ml_ops.v_benchmark_best_model_v1 bm ON ((bm.family_name = s.family_name)))
     LEFT JOIN ml_ops.v_benchmark_suggestions_status_v1 sug ON ((sug.family_name = s.family_name)))
  WHERE (s.is_active = true)
  ORDER BY bm.improvement_vs_assigned_pct DESC NULLS LAST, s.family_name;

--
-- Name: v_benchmark_recent_runs_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_benchmark_recent_runs_v1 AS
 SELECT run_id,
    scope,
    scope_detail,
    holdout_days,
    status,
    families_total,
    families_done,
    models_tested,
    started_at,
    finished_at,
    round((EXTRACT(epoch FROM (COALESCE(finished_at, now()) - started_at)) / 60.0), 1) AS duration_min,
    triggered_by,
    notes
   FROM ml_forecast.family_benchmark_run_v1 r
  ORDER BY started_at DESC
 LIMIT 50;

--
-- Name: v_daily_pipeline_summary_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_daily_pipeline_summary_v1 AS
 SELECT (date_trunc('day'::text, started_at))::date AS day,
    job_type,
    count(*) AS runs,
    count(*) FILTER (WHERE (status = 'success'::text)) AS ok_runs,
    count(*) FILTER (WHERE (status = 'failed'::text)) AS bad_runs,
    min(started_at) AS first_run_at,
    max(finished_at) AS last_finished_at
   FROM ml_ops.pipeline_run_log_v1
  GROUP BY ((date_trunc('day'::text, started_at))::date), job_type
  ORDER BY ((date_trunc('day'::text, started_at))::date) DESC, job_type;

--
-- Name: v_family_health_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_family_health_v1 AS
 SELECT s.family_name,
    s.business_tier,
    s.demand_class_final,
    a.model_code AS assigned_model_code,
    COALESCE(m.current_execution_engine, 'V4_TWEEDIE_BUNDLE'::text) AS effective_engine,
    a.is_locked,
    a.assigned_by,
    a.assigned_at,
        CASE
            WHEN (a.model_code IS NOT NULL) THEN 'manual_assignment'::text
            WHEN (s.model_code IS NOT NULL) THEN 'class_map'::text
            ELSE 'fallback_v4'::text
        END AS routing_source,
    s.last_train_at,
    s.last_train_status,
    s.needs_initial_train,
    s.needs_retrain,
    s.last_predict_at,
    s.last_predict_status,
    s.needs_predict,
    fmax.max_forecast_date,
    CURRENT_DATE AS today,
    (fmax.max_forecast_date - CURRENT_DATE) AS forecast_days_ahead,
        CASE
            WHEN (fmax.max_forecast_date IS NULL) THEN 'no_forecast'::text
            WHEN (fmax.max_forecast_date < CURRENT_DATE) THEN 'expired'::text
            WHEN (fmax.max_forecast_date < (CURRENT_DATE + 7)) THEN 'near_expiry'::text
            ELSE 'fresh'::text
        END AS forecast_status
   FROM (((ml_forecast.family_model_state_v1 s
     LEFT JOIN ml_forecast.family_model_assignment_v1 a ON ((a.family_name = s.family_name)))
     LEFT JOIN ml_forecast.model_engine_map_v1 m ON ((m.model_code = COALESCE(a.model_code, s.model_code, 'V4_TWEEDIE_BUNDLE'::text))))
     LEFT JOIN ( SELECT greenhouse_forecast_results_v2.famiglia AS family_name,
            max(greenhouse_forecast_results_v2.data) AS max_forecast_date
           FROM public.greenhouse_forecast_results_v2
          GROUP BY greenhouse_forecast_results_v2.famiglia) fmax ON ((fmax.family_name = s.family_name)))
  WHERE (s.is_active = true);

--
-- Name: v_family_ops_status_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_family_ops_status_v1 AS
 WITH last_train AS (
         SELECT DISTINCT ON (family_run_log_v1.family_name) family_run_log_v1.family_name,
            family_run_log_v1.family_run_id AS train_family_run_id,
            family_run_log_v1.started_at AS train_started_at,
            family_run_log_v1.finished_at AS train_finished_at,
            family_run_log_v1.status AS train_status,
            family_run_log_v1.error_message AS train_error_message,
            family_run_log_v1.error_trace AS train_error_trace,
            family_run_log_v1.artifact_path
           FROM ml_ops.family_run_log_v1
          WHERE (family_run_log_v1.job_type ~~* 'train%'::text)
          ORDER BY family_run_log_v1.family_name, family_run_log_v1.started_at DESC
        ), last_predict AS (
         SELECT DISTINCT ON (family_run_log_v1.family_name) family_run_log_v1.family_name,
            family_run_log_v1.family_run_id AS predict_family_run_id,
            family_run_log_v1.started_at AS predict_started_at,
            family_run_log_v1.finished_at AS predict_finished_at,
            family_run_log_v1.status AS predict_status,
            family_run_log_v1.rows_written AS predict_rows_written,
            family_run_log_v1.error_message AS predict_error_message,
            family_run_log_v1.error_trace AS predict_error_trace
           FROM ml_ops.family_run_log_v1
          WHERE (family_run_log_v1.job_type ~~* 'predict%'::text)
          ORDER BY family_run_log_v1.family_name, family_run_log_v1.started_at DESC
        )
 SELECT s.family_name,
    s.demand_class_final,
    s.last_train_at,
    s.last_train_status,
    s.needs_initial_train,
    s.needs_retrain,
    s.last_predict_at,
    s.last_predict_status,
    s.needs_predict,
    round((EXTRACT(epoch FROM (now() - s.last_train_at)) / 86400.0), 1) AS bundle_age_days,
    lt.artifact_path AS bundle_path,
        CASE
            WHEN (s.last_train_at IS NULL) THEN 'never_trained'::text
            WHEN (s.last_train_status = 'failed'::text) THEN 'train_failed'::text
            WHEN (s.last_predict_status = 'failed'::text) THEN 'predict_failed'::text
            WHEN (s.last_train_at < (now() - '90 days'::interval)) THEN 'stale_90d'::text
            ELSE 'ok'::text
        END AS model_state,
    lt.train_family_run_id,
    lt.train_started_at,
    lt.train_finished_at,
    lt.train_status,
    lt.train_error_message,
    lt.train_error_trace,
    lp.predict_family_run_id,
    lp.predict_started_at,
    lp.predict_finished_at,
    lp.predict_status,
    lp.predict_rows_written,
    lp.predict_error_message,
    lp.predict_error_trace
   FROM ((ml_forecast.family_model_state_v1 s
     LEFT JOIN last_train lt ON ((lt.family_name = s.family_name)))
     LEFT JOIN last_predict lp ON ((lp.family_name = s.family_name)))
  ORDER BY s.family_name;

--
-- Name: v_forecast_admin_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_forecast_admin_v1 AS
 SELECT s.family_name,
    s.business_tier,
    s.demand_class_final,
    a.model_code AS assigned_model_code,
    COALESCE(m.current_execution_engine, 'V4_TWEEDIE_BUNDLE'::text) AS effective_engine,
    a.is_locked,
    a.assigned_by,
        CASE
            WHEN (a.model_code IS NOT NULL) THEN 'manual_assignment'::text
            WHEN (s.model_code IS NOT NULL) THEN 'class_map'::text
            ELSE 'fallback_v4'::text
        END AS routing_source,
        CASE
            WHEN (cm.model_code IS NULL) THEN 'no_class_default'::text
            WHEN (a.model_code = cm.model_code) THEN 'aligned'::text
            ELSE 'overridden'::text
        END AS alignment_status,
    s.last_train_at,
    s.last_train_status,
    s.needs_initial_train,
    s.needs_retrain,
    s.last_predict_at,
    s.last_predict_status,
    s.needs_predict,
    fmax.max_forecast_date,
    (fmax.max_forecast_date - CURRENT_DATE) AS forecast_days_ahead,
        CASE
            WHEN (fmax.max_forecast_date IS NULL) THEN 'no_forecast'::text
            WHEN (fmax.max_forecast_date < CURRENT_DATE) THEN 'expired'::text
            WHEN (fmax.max_forecast_date < (CURRENT_DATE + 7)) THEN 'near_expiry'::text
            ELSE 'fresh'::text
        END AS forecast_status
   FROM ((((ml_forecast.family_model_state_v1 s
     LEFT JOIN ml_forecast.family_model_assignment_v1 a ON ((a.family_name = s.family_name)))
     LEFT JOIN ml_forecast.model_engine_map_v1 m ON ((m.model_code = COALESCE(a.model_code, s.model_code, 'V4_TWEEDIE_BUNDLE'::text))))
     LEFT JOIN ml_forecast.class_model_map_v1 cm ON ((cm.demand_class_final = s.demand_class_final)))
     LEFT JOIN ( SELECT greenhouse_forecast_results_v2.famiglia AS family_name,
            max(greenhouse_forecast_results_v2.data) AS max_forecast_date
           FROM public.greenhouse_forecast_results_v2
          GROUP BY greenhouse_forecast_results_v2.famiglia) fmax ON ((fmax.family_name = s.family_name)))
  WHERE (s.is_active = true)
  ORDER BY s.business_tier, s.family_name;

--
-- Name: v_forecast_freshness_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_forecast_freshness_v1 AS
 SELECT s.family_name,
    s.business_tier,
    s.demand_class_final,
    fmax.max_forecast_date,
    CURRENT_DATE AS today,
    (fmax.max_forecast_date - CURRENT_DATE) AS days_ahead,
        CASE
            WHEN (fmax.max_forecast_date IS NULL) THEN 'no_forecast'::text
            WHEN (fmax.max_forecast_date < CURRENT_DATE) THEN 'expired'::text
            WHEN (fmax.max_forecast_date < (CURRENT_DATE + 7)) THEN 'near_expiry'::text
            ELSE 'fresh'::text
        END AS freshness_status,
    s.last_predict_at,
    s.last_predict_status
   FROM (ml_forecast.family_model_state_v1 s
     LEFT JOIN ( SELECT greenhouse_forecast_results_v2.famiglia AS family_name,
            max(greenhouse_forecast_results_v2.data) AS max_forecast_date
           FROM public.greenhouse_forecast_results_v2
          GROUP BY greenhouse_forecast_results_v2.famiglia) fmax ON ((fmax.family_name = s.family_name)))
  WHERE (s.is_active = true)
  ORDER BY fmax.max_forecast_date NULLS FIRST, s.family_name;

--
-- Name: v_model_stale_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_model_stale_v1 AS
 SELECT family_name,
    demand_class_final,
    last_train_at,
    bundle_age_days,
    model_state,
    bundle_path
   FROM ml_ops.v_family_ops_status_v1
  WHERE ((model_state = ANY (ARRAY['stale_90d'::text, 'never_trained'::text, 'train_failed'::text])) OR (needs_initial_train = true) OR (needs_retrain = true))
  ORDER BY bundle_age_days DESC;

--
-- Name: v_pipeline_runs_recent_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_pipeline_runs_recent_v1 AS
 SELECT run_id,
    job_type,
    trigger_mode,
    status,
    started_at,
    finished_at,
    round((EXTRACT(epoch FROM (COALESCE(finished_at, now()) - started_at)) / 60.0), 1) AS duration_min,
    host_name,
    rows_processed,
    error_message,
    git_sha,
    notes
   FROM ml_ops.pipeline_run_log_v1
  ORDER BY started_at DESC, run_id DESC;

--
-- Name: v_predict_daily_candidates_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_predict_daily_candidates_v1 AS
 SELECT s.family_name,
    s.business_tier,
    s.demand_class_final,
    s.model_code,
    r.value_total,
    r.qty_total,
    s.last_train_at,
    s.last_predict_at
   FROM (ml_forecast.family_model_state_v1 s
     JOIN ml_forecast.family_model_registry_v2 r ON ((r.family_name = s.family_name)))
  WHERE ((s.is_active = true) AND (s.needs_initial_train = false) AND (COALESCE(s.last_train_status, 'missing'::text) = 'success'::text) AND ((s.last_predict_at IS NULL) OR ((s.last_predict_at)::date < CURRENT_DATE)))
  ORDER BY r.value_total DESC, s.family_name;

--
-- Name: v_predict_failures_last7d_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_predict_failures_last7d_v1 AS
 SELECT family_name,
    job_type,
    model_code,
    started_at,
    finished_at,
    round(EXTRACT(epoch FROM (finished_at - started_at)), 1) AS duration_sec,
    status,
    error_message
   FROM ml_ops.family_run_log_v1 r
  WHERE ((job_type ~~* 'predict%'::text) AND (status = 'failed'::text) AND (started_at >= (now() - '7 days'::interval)))
  ORDER BY started_at DESC;

--
-- Name: v_registry_health_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_registry_health_v1 AS
 SELECT r.family_name,
    r.business_tier,
    r.demand_class_final,
    r.model_code,
    s.execution_engine,
    s.bundle_version,
    s.last_train_at,
    s.last_predict_at,
    s.last_train_status,
    s.last_predict_status,
    s.needs_reclass,
    s.needs_retrain,
    s.needs_predict,
        CASE
            WHEN (a.family_name IS NOT NULL) THEN true
            ELSE false
        END AS has_active_artifact
   FROM ((ml_forecast.family_model_registry_v2 r
     LEFT JOIN ml_forecast.family_model_state_v1 s ON ((s.family_name = r.family_name)))
     LEFT JOIN ( SELECT DISTINCT model_artifact_registry_v1.family_name
           FROM ml_forecast.model_artifact_registry_v1
          WHERE (model_artifact_registry_v1.is_active = true)) a ON ((a.family_name = r.family_name)));

--
-- Name: v_registry_summary_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_registry_summary_v1 AS
 SELECT demand_class_final,
    model_code,
    count(*) AS n_families,
    round(sum(value_total), 2) AS total_value,
    round(sum(qty_total), 2) AS total_qty
   FROM ml_forecast.family_model_registry_v2
  GROUP BY demand_class_final, model_code
  ORDER BY (round(sum(value_total), 2)) DESC;

--
-- Name: v_state_summary_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_state_summary_v1 AS
 SELECT count(*) AS n_families,
    count(*) FILTER (WHERE (COALESCE(is_active, true) = true)) AS n_active,
    count(*) FILTER (WHERE (last_train_at IS NULL)) AS n_never_trained,
    count(*) FILTER (WHERE (needs_initial_train = true)) AS n_needs_initial_train,
    count(*) FILTER (WHERE (needs_retrain = true)) AS n_needs_retrain,
    count(*) FILTER (WHERE (needs_predict = true)) AS n_needs_predict,
    count(*) FILTER (WHERE ((last_train_at IS NOT NULL) AND (last_train_at < (now() - '14 days'::interval)))) AS n_older_than_14d
   FROM ml_forecast.family_model_state_v1 s;

--
-- Name: v_train_biweekly_candidates_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_train_biweekly_candidates_v1 AS
 SELECT r.family_name,
    r.business_tier,
    r.demand_class_final,
    r.model_code,
    COALESCE(s.execution_engine, 'V4_TWEEDIE_BUNDLE'::text) AS execution_engine,
    COALESCE(s.bundle_version, 'v4'::text) AS bundle_version,
    s.last_train_at,
    s.last_train_status,
    s.needs_initial_train,
    s.needs_retrain,
    s.needs_predict,
        CASE
            WHEN (a.family_name IS NOT NULL) THEN true
            ELSE false
        END AS has_active_artifact,
        CASE
            WHEN (s.last_train_at IS NULL) THEN 'never_trained'::text
            WHEN (s.needs_retrain = true) THEN 'flagged_retrain'::text
            WHEN (s.last_train_at < (now() - '14 days'::interval)) THEN 'older_than_14d'::text
            ELSE 'not_candidate'::text
        END AS candidate_reason
   FROM ((ml_forecast.family_model_registry_v2 r
     LEFT JOIN ml_forecast.family_model_state_v1 s ON ((s.family_name = r.family_name)))
     LEFT JOIN ( SELECT DISTINCT model_artifact_registry_v1.family_name
           FROM ml_forecast.model_artifact_registry_v1
          WHERE (model_artifact_registry_v1.is_active = true)) a ON ((a.family_name = r.family_name)))
  WHERE ((COALESCE(s.is_active, true) = true) AND (COALESCE(s.disable_reason, ''::text) = ''::text) AND ((s.last_train_at IS NULL) OR (s.needs_retrain = true) OR (s.last_train_at < (now() - '14 days'::interval))));

--
-- Name: v_train_failures_last7d_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_train_failures_last7d_v1 AS
 SELECT family_name,
    job_type,
    model_code,
    started_at,
    finished_at,
    round(EXTRACT(epoch FROM (finished_at - started_at)), 1) AS duration_sec,
    status,
    error_message
   FROM ml_ops.family_run_log_v1 r
  WHERE ((job_type ~~* 'train%'::text) AND (status = 'failed'::text) AND (started_at >= (now() - '7 days'::interval)))
  ORDER BY started_at DESC;

--
-- Name: v_train_missing_candidates_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_train_missing_candidates_v1 AS
 SELECT s.family_name,
    s.business_tier,
    s.demand_class_final,
    s.model_code,
    r.value_total,
    r.qty_total,
    s.last_train_at,
    s.needs_initial_train
   FROM (ml_forecast.family_model_state_v1 s
     JOIN ml_forecast.family_model_registry_v2 r ON ((r.family_name = s.family_name)))
  WHERE ((s.is_active = true) AND ((s.needs_initial_train = true) OR (s.last_train_at IS NULL)))
  ORDER BY r.value_total DESC, s.family_name;

--
-- Name: v_train_weekly_candidates_v1; Type: VIEW; Schema: ml_ops; Owner: -
--

CREATE VIEW ml_ops.v_train_weekly_candidates_v1 AS
 SELECT s.family_name,
    s.business_tier,
    s.demand_class_final,
    s.model_code,
    r.value_total,
    r.qty_total,
    s.last_train_at
   FROM (ml_forecast.family_model_state_v1 s
     JOIN ml_forecast.family_model_registry_v2 r ON ((r.family_name = s.family_name)))
  WHERE ((s.is_active = true) AND (s.needs_initial_train = false) AND ((s.last_train_at IS NULL) OR (s.last_train_at < (now() - '7 days'::interval))))
  ORDER BY r.value_total DESC, s.family_name;

--
-- Name: greenhouse_sales_enriched; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_sales_enriched AS
 SELECT s.progressivo,
    s.codart,
    s.descrizione AS descrizione_vendita,
    s.tipo,
    s.fascia,
    s.categoria,
    s.quantita,
    s.imponibilenetto,
    s.data_movimento AS data,
    s.disattivato,
    s.movim_cassa,
    p.fascia_corretta,
    p.categoria_corretta,
    p.famiglia,
    p.descrizione AS descrizione_articolo,
    p.prezzo_iva_esclusa,
    p.prezzo_iva_inclusa,
    p.fascia_prezzo_iva_inc,
    p.pot_size
   FROM (public.greenhouse_sales_raw s
     JOIN public.greenhouse_products_normalized p ON (((s.codart)::text = (p.codart)::text)));

--
-- Name: core_analytics__article_sales_daily; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__article_sales_daily AS
 SELECT s.data,
    s.famiglia,
    s.categoria_corretta,
    s.fascia_corretta,
    s.fascia_prezzo_iva_inc,
    s.codart,
    s.descrizione_articolo AS articolo_nome,
    s.pot_size,
    sum(s.quantita) AS qty,
    sum(s.imponibilenetto) AS imponibile_netto,
    sum(s.quantita) AS qty_venduta,
    NULL::numeric AS qty_forecast,
    (EXTRACT(dow FROM s.data))::integer AS dow,
    COALESCE(h.is_holiday, false) AS is_holiday,
    h.holiday_name
   FROM (public.greenhouse_sales_enriched s
     LEFT JOIN public.greenhouse_holidays h ON ((h.data = s.data)))
  GROUP BY s.data, s.famiglia, s.categoria_corretta, s.fascia_corretta, s.fascia_prezzo_iva_inc, s.codart, s.descrizione_articolo, s.pot_size, h.is_holiday, h.holiday_name;

--
-- Name: core_analytics__breakdown_daily_categoria_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_daily_categoria_fp AS
 SELECT data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast,
    dow,
    is_holiday,
    holiday_name
   FROM public.t_core_analytics__breakdown_daily_categoria_fp;

--
-- Name: core_analytics__breakdown_daily_categoria_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_daily_categoria_fp_v2 AS
 SELECT data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast,
    dow,
    is_holiday,
    holiday_name
   FROM public.t_core_analytics__breakdown_daily_categoria_fp_v2;

--
-- Name: core_analytics__breakdown_daily_famiglia_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_daily_famiglia_fp AS
 SELECT data,
    btrim(translate(entity_key_lc, chr(160), ' '::text)) AS entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast,
    dow,
    is_holiday,
    holiday_name
   FROM public.t_core_analytics__breakdown_daily_famiglia_fp;

--
-- Name: core_analytics__breakdown_daily_famiglia_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_daily_famiglia_fp_v2 AS
 SELECT data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast,
    dow,
    is_holiday,
    holiday_name
   FROM public.t_core_analytics__breakdown_daily_famiglia_fp_v2;

--
-- Name: core_analytics__breakdown_daily_fascia_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_daily_fascia_fp_v2 AS
 SELECT data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast,
    dow,
    is_holiday,
    holiday_name
   FROM public.t_core_analytics__breakdown_daily_fascia_fp_v2;

--
-- Name: core_analytics__breakdown_monthly_categoria_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_monthly_categoria_fp AS
 SELECT period_start AS data,
    lower(btrim(entity_key_lc)) AS entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast
   FROM public.t_core_analytics__breakdown_monthly_categoria_fp;

--
-- Name: core_analytics__breakdown_monthly_categoria_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_monthly_categoria_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_monthly_categoria_fp_v2;

--
-- Name: core_analytics__breakdown_monthly_famiglia_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_monthly_famiglia_fp AS
 SELECT period_start AS data,
    lower(btrim(entity_key_lc)) AS entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast
   FROM public.t_core_analytics__breakdown_monthly_famiglia_fp;

--
-- Name: core_analytics__breakdown_monthly_famiglia_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_monthly_famiglia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_monthly_famiglia_fp_v2;

--
-- Name: core_analytics__breakdown_monthly_fascia_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_monthly_fascia_fp AS
 SELECT period_start AS data,
    lower(btrim(entity_key_lc)) AS entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast
   FROM public.t_core_analytics__breakdown_monthly_fascia_fp;

--
-- Name: core_analytics__breakdown_monthly_fascia_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_monthly_fascia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_monthly_fascia_fp_v2;

--
-- Name: core_analytics__breakdown_weekly_categoria_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_weekly_categoria_fp AS
 SELECT period_start AS data,
    lower(btrim(entity_key_lc)) AS entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast
   FROM public.t_core_analytics__breakdown_weekly_categoria_fp;

--
-- Name: core_analytics__breakdown_weekly_categoria_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_weekly_categoria_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_weekly_categoria_fp_v2;

--
-- Name: core_analytics__breakdown_weekly_famiglia_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_weekly_famiglia_fp AS
 SELECT period_start AS data,
    lower(btrim(entity_key_lc)) AS entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast
   FROM public.t_core_analytics__breakdown_weekly_famiglia_fp;

--
-- Name: core_analytics__breakdown_weekly_famiglia_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_weekly_famiglia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_weekly_famiglia_fp_v2;

--
-- Name: core_analytics__breakdown_weekly_fascia_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_weekly_fascia_fp AS
 SELECT period_start AS data,
    lower(btrim(entity_key_lc)) AS entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast
   FROM public.t_core_analytics__breakdown_weekly_fascia_fp;

--
-- Name: core_analytics__breakdown_weekly_fascia_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_weekly_fascia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_weekly_fascia_fp_v2;

--
-- Name: core_analytics__breakdown_yearly_categoria_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_yearly_categoria_fp AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast
   FROM public.t_core_analytics__breakdown_yearly_categoria_fp;

--
-- Name: core_analytics__breakdown_yearly_categoria_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_yearly_categoria_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_yearly_categoria_fp_v2;

--
-- Name: core_analytics__breakdown_yearly_famiglia_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_yearly_famiglia_fp AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast
   FROM public.t_core_analytics__breakdown_yearly_famiglia_fp;

--
-- Name: core_analytics__breakdown_yearly_famiglia_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_yearly_famiglia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_yearly_famiglia_fp_v2;

--
-- Name: core_analytics__breakdown_yearly_fascia_fp; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_yearly_fascia_fp AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    qty_forecast
   FROM public.t_core_analytics__breakdown_yearly_fascia_fp;

--
-- Name: core_analytics__breakdown_yearly_fascia_fp_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__breakdown_yearly_fascia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_yearly_fascia_fp_v2;

--
-- Name: core_analytics__catalog; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__catalog AS
 SELECT DISTINCT 'famiglia'::text AS entity_type,
    greenhouse_forecast_features_dense.famiglia AS entity_key,
    greenhouse_forecast_features_dense.famiglia AS label
   FROM public.greenhouse_forecast_features_dense
  WHERE (greenhouse_forecast_features_dense.famiglia IS NOT NULL)
UNION ALL
 SELECT DISTINCT 'categoria'::text AS entity_type,
    greenhouse_forecast_features_dense.categoria_corretta AS entity_key,
    greenhouse_forecast_features_dense.categoria_corretta AS label
   FROM public.greenhouse_forecast_features_dense
  WHERE (greenhouse_forecast_features_dense.categoria_corretta IS NOT NULL)
UNION ALL
 SELECT DISTINCT 'fascia'::text AS entity_type,
    greenhouse_forecast_features_dense.fascia_corretta AS entity_key,
    greenhouse_forecast_features_dense.fascia_corretta AS label
   FROM public.greenhouse_forecast_features_dense
  WHERE (greenhouse_forecast_features_dense.fascia_corretta IS NOT NULL)
UNION ALL
 SELECT DISTINCT 'fascia_prezzo'::text AS entity_type,
    greenhouse_forecast_features_dense.fascia_prezzo_iva_inc AS entity_key,
    greenhouse_forecast_features_dense.fascia_prezzo_iva_inc AS label
   FROM public.greenhouse_forecast_features_dense
  WHERE (greenhouse_forecast_features_dense.fascia_prezzo_iva_inc IS NOT NULL);

--
-- Name: core_analytics__catalog_search; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__catalog_search AS
 WITH fam AS (
         SELECT 'famiglia'::text AS entity_type,
            lower(greenhouse_forecast_features_dense.famiglia) AS entity_key,
            greenhouse_forecast_features_dense.famiglia AS label
           FROM public.greenhouse_forecast_features_dense
          WHERE (greenhouse_forecast_features_dense.famiglia IS NOT NULL)
          GROUP BY 'famiglia'::text, (lower(greenhouse_forecast_features_dense.famiglia)), greenhouse_forecast_features_dense.famiglia
        ), cat AS (
         SELECT 'categoria'::text AS entity_type,
            lower(greenhouse_forecast_features_dense.categoria_corretta) AS entity_key,
            greenhouse_forecast_features_dense.categoria_corretta AS label
           FROM public.greenhouse_forecast_features_dense
          WHERE (greenhouse_forecast_features_dense.categoria_corretta IS NOT NULL)
          GROUP BY 'categoria'::text, (lower(greenhouse_forecast_features_dense.categoria_corretta)), greenhouse_forecast_features_dense.categoria_corretta
        ), fas AS (
         SELECT 'fascia'::text AS entity_type,
            lower(greenhouse_forecast_features_dense.fascia_corretta) AS entity_key,
            greenhouse_forecast_features_dense.fascia_corretta AS label
           FROM public.greenhouse_forecast_features_dense
          WHERE (greenhouse_forecast_features_dense.fascia_corretta IS NOT NULL)
          GROUP BY 'fascia'::text, (lower(greenhouse_forecast_features_dense.fascia_corretta)), greenhouse_forecast_features_dense.fascia_corretta
        ), fp AS (
         SELECT 'fascia_prezzo'::text AS entity_type,
            lower(greenhouse_forecast_features_dense.fascia_prezzo_iva_inc) AS entity_key,
            greenhouse_forecast_features_dense.fascia_prezzo_iva_inc AS label
           FROM public.greenhouse_forecast_features_dense
          WHERE (greenhouse_forecast_features_dense.fascia_prezzo_iva_inc IS NOT NULL)
          GROUP BY 'fascia_prezzo'::text, (lower(greenhouse_forecast_features_dense.fascia_prezzo_iva_inc)), greenhouse_forecast_features_dense.fascia_prezzo_iva_inc
        )
 SELECT fam.entity_type,
    fam.entity_key,
    fam.label
   FROM fam
UNION ALL
 SELECT cat.entity_type,
    cat.entity_key,
    cat.label
   FROM cat
UNION ALL
 SELECT fas.entity_type,
    fas.entity_key,
    fas.label
   FROM fas
UNION ALL
 SELECT fp.entity_type,
    fp.entity_key,
    fp.label
   FROM fp;

--
-- Name: core_analytics__components_articles; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__components_articles AS
 SELECT famiglia,
    categoria_corretta,
    fascia_corretta,
    fascia_prezzo_iva_inc,
    codart,
    descrizione AS articolo_nome,
    pot_size,
    prezzo_iva_inclusa,
    prezzo_iva_esclusa
   FROM public.greenhouse_products_normalized p
  WHERE (codart IS NOT NULL);

--
-- Name: core_analytics__series_daily; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily AS
 SELECT f.data,
    f.famiglia,
    f.fascia_corretta,
    f.categoria_corretta,
    f.fascia_prezzo_iva_inc,
    f.qty_venduta,
    f.imponibile_netto_tot,
    f.num_articoli,
    COALESCE(f.is_holiday, false) AS is_holiday,
    f.holiday_name,
    f.dow,
    f.week_num,
    f.month_num,
    f.year_num,
    fc.qty_forecast
   FROM (public.greenhouse_forecast_features_dense f
     LEFT JOIN public.greenhouse_forecast_results_v2 fc ON (((fc.data = f.data) AND (lower(fc.famiglia) = lower(f.famiglia)) AND (fc.fascia_prezzo_iva_inc = f.fascia_prezzo_iva_inc))));

--
-- Name: core_analytics__heatmap_dow_month; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__heatmap_dow_month AS
 SELECT famiglia,
    categoria_corretta,
    fascia_corretta,
    fascia_prezzo_iva_inc,
    month_num,
    dow,
    avg(qty_venduta) AS avg_qty
   FROM public.core_analytics__series_daily
  GROUP BY famiglia, categoria_corretta, fascia_corretta, fascia_prezzo_iva_inc, month_num, dow;

--
-- Name: core_analytics__seasonality_month; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__seasonality_month AS
 SELECT entity_type,
    entity_key_lc,
    month_num,
    avg_qty_per_day,
    sum_qty,
    avg_rev_per_day,
    sum_rev,
    n_days
   FROM public.t_core_analytics__seasonality_month;

--
-- Name: core_analytics__series_daily_categoria; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_categoria AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_categoria;

--
-- Name: core_analytics__series_daily_categoria_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_categoria_lc AS
 SELECT data,
    lower(entity_key) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_categoria;

--
-- Name: core_analytics__series_daily_categoria_v; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_categoria_v AS
 SELECT data,
    categoria_corretta AS entity_key,
    sum(qty_venduta) AS qty_venduta_tot,
    sum(imponibile_netto_tot) AS imponibile_netto_tot,
    sum(COALESCE(qty_forecast, (0)::numeric)) AS qty_forecast_tot,
    bool_or(is_holiday) AS is_holiday,
    max(holiday_name) AS holiday_name,
    max(dow) AS dow
   FROM public.core_analytics__series_daily
  WHERE (categoria_corretta IS NOT NULL)
  GROUP BY data, categoria_corretta;

--
-- Name: core_analytics__series_daily_famiglia; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_famiglia AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_famiglia;

--
-- Name: core_analytics__series_daily_famiglia_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_famiglia_lc AS
 SELECT data,
    lower(entity_key) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.core_analytics__series_daily_famiglia;

--
-- Name: core_analytics__series_daily_famiglia_slow; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_famiglia_slow AS
 SELECT data,
    famiglia AS entity_key,
    sum(qty_venduta) AS qty_venduta_tot,
    sum(imponibile_netto_tot) AS imponibile_netto_tot,
    sum(COALESCE(qty_forecast, (0)::numeric)) AS qty_forecast_tot,
    bool_or(is_holiday) AS is_holiday,
    max(holiday_name) AS holiday_name,
    max(dow) AS dow
   FROM public.core_analytics__series_daily
  GROUP BY data, famiglia;

--
-- Name: core_analytics__series_daily_famiglia_v; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_famiglia_v AS
 SELECT data,
    famiglia AS entity_key,
    sum(qty_venduta) AS qty_venduta_tot,
    sum(imponibile_netto_tot) AS imponibile_netto_tot,
    sum(COALESCE(qty_forecast, (0)::numeric)) AS qty_forecast_tot,
    bool_or(is_holiday) AS is_holiday,
    max(holiday_name) AS holiday_name,
    max(dow) AS dow
   FROM public.core_analytics__series_daily
  GROUP BY data, famiglia;

--
-- Name: core_analytics__series_daily_fascia; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_fascia AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_fascia;

--
-- Name: core_analytics__series_daily_fascia_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_fascia_lc AS
 SELECT data,
    lower(entity_key) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_fascia;

--
-- Name: core_analytics__series_daily_fascia_prezzo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_fascia_prezzo AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_fascia_prezzo;

--
-- Name: core_analytics__series_daily_fascia_prezzo_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_fascia_prezzo_lc AS
 SELECT data,
    lower(entity_key) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_fascia_prezzo;

--
-- Name: core_analytics__series_daily_fascia_prezzo_v; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_fascia_prezzo_v AS
 SELECT data,
    fascia_prezzo_iva_inc AS entity_key,
    sum(qty_venduta) AS qty_venduta_tot,
    sum(imponibile_netto_tot) AS imponibile_netto_tot,
    sum(COALESCE(qty_forecast, (0)::numeric)) AS qty_forecast_tot,
    bool_or(is_holiday) AS is_holiday,
    max(holiday_name) AS holiday_name,
    max(dow) AS dow
   FROM public.core_analytics__series_daily
  WHERE (fascia_prezzo_iva_inc IS NOT NULL)
  GROUP BY data, fascia_prezzo_iva_inc;

--
-- Name: core_analytics__series_daily_fascia_v; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_fascia_v AS
 SELECT data,
    fascia_corretta AS entity_key,
    sum(qty_venduta) AS qty_venduta_tot,
    sum(imponibile_netto_tot) AS imponibile_netto_tot,
    sum(COALESCE(qty_forecast, (0)::numeric)) AS qty_forecast_tot,
    bool_or(is_holiday) AS is_holiday,
    max(holiday_name) AS holiday_name,
    max(dow) AS dow
   FROM public.core_analytics__series_daily
  WHERE (fascia_corretta IS NOT NULL)
  GROUP BY data, fascia_corretta;

--
-- Name: core_analytics__series_daily_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_lc AS
 SELECT data,
    lower(famiglia) AS famiglia_lc,
    lower(categoria_corretta) AS categoria_lc,
    lower(fascia_corretta) AS fascia_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    is_holiday,
    holiday_name,
    dow,
    week_num,
    month_num,
    year_num,
    qty_forecast
   FROM public.core_analytics__series_daily;

--
-- Name: core_analytics__series_daily_total; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_daily_total AS
 SELECT data,
    famiglia,
    categoria_corretta,
    fascia_corretta,
    fascia_prezzo_iva_inc,
    sum(qty_venduta) AS qty_venduta_tot,
    sum(imponibile_netto_tot) AS imponibile_netto_tot,
    sum(num_articoli) AS num_articoli,
    bool_or(is_holiday) AS is_holiday,
    max(holiday_name) AS holiday_name,
    max(dow) AS dow,
    max(week_num) AS week_num,
    max(month_num) AS month_num,
    max(year_num) AS year_num,
    sum(COALESCE(qty_forecast, (0)::numeric)) AS qty_forecast_tot
   FROM public.core_analytics__series_daily
  GROUP BY data, famiglia, categoria_corretta, fascia_corretta, fascia_prezzo_iva_inc;

--
-- Name: core_analytics__series_monthly_categoria_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_monthly_categoria_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_monthly_categoria;

--
-- Name: core_analytics__series_monthly_famiglia_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_monthly_famiglia_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_monthly_famiglia;

--
-- Name: core_analytics__series_monthly_fascia_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_monthly_fascia_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_monthly_fascia;

--
-- Name: core_analytics__series_monthly_fascia_prezzo_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_monthly_fascia_prezzo_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_monthly_fascia_prezzo;

--
-- Name: core_analytics__series_weekly_categoria_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_weekly_categoria_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_weekly_categoria;

--
-- Name: core_analytics__series_weekly_famiglia_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_weekly_famiglia_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_weekly_famiglia;

--
-- Name: core_analytics__series_weekly_fascia_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_weekly_fascia_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_weekly_fascia;

--
-- Name: core_analytics__series_weekly_fascia_prezzo_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_weekly_fascia_prezzo_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_weekly_fascia_prezzo;

--
-- Name: core_analytics__series_yearly_categoria_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_yearly_categoria_lc AS
 SELECT period_start AS data,
    entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_yearly_categoria;

--
-- Name: core_analytics__series_yearly_famiglia_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_yearly_famiglia_lc AS
 SELECT period_start AS data,
    entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_yearly_famiglia;

--
-- Name: core_analytics__series_yearly_fascia_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_yearly_fascia_lc AS
 SELECT period_start AS data,
    entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_yearly_fascia;

--
-- Name: core_analytics__series_yearly_fascia_prezzo_lc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.core_analytics__series_yearly_fascia_prezzo_lc AS
 SELECT period_start AS data,
    entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_yearly_fascia_prezzo;

--
-- Name: dashboard__reorder_suggestions_top; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard__reorder_suggestions_top AS
 SELECT famiglia,
    fascia_prezzo_iva_inc,
    categoria_corretta,
    fascia_corretta,
    pot_sizes_text,
    qty_giacenza,
    qty_da_ordinare,
    rischio_stockout_prima_di_arrivo,
    demand_lead,
    demand_cycle,
    in_assortimento
   FROM public.greenhouse_order_suggestions_enriched_v2
  WHERE (COALESCE(qty_da_ordinare, (0)::numeric) > (0)::numeric)
  ORDER BY COALESCE(rischio_stockout_prima_di_arrivo, false) DESC, COALESCE(qty_da_ordinare, (0)::numeric) DESC, COALESCE(qty_giacenza, (0)::numeric)
 LIMIT 200;

--
-- Name: dashboard__sales_daily; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard__sales_daily AS
 SELECT data,
    qty_tot,
    imp_tot,
    num_articoli_tot
   FROM public.t_dashboard_sales_daily;

--
-- Name: dashboard__sales_monthly; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard__sales_monthly AS
 SELECT period_start AS data,
    qty_tot,
    imp_tot
   FROM public.t_dashboard_sales_monthly;

--
-- Name: dashboard__sales_weekly; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard__sales_weekly AS
 SELECT period_start AS data,
    qty_tot,
    imp_tot
   FROM public.t_dashboard_sales_weekly;

--
-- Name: dashboard__sales_yearly; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard__sales_yearly AS
 SELECT period_start AS data,
    qty_tot,
    imp_tot
   FROM public.t_dashboard_sales_yearly;

--
-- Name: greenhouse_elenco_articoli_tipo_piante; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_elenco_articoli_tipo_piante AS
 SELECT codart,
    min((tipo)::text) AS tipo,
    min((fascia)::text) AS fascia,
    min((categoria)::text) AS categoria,
    min((descrizione)::text) AS descrizione,
    min(disattivato) AS disattivato,
    sum(quantita) AS quantita_totale,
    sum(imponibilenetto) AS imponibile_netto_tot,
        CASE
            WHEN (sum(quantita) > (0)::numeric) THEN round((sum(imponibilenetto) / sum(quantita)), 2)
            ELSE NULL::numeric
        END AS prezzo_iva_esclusa,
        CASE
            WHEN (sum(quantita) > (0)::numeric) THEN round(((sum(imponibilenetto) / sum(quantita)) * 1.10), 2)
            ELSE NULL::numeric
        END AS prezzo_iva_inclusa
   FROM public.greenhouse_sales_raw s
  WHERE ((codart)::text ~~ '1%'::text)
  GROUP BY codart
  ORDER BY codart;

--
-- Name: greenhouse_articoli_da_normalizzare; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_articoli_da_normalizzare AS
 SELECT e.codart,
    e.tipo,
    e.fascia,
    e.categoria,
    e.descrizione,
    e.disattivato,
    e.quantita_totale,
    e.imponibile_netto_tot,
    e.prezzo_iva_esclusa,
    e.prezzo_iva_inclusa
   FROM (public.greenhouse_elenco_articoli_tipo_piante e
     LEFT JOIN public.greenhouse_products_normalized p ON (((e.codart)::text = (p.codart)::text)))
  WHERE (p.codart IS NULL)
  ORDER BY e.codart;

--
-- Name: greenhouse_articoli_piante_full; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_articoli_piante_full AS
 SELECT e.codart,
    e.tipo,
    e.fascia,
    e.categoria,
    e.descrizione,
    e.disattivato,
    e.quantita_totale,
    e.imponibile_netto_tot,
    e.prezzo_iva_esclusa,
    e.prezzo_iva_inclusa,
    p.fascia_corretta,
    p.categoria_corretta,
    p.famiglia,
    p.descrizione AS descrizione_articolo,
    p.prezzo_iva_esclusa AS prezzo_catalogo_iva_esclusa,
    p.prezzo_iva_inclusa AS prezzo_catalogo_iva_inclusa,
    p.fascia_prezzo_iva_inc,
    p.pot_size
   FROM (public.greenhouse_elenco_articoli_tipo_piante e
     LEFT JOIN public.greenhouse_products_normalized p ON (((e.codart)::text = (p.codart)::text)))
  ORDER BY e.codart;

--
-- Name: greenhouse_sales_family_daily; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_sales_family_daily AS
 SELECT data,
    famiglia,
    fascia_prezzo_iva_inc,
    pot_size,
    sum(quantita) AS qty_venduta,
    sum(imponibilenetto) AS imponibile_netto_tot,
    count(DISTINCT codart) AS num_articoli,
    min((fascia_corretta)::text) AS fascia_corretta,
    min((categoria_corretta)::text) AS categoria_corretta,
    string_agg(DISTINCT (((((codart)::text || '|'::text) || (descrizione_vendita)::text) || '|'::text) || (round((prezzo_iva_inclusa)::numeric, 2))::text), ','::text) AS articoli_inclusi,
    json_agg(DISTINCT jsonb_build_object('codart', codart, 'descrizione', descrizione_vendita, 'prezzo_iva_inclusa', round((prezzo_iva_inclusa)::numeric, 2))) AS articoli_json
   FROM public.greenhouse_sales_enriched s
  WHERE ((famiglia IS NOT NULL) AND (fascia_prezzo_iva_inc IS NOT NULL) AND (pot_size IS NOT NULL))
  GROUP BY data, famiglia, fascia_prezzo_iva_inc, pot_size
  ORDER BY data, famiglia, fascia_prezzo_iva_inc, pot_size;

--
-- Name: greenhouse_forecast_dataset; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_forecast_dataset AS
 WITH base AS (
         SELECT s.data,
            s.famiglia,
            s.fascia_prezzo_iva_inc,
            s.pot_size,
            s.qty_venduta,
            s.imponibile_netto_tot,
            s.num_articoli,
            s.fascia_corretta,
            s.categoria_corretta,
            s.articoli_inclusi,
            s.articoli_json
           FROM public.greenhouse_sales_family_daily s
        ), arricchita AS (
         SELECT b.data,
            b.famiglia,
            b.fascia_prezzo_iva_inc,
            b.pot_size,
            b.qty_venduta,
            b.imponibile_netto_tot,
            b.num_articoli,
            b.fascia_corretta,
            b.categoria_corretta,
            b.articoli_inclusi,
            b.articoli_json,
            w.tmin_c,
            w.tmax_c,
            w.tavg_c,
            w.rain_mm,
            w.sun_hours,
            COALESCE(h.is_holiday, false) AS is_holiday,
            h.holiday_name,
            EXTRACT(dow FROM b.data) AS dow,
            EXTRACT(week FROM b.data) AS week_num,
            EXTRACT(month FROM b.data) AS month_num,
            EXTRACT(year FROM b.data) AS year_num,
            lag(b.qty_venduta, 1) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data) AS qty_lag_1,
            lag(b.qty_venduta, 2) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data) AS qty_lag_2,
            lag(b.qty_venduta, 3) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data) AS qty_lag_3,
            lag(b.qty_venduta, 7) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data) AS qty_lag_7,
            lag(b.qty_venduta, 10) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data) AS qty_lag_10,
            lag(b.qty_venduta, 14) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data) AS qty_lag_14,
            avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS qty_ma_3,
            avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS qty_ma_7,
            avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data ROWS BETWEEN 10 PRECEDING AND 1 PRECEDING) AS qty_ma_10,
            avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS qty_ma_14,
            avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc, b.pot_size ORDER BY b.data ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING) AS qty_ma_28
           FROM ((base b
             LEFT JOIN public.greenhouse_weather_daily w ON ((w.data = b.data)))
             LEFT JOIN public.greenhouse_holidays h ON ((h.data = b.data)))
        )
 SELECT data,
    famiglia,
    fascia_prezzo_iva_inc,
    pot_size,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    fascia_corretta,
    categoria_corretta,
    articoli_inclusi,
    articoli_json,
    tmin_c,
    tmax_c,
    tavg_c,
    rain_mm,
    sun_hours,
    is_holiday,
    holiday_name,
    dow,
    week_num,
    month_num,
    year_num,
    qty_lag_1,
    qty_lag_2,
    qty_lag_3,
    qty_lag_7,
    qty_lag_10,
    qty_lag_14,
    qty_ma_3,
    qty_ma_7,
    qty_ma_10,
    qty_ma_14,
    qty_ma_28
   FROM arricchita
  WHERE (qty_venduta IS NOT NULL)
  ORDER BY data, famiglia, fascia_prezzo_iva_inc, pot_size;

--
-- Name: greenhouse_sales_family_daily_v2; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_sales_family_daily_v2 AS
 WITH per_articolo AS (
         SELECT s.data,
            s.famiglia,
            s.fascia_prezzo_iva_inc,
            min((s.fascia_corretta)::text) AS fascia_corretta,
            min((s.categoria_corretta)::text) AS categoria_corretta,
            s.codart,
            s.descrizione_vendita,
            s.pot_size,
            round(max((s.prezzo_iva_inclusa)::numeric), 2) AS prezzo_iva_inclusa,
            sum(s.quantita) AS qty_venduta_articolo,
            sum(s.imponibilenetto) AS imponibile_netto_articolo
           FROM public.greenhouse_sales_enriched s
          WHERE ((s.famiglia IS NOT NULL) AND (s.fascia_prezzo_iva_inc IS NOT NULL))
          GROUP BY s.data, s.famiglia, s.fascia_prezzo_iva_inc, s.codart, s.descrizione_vendita, s.pot_size
        ), per_gruppo AS (
         SELECT per_articolo.data,
            per_articolo.famiglia,
            per_articolo.fascia_prezzo_iva_inc,
            min(per_articolo.fascia_corretta) AS fascia_corretta,
            min(per_articolo.categoria_corretta) AS categoria_corretta,
            sum(per_articolo.qty_venduta_articolo) AS qty_venduta,
            sum(per_articolo.imponibile_netto_articolo) AS imponibile_netto_tot,
            count(DISTINCT per_articolo.codart) AS num_articoli,
            string_agg(DISTINCT COALESCE((per_articolo.pot_size)::text, ''::text), ','::text ORDER BY COALESCE((per_articolo.pot_size)::text, ''::text)) AS pot_sizes_text,
            jsonb_agg(DISTINCT COALESCE((per_articolo.pot_size)::text, ''::text)) AS pot_sizes_json,
            string_agg(DISTINCT (((((((((per_articolo.codart)::text || '|'::text) || (per_articolo.descrizione_vendita)::text) || '|'::text) || COALESCE((per_articolo.pot_size)::text, ''::text)) || '|'::text) || (per_articolo.prezzo_iva_inclusa)::text) || '|'::text) || (per_articolo.qty_venduta_articolo)::text), ','::text) AS articoli_inclusi,
            jsonb_agg(DISTINCT jsonb_build_object('codart', per_articolo.codart, 'descrizione', per_articolo.descrizione_vendita, 'pot_size', per_articolo.pot_size, 'prezzo_iva_inclusa', per_articolo.prezzo_iva_inclusa, 'qty_venduta', per_articolo.qty_venduta_articolo)) AS articoli_json
           FROM per_articolo
          GROUP BY per_articolo.data, per_articolo.famiglia, per_articolo.fascia_prezzo_iva_inc
        )
 SELECT data,
    famiglia,
    fascia_prezzo_iva_inc,
    fascia_corretta,
    categoria_corretta,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    pot_sizes_text,
    pot_sizes_json,
    articoli_inclusi,
    articoli_json
   FROM per_gruppo;

--
-- Name: greenhouse_sales_family_meta; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_sales_family_meta AS
 WITH exploded AS (
         SELECT greenhouse_sales_family_daily.famiglia,
            greenhouse_sales_family_daily.fascia_prezzo_iva_inc,
            greenhouse_sales_family_daily.pot_size,
            greenhouse_sales_family_daily.fascia_corretta,
            greenhouse_sales_family_daily.categoria_corretta,
            jsonb_array_elements((greenhouse_sales_family_daily.articoli_json)::jsonb) AS articolo
           FROM public.greenhouse_sales_family_daily
        )
 SELECT famiglia,
    fascia_prezzo_iva_inc,
    pot_size,
    min(fascia_corretta) AS fascia_corretta,
    min(categoria_corretta) AS categoria_corretta,
    jsonb_agg(DISTINCT articolo) AS articoli_json
   FROM exploded
  GROUP BY famiglia, fascia_prezzo_iva_inc, pot_size;

--
-- Name: greenhouse_series_list; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_series_list AS
 SELECT famiglia,
    fascia_prezzo_iva_inc,
    min(fascia_corretta) AS fascia_corretta,
    min(categoria_corretta) AS categoria_corretta
   FROM public.greenhouse_sales_family_daily_v2
  WHERE ((famiglia IS NOT NULL) AND (fascia_prezzo_iva_inc IS NOT NULL))
  GROUP BY famiglia, fascia_prezzo_iva_inc;

--
-- Name: greenhouse_stock_family_latest; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.greenhouse_stock_family_latest AS
 WITH latest_date AS (
         SELECT max(greenhouse_stock_raw_upload.data_rilevazione) AS data_rilevazione
           FROM public.greenhouse_stock_raw_upload
        )
 SELECT e.data_rilevazione,
    e.famiglia,
    e.fascia_prezzo_iva_inc,
    e.pot_size,
    sum(e.qty_giacenza) AS qty_giacenza
   FROM (public.greenhouse_stock_enriched e
     JOIN latest_date ld ON ((e.data_rilevazione = ld.data_rilevazione)))
  WHERE ((e.famiglia IS NOT NULL) AND (e.fascia_prezzo_iva_inc IS NOT NULL) AND (e.pot_size IS NOT NULL))
  GROUP BY e.data_rilevazione, e.famiglia, e.fascia_prezzo_iva_inc, e.pot_size
  ORDER BY e.famiglia, e.fascia_prezzo_iva_inc, e.pot_size;

--
-- Name: v_ops_pipeline_monitor_latest; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ops_pipeline_monitor_latest AS
 SELECT id,
    snap_ts,
    ok,
    raw_max_data,
    raw_rows_max_day,
    raw_last_load_ts,
    etl_last_run_id,
    etl_last_status,
    etl_last_message,
    etl_last_started_at,
    etl_last_ended_at,
    etl_last_target_last,
    etl_last_success_run_id,
    etl_last_success_started_at,
    etl_last_success_ended_at,
    etl_last_success_target_last,
    etl_last_success_message,
    fact_max_data,
    dense_max_data,
    features_dense_max_data,
    analytics_daily_max_data,
    dash_daily_max_date,
    dash_weekly_max_period_start,
    dash_monthly_max_period_start,
    planner_weekly_last_day,
    planner_weekly_fact_max_week_start,
    roll4_step,
    roll4_cursor_int,
    roll4_updated_at,
    notes
   FROM public.t_ops_pipeline_monitor m
  ORDER BY snap_ts DESC
 LIMIT 1;

--
-- Name: v_ops_pipeline_status; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ops_pipeline_status AS
 SELECT id,
    snap_ts,
    raw_max_data,
    raw_rows_max_day,
    raw_last_load_ts,
    etl_last_run_id,
    etl_last_status,
    etl_last_message,
    etl_last_started_at,
    etl_last_ended_at,
    etl_last_target_last,
    fact_max_data,
    dense_max_data,
    features_dense_max_data,
    analytics_daily_max_data,
    planner_weekly_last_day,
    roll4_step,
    roll4_cursor_int,
    roll4_updated_at,
    dash_daily_max_date,
    dash_weekly_max_period_start,
    dash_monthly_max_period_start,
    ok,
    notes
   FROM public.t_ops_pipeline_monitor m
  ORDER BY snap_ts DESC
 LIMIT 1;

--
-- Name: v_order_suggestions_api; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_order_suggestions_api AS
 SELECT famiglia,
    fascia_prezzo_iva_inc,
    demand_lead,
    demand_cycle,
    in_assortimento,
    qty_giacenza,
    stock_after_lead_raw,
    stock_after_lead,
    required_on_arrival,
    qty_da_ordinare,
    rischio_stockout_prima_di_arrivo,
    fascia_corretta,
    categoria_corretta,
    pot_sizes_text,
    pot_sizes_json
   FROM public.greenhouse_order_suggestions_enriched_v2;

