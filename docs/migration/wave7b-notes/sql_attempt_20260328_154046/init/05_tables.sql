-- GreenBrain Client Runtime — Table definitions
-- Extracted from Supabase/local schema snapshot (sql/schema/current-schema.sql)
-- Wave 7B — DO NOT hand-edit; re-run extract-schema.py to regenerate
--
-- Apply order: 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
-- (tables before views, views before functions)
--
--
-- Name: greenhouse_forecast_results_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_forecast_results_v2 (
    data date NOT NULL,
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_forecast numeric(12,3) NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);

--
-- Name: greenhouse_products_normalized; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_products_normalized (
    codart character varying(50) NOT NULL,
    tipo character varying(50),
    fascia character varying(50),
    categoria character varying(50),
    descrizione character varying(255),
    fascia_corretta character varying(50),
    categoria_corretta character varying(50),
    famiglia character varying(100),
    prezzo_iva_esclusa numeric(12,2),
    prezzo_iva_inclusa numeric(12,2),
    fascia_prezzo_iva_inc character varying(50),
    pot_size character varying(20),
    load_timestamp timestamp without time zone DEFAULT now()
);

--
-- Name: greenhouse_stock_raw_upload; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_stock_raw_upload (
    data_rilevazione date DEFAULT CURRENT_DATE NOT NULL,
    codart text NOT NULL,
    descrizione text,
    qty_giacenza numeric(12,3) NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);

--
-- Name: greenhouse_sales_family_daily_fact; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_sales_family_daily_fact (
    data date NOT NULL,
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    fascia_corretta text,
    categoria_corretta text,
    pot_sizes_text text,
    pot_sizes_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    articoli_inclusi text,
    articoli_json jsonb DEFAULT '[]'::jsonb NOT NULL
);

--
-- Name: t_etl_runs; Type: TABLE; Schema: etl; Owner: -
--

CREATE TABLE etl.t_etl_runs (
    run_id uuid DEFAULT gen_random_uuid() NOT NULL,
    pipeline text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    status text DEFAULT 'running'::text NOT NULL,
    message text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL
);

--
-- Name: t_etl_steps; Type: TABLE; Schema: etl; Owner: -
--

CREATE TABLE etl.t_etl_steps (
    step_id bigint NOT NULL,
    run_id uuid NOT NULL,
    step_name text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    status text DEFAULT 'running'::text NOT NULL,
    message text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL
);

--
-- Name: greenhouse_sales_family_daily_dense; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_sales_family_daily_dense (
    data date NOT NULL,
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    fascia_corretta text,
    categoria_corretta text,
    pot_sizes_text text,
    pot_sizes_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    articoli_inclusi text,
    articoli_json jsonb DEFAULT '[]'::jsonb NOT NULL
);

--
-- Name: greenhouse_forecast_features_dense; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_forecast_features_dense (
    data date NOT NULL,
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    fascia_corretta text,
    categoria_corretta text,
    pot_sizes_text text,
    pot_sizes_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    articoli_inclusi text,
    articoli_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    tmin_c numeric(5,2),
    tmax_c numeric(5,2),
    tavg_c numeric(5,2),
    rain_mm numeric(7,2),
    sun_hours numeric(5,2),
    is_holiday boolean DEFAULT false NOT NULL,
    holiday_name text,
    dow integer,
    week_num integer,
    month_num integer,
    year_num integer,
    qty_lag_1 numeric(12,3),
    qty_lag_2 numeric(12,3),
    qty_lag_3 numeric(12,3),
    qty_lag_7 numeric(12,3),
    qty_lag_10 numeric(12,3),
    qty_lag_14 numeric(12,3),
    qty_ma_3 numeric(18,10),
    qty_ma_7 numeric(18,10),
    qty_ma_10 numeric(18,10),
    qty_ma_14 numeric(18,10),
    qty_ma_28 numeric(18,10),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);

--
-- Name: class_model_map_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.class_model_map_v1 (
    demand_class_final text NOT NULL,
    model_code text NOT NULL,
    mapping_notes text
);

