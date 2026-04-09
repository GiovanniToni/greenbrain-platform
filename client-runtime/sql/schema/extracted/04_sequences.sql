-- GreenBrain Client Runtime — Sequences
-- Extracted from Supabase/local schema snapshot (sql/schema/current-schema.sql)
-- Wave 7B — DO NOT hand-edit; re-run extract-schema.py to regenerate
--
-- Apply order: 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
-- (tables before views, views before functions)
--
--
-- Name: t_etl_steps_step_id_seq; Type: SEQUENCE; Schema: etl; Owner: -
--

CREATE SEQUENCE etl.t_etl_steps_step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: family_benchmark_run_v1_run_id_seq; Type: SEQUENCE; Schema: ml_forecast; Owner: -
--

CREATE SEQUENCE ml_forecast.family_benchmark_run_v1_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: family_model_assignment_log_v1_log_id_seq; Type: SEQUENCE; Schema: ml_forecast; Owner: -
--

ALTER TABLE ml_forecast.family_model_assignment_log_v1 ALTER COLUMN log_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME ml_forecast.family_model_assignment_log_v1_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: family_model_benchmark_v1_benchmark_id_seq; Type: SEQUENCE; Schema: ml_forecast; Owner: -
--

CREATE SEQUENCE ml_forecast.family_model_benchmark_v1_benchmark_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: family_model_suggestion_benchmark_v1_suggestion_id_seq; Type: SEQUENCE; Schema: ml_forecast; Owner: -
--

ALTER TABLE ml_forecast.family_model_suggestion_benchmark_v1 ALTER COLUMN suggestion_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME ml_forecast.family_model_suggestion_benchmark_v1_suggestion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: model_artifact_registry_v1_artifact_id_seq; Type: SEQUENCE; Schema: ml_forecast; Owner: -
--

CREATE SEQUENCE ml_forecast.model_artifact_registry_v1_artifact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: classification_change_log_v1_change_id_seq; Type: SEQUENCE; Schema: ml_ops; Owner: -
--

CREATE SEQUENCE ml_ops.classification_change_log_v1_change_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: family_run_log_v1_family_run_id_seq; Type: SEQUENCE; Schema: ml_ops; Owner: -
--

CREATE SEQUENCE ml_ops.family_run_log_v1_family_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: pipeline_run_log_v1_run_id_seq; Type: SEQUENCE; Schema: ml_ops; Owner: -
--

CREATE SEQUENCE ml_ops.pipeline_run_log_v1_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: greenhouse_alerts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.greenhouse_alerts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: ops_parquet_export_runs_run_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ops_parquet_export_runs_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: t_ops_pipeline_monitor_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_ops_pipeline_monitor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