--
-- Name: execution_engine_catalog_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.execution_engine_catalog_v1 (
    execution_engine text NOT NULL,
    engine_name text NOT NULL,
    engine_family text NOT NULL,
    supports_seasonal boolean DEFAULT false NOT NULL,
    supports_intermittent boolean DEFAULT false NOT NULL,
    is_fallback boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    notes text
);

--
-- Name: family_benchmark_run_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.family_benchmark_run_v1 (
    run_id bigint NOT NULL,
    triggered_by text DEFAULT 'manual'::text NOT NULL,
    scope text,
    scope_detail text,
    holdout_days integer DEFAULT 10 NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    status text DEFAULT 'running'::text NOT NULL,
    families_total integer DEFAULT 0,
    families_done integer DEFAULT 0,
    models_tested integer DEFAULT 0,
    error_message text,
    notes text
);

--
-- Name: family_model_assignment_log_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.family_model_assignment_log_v1 (
    log_id bigint NOT NULL,
    family_name text NOT NULL,
    old_model_code text,
    new_model_code text NOT NULL,
    old_is_locked boolean,
    new_is_locked boolean,
    changed_by text DEFAULT 'system'::text NOT NULL,
    pipeline_run_id bigint,
    changed_at timestamp with time zone DEFAULT now() NOT NULL,
    reason text
);

--
-- Name: family_model_assignment_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.family_model_assignment_v1 (
    family_name text NOT NULL,
    model_code text NOT NULL,
    is_locked boolean DEFAULT false NOT NULL,
    assigned_by text DEFAULT 'system'::text NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    assignment_reason text,
    notes text
);

--
-- Name: family_model_benchmark_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.family_model_benchmark_v1 (
    benchmark_id bigint NOT NULL,
    run_id bigint,
    family_name text NOT NULL,
    model_code text NOT NULL,
    holdout_days integer DEFAULT 10 NOT NULL,
    holdout_start date,
    holdout_end date,
    train_rows integer,
    test_rows integer,
    wmape numeric(10,4),
    mae numeric(10,4),
    rmse numeric(10,4),
    bias numeric(10,4),
    is_best boolean DEFAULT false NOT NULL,
    competed_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    holdout_sum_actual numeric(14,4),
    holdout_nonzero_days integer,
    training_sum_actual numeric(14,4),
    training_nonzero_days integer
);

--
-- Name: family_model_registry_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.family_model_registry_v1 (
    family_name text NOT NULL,
    business_tier text,
    value_total numeric(16,2),
    qty_total numeric(16,3),
    demand_class_v7_1 text,
    demand_class_v7_2 text,
    demand_class_final text,
    model_code text,
    model_name text,
    model_family text,
    model_priority integer,
    is_seasonal boolean,
    is_intermittent boolean,
    default_horizon_days integer,
    update_frequency text,
    seasonal_strength numeric,
    burst_strength numeric,
    weeks_active_ratio numeric,
    months_active_ratio numeric,
    zero_rate numeric,
    avg_pos_run_len_max_v6 numeric,
    top3_months_share_max_v6 numeric,
    top10_days_share_max_v6 numeric,
    top4_weeks_share_max_v6 numeric,
    max_week_share numeric,
    max_month_share numeric,
    months_to_80_min_v6 bigint,
    adi_v7 numeric,
    horizon_days integer,
    registry_created_at timestamp with time zone
);

--
-- Name: family_model_registry_v2; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.family_model_registry_v2 (
    family_name text NOT NULL,
    business_tier text,
    value_total numeric(16,2),
    qty_total numeric(16,3),
    demand_class_final text,
    model_code text,
    model_name text,
    seasonal_strength numeric,
    burst_strength numeric,
    weeks_active_ratio numeric,
    months_active_ratio numeric,
    avg_pos_run_len_max_v6 numeric,
    top3_months_share_max_v6 numeric,
    top10_days_share_max_v6 numeric,
    top4_weeks_share_max_v6 numeric,
    max_week_share numeric,
    max_month_share numeric,
    months_to_80_min_v6 bigint,
    adi_v7 numeric,
    source_view_name text,
    classification_version text,
    registry_generated_at timestamp with time zone,
    execution_engine text,
    bundle_version text
);

--
-- Name: family_model_state_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.family_model_state_v1 (
    family_name text NOT NULL,
    business_tier text,
    demand_class_final text NOT NULL,
    model_code text NOT NULL,
    first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    classification_changed_at timestamp with time zone DEFAULT now() NOT NULL,
    model_changed_at timestamp with time zone DEFAULT now() NOT NULL,
    last_train_at timestamp with time zone,
    last_predict_at timestamp with time zone,
    last_missing_train_at timestamp with time zone,
    last_train_status text,
    last_predict_status text,
    last_train_run_id bigint,
    last_predict_run_id bigint,
    needs_initial_train boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    active_from_date date,
    active_to_date date,
    notes text,
    execution_engine text DEFAULT 'V4_TWEEDIE_BUNDLE'::text,
    bundle_version text DEFAULT 'v4'::text,
    classification_version text DEFAULT 'v7_2_quater'::text,
    data_snapshot_date date,
    registry_last_refreshed_at timestamp with time zone,
    needs_reclass boolean DEFAULT false NOT NULL,
    needs_retrain boolean DEFAULT false NOT NULL,
    needs_predict boolean DEFAULT true NOT NULL,
    disable_reason text
);

--
-- Name: family_model_suggestion_benchmark_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.family_model_suggestion_benchmark_v1 (
    suggestion_id bigint NOT NULL,
    family_name text NOT NULL,
    model_code text NOT NULL,
    benchmark_run_id bigint,
    error_metric text DEFAULT 'WMAPE'::text NOT NULL,
    error_value numeric,
    competitor_model_code text,
    competitor_error_value numeric,
    improvement_pct numeric,
    suggested_at timestamp with time zone DEFAULT now() NOT NULL,
    is_applied boolean DEFAULT false NOT NULL,
    applied_at timestamp with time zone,
    notes text,
    is_best boolean DEFAULT true NOT NULL,
    suggestion_strength text,
    min_improvement_threshold numeric(6,2) DEFAULT 3.0,
    suppression_reason text
);

--
-- Name: model_artifact_registry_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.model_artifact_registry_v1 (
    artifact_id bigint NOT NULL,
    family_name text NOT NULL,
    family_slug text,
    model_code text NOT NULL,
    execution_engine text DEFAULT 'V4_TWEEDIE_BUNDLE'::text NOT NULL,
    bundle_version text DEFAULT 'v4'::text NOT NULL,
    artifact_path text NOT NULL,
    artifact_store text DEFAULT 'local_fs'::text NOT NULL,
    artifact_etag text,
    artifact_size_bytes bigint,
    trained_at timestamp with time zone,
    train_max_date date,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: model_catalog_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.model_catalog_v1 (
    model_code text NOT NULL,
    model_name text NOT NULL,
    model_family text NOT NULL,
    model_priority integer NOT NULL,
    is_seasonal boolean DEFAULT false NOT NULL,
    is_intermittent boolean DEFAULT false NOT NULL,
    default_horizon_days integer NOT NULL,
    update_frequency text NOT NULL,
    notes text,
    is_active boolean DEFAULT true NOT NULL,
    benchmark_enabled boolean DEFAULT true NOT NULL,
    supports_backtest boolean DEFAULT true NOT NULL
);

--
-- Name: model_engine_map_v1; Type: TABLE; Schema: ml_forecast; Owner: -
--

CREATE TABLE ml_forecast.model_engine_map_v1 (
    model_code text NOT NULL,
    target_execution_engine text NOT NULL,
    current_execution_engine text NOT NULL,
    rollout_stage text NOT NULL,
    notes text
);

--
-- Name: classification_change_log_v1; Type: TABLE; Schema: ml_ops; Owner: -
--

CREATE TABLE ml_ops.classification_change_log_v1 (
    change_id bigint NOT NULL,
    family_name text NOT NULL,
    old_demand_class text,
    new_demand_class text,
    old_model_code text,
    new_model_code text,
    detected_at timestamp with time zone DEFAULT now() NOT NULL,
    trigger_mode text DEFAULT 'system'::text NOT NULL,
    notes text
);

--
-- Name: family_run_log_v1; Type: TABLE; Schema: ml_ops; Owner: -
--

CREATE TABLE ml_ops.family_run_log_v1 (
    family_run_id bigint NOT NULL,
    pipeline_run_id bigint,
    job_type text NOT NULL,
    family_name text NOT NULL,
    demand_class_final text,
    model_code text,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    status text DEFAULT 'running'::text NOT NULL,
    rows_written integer,
    artifact_path text,
    error_message text,
    error_trace text
);

--
-- Name: job_schedule_config_v1; Type: TABLE; Schema: ml_ops; Owner: -
--

CREATE TABLE ml_ops.job_schedule_config_v1 (
    job_type text NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL,
    schedule_kind text NOT NULL,
    schedule_note text,
    expected_start_local time without time zone,
    max_runtime_minutes integer,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: pipeline_run_log_v1; Type: TABLE; Schema: ml_ops; Owner: -
--

CREATE TABLE ml_ops.pipeline_run_log_v1 (
    run_id bigint NOT NULL,
    job_type text NOT NULL,
    trigger_mode text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    status text DEFAULT 'running'::text NOT NULL,
    host_name text,
    notes text,
    rows_processed integer,
    error_message text,
    git_sha text,
    env_snapshot jsonb
);

--
-- Name: greenhouse_holidays; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_holidays (
    data date NOT NULL,
    is_holiday boolean DEFAULT true NOT NULL,
    holiday_name text,
    created_at timestamp without time zone DEFAULT now()
);

--
-- Name: greenhouse_sales_raw; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_sales_raw (
    progressivo bigint NOT NULL,
    codart character varying(50),
    descrizione character varying(255),
    tipo character varying(50),
    fascia character varying(50),
    categoria character varying(50),
    quantita numeric(10,2),
    imponibilenetto numeric(12,2),
    data_movimento date,
    disattivato smallint,
    movim_cassa smallint,
    load_timestamp timestamp without time zone DEFAULT now()
);

--
-- Name: t_core_analytics__breakdown_daily_categoria_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_daily_categoria_fp (
    data date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(12,3) NOT NULL,
    imponibile_netto_tot numeric(12,2) NOT NULL,
    num_articoli integer NOT NULL,
    is_holiday boolean NOT NULL,
    holiday_name text,
    dow integer NOT NULL,
    qty_forecast numeric(12,3)
);

--
-- Name: t_core_analytics__breakdown_daily_categoria_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_daily_categoria_fp_v2 (
    data date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    is_holiday boolean DEFAULT false NOT NULL,
    holiday_name text,
    dow integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_daily_famiglia_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_daily_famiglia_fp (
    data date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(12,3) NOT NULL,
    imponibile_netto_tot numeric(12,2) NOT NULL,
    num_articoli integer NOT NULL,
    is_holiday boolean NOT NULL,
    holiday_name text,
    dow integer NOT NULL,
    qty_forecast numeric(12,3)
);

--
-- Name: t_core_analytics__breakdown_daily_famiglia_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_daily_famiglia_fp_v2 (
    data date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    is_holiday boolean DEFAULT false NOT NULL,
    holiday_name text,
    dow integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_daily_fascia_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_daily_fascia_fp_v2 (
    data date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    is_holiday boolean DEFAULT false NOT NULL,
    holiday_name text,
    dow integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_monthly_categoria_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_monthly_categoria_fp (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_monthly_categoria_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_monthly_categoria_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_monthly_famiglia_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_monthly_famiglia_fp (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_monthly_famiglia_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_monthly_famiglia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_monthly_fascia_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_monthly_fascia_fp (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_monthly_fascia_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_monthly_fascia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_weekly_categoria_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_weekly_categoria_fp (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_weekly_categoria_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_weekly_categoria_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_weekly_famiglia_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_weekly_famiglia_fp (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_weekly_famiglia_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_weekly_famiglia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_weekly_fascia_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_weekly_fascia_fp (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_weekly_fascia_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_weekly_fascia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_yearly_categoria_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_yearly_categoria_fp (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(12,3) DEFAULT 0 NOT NULL,
    qty_forecast numeric(12,3)
);

--
-- Name: t_core_analytics__breakdown_yearly_categoria_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_yearly_categoria_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_yearly_famiglia_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_yearly_famiglia_fp (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(12,3) DEFAULT 0 NOT NULL,
    qty_forecast numeric(12,3)
);

--
-- Name: t_core_analytics__breakdown_yearly_famiglia_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_yearly_famiglia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__breakdown_yearly_fascia_fp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_yearly_fascia_fp (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(12,3) DEFAULT 0 NOT NULL,
    qty_forecast numeric(12,3)
);

--
-- Name: t_core_analytics__breakdown_yearly_fascia_fp_v2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__breakdown_yearly_fascia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

--
-- Name: t_core_analytics__seasonality_month; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__seasonality_month (
    entity_type text NOT NULL,
    entity_key_lc text NOT NULL,
    month_num integer NOT NULL,
    avg_qty_per_day numeric(12,3) DEFAULT 0 NOT NULL,
    sum_qty numeric(14,3) DEFAULT 0 NOT NULL,
    avg_rev_per_day numeric(12,2) DEFAULT 0 NOT NULL,
    sum_rev numeric(14,2) DEFAULT 0 NOT NULL,
    n_days integer DEFAULT 0 NOT NULL
);

--
-- Name: t_core_analytics__series_daily_categoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_daily_categoria (
    data date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric,
    is_holiday boolean,
    holiday_name text,
    dow integer
);

--
-- Name: t_core_analytics__series_daily_famiglia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_daily_famiglia (
    data date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric,
    is_holiday boolean,
    holiday_name text,
    dow integer
);

--
-- Name: t_core_analytics__series_daily_fascia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_daily_fascia (
    data date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric,
    is_holiday boolean,
    holiday_name text,
    dow integer
);

--
-- Name: t_core_analytics__series_daily_fascia_prezzo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_daily_fascia_prezzo (
    data date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric,
    is_holiday boolean,
    holiday_name text,
    dow integer
);

--
-- Name: t_core_analytics__series_monthly_categoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_monthly_categoria (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);

--
-- Name: t_core_analytics__series_monthly_famiglia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_monthly_famiglia (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);

--
-- Name: t_core_analytics__series_monthly_fascia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_monthly_fascia (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);

--
-- Name: t_core_analytics__series_monthly_fascia_prezzo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_monthly_fascia_prezzo (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);

--
-- Name: t_core_analytics__series_weekly_categoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_weekly_categoria (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);

--
-- Name: t_core_analytics__series_weekly_famiglia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_weekly_famiglia (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);

--
-- Name: t_core_analytics__series_weekly_fascia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_weekly_fascia (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);

--
-- Name: t_core_analytics__series_weekly_fascia_prezzo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_weekly_fascia_prezzo (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);

--
-- Name: t_core_analytics__series_yearly_categoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_yearly_categoria (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    qty_venduta_tot numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    qty_forecast_tot numeric(12,3)
);

--
-- Name: t_core_analytics__series_yearly_famiglia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_yearly_famiglia (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    qty_venduta_tot numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    qty_forecast_tot numeric(12,3)
);

--
-- Name: t_core_analytics__series_yearly_fascia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_yearly_fascia (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    qty_venduta_tot numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    qty_forecast_tot numeric(12,3)
);

--
-- Name: t_core_analytics__series_yearly_fascia_prezzo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_analytics__series_yearly_fascia_prezzo (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    qty_venduta_tot numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    qty_forecast_tot numeric(12,3)
);

--
-- Name: t_dashboard_sales_daily; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_dashboard_sales_daily (
    data date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli_tot integer DEFAULT 0 NOT NULL
);

--
-- Name: t_dashboard_sales_monthly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_dashboard_sales_monthly (
    period_start date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL
);

--
-- Name: t_dashboard_sales_weekly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_dashboard_sales_weekly (
    period_start date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL
);

--
-- Name: t_dashboard_sales_yearly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_dashboard_sales_yearly (
    period_start date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL
);

--
-- Name: dim_iso_day; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_iso_day (
    day date NOT NULL,
    iso_year integer NOT NULL,
    iso_week integer NOT NULL,
    week_start date NOT NULL,
    week_52 integer NOT NULL,
    week_label text NOT NULL,
    month_num integer NOT NULL
);

--
-- Name: famiglie_catalog_static; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.famiglie_catalog_static (
    famiglia text NOT NULL,
    famiglia_slug text
);

--
-- Name: greenhouse_alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_alerts (
    id bigint NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    level text NOT NULL,
    code text NOT NULL,
    message text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_sent boolean DEFAULT false NOT NULL,
    sent_at timestamp without time zone,
    alert_day date GENERATED ALWAYS AS ((created_at)::date) STORED
);

--
-- Name: greenhouse_weather_daily; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_weather_daily (
    data date NOT NULL,
    tmin_c numeric(5,2),
    tmax_c numeric(5,2),
    tavg_c numeric(5,2),
    rain_mm numeric(7,2),
    sun_hours numeric(5,2),
    created_at timestamp without time zone DEFAULT now()
);

--
-- Name: greenhouse_series_list_fact; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_series_list_fact (
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    fascia_corretta text,
    categoria_corretta text,
    first_seen date,
    last_seen date,
    updated_at timestamp without time zone DEFAULT now()
);

--
-- Name: greenhouse_weekday_strength; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_weekday_strength (
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    week_of_year integer NOT NULL,
    dow integer NOT NULL,
    avg_qty_dow numeric(18,6) NOT NULL,
    avg_qty_week numeric(18,6) NOT NULL,
    strength numeric(18,6) NOT NULL,
    n_days integer NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);

--
-- Name: greenhouse_weekday_strength_family; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.greenhouse_weekday_strength_family (
    famiglia text NOT NULL,
    week_of_year integer NOT NULL,
    dow integer NOT NULL,
    avg_qty_dow numeric(18,6) NOT NULL,
    avg_qty_week numeric(18,6) NOT NULL,
    strength numeric(18,6) NOT NULL,
    n_days integer NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);

--
-- Name: ops_parquet_export_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ops_parquet_export_runs (
    run_id bigint NOT NULL,
    dataset text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    status text DEFAULT 'running'::text NOT NULL,
    from_day date,
    to_day date,
    n_families integer,
    n_files integer,
    n_rows bigint,
    error_message text,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL
);

--
-- Name: ops_parquet_export_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ops_parquet_export_state (
    id integer DEFAULT 1 NOT NULL,
    dataset text NOT NULL,
    export_mode text NOT NULL,
    overwrite_days integer DEFAULT 40 NOT NULL,
    last_success_run_at timestamp with time zone,
    last_success_day date,
    storage_prefix text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: t_analytics_backfill_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_analytics_backfill_state (
    job_name text NOT NULL,
    next_day date NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: t_core_planner__assortment_calendar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_planner__assortment_calendar (
    mode text NOT NULL,
    level text NOT NULL,
    node_id text NOT NULL,
    week_52 integer NOT NULL,
    state text NOT NULL,
    space_m2_raw numeric DEFAULT 0 NOT NULL,
    space_share numeric DEFAULT 0 NOT NULL,
    stock_target numeric,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_assortment_level CHECK ((level = ANY (ARRAY['famiglia'::text, 'categoria'::text]))),
    CONSTRAINT chk_assortment_mode CHECK ((mode = ANY (ARRAY['week'::text, 'roll4'::text]))),
    CONSTRAINT chk_assortment_state CHECK ((state = ANY (ARRAY['OFF'::text, 'LOW'::text, 'MED'::text, 'HIGH'::text]))),
    CONSTRAINT chk_assortment_week CHECK (((week_52 >= 1) AND (week_52 <= 52)))
);

--
-- Name: t_core_planner__density; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_planner__density (
    pot_size_group text NOT NULL,
    units_per_m2 numeric NOT NULL,
    layout text DEFAULT 'banco'::text NOT NULL,
    display_buffer_pct numeric DEFAULT 0.15 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: t_core_planner__fact_weekly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_planner__fact_weekly (
    iso_year integer NOT NULL,
    week_52 integer NOT NULL,
    week_start date NOT NULL,
    fascia text NOT NULL,
    categoria text NOT NULL,
    famiglia text NOT NULL,
    fascia_prezzo text NOT NULL,
    qty numeric DEFAULT 0 NOT NULL,
    rev numeric DEFAULT 0 NOT NULL,
    days_present integer DEFAULT 0 NOT NULL,
    days_active integer DEFAULT 0 NOT NULL,
    days_zero integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: t_core_planner__heat_cells; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_planner__heat_cells (
    mode text NOT NULL,
    level text NOT NULL,
    fascia text,
    categoria text,
    famiglia text,
    fascia_prezzo text,
    node_id text NOT NULL,
    parent_id text,
    label text NOT NULL,
    week_52 integer NOT NULL,
    avg_qty numeric DEFAULT 0 NOT NULL,
    avg_rev numeric DEFAULT 0 NOT NULL,
    share_rev numeric DEFAULT 0 NOT NULL,
    sigma_qty numeric,
    avg_days_active numeric,
    avg_days_zero numeric,
    color_score numeric,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    min_qty numeric,
    max_qty numeric,
    min_rev numeric,
    max_rev numeric,
    stock_target numeric,
    space_m2 numeric
);

--
-- Name: t_core_planner__orchestrator_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_planner__orchestrator_state (
    pipeline text NOT NULL,
    step text NOT NULL,
    cursor_int integer,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: t_core_planner__params_level; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_planner__params_level (
    level text NOT NULL,
    cover_days numeric NOT NULL,
    service_level_z numeric DEFAULT 1.28 NOT NULL,
    max_days_on_floor numeric NOT NULL,
    buffer_pct numeric DEFAULT 0.15 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_level_planner_params CHECK ((level = ANY (ARRAY['famiglia'::text, 'fascia_prezzo'::text])))
);

--
-- Name: t_core_planner__potsize_profile; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_planner__potsize_profile (
    level text NOT NULL,
    famiglia text NOT NULL,
    fascia_prezzo text NOT NULL,
    pot_size_group_main text NOT NULL,
    units_per_m2_est numeric NOT NULL,
    sample_qty numeric DEFAULT 0 NOT NULL,
    total_qty numeric DEFAULT 0 NOT NULL,
    share_qty numeric DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: t_core_planner__refresh_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_planner__refresh_state (
    pipeline text NOT NULL,
    last_day date NOT NULL
);

--
-- Name: t_core_planner__space_budget; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_core_planner__space_budget (
    mode text NOT NULL,
    level text NOT NULL,
    node_id text NOT NULL,
    week_52 integer NOT NULL,
    space_m2_raw numeric DEFAULT 0 NOT NULL,
    space_share numeric DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_space_budget_level CHECK ((level = ANY (ARRAY['famiglia'::text, 'categoria'::text]))),
    CONSTRAINT chk_space_budget_mode CHECK ((mode = ANY (ARRAY['week'::text, 'roll4'::text]))),
    CONSTRAINT chk_space_budget_week CHECK (((week_52 >= 1) AND (week_52 <= 52)))
);

--
-- Name: t_forecast_fam_daily; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_forecast_fam_daily (
    data date,
    entity_key text,
    qty_forecast_tot numeric
);

--
-- Name: t_ops_pipeline_monitor; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_ops_pipeline_monitor (
    id bigint NOT NULL,
    snap_ts timestamp with time zone DEFAULT now() NOT NULL,
    raw_max_data date,
    raw_rows_max_day bigint,
    raw_last_load_ts timestamp without time zone,
    etl_last_run_id uuid,
    etl_last_status text,
    etl_last_message text,
    etl_last_started_at timestamp with time zone,
    etl_last_ended_at timestamp with time zone,
    etl_last_target_last date,
    planner_weekly_last_day date,
    roll4_step text,
    roll4_cursor_int integer,
    roll4_updated_at timestamp with time zone,
    dash_daily_max_date date,
    dash_weekly_max_period_start date,
    dash_monthly_max_period_start date,
    ok boolean DEFAULT false NOT NULL,
    notes text,
    fact_max_data date,
    features_dense_max_data date,
    analytics_daily_max_data date,
    planner_weekly_fact_max_week_start date,
    etl_last_success_run_id uuid,
    etl_last_success_started_at timestamp with time zone,
    etl_last_success_ended_at timestamp with time zone,
    etl_last_success_target_last date,
    etl_last_success_message text,
    dense_max_data date
);

