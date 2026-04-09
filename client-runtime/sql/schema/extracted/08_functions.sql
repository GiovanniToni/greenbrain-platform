-- GreenBrain Client Runtime — Functions and RPCs
-- Extracted from Supabase/local schema snapshot (sql/schema/current-schema.sql)
-- Wave 7B — DO NOT hand-edit; re-run extract-schema.py to regenerate
--
-- Apply order: 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
-- (tables before views, views before functions)
--
--
-- Name: _end_run(uuid, text, text, jsonb); Type: PROCEDURE; Schema: etl; Owner: -
--

CREATE PROCEDURE etl._end_run(IN p_run_id uuid, IN p_status text, IN p_message text DEFAULT NULL::text, IN p_payload jsonb DEFAULT NULL::jsonb)
    LANGUAGE plpgsql
    AS $$
begin
  update etl.t_etl_runs
  set ended_at = now(),
      status = p_status,
      message = p_message,
      payload = case when p_payload is null then payload else p_payload end
  where run_id = p_run_id;
end;
$$;

--
-- Name: _end_step(bigint, text, text, jsonb); Type: PROCEDURE; Schema: etl; Owner: -
--

CREATE PROCEDURE etl._end_step(IN p_step_id bigint, IN p_status text, IN p_message text DEFAULT NULL::text, IN p_payload jsonb DEFAULT NULL::jsonb)
    LANGUAGE plpgsql
    AS $$
begin
  update etl.t_etl_steps
  set ended_at = now(),
      status = p_status,
      message = p_message,
      payload = case when p_payload is null then payload else p_payload end
  where step_id = p_step_id;
end;
$$;

--
-- Name: _start_run(text, jsonb); Type: FUNCTION; Schema: etl; Owner: -
--

CREATE FUNCTION etl._start_run(p_pipeline text, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare v_run uuid;
begin
  insert into etl.t_etl_runs(pipeline, payload)
  values (p_pipeline, coalesce(p_payload,'{}'::jsonb))
  returning run_id into v_run;
  return v_run;
end;
$$;

--
-- Name: _start_step(uuid, text, jsonb); Type: FUNCTION; Schema: etl; Owner: -
--

CREATE FUNCTION etl._start_step(p_run_id uuid, p_step_name text, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
declare v_step bigint;
begin
  insert into etl.t_etl_steps(run_id, step_name, payload)
  values (p_run_id, p_step_name, coalesce(p_payload,'{}'::jsonb))
  returning step_id into v_step;
  return v_step;
end;
$$;

--
-- Name: backfill_family_state_from_artifacts_v1(); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.backfill_family_state_from_artifacts_v1() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    update ml_forecast.family_model_state_v1 s
    set
        execution_engine = coalesce(a.execution_engine, s.execution_engine),
        bundle_version = coalesce(a.bundle_version, s.bundle_version),
        last_train_at = coalesce(a.trained_at, s.last_train_at, a.updated_at),
        last_train_status = case
            when a.family_name is not null then 'success'
            else s.last_train_status
        end,
        needs_initial_train = case
            when a.family_name is not null then false
            else s.needs_initial_train
        end,
        needs_retrain = case
            when a.family_name is not null and coalesce(s.needs_reclass, false) = false then false
            else s.needs_retrain
        end,
        notes = case
            when a.family_name is not null and coalesce(s.notes, '') = '' then 'backfilled from artifact registry'
            else s.notes
        end
    from (
        select distinct on (family_name)
            family_name,
            execution_engine,
            bundle_version,
            trained_at,
            updated_at
        from ml_forecast.model_artifact_registry_v1
        where is_active = true
        order by family_name, coalesce(trained_at, updated_at) desc, artifact_id desc
    ) a
    where a.family_name = s.family_name;
end;
$$;

--
-- Name: backfill_family_state_from_artifacts_v2(); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.backfill_family_state_from_artifacts_v2() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    update ml_forecast.family_model_state_v1 s
    set
        execution_engine = coalesce(a.execution_engine, s.execution_engine),
        bundle_version = coalesce(a.bundle_version, s.bundle_version),
        last_train_at = coalesce(a.trained_at, a.updated_at, s.last_train_at),
        last_train_status = case
            when a.family_name is not null then 'success'
            else s.last_train_status
        end,
        needs_initial_train = case
            when a.family_name is not null then false
            else s.needs_initial_train
        end,
        needs_retrain = case
            when a.family_name is not null and coalesce(s.needs_reclass, false) = false then false
            else s.needs_retrain
        end,
        notes = case
            when a.family_name is not null and coalesce(s.notes, '') = '' then 'backfilled from artifact registry v2'
            else s.notes
        end
    from (
        select distinct on (family_name)
            family_name,
            execution_engine,
            bundle_version,
            trained_at,
            updated_at
        from ml_forecast.model_artifact_registry_v1
        where is_active = true
        order by family_name, coalesce(trained_at, updated_at) desc, artifact_id desc
    ) a
    where a.family_name = s.family_name;
end;
$$;

--
-- Name: log_classification_changes_v1(); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.log_classification_changes_v1() RETURNS void
    LANGUAGE sql
    AS $$
insert into ml_ops.classification_change_log_v1 (
    family_name,
    old_demand_class,
    new_demand_class,
    old_model_code,
    new_model_code,
    trigger_mode,
    notes
)
select
    s.family_name,
    s.demand_class_final,
    r.demand_class_final,
    s.model_code,
    r.model_code,
    'system',
    'Detected during registry sync'
from ml_forecast.family_model_state_v1 s
join ml_forecast.family_model_registry_v2 r
  on r.family_name = s.family_name
where s.demand_class_final is distinct from r.demand_class_final
   or s.model_code is distinct from r.model_code;
$$;

--
-- Name: mark_family_predict_failed_v1(text, bigint, text); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.mark_family_predict_failed_v1(p_family_name text, p_pipeline_run_id bigint DEFAULT NULL::bigint, p_error text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    update ml_forecast.family_model_state_v1
    set
        last_predict_at = now(),
        last_predict_status = 'failed',
        last_predict_run_id = p_pipeline_run_id,
        needs_predict = true,
        notes = coalesce(p_error, notes)
    where family_name = p_family_name;
end;
$$;

--
-- Name: mark_family_predict_success_v1(text, bigint, text); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.mark_family_predict_success_v1(p_family_name text, p_pipeline_run_id bigint DEFAULT NULL::bigint, p_notes text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    update ml_forecast.family_model_state_v1
    set
        last_predict_at = now(),
        last_predict_status = 'success',
        last_predict_run_id = p_pipeline_run_id,
        needs_predict = false,
        notes = coalesce(p_notes, notes)
    where family_name = p_family_name;
end;
$$;

--
-- Name: mark_family_train_failed_v1(text, bigint, text); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.mark_family_train_failed_v1(p_family_name text, p_pipeline_run_id bigint DEFAULT NULL::bigint, p_error text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    update ml_forecast.family_model_state_v1
    set
        last_train_at = now(),
        last_train_status = 'failed',
        last_train_run_id = p_pipeline_run_id,
        needs_retrain = true,
        notes = coalesce(p_error, notes)
    where family_name = p_family_name;
end;
$$;

--
-- Name: mark_family_train_success_v1(text, bigint, text, timestamp with time zone, date, text); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.mark_family_train_success_v1(p_family_name text, p_pipeline_run_id bigint DEFAULT NULL::bigint, p_model_code text DEFAULT NULL::text, p_trained_at timestamp with time zone DEFAULT now(), p_train_max_date date DEFAULT NULL::date, p_notes text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    update ml_forecast.family_model_state_v1
    set
        last_train_at = coalesce(p_trained_at, now()),
        last_train_status = 'success',
        last_train_run_id = p_pipeline_run_id,
        needs_initial_train = false,
        needs_retrain = false,
        notes = coalesce(p_notes, notes)
    where family_name = p_family_name;

    update ml_forecast.model_artifact_registry_v1
    set
        trained_at = coalesce(p_trained_at, trained_at, now()),
        train_max_date = coalesce(p_train_max_date, train_max_date),
        updated_at = now()
    where family_name = p_family_name
      and is_active = true
      and (p_model_code is null or model_code = p_model_code);
end;
$$;

--
-- Name: refresh_family_model_registry_v2(); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.refresh_family_model_registry_v2() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    truncate table ml_forecast.family_model_registry_v2;

    insert into ml_forecast.family_model_registry_v2
    select *
    from ml_forecast.v_family_model_registry_v2;
end;
$$;

--
-- Name: sync_family_model_state_from_artifacts_v1(); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.sync_family_model_state_from_artifacts_v1() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    update ml_forecast.family_model_state_v1 s
    set
        execution_engine = coalesce(a.execution_engine, s.execution_engine),
        bundle_version = coalesce(a.bundle_version, s.bundle_version),
        data_snapshot_date = coalesce(a.train_max_date, s.data_snapshot_date),
        needs_initial_train = case
            when a.family_name is not null then false
            else s.needs_initial_train
        end,
        needs_retrain = case
            when a.family_name is not null and coalesce(s.needs_reclass, false) = false then false
            else s.needs_retrain
        end,
        last_train_at = coalesce(a.trained_at, a.updated_at, s.last_train_at),
        last_train_status = case
            when a.family_name is not null then 'success'
            else s.last_train_status
        end,
        notes = case
            when a.family_name is not null and coalesce(s.notes, '') = '' then 'synced from active artifact'
            else s.notes
        end
    from (
        select distinct on (family_name)
            family_name,
            model_code,
            execution_engine,
            bundle_version,
            trained_at,
            updated_at,
            train_max_date
        from ml_forecast.model_artifact_registry_v1
        where is_active = true
        order by family_name, coalesce(trained_at, updated_at) desc, artifact_id desc
    ) a
    where a.family_name = s.family_name;
end;
$$;

--
-- Name: sync_family_model_state_from_registry_v1(); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.sync_family_model_state_from_registry_v1() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    insert into ml_forecast.family_model_state_v1 (
        family_name,
        business_tier,
        demand_class_final,
        model_code,
        execution_engine,
        bundle_version,
        classification_version,
        data_snapshot_date,
        registry_last_refreshed_at,
        first_seen_at,
        last_seen_at,
        needs_reclass,
        needs_retrain,
        needs_predict,
        needs_initial_train,
        is_active,
        active_from_date
    )
    select
        r.family_name,
        r.business_tier,
        r.demand_class_final,
        r.model_code,
        'V4_TWEEDIE_BUNDLE',
        'v4',
        'v7_2_quater',
        current_date,
        now(),
        now(),
        now(),
        false,
        true,
        true,
        true,
        true,
        current_date
    from ml_forecast.family_model_registry_v2 r
    on conflict (family_name) do update
    set
        business_tier = excluded.business_tier,
        demand_class_final = excluded.demand_class_final,
        model_code = excluded.model_code,
        execution_engine = excluded.execution_engine,
        bundle_version = excluded.bundle_version,
        classification_version = excluded.classification_version,
        data_snapshot_date = excluded.data_snapshot_date,
        registry_last_refreshed_at = excluded.registry_last_refreshed_at,
        last_seen_at = now(),
        needs_reclass =
            case
                when ml_forecast.family_model_state_v1.demand_class_final is distinct from excluded.demand_class_final
                  or ml_forecast.family_model_state_v1.model_code is distinct from excluded.model_code
                then true
                else ml_forecast.family_model_state_v1.needs_reclass
            end,
        needs_retrain =
            case
                when ml_forecast.family_model_state_v1.model_code is distinct from excluded.model_code
                  or ml_forecast.family_model_state_v1.demand_class_final is distinct from excluded.demand_class_final
                then true
                else ml_forecast.family_model_state_v1.needs_retrain
            end,
        needs_predict = true,
        is_active = true;
end;
$$;

--
-- Name: sync_family_model_state_v1(); Type: FUNCTION; Schema: ml_forecast; Owner: -
--

CREATE FUNCTION ml_forecast.sync_family_model_state_v1() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    insert into ml_forecast.family_model_state_v1 (
        family_name,
        business_tier,
        demand_class_final,
        model_code,
        first_seen_at,
        last_seen_at,
        classification_changed_at,
        model_changed_at,
        needs_initial_train,
        is_active,
        active_from_date,
        execution_engine,
        bundle_version,
        classification_version,
        registry_last_refreshed_at,
        needs_reclass,
        needs_retrain,
        needs_predict
    )
    select
        r.family_name,
        r.business_tier,
        r.demand_class_final,
        r.model_code,
        now(),
        now(),
        now(),
        now(),
        true,
        true,
        current_date,
        coalesce(r.execution_engine, 'V4_TWEEDIE_BUNDLE'),
        coalesce(r.bundle_version, 'v4'),
        r.classification_version,
        now(),
        false,
        false,
        true
    from ml_forecast.family_model_registry_v2 r
    on conflict (family_name) do update
    set
        business_tier = excluded.business_tier,
        last_seen_at = now(),
        is_active = true,
        demand_class_final = excluded.demand_class_final,
        model_code = excluded.model_code,
        execution_engine = excluded.execution_engine,
        bundle_version = excluded.bundle_version,
        classification_version = excluded.classification_version,
        registry_last_refreshed_at = now(),
        classification_changed_at = case
            when ml_forecast.family_model_state_v1.demand_class_final is distinct from excluded.demand_class_final
                then now()
            else ml_forecast.family_model_state_v1.classification_changed_at
        end,
        model_changed_at = case
            when ml_forecast.family_model_state_v1.model_code is distinct from excluded.model_code
                then now()
            else ml_forecast.family_model_state_v1.model_changed_at
        end,
        needs_initial_train = case
            when ml_forecast.family_model_state_v1.last_train_at is null then true
            when ml_forecast.family_model_state_v1.model_code is distinct from excluded.model_code
              or ml_forecast.family_model_state_v1.demand_class_final is distinct from excluded.demand_class_final
              or coalesce(ml_forecast.family_model_state_v1.execution_engine, '') is distinct from coalesce(excluded.execution_engine, '')
              or coalesce(ml_forecast.family_model_state_v1.bundle_version, '') is distinct from coalesce(excluded.bundle_version, '')
                then true
            else ml_forecast.family_model_state_v1.needs_initial_train
        end,
        needs_retrain = case
            when ml_forecast.family_model_state_v1.last_train_at is null then ml_forecast.family_model_state_v1.needs_retrain
            when ml_forecast.family_model_state_v1.model_code is distinct from excluded.model_code
              or ml_forecast.family_model_state_v1.demand_class_final is distinct from excluded.demand_class_final
              or coalesce(ml_forecast.family_model_state_v1.execution_engine, '') is distinct from coalesce(excluded.execution_engine, '')
              or coalesce(ml_forecast.family_model_state_v1.bundle_version, '') is distinct from coalesce(excluded.bundle_version, '')
                then true
            else ml_forecast.family_model_state_v1.needs_retrain
        end,
        needs_predict = true;

    update ml_forecast.family_model_state_v1 s
    set
        is_active = false,
        active_to_date = current_date,
        registry_last_refreshed_at = now()
    where not exists (
        select 1
        from ml_forecast.family_model_registry_v2 r
        where r.family_name = s.family_name
    )
      and s.is_active = true;
end;
$$;

--
-- Name: _touch_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at := now();
  return new;
end $$;

--
-- Name: backfill_analytics_aggregates_resume(text, date, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.backfill_analytics_aggregates_resume(p_job_name text DEFAULT 'analytics_agg_full'::text, p_to date DEFAULT CURRENT_DATE, p_step_days integer DEFAULT 1, p_max_steps integer DEFAULT 2) RETURNS TABLE(step_no integer, ran_from date, ran_to date, status text, new_next_day date)
    LANGUAGE plpgsql
    AS $$
declare
  v_from date;
  v_cur date;
  v_end date := p_to;
  v_i int := 0;
  v_next date;
begin
  if p_step_days < 1 then
    raise exception 'p_step_days must be >= 1';
  end if;

  -- leggi stato
  select s.next_day into v_from
  from public.t_analytics_backfill_state s
  where s.job_name = p_job_name;

  if v_from is null then
    raise exception 'Job not initialized: % (run the init insert first)', p_job_name;
  end if;

  v_cur := v_from;

  if v_cur > v_end then
    step_no := 0;
    ran_from := null;
    ran_to := null;
    status := 'DONE';
    new_next_day := v_cur;
    return next;
    return;
  end if;

  while v_cur <= v_end and v_i < p_max_steps loop
    v_next := least(v_cur + (p_step_days - 1), v_end);

    perform public.refresh_analytics_aggregates_range(v_cur, v_next);

    v_i := v_i + 1;

    -- aggiorna stato (resume point = giorno dopo)
    update public.t_analytics_backfill_state
    set next_day = v_next + 1,
        updated_at = now()
    where job_name = p_job_name;

    step_no := v_i;
    ran_from := v_cur;
    ran_to := v_next;
    status := 'OK';
    new_next_day := v_next + 1;
    return next;

    v_cur := v_next + 1;
  end loop;

  if v_cur <= v_end then
    step_no := v_i + 1;
    ran_from := v_cur;
    ran_to := v_end;
    status := 'PENDING_MORE';
    new_next_day := (select next_day from public.t_analytics_backfill_state where job_name = p_job_name);
    return next;
  end if;
end;
$$;

--
-- Name: backfill_analytics_aggregates_step(date, date, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.backfill_analytics_aggregates_step(p_from date, p_to date, p_step_days integer DEFAULT 1, p_max_steps integer DEFAULT 2) RETURNS TABLE(step_no integer, ran_from date, ran_to date, status text)
    LANGUAGE plpgsql
    AS $$
declare
  v_cur date := p_from;
  v_end date := p_to;
  v_i int := 0;
  v_next date;
begin
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'Invalid range % - %', p_from, p_to;
  end if;

  if p_step_days < 1 then
    raise exception 'p_step_days must be >= 1';
  end if;

  while v_cur <= v_end and v_i < p_max_steps loop
    v_next := least(v_cur + (p_step_days - 1), v_end);

    perform public.refresh_analytics_aggregates_range(v_cur, v_next);

    v_i := v_i + 1;
    step_no := v_i;
    ran_from := v_cur;
    ran_to := v_next;
    status := 'OK';
    return next;

    v_cur := v_next + 1;
  end loop;

  if v_cur <= v_end then
    step_no := v_i + 1;
    ran_from := v_cur;
    ran_to := v_end;
    status := 'PENDING_MORE';
    return next;
  end if;
end;
$$;

--
-- Name: backfill_features_weekly_step(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.backfill_features_weekly_step(p_job_name text DEFAULT 'features_weekly_full'::text, p_weeks_per_run integer DEFAULT 2) RETURNS TABLE(job_name text, ran_from date, ran_to date, new_next_start date, status text)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_start date;
  v_end date;
  v_next date;
  v_job public.greenhouse_backfill_jobs%ROWTYPE;
  i int;
  chunk_start date;
  chunk_end date;
BEGIN
  IF p_weeks_per_run IS NULL OR p_weeks_per_run < 1 THEN
    RAISE EXCEPTION 'p_weeks_per_run deve essere >= 1';
  END IF;

  SELECT * INTO v_job
  FROM public.greenhouse_backfill_jobs
  WHERE job_name = p_job_name
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'job_name % non esiste in greenhouse_backfill_jobs', p_job_name;
  END IF;

  IF v_job.status <> 'RUNNING' THEN
    RETURN QUERY
    SELECT v_job.job_name, v_job.next_start, v_job.next_start, v_job.next_start, v_job.status;
    RETURN;
  END IF;

  v_start := v_job.next_start;
  v_end   := v_job.end_date;

  -- già finito
  IF v_start > v_end THEN
    UPDATE public.greenhouse_backfill_jobs
    SET status='DONE', updated_at=now()
    WHERE job_name=p_job_name;

    RETURN QUERY
    SELECT p_job_name, v_start, v_start, v_start, 'DONE';
    RETURN;
  END IF;

  -- processa fino a N settimane, ma non oltre end_date
  chunk_start := v_start;

  FOR i IN 1..p_weeks_per_run LOOP
    EXIT WHEN chunk_start > v_end;

    chunk_end := LEAST((chunk_start + 6), v_end);

    -- aumenta timeout solo per questa sessione/run (opzionale)
    PERFORM set_config('statement_timeout', '180000', true);

    -- chiamata reale (la tua funzione che cancella+reinserisce il range)
    PERFORM public.refresh_forecast_features_dense_range(chunk_start, chunk_end);

    -- avanzamento
    v_job.last_ok_end := chunk_end;
    chunk_start := (chunk_end + 1);
  END LOOP;

  v_next := chunk_start;

  UPDATE public.greenhouse_backfill_jobs
  SET
    next_start = v_next,
    last_ok_end = v_job.last_ok_end,
    last_error = NULL,
    status = CASE WHEN v_next > v_end THEN 'DONE' ELSE 'RUNNING' END,
    updated_at = now()
  WHERE job_name = p_job_name;

  RETURN QUERY
  SELECT
    p_job_name,
    v_start AS ran_from,
    v_job.last_ok_end AS ran_to,
    v_next AS new_next_start,
    CASE WHEN v_next > v_end THEN 'DONE' ELSE 'RUNNING' END;
EXCEPTION
  WHEN OTHERS THEN
    UPDATE public.greenhouse_backfill_jobs
    SET status='ERROR', last_error=SQLERRM, updated_at=now()
    WHERE job_name=p_job_name;

    RETURN QUERY
    SELECT p_job_name, v_start, NULL::date, v_start, 'ERROR';
END;
$$;

--
-- Name: core_analytics__catalog_children(text, text, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__catalog_children(p_level text, p_fascia text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text, p_famiglia text DEFAULT NULL::text, p_fascia_prezzo text DEFAULT NULL::text, p_limit integer DEFAULT 500) RETURNS TABLE(node_type text, node_key text, label text, extra jsonb)
    LANGUAGE sql STABLE
    AS $$
with base as (
  select *
  from public.core_analytics__components_articles a
  where (p_fascia is null or lower(a.fascia_corretta) = lower(p_fascia))
    and (p_categoria is null or lower(a.categoria_corretta) = lower(p_categoria))
    and (p_famiglia is null or lower(a.famiglia) = lower(p_famiglia))
    and (p_fascia_prezzo is null or lower(a.fascia_prezzo_iva_inc) = lower(p_fascia_prezzo))
)

-- ROOT: fasce
select
  'fascia'::text as node_type,
  coalesce(fascia_corretta, '(senza fascia)') as node_key,
  coalesce(fascia_corretta, '(senza fascia)') as label,
  jsonb_build_object('count', count(*)) as extra
from base
where lower(p_level) = 'fascia'
group by 1,2,3

union all

-- categorie (dato fascia)
select
  'categoria'::text,
  coalesce(categoria_corretta, '(senza categoria)'),
  coalesce(categoria_corretta, '(senza categoria)'),
  jsonb_build_object('count', count(*)) as extra
from base
where lower(p_level) = 'categoria'
group by 1,2,3

union all

-- famiglie (dato fascia+categoria)
select
  'famiglia'::text,
  coalesce(famiglia, '(senza famiglia)'),
  coalesce(famiglia, '(senza famiglia)'),
  jsonb_build_object('count', count(*)) as extra
from base
where lower(p_level) = 'famiglia'
group by 1,2,3

union all

-- fasce prezzo (dato fascia+categoria+famiglia)
select
  'fascia_prezzo'::text,
  coalesce(fascia_prezzo_iva_inc, '(senza fascia prezzo)'),
  coalesce(fascia_prezzo_iva_inc, '(senza fascia prezzo)'),
  jsonb_build_object('count', count(*)) as extra
from base
where lower(p_level) = 'fascia_prezzo'
group by 1,2,3

union all

-- articoli (dato fascia+categoria+famiglia+fascia_prezzo)
select
  'articolo'::text,
  codart as node_key,
  (codart || ' — ' || articolo_nome)::text as label,
  jsonb_build_object(
    'codart', codart,
    'articolo_nome', articolo_nome,
    'pot_size', pot_size,
    'prezzo_iva_inclusa', prezzo_iva_inclusa
  ) as extra
from base
where lower(p_level) = 'articolo'
  and codart is not null
limit greatest(coalesce(p_limit, 500), 0);
$$;

--
-- Name: core_analytics__entity_hierarchy_tree_v1(text, text, date, date, integer, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__entity_hierarchy_tree_v1(p_entity_type text, p_entity_key text, p_date_from date, p_date_to date, p_top_n integer, p_fascia text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text, p_famiglia text DEFAULT NULL::text, p_fascia_prezzo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql
    AS $$with params as (
  select
    lower(trim(coalesce(p_entity_type,''))) as et,
    lower(trim(coalesce(p_entity_key,'')))  as ek,
    nullif(greatest(coalesce(p_top_n, 0), 0), 0) as top_n
),
ctx as (
  select
    nullif(lower(trim(coalesce(p_fascia,''))), '')        as c_fascia,
    nullif(lower(trim(coalesce(p_categoria,''))), '')     as c_categoria,
    nullif(lower(trim(coalesce(p_famiglia,''))), '')      as c_famiglia,
    nullif(lower(trim(coalesce(p_fascia_prezzo,''))), '') as c_fp
),

-- Base gerarchia: SOLO dalla tabella "components_articles" (piccola)
base as (
  select
    coalesce(a.fascia_corretta, '(senza fascia)')              as fascia_key,
    coalesce(a.categoria_corretta, '(senza categoria)')        as categoria_key,
    coalesce(a.famiglia, '(senza famiglia)')                   as famiglia_key,
    coalesce(a.fascia_prezzo_iva_inc, '(senza fascia prezzo)') as fp_key,
    a.codart,
    a.articolo_nome,
    a.pot_size,
    a.prezzo_iva_inclusa
  from public.core_analytics__components_articles a
  cross join params p
  cross join ctx c
  where
    -- filtro per entità selezionata
    (
      (p.et = 'famiglia'      and lower(coalesce(a.famiglia,'(senza famiglia)')) = p.ek) or
      (p.et = 'categoria'     and lower(coalesce(a.categoria_corretta,'(senza categoria)')) = p.ek) or
      (p.et = 'fascia'        and lower(coalesce(a.fascia_corretta,'(senza fascia)')) = p.ek) or
      (p.et = 'fascia_prezzo' and lower(coalesce(a.fascia_prezzo_iva_inc,'(senza fascia prezzo)')) = p.ek) or
      (p.et = 'articolo'      and a.codart = btrim(coalesce(p_entity_key,'')))
    )
    -- filtri contesto opzionali (se presenti)
    and (c.c_fascia    is null or lower(coalesce(a.fascia_corretta,'(senza fascia)')) = c.c_fascia)
    and (c.c_categoria is null or lower(coalesce(a.categoria_corretta,'(senza categoria)')) = c.c_categoria)
    and (c.c_famiglia  is null or lower(coalesce(a.famiglia,'(senza famiglia)')) = c.c_famiglia)
    and (c.c_fp        is null or lower(coalesce(a.fascia_prezzo_iva_inc,'(senza fascia prezzo)')) = c.c_fp)
),

-- ==============
-- ARTICOLI leaf
-- ==============
articles_ranked as (
  select
    b.fascia_key, b.categoria_key, b.famiglia_key, b.fp_key,
    b.codart, b.articolo_nome, b.pot_size, b.prezzo_iva_inclusa,
    row_number() over (
      partition by b.fascia_key, b.categoria_key, b.famiglia_key, b.fp_key
      order by
        case when b.pot_size is null or btrim(b.pot_size) = '' then 1 else 0 end,
        nullif(regexp_replace(b.pot_size, '[^0-9\.]', '', 'g'), '')::numeric nulls last,
        case when b.pot_size is null or btrim(b.pot_size) = '' then b.prezzo_iva_inclusa else null end nulls last,
        b.codart asc
    ) as rn
  from base b
),
articles_trim as (
  select * from articles_ranked where rn <= 300
),
articles_json as (
  select
    ar.fascia_key, ar.categoria_key, ar.famiglia_key, ar.fp_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type','articolo',
          'entity_key', ar.codart,
          'label', ar.codart || ' — ' || ar.articolo_nome,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'extra', jsonb_build_object(
            'pot_size', ar.pot_size,
            'prezzo_iva_inclusa', ar.prezzo_iva_inclusa
          )
        )
        order by ar.rn
      ),
      '[]'::jsonb
    ) as children_articoli
  from articles_trim ar
  group by 1,2,3,4
),

-- =========================
-- Fascia prezzo (senza totali)
-- =========================
fp_groups as (
  select distinct fascia_key, categoria_key, famiglia_key, fp_key
  from base
),
fp_ranked as (
  select
    g.*,
    row_number() over (
      partition by g.fascia_key, g.categoria_key, g.famiglia_key
      order by g.fp_key asc
    ) as rn
  from fp_groups g
),
fp_trim as (
  select r.*
  from fp_ranked r
  cross join params p
  where p.top_n is null or r.rn <= p.top_n
),
fp_json_per_family as (
  select
    fpt.fascia_key, fpt.categoria_key, fpt.famiglia_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'fascia_prezzo',
          'entity_key', fpt.fp_key,
          'label', fpt.fp_key,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'children', coalesce(aj.children_articoli, '[]'::jsonb)
        )
        order by fpt.fp_key asc
      ),
      '[]'::jsonb
    ) as children_fp
  from fp_trim fpt
  left join articles_json aj
    on aj.fascia_key = fpt.fascia_key
   and aj.categoria_key = fpt.categoria_key
   and aj.famiglia_key = fpt.famiglia_key
   and aj.fp_key = fpt.fp_key
  group by 1,2,3
),

-- =========================
-- Famiglia
-- =========================
fam_groups as (
  select distinct fascia_key, categoria_key, famiglia_key
  from base
),
fam_ranked as (
  select
    g.*,
    row_number() over (
      partition by g.fascia_key, g.categoria_key
      order by g.famiglia_key asc
    ) as rn
  from fam_groups g
),
fam_trim as (
  select r.*
  from fam_ranked r
  cross join params p
  where p.top_n is null or r.rn <= p.top_n
),
fam_json_per_cat as (
  select
    ft.fascia_key, ft.categoria_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'famiglia',
          'entity_key', ft.famiglia_key,
          'label', ft.famiglia_key,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'children', coalesce(fp.children_fp, '[]'::jsonb)
        )
        order by ft.famiglia_key asc
      ),
      '[]'::jsonb
    ) as children_famiglie
  from fam_trim ft
  left join fp_json_per_family fp
    on fp.fascia_key = ft.fascia_key
   and fp.categoria_key = ft.categoria_key
   and fp.famiglia_key = ft.famiglia_key
  group by 1,2
),

-- =========================
-- Categoria
-- =========================
cat_groups as (
  select distinct fascia_key, categoria_key
  from base
),
cat_ranked as (
  select
    g.*,
    row_number() over (
      partition by g.fascia_key
      order by g.categoria_key asc
    ) as rn
  from cat_groups g
),
cat_trim as (
  select r.*
  from cat_ranked r
  cross join params p
  where p.top_n is null or r.rn <= p.top_n
),
cat_json_per_fascia as (
  select
    ct.fascia_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'categoria',
          'entity_key', ct.categoria_key,
          'label', ct.categoria_key,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'children', coalesce(fj.children_famiglie, '[]'::jsonb)
        )
        order by ct.categoria_key asc
      ),
      '[]'::jsonb
    ) as children_categorie
  from cat_trim ct
  left join fam_json_per_cat fj
    on fj.fascia_key = ct.fascia_key
   and fj.categoria_key = ct.categoria_key
  group by 1
),

-- =========================
-- Fascia (root)
-- =========================
fas_groups as (
  select distinct fascia_key
  from base
),
fas_ranked as (
  select
    g.*,
    row_number() over (order by g.fascia_key asc) as rn
  from fas_groups g
),
fas_trim as (
  select r.*
  from fas_ranked r
  cross join params p
  where p.top_n is null or r.rn <= p.top_n
),
fas_json as (
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'fascia',
          'entity_key', ft.fascia_key,
          'label', ft.fascia_key,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'children', coalesce(cj.children_categorie, '[]'::jsonb)
        )
        order by ft.fascia_key asc
      ),
      '[]'::jsonb
    ) as tree
  from fas_trim ft
  left join cat_json_per_fascia cj
    on cj.fascia_key = ft.fascia_key
)

select jsonb_build_object(
  'entity_type', (select et from params),
  'entity_key',  p_entity_key,
  'date_from',   p_date_from,
  'date_to',     p_date_to,
  'totals',      jsonb_build_object('qty_tot',0,'imponibile_tot',0,'num_articoli_tot',0),
  'tree',        (select tree from fas_json)
);$$;

--
-- Name: core_analytics__entity_summary(text, text, date, date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__entity_summary(p_entity_type text, p_entity_key text, p_date_from date, p_date_to date, p_top_n integer) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
with filtered as (
  select
    data,
    famiglia,
    categoria_corretta,
    fascia_corretta,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli
  from public.greenhouse_forecast_features_dense g
  where g.data between p_date_from and p_date_to
    and (
      (lower(p_entity_type) = 'famiglia' and lower(g.famiglia) = lower(p_entity_key)) or
      (lower(p_entity_type) = 'categoria' and lower(g.categoria_corretta) = lower(p_entity_key)) or
      (lower(p_entity_type) = 'fascia' and lower(g.fascia_corretta) = lower(p_entity_key)) or
      (lower(p_entity_type) = 'fascia_prezzo' and lower(g.fascia_prezzo_iva_inc) = lower(p_entity_key))
    )
),

totals as (
  select
    coalesce(sum(qty_venduta), 0) as qty_tot,
    coalesce(sum(imponibile_netto_tot), 0) as imponibile_tot,
    coalesce(sum(num_articoli), 0) as num_articoli_tot
  from filtered
),

breakdown_raw as (
  select
    case
      when lower(p_entity_type) = 'famiglia' then coalesce(categoria_corretta, '(senza categoria)')
      when lower(p_entity_type) = 'categoria' then coalesce(fascia_corretta, '(senza fascia)')
      when lower(p_entity_type) = 'fascia' then coalesce(fascia_prezzo_iva_inc, '(senza fascia prezzo)')
      else null
    end as child_key,

    case
      when lower(p_entity_type) = 'famiglia' then 'categoria'
      when lower(p_entity_type) = 'categoria' then 'fascia'
      when lower(p_entity_type) = 'fascia' then 'fascia_prezzo'
      else null
    end as child_type,

    coalesce(sum(qty_venduta), 0) as qty_tot,
    coalesce(sum(imponibile_netto_tot), 0) as imponibile_tot,
    coalesce(sum(num_articoli), 0) as num_articoli_tot
  from filtered
  where lower(p_entity_type) in ('famiglia','categoria','fascia')
  group by 1,2
),

breakdown_top as (
  select *
  from breakdown_raw
  order by qty_tot desc
  limit greatest(coalesce(p_top_n, 10), 0)
),

breakdown_json as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'entity_type', child_type,
        'entity_key', child_key,
        'label', child_key,
        'qty_tot', qty_tot,
        'imponibile_tot', imponibile_tot,
        'num_articoli_tot', num_articoli_tot
      )
      order by qty_tot desc
    ),
    '[]'::jsonb
  ) as items
  from breakdown_top
)

select jsonb_build_object(
  'entity_type', lower(p_entity_type),
  'entity_key', p_entity_key,
  'date_from', p_date_from,
  'date_to', p_date_to,
  'totals', (select to_jsonb(t) from totals t),
  'breakdown', (select items from breakdown_json)
);
$$;

--
-- Name: core_analytics__entity_summary_tree(text, text, date, date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__entity_summary_tree(p_entity_type text, p_entity_key text, p_date_from date, p_date_to date, p_top_n integer) RETURNS jsonb
    LANGUAGE sql
    AS $$
  select public.core_analytics__entity_summary_tree_v2(
    p_entity_type,
    p_entity_key,
    p_date_from,
    p_date_to,
    p_top_n,
    null, null, null, null
  );
$$;

--
-- Name: core_analytics__entity_summary_tree_v2(text, text, date, date, integer, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__entity_summary_tree_v2(p_entity_type text, p_entity_key text, p_date_from date, p_date_to date, p_top_n integer, p_fascia text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text, p_famiglia text DEFAULT NULL::text, p_fascia_prezzo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql
    AS $$
with params as (
  select
    lower(trim(coalesce(p_entity_type,''))) as et,
    lower(trim(coalesce(p_entity_key,'')))  as ek,
    greatest(coalesce(p_top_n, 10), 0) as top_n
),
ctx as (
  select
    nullif(lower(trim(coalesce(p_fascia,''))), '')        as c_fascia,
    nullif(lower(trim(coalesce(p_categoria,''))), '')     as c_categoria,
    nullif(lower(trim(coalesce(p_famiglia,''))), '')      as c_famiglia,
    nullif(lower(trim(coalesce(p_fascia_prezzo,''))), '') as c_fp
),

filtered as (
  select
    g.data,
    coalesce(g.fascia_corretta, '(senza fascia)')               as fascia_key,
    coalesce(g.categoria_corretta, '(senza categoria)')         as categoria_key,
    coalesce(g.famiglia, '(senza famiglia)')                    as famiglia_key,
    coalesce(g.fascia_prezzo_iva_inc, '(senza fascia prezzo)')  as fp_key,
    g.qty_venduta,
    g.imponibile_netto_tot,
    g.num_articoli
  from public.greenhouse_forecast_features_dense g
  cross join params p
  cross join ctx c
  where g.data between p_date_from and p_date_to
    and (
      (p.et = 'famiglia'      and lower(g.famiglia) = p.ek) or
      (p.et = 'categoria'     and lower(g.categoria_corretta) = p.ek) or
      (p.et = 'fascia'        and lower(g.fascia_corretta) = p.ek) or
      (p.et = 'fascia_prezzo' and lower(g.fascia_prezzo_iva_inc) = p.ek)
    )
    and (c.c_fascia    is null or lower(coalesce(g.fascia_corretta,'(senza fascia)')) = c.c_fascia)
    and (c.c_categoria is null or lower(coalesce(g.categoria_corretta,'(senza categoria)')) = c.c_categoria)
    and (c.c_famiglia  is null or lower(coalesce(g.famiglia,'(senza famiglia)')) = c.c_famiglia)
    and (c.c_fp        is null or lower(coalesce(g.fascia_prezzo_iva_inc,'(senza fascia prezzo)')) = c.c_fp)
),

totals as (
  select
    coalesce(sum(f.qty_venduta), 0) as qty_tot,
    coalesce(sum(f.imponibile_netto_tot), 0) as imponibile_tot,
    coalesce(sum(f.num_articoli), 0) as num_articoli_tot
  from filtered f
),

-- =========================
-- ARTICOLI (leaf sotto fascia_prezzo)
-- =========================
articles_ranked as (
  select
    f.fascia_key,
    f.categoria_key,
    f.famiglia_key,
    f.fp_key,
    a.codart,
    a.articolo_nome,
    a.pot_size,
    a.prezzo_iva_inclusa,
    row_number() over (
      partition by f.fascia_key, f.categoria_key, f.famiglia_key, f.fp_key
      order by
        case when a.pot_size is null or btrim(a.pot_size) = '' then 1 else 0 end,
        nullif(regexp_replace(a.pot_size, '[^0-9\.]', '', 'g'), '')::numeric nulls last,
        case when a.pot_size is null or btrim(a.pot_size) = '' then a.prezzo_iva_inclusa else null end nulls last,
        a.codart asc
    ) as rn
  from (select distinct fascia_key, categoria_key, famiglia_key, fp_key from filtered) f
  join public.core_analytics__components_articles a
    on lower(coalesce(a.fascia_corretta,'(senza fascia)')) = lower(f.fascia_key)
   and lower(coalesce(a.categoria_corretta,'(senza categoria)')) = lower(f.categoria_key)
   and lower(coalesce(a.famiglia,'(senza famiglia)')) = lower(f.famiglia_key)
   and lower(coalesce(a.fascia_prezzo_iva_inc,'(senza fascia prezzo)')) = lower(f.fp_key)
),

articles_trim as (
  select * from articles_ranked where rn <= 300
),

articles_json as (
  select
    ar.fascia_key,
    ar.categoria_key,
    ar.famiglia_key,
    ar.fp_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type','articolo',
          'entity_key', ar.codart,
          'label', ar.codart || ' — ' || ar.articolo_nome,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'extra', jsonb_build_object(
            'pot_size', ar.pot_size,
            'prezzo_iva_inclusa', ar.prezzo_iva_inclusa
          )
        )
        order by
          case when ar.pot_size is null or btrim(ar.pot_size) = '' then 1 else 0 end,
          nullif(regexp_replace(ar.pot_size, '[^0-9\.]', '', 'g'), '')::numeric nulls last,
          case when ar.pot_size is null or btrim(ar.pot_size) = '' then ar.prezzo_iva_inclusa else null end nulls last,
          ar.codart asc
      ),
      '[]'::jsonb
    ) as children_articoli
  from articles_trim ar
  group by 1,2,3,4
),

-- =========================
-- Fascia prezzo
-- =========================
fp_totals as (
  select
    f.fascia_key,
    f.categoria_key,
    f.famiglia_key,
    f.fp_key,
    coalesce(sum(f.qty_venduta), 0) as qty_tot,
    coalesce(sum(f.imponibile_netto_tot), 0) as imponibile_tot,
    coalesce(sum(f.num_articoli), 0) as num_articoli_tot
  from filtered f
  group by 1,2,3,4
  having coalesce(sum(f.qty_venduta), 0) > 0
),

fp_ranked as (
  select
    t.*,
    row_number() over (
      partition by t.fascia_key, t.categoria_key, t.famiglia_key
      order by t.qty_tot desc, t.fp_key asc
    ) as rn
  from fp_totals t
),

fp_trim as (
  select r.*
  from fp_ranked r
  cross join params p
  where r.rn <= p.top_n
),

fp_json_per_family as (
  select
    fpt.fascia_key,
    fpt.categoria_key,
    fpt.famiglia_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'fascia_prezzo',
          'entity_key', fpt.fp_key,
          'label', fpt.fp_key,
          'qty_tot', fpt.qty_tot,
          'imponibile_tot', fpt.imponibile_tot,
          'num_articoli_tot', fpt.num_articoli_tot,
          'children', coalesce(aj.children_articoli, '[]'::jsonb)
        )
        order by fpt.qty_tot desc, fpt.fp_key asc
      ),
      '[]'::jsonb
    ) as children_fp
  from fp_trim fpt
  left join articles_json aj
    on aj.fascia_key = fpt.fascia_key
   and aj.categoria_key = fpt.categoria_key
   and aj.famiglia_key = fpt.famiglia_key
   and aj.fp_key = fpt.fp_key
  group by 1,2,3
),

-- =========================
-- Famiglia (livello)
-- =========================
fam_totals as (
  select
    f.fascia_key,
    f.categoria_key,
    f.famiglia_key,
    coalesce(sum(f.qty_venduta), 0) as qty_tot,
    coalesce(sum(f.imponibile_netto_tot), 0) as imponibile_tot,
    coalesce(sum(f.num_articoli), 0) as num_articoli_tot
  from filtered f
  group by 1,2,3
  having coalesce(sum(f.qty_venduta), 0) > 0
),

fam_ranked as (
  select
    t.*,
    row_number() over (
      partition by t.fascia_key, t.categoria_key
      order by t.qty_tot desc, t.famiglia_key asc
    ) as rn
  from fam_totals t
),

fam_trim as (
  select r.*
  from fam_ranked r
  cross join params p
  where r.rn <= p.top_n
),

fam_json_per_cat as (
  select
    ft.fascia_key,
    ft.categoria_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'famiglia',
          'entity_key', ft.famiglia_key,
          'label', ft.famiglia_key,
          'qty_tot', ft.qty_tot,
          'imponibile_tot', ft.imponibile_tot,
          'num_articoli_tot', ft.num_articoli_tot,
          'children', coalesce(fp.children_fp, '[]'::jsonb)
        )
        order by ft.qty_tot desc, ft.famiglia_key asc
      ),
      '[]'::jsonb
    ) as children_famiglie
  from fam_trim ft
  left join fp_json_per_family fp
    on fp.fascia_key = ft.fascia_key
   and fp.categoria_key = ft.categoria_key
   and fp.famiglia_key = ft.famiglia_key
  group by 1,2
),

-- =========================
-- Categoria
-- =========================
cat_totals as (
  select
    f.fascia_key,
    f.categoria_key,
    coalesce(sum(f.qty_venduta), 0) as qty_tot,
    coalesce(sum(f.imponibile_netto_tot), 0) as imponibile_tot,
    coalesce(sum(f.num_articoli), 0) as num_articoli_tot
  from filtered f
  group by 1,2
  having coalesce(sum(f.qty_venduta), 0) > 0
),

cat_ranked as (
  select
    t.*,
    row_number() over (
      partition by t.fascia_key
      order by t.qty_tot desc, t.categoria_key asc
    ) as rn
  from cat_totals t
),

cat_trim as (
  select r.*
  from cat_ranked r
  cross join params p
  where r.rn <= p.top_n
),

cat_json_per_fascia as (
  select
    ct.fascia_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'categoria',
          'entity_key', ct.categoria_key,
          'label', ct.categoria_key,
          'qty_tot', ct.qty_tot,
          'imponibile_tot', ct.imponibile_tot,
          'num_articoli_tot', ct.num_articoli_tot,
          'children', coalesce(fj.children_famiglie, '[]'::jsonb)
        )
        order by ct.qty_tot desc, ct.categoria_key asc
      ),
      '[]'::jsonb
    ) as children_categorie
  from cat_trim ct
  left join fam_json_per_cat fj
    on fj.fascia_key = ct.fascia_key
   and fj.categoria_key = ct.categoria_key
  group by 1
),

-- =========================
-- Fascia (root)
-- =========================
fas_totals as (
  select
    f.fascia_key,
    coalesce(sum(f.qty_venduta), 0) as qty_tot,
    coalesce(sum(f.imponibile_netto_tot), 0) as imponibile_tot,
    coalesce(sum(f.num_articoli), 0) as num_articoli_tot
  from filtered f
  group by 1
  having coalesce(sum(f.qty_venduta), 0) > 0
),

fas_ranked as (
  select
    t.*,
    row_number() over (order by t.qty_tot desc, t.fascia_key asc) as rn
  from fas_totals t
),

fas_trim as (
  select r.*
  from fas_ranked r
  cross join params p
  where r.rn <= p.top_n
),

fas_json as (
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'fascia',
          'entity_key', ft.fascia_key,
          'label', ft.fascia_key,
          'qty_tot', ft.qty_tot,
          'imponibile_tot', ft.imponibile_tot,
          'num_articoli_tot', ft.num_articoli_tot,
          'children', coalesce(cj.children_categorie, '[]'::jsonb)
        )
        order by ft.qty_tot desc, ft.fascia_key asc
      ),
      '[]'::jsonb
    ) as tree
  from fas_trim ft
  left join cat_json_per_fascia cj
    on cj.fascia_key = ft.fascia_key
)

select jsonb_build_object(
  'entity_type', (select et from params),
  'entity_key',  p_entity_key,
  'date_from',   p_date_from,
  'date_to',     p_date_to,
  'totals',      (select to_jsonb(t) from totals t),
  'tree',        (select tree from fas_json)
);
$$;

--
-- Name: core_analytics__future_window_stats(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__future_window_stats(p_entity_type text, p_entity_key text, p_famiglia text DEFAULT NULL::text) RETURNS TABLE(window_days integer, min_qty numeric, max_qty numeric, avg_qty numeric)
    LANGUAGE plpgsql STABLE
    AS $$
declare
  m int := extract(month from current_date);
  d int := extract(day from current_date);

  v_type text := lower(trim(p_entity_type));
  v_key  text := lower(trim(p_entity_key));
  v_fam  text := case when p_famiglia is null then null else lower(trim(p_famiglia)) end;

  end_y int := extract(year from current_date)::int - 1;
begin
  if v_type is null or v_type = '' then
    raise exception 'p_entity_type is required';
  end if;

  if p_entity_key is null or length(trim(p_entity_key)) = 0 then
    raise exception 'p_entity_key is required';
  end if;

  if v_type = 'fascia_prezzo' and (v_fam is null or v_fam = '') then
    raise exception 'fascia_prezzo requires p_famiglia';
  end if;

  -- ====== FAMIGLIA ======
  if v_type = 'famiglia' then
    return query
    with years as (
      select generate_series(2008, end_y) as y
    ),
    anchors as (
      select
        y,
        case
          when m = 2 and d = 29 and not exists (
            select 1
            where (make_date(y, 2, 1) + interval '1 month - 1 day')::date = make_date(y, 2, 29)
          )
          then make_date(y, 2, 28)
          else make_date(y, m, d)
        end as anchor_date
      from years
    ),
    totals as (
      select
        a.y,
        coalesce(sum(case when g.data <= a.anchor_date + 7  then g.qty_venduta else 0 end),0) as qty_7,
        coalesce(sum(case when g.data <= a.anchor_date + 10 then g.qty_venduta else 0 end),0) as qty_10,
        coalesce(sum(case when g.data <= a.anchor_date + 15 then g.qty_venduta else 0 end),0) as qty_15,
        coalesce(sum(case when g.data <= a.anchor_date + 30 then g.qty_venduta else 0 end),0) as qty_30
      from anchors a
      left join public.greenhouse_forecast_features_dense g
        on g.data >= a.anchor_date + 1
       and g.data <= a.anchor_date + 30
       and lower(g.famiglia) = v_key
      group by a.y
    ),
    unpivot as (
      select y, 7  as window_days, qty_7  as qty from totals
      union all select y, 10, qty_10 from totals
      union all select y, 15, qty_15 from totals
      union all select y, 30, qty_30 from totals
    )
    select
      u.window_days,
      min(u.qty)::numeric as min_qty,
      max(u.qty)::numeric as max_qty,
      avg(u.qty)::numeric as avg_qty
    from unpivot u
    group by u.window_days
    order by u.window_days;

    return;
  end if;

  -- ====== CATEGORIA ======
  if v_type = 'categoria' then
    return query
    with years as (
      select generate_series(2008, end_y) as y
    ),
    anchors as (
      select
        y,
        case
          when m = 2 and d = 29 and not exists (
            select 1
            where (make_date(y, 2, 1) + interval '1 month - 1 day')::date = make_date(y, 2, 29)
          )
          then make_date(y, 2, 28)
          else make_date(y, m, d)
        end as anchor_date
      from years
    ),
    totals as (
      select
        a.y,
        coalesce(sum(case when g.data <= a.anchor_date + 7  then g.qty_venduta else 0 end),0) as qty_7,
        coalesce(sum(case when g.data <= a.anchor_date + 10 then g.qty_venduta else 0 end),0) as qty_10,
        coalesce(sum(case when g.data <= a.anchor_date + 15 then g.qty_venduta else 0 end),0) as qty_15,
        coalesce(sum(case when g.data <= a.anchor_date + 30 then g.qty_venduta else 0 end),0) as qty_30
      from anchors a
      left join public.greenhouse_forecast_features_dense g
        on g.data >= a.anchor_date + 1
       and g.data <= a.anchor_date + 30
       and lower(g.categoria_corretta) = v_key
      group by a.y
    ),
    unpivot as (
      select y, 7  as window_days, qty_7  as qty from totals
      union all select y, 10, qty_10 from totals
      union all select y, 15, qty_15 from totals
      union all select y, 30, qty_30 from totals
    )
    select
      u.window_days,
      min(u.qty)::numeric as min_qty,
      max(u.qty)::numeric as max_qty,
      avg(u.qty)::numeric as avg_qty
    from unpivot u
    group by u.window_days
    order by u.window_days;

    return;
  end if;

  -- ====== FASCIA ======
  if v_type = 'fascia' then
    return query
    with years as (
      select generate_series(2008, end_y) as y
    ),
    anchors as (
      select
        y,
        case
          when m = 2 and d = 29 and not exists (
            select 1
            where (make_date(y, 2, 1) + interval '1 month - 1 day')::date = make_date(y, 2, 29)
          )
          then make_date(y, 2, 28)
          else make_date(y, m, d)
        end as anchor_date
      from years
    ),
    totals as (
      select
        a.y,
        coalesce(sum(case when g.data <= a.anchor_date + 7  then g.qty_venduta else 0 end),0) as qty_7,
        coalesce(sum(case when g.data <= a.anchor_date + 10 then g.qty_venduta else 0 end),0) as qty_10,
        coalesce(sum(case when g.data <= a.anchor_date + 15 then g.qty_venduta else 0 end),0) as qty_15,
        coalesce(sum(case when g.data <= a.anchor_date + 30 then g.qty_venduta else 0 end),0) as qty_30
      from anchors a
      left join public.greenhouse_forecast_features_dense g
        on g.data >= a.anchor_date + 1
       and g.data <= a.anchor_date + 30
       and lower(g.fascia_corretta) = v_key
      group by a.y
    ),
    unpivot as (
      select y, 7  as window_days, qty_7  as qty from totals
      union all select y, 10, qty_10 from totals
      union all select y, 15, qty_15 from totals
      union all select y, 30, qty_30 from totals
    )
    select
      u.window_days,
      min(u.qty)::numeric as min_qty,
      max(u.qty)::numeric as max_qty,
      avg(u.qty)::numeric as avg_qty
    from unpivot u
    group by u.window_days
    order by u.window_days;

    return;
  end if;

  -- ====== FASCIA PREZZO (richiede famiglia) ======
  if v_type = 'fascia_prezzo' then
    return query
    with years as (
      select generate_series(2008, end_y) as y
    ),
    anchors as (
      select
        y,
        case
          when m = 2 and d = 29 and not exists (
            select 1
            where (make_date(y, 2, 1) + interval '1 month - 1 day')::date = make_date(y, 2, 29)
          )
          then make_date(y, 2, 28)
          else make_date(y, m, d)
        end as anchor_date
      from years
    ),
    totals as (
      select
        a.y,
        coalesce(sum(case when g.data <= a.anchor_date + 7  then g.qty_venduta else 0 end),0) as qty_7,
        coalesce(sum(case when g.data <= a.anchor_date + 10 then g.qty_venduta else 0 end),0) as qty_10,
        coalesce(sum(case when g.data <= a.anchor_date + 15 then g.qty_venduta else 0 end),0) as qty_15,
        coalesce(sum(case when g.data <= a.anchor_date + 30 then g.qty_venduta else 0 end),0) as qty_30
      from anchors a
      left join public.greenhouse_forecast_features_dense g
        on g.data >= a.anchor_date + 1
       and g.data <= a.anchor_date + 30
       and lower(g.famiglia) = v_fam
       and g.fascia_prezzo_iva_inc = p_entity_key
      group by a.y
    ),
    unpivot as (
      select y, 7  as window_days, qty_7  as qty from totals
      union all select y, 10, qty_10 from totals
      union all select y, 15, qty_15 from totals
      union all select y, 30, qty_30 from totals
    )
    select
      u.window_days,
      min(u.qty)::numeric as min_qty,
      max(u.qty)::numeric as max_qty,
      avg(u.qty)::numeric as avg_qty
    from unpivot u
    group by u.window_days
    order by u.window_days;

    return;
  end if;

  raise exception 'Unsupported p_entity_type=%', p_entity_type;
end;
$$;

--
-- Name: core_analytics__list_catalog(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__list_catalog(p_entity_type text, p_limit integer DEFAULT 500) RETURNS TABLE(entity_type text, entity_key text, label text)
    LANGUAGE sql STABLE
    AS $$
  select
    c.entity_type,
    c.entity_key,
    c.label
  from public.core_analytics__catalog c
  where c.entity_type = p_entity_type
  order by c.label asc
  limit greatest(1, least(p_limit, 2000));
$$;

--
-- Name: core_analytics__range_totals_v2(text, text, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__range_totals_v2(p_entity_type text, p_entity_key text, p_date_from date, p_date_to date) RETURNS TABLE(qty_tot numeric, imp_tot numeric, days integer, active_days integer, zero_days integer, min_day date, min_qty numeric, max_day date, max_qty numeric)
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_type text := lower(btrim(p_entity_type::text));
  v_key  text := lower(btrim(p_entity_key::text));
begin
  if v_type is null or v_type = '' then
    raise exception 'p_entity_type is required (got=%)', p_entity_type;
  end if;

  if p_entity_key is null or btrim(p_entity_key::text) = '' then
    raise exception 'p_entity_key is required';
  end if;

  -- Normalizza eventuali sinonimi (opzionale)
  if v_type in ('family') then v_type := 'famiglia'; end if;
  if v_type in ('category') then v_type := 'categoria'; end if;
  if v_type in ('band','range') then v_type := 'fascia'; end if;
  if v_type in ('price_band','fascia-prezzo','fascia prezzo') then v_type := 'fascia_prezzo'; end if;

  -- ARTICOLO (codart case-sensitive: NON loweriamo la chiave)
  if v_type = 'articolo' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta::numeric as qty,
        imponibile_netto::numeric as imp
      from public.core_analytics__article_sales_daily
      where codart = btrim(p_entity_key::text)
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0)                                         as qty_tot,
      coalesce(sum(r.imp),0)                                         as imp_tot,
      count(*)::int                                                  as days,
      count(*) filter (where r.qty > 0)::int                         as active_days,
      count(*) filter (where r.qty = 0)::int                         as zero_days,
      (select rr.data from r rr order by rr.qty asc, rr.data asc limit 1)  as min_day,
      (select rr.qty  from r rr order by rr.qty asc, rr.data asc limit 1)  as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc limit 1) as max_qty
    from r;

    return;
  end if;

  -- FAMIGLIA
  if v_type = 'famiglia' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta_tot::numeric as qty,
        imponibile_netto_tot::numeric as imp
      from public.core_analytics__series_daily_famiglia_lc
      where entity_key_lc = v_key
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0)                                         as qty_tot,
      coalesce(sum(r.imp),0)                                         as imp_tot,
      count(*)::int                                                  as days,
      count(*) filter (where r.qty > 0)::int                         as active_days,
      count(*) filter (where r.qty = 0)::int                         as zero_days,
      (select rr.data from r rr order by rr.qty asc, rr.data asc limit 1)  as min_day,
      (select rr.qty  from r rr order by rr.qty asc, rr.data asc limit 1)  as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc limit 1) as max_qty
    from r;

    return;
  end if;

  -- CATEGORIA
  if v_type = 'categoria' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta_tot::numeric as qty,
        imponibile_netto_tot::numeric as imp
      from public.core_analytics__series_daily_categoria_lc
      where entity_key_lc = v_key
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0)                                         as qty_tot,
      coalesce(sum(r.imp),0)                                         as imp_tot,
      count(*)::int                                                  as days,
      count(*) filter (where r.qty > 0)::int                         as active_days,
      count(*) filter (where r.qty = 0)::int                         as zero_days,
      (select rr.data from r rr order by rr.qty asc, rr.data asc limit 1)  as min_day,
      (select rr.qty  from r rr order by rr.qty asc, rr.data asc limit 1)  as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc limit 1) as max_qty
    from r;

    return;
  end if;

  -- FASCIA
  if v_type = 'fascia' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta_tot::numeric as qty,
        imponibile_netto_tot::numeric as imp
      from public.core_analytics__series_daily_fascia_lc
      where entity_key_lc = v_key
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0)                                         as qty_tot,
      coalesce(sum(r.imp),0)                                         as imp_tot,
      count(*)::int                                                  as days,
      count(*) filter (where r.qty > 0)::int                         as active_days,
      count(*) filter (where r.qty = 0)::int                         as zero_days,
      (select rr.data from r rr order by rr.qty asc, rr.data asc limit 1)  as min_day,
      (select rr.qty  from r rr order by rr.qty asc, rr.data asc limit 1)  as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc limit 1) as max_qty
    from r;

    return;
  end if;

  -- FASCIA PREZZO
  if v_type = 'fascia_prezzo' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta_tot::numeric as qty,
        imponibile_netto_tot::numeric as imp
      from public.core_analytics__series_daily_fascia_prezzo_lc
      where entity_key_lc = v_key
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0)                                         as qty_tot,
      coalesce(sum(r.imp),0)                                         as imp_tot,
      count(*)::int                                                  as days,
      count(*) filter (where r.qty > 0)::int                         as active_days,
      count(*) filter (where r.qty = 0)::int                         as zero_days,
      (select rr.data from r rr order by rr.qty asc, rr.data asc limit 1)  as min_day,
      (select rr.qty  from r rr order by rr.qty asc, rr.data asc limit 1)  as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc limit 1) as max_qty
    from r;

    return;
  end if;

  raise exception 'Unsupported p_entity_type=% (normalized=%)', p_entity_type, v_type;
end;
$$;

--
-- Name: core_analytics__search_catalog(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__search_catalog(term text, limit_n integer DEFAULT 50) RETURNS TABLE(entity_type text, entity_key text, label text, score numeric)
    LANGUAGE sql STABLE
    AS $$
  with q as (
    select
      lower(trim(term)) as t,
      greatest(1, least(limit_n, 200)) as lim
  ),
  candidates as (
    -- FAMIGLIA
    select
      'famiglia'::text as entity_type,
      lower(f.famiglia) as entity_key,
      f.famiglia as label,
      similarity(lower(f.famiglia), (select t from q))::numeric as score
    from public.greenhouse_forecast_features_dense f, q
    where f.famiglia is not null
      and lower(f.famiglia) % q.t
    group by f.famiglia

    union all

    -- CATEGORIA
    select
      'categoria'::text as entity_type,
      lower(f.categoria_corretta) as entity_key,
      f.categoria_corretta as label,
      similarity(lower(f.categoria_corretta), (select t from q))::numeric as score
    from public.greenhouse_forecast_features_dense f, q
    where f.categoria_corretta is not null
      and lower(f.categoria_corretta) % q.t
    group by f.categoria_corretta

    union all

    -- FASCIA
    select
      'fascia'::text as entity_type,
      lower(f.fascia_corretta) as entity_key,
      f.fascia_corretta as label,
      similarity(lower(f.fascia_corretta), (select t from q))::numeric as score
    from public.greenhouse_forecast_features_dense f, q
    where f.fascia_corretta is not null
      and lower(f.fascia_corretta) % q.t
    group by f.fascia_corretta

    union all

    -- FASCIA PREZZO
    select
      'fascia_prezzo'::text as entity_type,
      lower(f.fascia_prezzo_iva_inc) as entity_key,
      f.fascia_prezzo_iva_inc as label,
      similarity(lower(f.fascia_prezzo_iva_inc), (select t from q))::numeric as score
    from public.greenhouse_forecast_features_dense f, q
    where f.fascia_prezzo_iva_inc is not null
      and lower(f.fascia_prezzo_iva_inc) % q.t
    group by f.fascia_prezzo_iva_inc
  )
  select *
  from candidates
  where score >= 0.15
  order by
    case entity_type
      when 'famiglia' then 1
      when 'categoria' then 2
      when 'fascia' then 3
      else 4
    end,
    score desc,
    label asc
  limit (select lim from q);
$$;

--
-- Name: core_analytics__series_bounds(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__series_bounds(p_entity_type text, p_entity_key text) RETURNS TABLE(min_data date, max_data date)
    LANGUAGE sql STABLE
    AS $$
  select
    case
      when p_entity_type = 'famiglia' then (
        select min(data)::date
        from public.core_analytics__series_daily_famiglia
        where lower(entity_key) = lower(p_entity_key)
      )
      when p_entity_type = 'categoria' then (
        select min(data)::date
        from public.core_analytics__series_daily_categoria
        where lower(entity_key) = lower(p_entity_key)
      )
      when p_entity_type = 'fascia' then (
        select min(data)::date
        from public.core_analytics__series_daily_fascia
        where lower(entity_key) = lower(p_entity_key)
      )
      when p_entity_type = 'fascia_prezzo' then (
        select min(data)::date
        from public.core_analytics__series_daily_fascia_prezzo
        where lower(entity_key) = lower(p_entity_key)
      )
      when p_entity_type = 'articolo' then (
        select min(data)::date
        from public.core_analytics__article_sales_daily
        where codart = p_entity_key
      )
      else null::date
    end as min_data,
    case
      when p_entity_type = 'famiglia' then (
        select max(data)::date
        from public.core_analytics__series_daily_famiglia
        where lower(entity_key) = lower(p_entity_key)
      )
      when p_entity_type = 'categoria' then (
        select max(data)::date
        from public.core_analytics__series_daily_categoria
        where lower(entity_key) = lower(p_entity_key)
      )
      when p_entity_type = 'fascia' then (
        select max(data)::date
        from public.core_analytics__series_daily_fascia
        where lower(entity_key) = lower(p_entity_key)
      )
      when p_entity_type = 'fascia_prezzo' then (
        select max(data)::date
        from public.core_analytics__series_daily_fascia_prezzo
        where lower(entity_key) = lower(p_entity_key)
      )
      when p_entity_type = 'articolo' then (
        select max(data)::date
        from public.core_analytics__article_sales_daily
        where codart = p_entity_key
      )
      else null::date
    end as max_data;
$$;

--
-- Name: core_analytics__stock_and_reorder_v1(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__stock_and_reorder_v1(p_entity_type text, p_entity_key text, p_fascia_prezzo text DEFAULT NULL::text) RETURNS TABLE(stock_qty numeric, reorder_qty numeric)
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_entity_type text := lower(trim(coalesce(p_entity_type,'')));
  v_key text := lower(trim(coalesce(p_entity_key,'')));
  v_fp text := nullif(lower(trim(coalesce(p_fascia_prezzo,''))), '');
  v_latest_date date;
begin
  if v_entity_type = '' or v_key = '' then
    stock_qty := null;
    reorder_qty := null;
    return next;
    return;
  end if;

  -- 1) latest stock date
  select max(data_rilevazione)::date
  into v_latest_date
  from public.greenhouse_stock_raw_upload;

  -- se non ho stock date, stock null (ma reorder lo posso calcolare)
  -- 2) STOCK: greenhouse_stock_enriched filtrata su ultima data
  if v_latest_date is null then
    stock_qty := null;
  else
    select coalesce(sum(se.qty_giacenza),0)
    into stock_qty
    from public.greenhouse_stock_enriched se
    where se.data_rilevazione::date = v_latest_date
      and (
        (v_entity_type = 'famiglia'      and lower(trim(se.famiglia)) = v_key) or
        (v_entity_type = 'categoria'     and lower(trim(se.categoria_corretta)) = v_key) or
        (v_entity_type = 'fascia'        and lower(trim(se.fascia_corretta)) = v_key) or
        (v_entity_type = 'fascia_prezzo' and lower(trim(se.fascia_prezzo_iva_inc)) = v_key) or
        (v_entity_type = 'articolo'      and lower(trim(se.codart)) = v_key)
      )
      and (
        -- cascata fascia prezzo SOLO se entity è famiglia/categoria/fascia
        v_fp is null
        or v_entity_type not in ('famiglia','categoria','fascia')
        or lower(trim(se.fascia_prezzo_iva_inc)) = v_fp
      );
  end if;

  -- 3) REORDER: dalla view greenhouse_order_suggestions_enriched_v2 (già qty_da_ordinare >= 1)
  -- articolo non supportato in reorder (come già fai)
  if v_entity_type = 'articolo' then
    reorder_qty := null;
  else
    select coalesce(sum(v.qty_da_ordinare),0)
    into reorder_qty
    from public.greenhouse_order_suggestions_enriched_v2 v
    where (
        (v_entity_type = 'famiglia'      and lower(trim(v.famiglia)) = v_key) or
        (v_entity_type = 'categoria'     and lower(trim(v.categoria_corretta)) = v_key) or
        (v_entity_type = 'fascia'        and lower(trim(v.fascia_corretta)) = v_key) or
        (v_entity_type = 'fascia_prezzo' and lower(trim(v.fascia_prezzo_iva_inc)) = v_key)
      )
      and (
        v_fp is null
        or v_entity_type not in ('famiglia','categoria','fascia')
        or lower(trim(v.fascia_prezzo_iva_inc)) = v_fp
      );
  end if;

  return next;
end;
$$;

--
-- Name: core_planner__build_weekly_backfill(date, date, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__build_weekly_backfill(p_start date DEFAULT '2009-01-01'::date, p_end date DEFAULT CURRENT_DATE, p_step_days integer DEFAULT 31, p_max_steps integer DEFAULT 3) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  cur_from date;
  cur_to date;
  i int := 0;
  st date;
begin
  select last_day into st
  from public.t_core_planner__refresh_state
  where pipeline = 'planner_weekly';

  -- se non esiste, fallback
  if st is null then
    st := p_start - 1;
  end if;

  -- riparto dal giorno successivo a last_day
  cur_from := greatest(p_start, st + 1);
  if cur_from > p_end then
    return jsonb_build_object(
      'status','done',
      'last_day', st,
      'message','Nessun backfill necessario'
    );
  end if;

  while i < p_max_steps loop
    cur_to := least(p_end, cur_from + (p_step_days - 1));

    perform public.core_planner__refresh_fact_weekly(cur_from, cur_to);

    i := i + 1;
    cur_from := cur_to + 1;

    exit when cur_from > p_end;
  end loop;

  select last_day into st
  from public.t_core_planner__refresh_state
  where pipeline = 'planner_weekly';

  return jsonb_build_object(
    'status', case when st >= p_end then 'done' else 'running' end,
    'last_day', st,
    'processed_steps', i,
    'next_from', (st + 1),
    'target_end', p_end
  );
end $$;

--
-- Name: core_planner__get_assortment_calendar(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__get_assortment_calendar(p_mode text DEFAULT 'week'::text, p_level text DEFAULT 'famiglia'::text) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select jsonb_build_object(
    'mode', p_mode,
    'level', p_level,
    'rows', coalesce(
      jsonb_agg(to_jsonb(r) order by r.node_id, r.week_52),
      '[]'::jsonb
    )
  )
  from (
    select
      node_id,
      week_52,
      state,
      space_m2_raw,
      space_share,
      stock_target
    from public.t_core_planner__assortment_calendar
    where mode = p_mode
      and level = p_level
  ) r;
$$;

--
-- Name: core_planner__get_current_week52(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__get_current_week52() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select jsonb_build_object(
    'today', current_date,
    'week_52', (select week_52 from public.dim_iso_day where day=current_date),
    'iso_year', (select iso_year from public.dim_iso_day where day=current_date),
    'week_start', (select week_start from public.dim_iso_day where day=current_date)
  );
$$;

--
-- Name: core_planner__get_heatmap(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__get_heatmap(p_mode text DEFAULT 'week'::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_mode text := coalesce(nullif(p_mode,''), 'week');
  result jsonb;
begin
  if v_mode not in ('week','roll4') then
    raise exception 'p_mode deve essere week o roll4';
  end if;

  with nodes as (
    select distinct
      node_id, parent_id, level, label,
      fascia, categoria, famiglia, fascia_prezzo
    from public.t_core_planner__heat_cells
    where mode = v_mode
  ),
  cells as (
    select
      node_id, week_52,
      avg_qty, avg_rev, share_rev,
      sigma_qty, avg_days_active, avg_days_zero,
      min_qty, max_qty, min_rev, max_rev,
      stock_target, space_m2,
      color_score
    from public.t_core_planner__heat_cells
    where mode = v_mode
  )
  select jsonb_build_object(
    'mode', v_mode,
    'nodes', coalesce((select jsonb_agg(to_jsonb(n) order by n.level, n.label) from nodes n), '[]'::jsonb),
    'cells', coalesce((select jsonb_agg(to_jsonb(c)) from cells c), '[]'::jsonb)
  )
  into result;

  return result;
end;
$$;

--
-- Name: core_planner__get_heatmap_cells(text, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__get_heatmap_cells(p_mode text, p_node_ids text[] DEFAULT NULL::text[]) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select jsonb_build_object(
    'mode', p_mode,
    'cells', coalesce(jsonb_agg(to_jsonb(c) order by c.node_id, c.week_52), '[]'::jsonb)
  )
  from (
    select
      node_id,
      week_52,
      avg_qty,
      avg_rev,
      share_rev,
      sigma_qty,
      avg_days_active,
      avg_days_zero,
      min_qty,
      max_qty,
      min_rev,
      max_rev,
      stock_target,
      space_m2,
      color_score
    from public.t_core_planner__heat_cells
    where mode = p_mode
      and (p_node_ids is null or node_id = any(p_node_ids))
  ) c;
$$;

--
-- Name: core_planner__get_heatmap_nodes(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__get_heatmap_nodes(p_mode text DEFAULT 'week'::text) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select jsonb_build_object(
    'mode', p_mode,
    'nodes', coalesce(jsonb_agg(to_jsonb(n) order by n.level, n.label), '[]'::jsonb)
  )
  from (
    select distinct
      node_id,
      parent_id,
      level,
      label,
      fascia, categoria, famiglia, fascia_prezzo
    from public.t_core_planner__heat_cells
    where mode = p_mode
  ) n;
$$;

--
-- Name: core_planner__get_heatmap_roll4_ranges(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__get_heatmap_roll4_ranges(p_node_ids text[] DEFAULT NULL::text[]) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with _guard as (
    select case
      when p_node_ids is null or array_length(p_node_ids,1) is null then true
      else false
    end as no_filter
  ),
  ranges as (
    select
      node_id,
      week_52,
      min_qty,
      max_qty,
      min_rev,
      max_rev
    from public.t_core_planner__heat_cells
    where mode = 'roll4'
      and (p_node_ids is not null and node_id = any(p_node_ids))
  )
  select
    case
      when (select no_filter from _guard) then jsonb_build_object('mode','roll4','ranges','[]'::jsonb)
      else jsonb_build_object(
        'mode','roll4',
        'ranges', coalesce(jsonb_agg(to_jsonb(r) order by r.node_id, r.week_52), '[]'::jsonb)
      )
    end
  from ranges r;
$$;

--
-- Name: core_planner__get_heatmap_week_ranges(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__get_heatmap_week_ranges(p_node_ids text[] DEFAULT NULL::text[]) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
with _guard as (
  select case
    when p_node_ids is null or array_length(p_node_ids,1) is null then true
    else false
  end as no_filter
),
ranges as (
  select
    node_id,
    week_52,
    min_qty,
    max_qty,
    min_rev,
    max_rev
  from public.t_core_planner__heat_cells
  where mode = 'week'
    and (p_node_ids is not null and node_id = any(p_node_ids))
)
select
  case
    when (select no_filter from _guard) then jsonb_build_object('mode','week','ranges','[]'::jsonb)
    else jsonb_build_object(
      'mode','week',
      'ranges', coalesce(jsonb_agg(to_jsonb(r) order by r.node_id, r.week_52), '[]'::jsonb)
    )
  end
from ranges r;
$$;

--
-- Name: core_planner__get_space_budget(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__get_space_budget(p_mode text DEFAULT 'week'::text, p_level text DEFAULT 'famiglia'::text) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select jsonb_build_object(
    'mode', p_mode,
    'level', p_level,
    'rows', coalesce(
      jsonb_agg(to_jsonb(r) order by r.node_id, r.week_52),
      '[]'::jsonb
    )
  )
  from (
    select
      node_id,
      week_52,
      space_m2_raw,
      space_share
    from public.t_core_planner__space_budget
    where mode = p_mode
      and level = p_level
  ) r;
$$;

--
-- Name: core_planner__map_pot_size_group(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__map_pot_size_group(p_raw text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  v text := lower(coalesce(trim(p_raw), ''));
  n int;
begin
  if v = '' then
    return 'DEFAULT';
  end if;

  -- se già è un gruppo valido (es: 'P14', 'V14', '14', 'default')
  -- normalizza numeri tipo 14 / v14 / Ø14 / vaso 14
  -- estrae il primo numero 2-3 cifre
  begin
    n := nullif(regexp_replace(v, '.*?([0-9]{2,3}).*', '\1'), v)::int;
  exception when others then
    n := null;
  end;

  if n is null then
    -- fallback: stringa uppercase (può essere un gruppo custom)
    return upper(v);
  end if;

  -- bucket (personalizza se vuoi)
  if n <= 10 then return 'P10';
  elsif n <= 12 then return 'P12';
  elsif n <= 14 then return 'P14';
  elsif n <= 16 then return 'P16';
  elsif n <= 18 then return 'P18';
  elsif n <= 20 then return 'P20';
  elsif n <= 24 then return 'P24';
  elsif n <= 30 then return 'P30';
  else return 'P31+';
  end if;
end;
$$;

--
-- Name: core_planner__nightly_roll4_reset(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__nightly_roll4_reset() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  -- lock anti-overlap
  if not pg_try_advisory_lock(hashtext('core_planner__nightly_roll4_reset')) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_running');
  end if;

  insert into public.t_core_planner__orchestrator_state(pipeline, step, cursor_int)
  values ('nightly_roll4','roll4_weeks',1)
  on conflict (pipeline)
  do update set step='roll4_weeks', cursor_int=1, updated_at=now();

  perform pg_advisory_unlock(hashtext('core_planner__nightly_roll4_reset'));

  return jsonb_build_object('ok', true, 'pipeline', 'nightly_roll4_reset', 'cursor', 1, 'ts', now());
exception when others then
  begin
    perform pg_advisory_unlock(hashtext('core_planner__nightly_roll4_reset'));
  exception when others then null;
  end;
  return jsonb_build_object('ok', false, 'pipeline', 'nightly_roll4_reset', 'error', sqlerrm, 'ts', now());
end;
$$;

--
-- Name: core_planner__nightly_roll4_tick(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__nightly_roll4_tick(p_weeks_per_run integer DEFAULT 2) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_step text;
  v_res jsonb;
begin
  if not pg_try_advisory_lock(hashtext('core_planner__nightly_roll4_tick')) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_running');
  end if;

  select step into v_step
  from public.t_core_planner__orchestrator_state
  where pipeline='nightly_roll4';

  if v_step = 'done' then
    perform pg_advisory_unlock(hashtext('core_planner__nightly_roll4_tick'));
    return jsonb_build_object('ok', true, 'pipeline','nightly_roll4_tick', 'status','done', 'ts', now());
  end if;

  v_res := public.core_planner__refresh_nightly_step(greatest(1, p_weeks_per_run));

  perform pg_advisory_unlock(hashtext('core_planner__nightly_roll4_tick'));
  return v_res;

exception when others then
  begin
    perform pg_advisory_unlock(hashtext('core_planner__nightly_roll4_tick'));
  exception when others then null;
  end;
  return jsonb_build_object('ok', false, 'pipeline','nightly_roll4_tick', 'error', sqlerrm, 'ts', now());
end;
$$;

--
-- Name: core_planner__refresh_after_import(integer, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_after_import(p_buffer_days integer DEFAULT 14, p_force_potsize boolean DEFAULT false, p_potsize_years integer DEFAULT 5) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_now timestamptz := now();

  v_from date;
  v_to date;  -- ✅ anchored

  v_last date;
  v_rows_potsize bigint;

  v_dense_max date;
  v_raw_max date;

  v_result jsonb;
begin
  -- prova a togliere timeout locale (se permesso)
  begin
    execute 'set local statement_timeout = 0';
  exception when others then
    null;
  end;

  /* -------------------------
     Anchor "reale": max giorno disponibile
     preferisci DENSE, fallback RAW
     ------------------------- */
  select max(data)::date
  into v_dense_max
  from public.greenhouse_sales_family_daily_dense;

  select max(data_movimento)::date
  into v_raw_max
  from public.greenhouse_sales_raw;

  v_to := coalesce(v_dense_max, v_raw_max);

  if v_to is null then
    raise exception 'No data found: dense and raw are empty. Cannot compute v_to';
  end if;

  -- opzionale: evita date future "sporche"
  v_to := least(v_to, current_date);

  /* -------------------------
     ensure refresh_state row (usa v_to, non current_date)
     ------------------------- */
  insert into public.t_core_planner__refresh_state (pipeline, last_day)
  values ('planner_weekly', (v_to - 30))
  on conflict (pipeline) do nothing;

  select last_day
  into v_last
  from public.t_core_planner__refresh_state
  where pipeline = 'planner_weekly';

  -- clamp robusto: se refresh_state è avanti ai dati reali
  v_last := least(v_last, v_to);

  -- finestra incrementale robusta: riprendi buffer dietro
  v_from := greatest((v_last - p_buffer_days), date '2009-01-01');

  /* -------------------------
     1) fact_weekly incremental (range)
     ------------------------- */
  perform public.core_planner__refresh_fact_weekly(v_from, v_to);

  /* -------------------------
     2) heat week
     ------------------------- */
  perform public.core_planner__refresh_heat_week();

  /* -------------------------
     3) potsize_profile (solo se vuota o forzata)
     ------------------------- */
  select count(*)
  into v_rows_potsize
  from public.t_core_planner__potsize_profile;

  if p_force_potsize or coalesce(v_rows_potsize,0) = 0 then
    perform public.core_planner__refresh_potsize_profile(p_potsize_years);
  end if;

  /* -------------------------
     4) space_from_heat(week)
     ------------------------- */
  perform public.core_planner__refresh_space_from_heat('week');

  /* -------------------------
     5) space_budget week (famiglia + categoria)
     ------------------------- */
  perform public.core_planner__refresh_space_budget('week','famiglia');
  perform public.core_planner__refresh_space_budget('week','categoria');

  /* -------------------------
     6) assortment_calendar week (famiglia + categoria)
     ------------------------- */
  perform public.core_planner__refresh_assortment_calendar('week','famiglia');
  perform public.core_planner__refresh_assortment_calendar('week','categoria');

  v_result := jsonb_build_object(
    'ok', true,
    'pipeline', 'after_import',
    'ts', v_now,
    'anchor', jsonb_build_object(
      'dense_max', v_dense_max,
      'raw_max', v_raw_max,
      'v_to', v_to
    ),
    'fact_weekly', jsonb_build_object(
      'from', v_from,
      'to', v_to,
      'buffer_days', p_buffer_days
    ),
    'heat', jsonb_build_object('week', true),
    'potsize', jsonb_build_object(
      'forced', p_force_potsize,
      'ran', (p_force_potsize or coalesce(v_rows_potsize,0)=0),
      'years', p_potsize_years
    ),
    'space_from_heat', jsonb_build_object('week', true),
    'space_budget', jsonb_build_object('week_famiglia', true, 'week_categoria', true),
    'assortment_calendar', jsonb_build_object('week_famiglia', true, 'week_categoria', true)
  );

  return v_result;

exception when others then
  return jsonb_build_object(
    'ok', false,
    'pipeline', 'after_import',
    'ts', v_now,
    'error', sqlerrm
  );
end;
$$;

--
-- Name: core_planner__refresh_after_import_full(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_after_import_full() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_now timestamptz := now();
begin
  begin
    execute 'set local statement_timeout = 0';
  exception when others then null;
  end;

  -- qui chiami la tua orchestratrice che oggi va in timeout via API,
  -- ma in DB con pg_cron tipicamente no.
  return public.core_planner__refresh_after_import();

exception when others then
  return jsonb_build_object('ok', false, 'pipeline','after_import_full', 'ts', v_now, 'error', sqlerrm);
end;
$$;

--
-- Name: core_planner__refresh_after_import_full(integer, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_after_import_full(p_buffer_days integer DEFAULT 14, p_force_potsize boolean DEFAULT false, p_potsize_years integer DEFAULT 5) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_now timestamptz := now();
begin
  begin
    execute 'set local statement_timeout = 0';
  exception when others then
    null;
  end;

  return public.core_planner__refresh_after_import(
    p_buffer_days := p_buffer_days,
    p_force_potsize := p_force_potsize,
    p_potsize_years := p_potsize_years
  );

exception when others then
  return jsonb_build_object('ok', false, 'pipeline','after_import_full', 'ts', v_now, 'error', sqlerrm);
end;
$$;

--
-- Name: core_planner__refresh_after_import_step(integer, integer, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_after_import_step(p_buffer_days integer DEFAULT 14, p_weeks_per_run integer DEFAULT 3, p_force_potsize boolean DEFAULT false, p_potsize_years integer DEFAULT 5) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_now timestamptz := now();

  v_dense_max date;
  v_raw_max date;
  v_to date;

  v_last date;
  v_from date;

  v_rows_potsize bigint;
  v_heat jsonb;

begin
  begin
    execute 'set local statement_timeout = 0';
  exception when others then null;
  end;

  -- anchor
  select max(data)::date into v_dense_max from public.greenhouse_sales_family_daily_dense;
  select max(data_movimento)::date into v_raw_max from public.greenhouse_sales_raw;
  v_to := least(coalesce(v_dense_max, v_raw_max), current_date);

  if v_to is null then
    return jsonb_build_object('ok', false, 'error', 'no data: dense/raw empty');
  end if;

  -- ensure refresh_state
  insert into public.t_core_planner__refresh_state (pipeline, last_day)
  values ('planner_weekly', (v_to - 30))
  on conflict (pipeline) do nothing;

  select last_day into v_last
  from public.t_core_planner__refresh_state
  where pipeline='planner_weekly';

  v_last := least(v_last, v_to);
  v_from := greatest((v_last - p_buffer_days), date '2009-01-01');

  -- 1) fact_weekly
  perform public.core_planner__refresh_fact_weekly(v_from, v_to);

  -- 2) heat step (NO TIMEOUT)
  v_heat := public.core_planner__refresh_heat_week_step(p_weeks_per_run);

  -- 3) potsize (solo se vuota o forzata)
  select count(*) into v_rows_potsize from public.t_core_planner__potsize_profile;
  if p_force_potsize or coalesce(v_rows_potsize,0)=0 then
    perform public.core_planner__refresh_potsize_profile(p_potsize_years);
  end if;

  -- 4) derivati SOLO quando heat è done
  if coalesce(v_heat->>'status','') = 'done' then
    perform public.core_planner__refresh_space_from_heat('week');
    perform public.core_planner__refresh_space_budget('week','famiglia');
    perform public.core_planner__refresh_space_budget('week','categoria');
    perform public.core_planner__refresh_assortment_calendar('week','famiglia');
    perform public.core_planner__refresh_assortment_calendar('week','categoria');
  end if;

  return jsonb_build_object(
    'ok', true,
    'ts', v_now,
    'anchor', jsonb_build_object('dense_max', v_dense_max, 'raw_max', v_raw_max, 'to', v_to),
    'fact_weekly', jsonb_build_object('from', v_from, 'to', v_to),
    'heat', v_heat,
    'derived_ran', (coalesce(v_heat->>'status','')='done')
  );

exception when others then
  return jsonb_build_object('ok', false, 'ts', v_now, 'error', sqlerrm);
end;
$$;

--
-- Name: core_planner__refresh_after_import_step(integer, integer, boolean, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_after_import_step(p_buffer_days integer DEFAULT 14, p_weeks_per_run integer DEFAULT 3, p_force_potsize boolean DEFAULT false, p_potsize_years integer DEFAULT 5, p_run_derived_on_cycle boolean DEFAULT true) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_now timestamptz := now();

  v_dense_max date;
  v_raw_max date;
  v_to date;

  v_last date;
  v_from date;

  v_rows_potsize bigint;
  v_heat jsonb;

  v_next_week int;
  v_cycle_completed boolean := false;
  v_derived_ran boolean := false;
begin
  begin
    execute 'set local statement_timeout = 0';
  exception when others then null;
  end;

  /* -------------------------
     Anchor: preferisci DENSE, fallback RAW
     ------------------------- */
  select max(data)::date
  into v_dense_max
  from public.greenhouse_sales_family_daily_dense;

  select max(data_movimento)::date
  into v_raw_max
  from public.greenhouse_sales_raw;

  v_to := least(coalesce(v_dense_max, v_raw_max), current_date);

  if v_to is null then
    return jsonb_build_object('ok', false, 'error', 'no data: dense/raw empty');
  end if;

  /* -------------------------
     ensure refresh_state
     ------------------------- */
  insert into public.t_core_planner__refresh_state (pipeline, last_day)
  values ('planner_weekly', (v_to - 30))
  on conflict (pipeline) do nothing;

  select last_day
  into v_last
  from public.t_core_planner__refresh_state
  where pipeline='planner_weekly';

  v_last := least(v_last, v_to);
  v_from := greatest((v_last - p_buffer_days), date '2009-01-01');

  /* -------------------------
     1) fact_weekly incremental
     ------------------------- */
  perform public.core_planner__refresh_fact_weekly(v_from, v_to);

  /* -------------------------
     2) heat step (incrementale ciclico)
     ------------------------- */
  v_heat := public.core_planner__refresh_heat_week_step(p_weeks_per_run);

  v_next_week := nullif(coalesce((v_heat->>'next_week')::int, 0), 0);

  -- se il next_week torna a 1 => ho appena chiuso un giro
  if v_next_week = 1 then
    v_cycle_completed := true;
  end if;

  /* -------------------------
     3) potsize_profile (solo se vuota o forzata)
     ------------------------- */
  select count(*)
  into v_rows_potsize
  from public.t_core_planner__potsize_profile;

  if p_force_potsize or coalesce(v_rows_potsize,0) = 0 then
    perform public.core_planner__refresh_potsize_profile(p_potsize_years);
  end if;

  /* -------------------------
     4) derivati
     - se p_run_derived_on_cycle=true => solo a fine ciclo
     - se false => sempre
     ------------------------- */
  if (not p_run_derived_on_cycle) or v_cycle_completed then
    perform public.core_planner__refresh_space_from_heat('week');
    perform public.core_planner__refresh_space_budget('week','famiglia');
    perform public.core_planner__refresh_space_budget('week','categoria');
    perform public.core_planner__refresh_assortment_calendar('week','famiglia');
    perform public.core_planner__refresh_assortment_calendar('week','categoria');

    v_derived_ran := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'ts', v_now,
    'anchor', jsonb_build_object('dense_max', v_dense_max, 'raw_max', v_raw_max, 'to', v_to),
    'fact_weekly', jsonb_build_object('from', v_from, 'to', v_to, 'buffer_days', p_buffer_days),
    'heat', v_heat,
    'cycle_completed', v_cycle_completed,
    'derived_ran', v_derived_ran,
    'potsize_ran', (p_force_potsize or coalesce(v_rows_potsize,0)=0)
  );

exception when others then
  return jsonb_build_object('ok', false, 'ts', v_now, 'error', sqlerrm);
end;
$$;

--
-- Name: core_planner__refresh_assortment_calendar(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_assortment_calendar(p_mode text, p_level text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_mode  text := coalesce(nullif(p_mode,''),'week');
  v_level text := coalesce(nullif(p_level,''),'famiglia');
begin
  if v_mode not in ('week','roll4') then
    raise exception 'p_mode deve essere week o roll4';
  end if;

  if v_level not in ('famiglia','categoria') then
    raise exception 'p_level deve essere famiglia o categoria';
  end if;

  -- pulizia subset
  delete from public.t_core_planner__assortment_calendar
  where mode = v_mode and level = v_level;

  with sb as (
    select
      mode,
      level,
      node_id,
      week_52,
      coalesce(space_m2_raw,0)::numeric as space_m2_raw,
      coalesce(space_share,0)::numeric  as space_share
    from public.t_core_planner__space_budget
    where mode = v_mode
      and level = v_level
  ),

  -- percentili per riga (node_id) su 52 settimane
  pct as (
    select
      node_id,
      percentile_cont(0.10) within group (order by space_share) as p10,
      percentile_cont(0.40) within group (order by space_share) as p40,
      percentile_cont(0.75) within group (order by space_share) as p75
    from sb
    group by node_id
  ),

  -- stock_target (utile nel tooltip)
  st as (
    select
      hc.mode,
      hc.level,
      hc.node_id,
      hc.week_52,
      hc.stock_target
    from public.t_core_planner__heat_cells hc
    where hc.mode = v_mode
      and hc.level = v_level
  ),

  final as (
    select
      sb.mode,
      sb.level,
      sb.node_id,
      sb.week_52,
      sb.space_m2_raw,
      sb.space_share,
      st.stock_target,

      case
        when sb.space_share <  p.p10 then 'OFF'
        when sb.space_share <  p.p40 then 'LOW'
        when sb.space_share <= p.p75 then 'MED'
        else 'HIGH'
      end as state
    from sb
    join pct p
      on p.node_id = sb.node_id
    left join st
      on st.mode=sb.mode and st.level=sb.level and st.node_id=sb.node_id and st.week_52=sb.week_52
  )

  insert into public.t_core_planner__assortment_calendar (
    mode, level, node_id, week_52,
    state,
    space_m2_raw, space_share,
    stock_target,
    updated_at
  )
  select
    mode, level, node_id, week_52,
    state,
    space_m2_raw, space_share,
    stock_target,
    now()
  from final;

end;
$$;

--
-- Name: core_planner__refresh_fact_weekly(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_fact_weekly(p_from date, p_to date) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  v_from date;
  v_to date;
  v_has_weeks boolean;
begin
  if p_from is null or p_to is null then
    raise exception 'p_from e p_to sono obbligatori';
  end if;

  if p_to < p_from then
    raise exception 'p_to (%), deve essere >= p_from (%)', p_to, p_from;
  end if;

  v_from := p_from;
  v_to := p_to;

  -- ✅ early exit: se nel range non cade nessuna settimana (improbabile ma corretto)
  select exists (
    select 1
    from public.dim_iso_day d
    where d.day between v_from and v_to
    limit 1
  ) into v_has_weeks;

  if not v_has_weeks then
    return;
  end if;

  -- ✅ cancella solo le settimane impattate
  delete from public.t_core_planner__fact_weekly fw
  using (
    select distinct d.week_start
    from public.dim_iso_day d
    where d.day between v_from and v_to
  ) w
  where fw.week_start = w.week_start;

  -- ✅ ricalcola e inserisci solo le settimane impattate
  with weeks as (
    select distinct d.week_start
    from public.dim_iso_day d
    where d.day between v_from and v_to
  ),
  src as (
    select
      d.iso_year,
      d.week_52,
      d.week_start,

      coalesce(nullif(trim(s.fascia_corretta), ''), 'n/d') as fascia,
      coalesce(nullif(trim(s.categoria_corretta), ''), 'n/d') as categoria,
      coalesce(nullif(trim(s.famiglia), ''), 'n/d') as famiglia,
      coalesce(nullif(trim(s.fascia_prezzo_iva_inc), ''), 'n/d') as fascia_prezzo,

      sum(coalesce(s.qty_venduta, 0))::numeric as qty,
      sum(coalesce(s.imponibile_netto_tot, 0))::numeric as rev,

      count(*)::int as days_present,
      sum(case when coalesce(s.qty_venduta,0) > 0 then 1 else 0 end)::int as days_active,
      sum(case when coalesce(s.qty_venduta,0) = 0 then 1 else 0 end)::int as days_zero
    from public.greenhouse_sales_family_daily_dense s
    join public.dim_iso_day d
      on d.day = s.data
    where d.week_start in (select week_start from weeks)
      and s.data between v_from and (v_to + 6)  -- piccolo cuscinetto per includere tutta la settimana
    group by
      d.iso_year, d.week_52, d.week_start,
      coalesce(nullif(trim(s.fascia_corretta), ''), 'n/d'),
      coalesce(nullif(trim(s.categoria_corretta), ''), 'n/d'),
      coalesce(nullif(trim(s.famiglia), ''), 'n/d'),
      coalesce(nullif(trim(s.fascia_prezzo_iva_inc), ''), 'n/d')
  )
  insert into public.t_core_planner__fact_weekly (
    iso_year, week_52, week_start,
    fascia, categoria, famiglia, fascia_prezzo,
    qty, rev, days_present, days_active, days_zero,
    updated_at
  )
  select
    iso_year, week_52, week_start,
    fascia, categoria, famiglia, fascia_prezzo,
    qty, rev, days_present, days_active, days_zero,
    now()
  from src
  on conflict (iso_year, week_52, week_start, fascia, categoria, famiglia, fascia_prezzo)
  do update set
    qty = excluded.qty,
    rev = excluded.rev,
    days_present = excluded.days_present,
    days_active = excluded.days_active,
    days_zero = excluded.days_zero,
    updated_at = now();

  update public.t_core_planner__refresh_state
  set last_day = greatest(last_day, v_to)
  where pipeline = 'planner_weekly';
end $$;

--
-- Name: core_planner__refresh_heat_all(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_heat_all() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  perform public.core_planner__refresh_heat_week();
  perform public.core_planner__refresh_heat_roll4();
end;
$$;

--
-- Name: core_planner__refresh_heat_roll4(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_heat_roll4() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_w int;
begin
  -- opzionale: prova a togliere timeout (se policy permette)
  begin
    execute 'set local statement_timeout = 0';
  exception when others then
    -- ignora se non permesso
    null;
  end;

  -- 1) pulizia (solo mode='roll4')
  delete from public.t_core_planner__heat_cells
  where mode = 'roll4';

  -- 2) batch per week_52 (1..52) per evitare upstream timeout
  for v_w in 1..52 loop

    with
    -- "dimensione settimane" (una riga per week_start)
    weeks_dim as (
      select distinct
        d.week_start,
        d.iso_year,
        d.week_52
      from public.dim_iso_day d
      where d.week_start is not null
    ),

    -- anchor = tutte le settimane con week_52 = v_w
    anchors as (
      select
        w.iso_year as anchor_iso_year,
        w.week_52  as anchor_week_52,
        w.week_start as anchor_week_start
      from weeks_dim w
      where w.week_52 = v_w
    ),

    -- finestra roll4 = week_start, +7, +14, +21 (4 settimane)
    anchor_weeks as (
      select
        a.anchor_iso_year,
        a.anchor_week_52,
        a.anchor_week_start,
        w2.week_start as win_week_start
      from anchors a
      join weeks_dim w2
        on w2.week_start in (
          a.anchor_week_start,
          a.anchor_week_start + interval '7 days',
          a.anchor_week_start + interval '14 days',
          a.anchor_week_start + interval '21 days'
        )
    ),

    -- roll4 aggregato per anno anchor / week_52 anchor / chiavi merce
    roll4_yearly as (
      select
        aw.anchor_iso_year as iso_year,
        aw.anchor_week_52  as week_52,

        fw.fascia,
        fw.categoria,
        fw.famiglia,
        fw.fascia_prezzo,

        sum(fw.qty)::numeric as qty,
        sum(fw.rev)::numeric as rev,
        sum(fw.days_active)::numeric as days_active,
        sum(fw.days_zero)::numeric as days_zero
      from anchor_weeks aw
      join public.t_core_planner__fact_weekly fw
        on fw.week_start = aw.win_week_start
      group by
        aw.anchor_iso_year, aw.anchor_week_52,
        fw.fascia, fw.categoria, fw.famiglia, fw.fascia_prezzo
    ),

    -- base stats: fascia_prezzo (anni attivi)
    fp_stats as (
      select
        'roll4'::text as mode,
        'fascia_prezzo'::text as level,

        y.fascia,
        y.categoria,
        y.famiglia,
        y.fascia_prezzo,
        y.week_52,

        count(distinct y.iso_year)
          filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0))::int as active_years,

        coalesce(avg(y.qty) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_qty,
        coalesce(avg(y.rev) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_rev,

        coalesce(avg(y.days_active) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_days_active,
        coalesce(avg(y.days_zero)   filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_days_zero,

        case
          when count(distinct y.iso_year) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)) >= 2
            then coalesce(stddev_samp(y.qty) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)
          else 0
        end::numeric as sigma_qty,

        coalesce(min(y.qty) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as min_qty,
        coalesce(max(y.qty) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as max_qty,
        coalesce(min(y.rev) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as min_rev,
        coalesce(max(y.rev) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as max_rev

      from roll4_yearly y
      group by y.fascia, y.categoria, y.famiglia, y.fascia_prezzo, y.week_52
    ),

    fp_enriched as (
      select
        s.*,
        ('fascia_prezzo::' || s.fascia || '::' || s.categoria || '::' || s.famiglia || '::' || s.fascia_prezzo) as node_id,
        ('famiglia::' || s.fascia || '::' || s.categoria || '::' || s.famiglia) as parent_id,
        s.fascia_prezzo as label
      from fp_stats s
    ),

    fam_stats as (
      select
        'roll4'::text as mode,
        'famiglia'::text as level,
        fp.fascia,
        fp.categoria,
        fp.famiglia,
        null::text as fascia_prezzo,
        fp.week_52,

        max(fp.active_years)::int as active_years,

        sum(fp.avg_qty)::numeric as avg_qty,
        sum(fp.avg_rev)::numeric as avg_rev,
        sum(fp.avg_days_active)::numeric as avg_days_active,
        sum(fp.avg_days_zero)::numeric as avg_days_zero,

        sqrt(sum(power(coalesce(fp.sigma_qty,0), 2)))::numeric as sigma_qty,

        min(fp.min_qty)::numeric as min_qty,
        max(fp.max_qty)::numeric as max_qty,
        min(fp.min_rev)::numeric as min_rev,
        max(fp.max_rev)::numeric as max_rev

      from fp_enriched fp
      group by fp.fascia, fp.categoria, fp.famiglia, fp.week_52
    ),

    fam_enriched as (
      select
        s.*,
        ('famiglia::' || s.fascia || '::' || s.categoria || '::' || s.famiglia) as node_id,
        ('categoria::' || s.fascia || '::' || s.categoria) as parent_id,
        s.famiglia as label
      from fam_stats s
    ),

    cat_stats as (
      select
        'roll4'::text as mode,
        'categoria'::text as level,
        f.fascia,
        f.categoria,
        null::text as famiglia,
        null::text as fascia_prezzo,
        f.week_52,

        max(f.active_years)::int as active_years,

        sum(f.avg_qty)::numeric as avg_qty,
        sum(f.avg_rev)::numeric as avg_rev,
        sum(f.avg_days_active)::numeric as avg_days_active,
        sum(f.avg_days_zero)::numeric as avg_days_zero,

        sqrt(sum(power(coalesce(f.sigma_qty,0), 2)))::numeric as sigma_qty,

        min(f.min_qty)::numeric as min_qty,
        max(f.max_qty)::numeric as max_qty,
        min(f.min_rev)::numeric as min_rev,
        max(f.max_rev)::numeric as max_rev

      from fam_enriched f
      group by f.fascia, f.categoria, f.week_52
    ),

    cat_enriched as (
      select
        s.*,
        ('categoria::' || s.fascia || '::' || s.categoria) as node_id,
        ('fascia::' || s.fascia) as parent_id,
        s.categoria as label
      from cat_stats s
    ),

    fascia_stats as (
      select
        'roll4'::text as mode,
        'fascia'::text as level,
        c.fascia,
        null::text as categoria,
        null::text as famiglia,
        null::text as fascia_prezzo,
        c.week_52,

        max(c.active_years)::int as active_years,

        sum(c.avg_qty)::numeric as avg_qty,
        sum(c.avg_rev)::numeric as avg_rev,
        sum(c.avg_days_active)::numeric as avg_days_active,
        sum(c.avg_days_zero)::numeric as avg_days_zero,

        sqrt(sum(power(coalesce(c.sigma_qty,0), 2)))::numeric as sigma_qty,

        min(c.min_qty)::numeric as min_qty,
        max(c.max_qty)::numeric as max_qty,
        min(c.min_rev)::numeric as min_rev,
        max(c.max_rev)::numeric as max_rev

      from cat_enriched c
      group by c.fascia, c.week_52
    ),

    fascia_enriched as (
      select
        s.*,
        ('fascia::' || s.fascia) as node_id,
        null::text as parent_id,
        s.fascia as label
      from fascia_stats s
    ),

    unioned as (
      select * from fascia_enriched
      union all
      select * from cat_enriched
      union all
      select * from fam_enriched
      union all
      select * from fp_enriched
    ),

    with_share as (
      select
        u.*,
        case
          when (
            case u.level
              when 'fascia'        then sum(u.avg_rev) over (partition by u.week_52, u.level)
              when 'categoria'     then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia)
              when 'famiglia'      then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria)
              when 'fascia_prezzo' then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria, u.famiglia)
            end
          ) = 0 then 0
          else
            u.avg_rev /
            (
              case u.level
                when 'fascia'        then sum(u.avg_rev) over (partition by u.week_52, u.level)
                when 'categoria'     then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia)
                when 'famiglia'      then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria)
                when 'fascia_prezzo' then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria, u.famiglia)
              end
            )
        end::numeric as share_rev
      from unioned u
    ),

    with_color as (
      select
        s.*,
        percent_rank() over (partition by s.node_id order by s.avg_qty) as color_score
      from with_share s
    )

    insert into public.t_core_planner__heat_cells (
      mode, level,
      fascia, categoria, famiglia, fascia_prezzo,
      node_id, parent_id, label,
      week_52,
      avg_qty, avg_rev, share_rev,
      sigma_qty, avg_days_active, avg_days_zero,
      min_qty, max_qty, min_rev, max_rev,
      color_score,
      updated_at
    )
    select
      mode, level,
      fascia, categoria, famiglia, fascia_prezzo,
      node_id, parent_id, label,
      week_52,
      coalesce(avg_qty,0), coalesce(avg_rev,0), coalesce(share_rev,0),
      coalesce(sigma_qty,0), coalesce(avg_days_active,0), coalesce(avg_days_zero,0),
      coalesce(min_qty,0), coalesce(max_qty,0), coalesce(min_rev,0), coalesce(max_rev,0),
      coalesce(color_score,0),
      now()
    from with_color;

  end loop;

end;
$$;

--
-- Name: core_planner__refresh_heat_roll4_week(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_heat_roll4_week(p_week_52 integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_w int := p_week_52;
begin
  if v_w < 1 or v_w > 52 then
    raise exception 'p_week_52 deve essere 1..52';
  end if;

  -- per sicurezza: pulisci solo la week target
  delete from public.t_core_planner__heat_cells
  where mode='roll4' and week_52=v_w;

  -- ==== QUI incolli ESATTAMENTE il corpo del tuo loop per v_w,
  --      sostituendo "for v_w in 1..52 loop" con "v_w := p_week_52".
  --      Io ti metto solo lo scheletro: tu copi il tuo blocco "with ... insert"
  --      già funzionante, cambiando solo il filtro w.week_52 = v_w e usando v_w.

  with
  weeks_dim as (
    select distinct d.week_start, d.iso_year, d.week_52
    from public.dim_iso_day d
    where d.week_start is not null
  ),
  anchors as (
    select w.iso_year as anchor_iso_year, w.week_52 as anchor_week_52, w.week_start as anchor_week_start
    from weeks_dim w
    where w.week_52 = v_w
  ),
  anchor_weeks as (
    select a.anchor_iso_year, a.anchor_week_52, a.anchor_week_start, w2.week_start as win_week_start
    from anchors a
    join weeks_dim w2
      on w2.week_start in (
        a.anchor_week_start,
        a.anchor_week_start + interval '7 days',
        a.anchor_week_start + interval '14 days',
        a.anchor_week_start + interval '21 days'
      )
  ),
  roll4_yearly as (
    select
      aw.anchor_iso_year as iso_year,
      aw.anchor_week_52  as week_52,
      fw.fascia, fw.categoria, fw.famiglia, fw.fascia_prezzo,
      sum(fw.qty)::numeric as qty,
      sum(fw.rev)::numeric as rev,
      sum(fw.days_active)::numeric as days_active,
      sum(fw.days_zero)::numeric as days_zero
    from anchor_weeks aw
    join public.t_core_planner__fact_weekly fw
      on fw.week_start = aw.win_week_start
    group by aw.anchor_iso_year, aw.anchor_week_52, fw.fascia, fw.categoria, fw.famiglia, fw.fascia_prezzo
  ),
  fp_stats as (
    -- identico al tuo fp_stats...
    select
      'roll4'::text as mode,
      'fascia_prezzo'::text as level,
      y.fascia, y.categoria, y.famiglia, y.fascia_prezzo,
      y.week_52,
      count(distinct y.iso_year)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0))::int as active_years,
      coalesce(avg(y.qty) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_qty,
      coalesce(avg(y.rev) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_rev,
      coalesce(avg(y.days_active) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_days_active,
      coalesce(avg(y.days_zero)   filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_days_zero,
      case
        when count(distinct y.iso_year) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)) >= 2
          then coalesce(stddev_samp(y.qty) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)
        else 0
      end::numeric as sigma_qty,
      coalesce(min(y.qty) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as min_qty,
      coalesce(max(y.qty) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as max_qty,
      coalesce(min(y.rev) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as min_rev,
      coalesce(max(y.rev) filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as max_rev
    from roll4_yearly y
    group by y.fascia, y.categoria, y.famiglia, y.fascia_prezzo, y.week_52
  ),
  fp_enriched as (
    select s.*,
      ('fascia_prezzo::' || s.fascia || '::' || s.categoria || '::' || s.famiglia || '::' || s.fascia_prezzo) as node_id,
      ('famiglia::' || s.fascia || '::' || s.categoria || '::' || s.famiglia) as parent_id,
      s.fascia_prezzo as label
    from fp_stats s
  ),
  fam_stats as (
    select
      'roll4'::text as mode,
      'famiglia'::text as level,
      fp.fascia, fp.categoria, fp.famiglia,
      null::text as fascia_prezzo,
      fp.week_52,
      max(fp.active_years)::int as active_years,
      sum(fp.avg_qty)::numeric as avg_qty,
      sum(fp.avg_rev)::numeric as avg_rev,
      sum(fp.avg_days_active)::numeric as avg_days_active,
      sum(fp.avg_days_zero)::numeric as avg_days_zero,
      sqrt(sum(power(coalesce(fp.sigma_qty,0), 2)))::numeric as sigma_qty,
      min(fp.min_qty)::numeric as min_qty,
      max(fp.max_qty)::numeric as max_qty,
      min(fp.min_rev)::numeric as min_rev,
      max(fp.max_rev)::numeric as max_rev
    from fp_enriched fp
    group by fp.fascia, fp.categoria, fp.famiglia, fp.week_52
  ),
  fam_enriched as (
    select s.*,
      ('famiglia::' || s.fascia || '::' || s.categoria || '::' || s.famiglia) as node_id,
      ('categoria::' || s.fascia || '::' || s.categoria) as parent_id,
      s.famiglia as label
    from fam_stats s
  ),
  cat_stats as (
    select
      'roll4'::text as mode,
      'categoria'::text as level,
      f.fascia, f.categoria,
      null::text as famiglia,
      null::text as fascia_prezzo,
      f.week_52,
      max(f.active_years)::int as active_years,
      sum(f.avg_qty)::numeric as avg_qty,
      sum(f.avg_rev)::numeric as avg_rev,
      sum(f.avg_days_active)::numeric as avg_days_active,
      sum(f.avg_days_zero)::numeric as avg_days_zero,
      sqrt(sum(power(coalesce(f.sigma_qty,0), 2)))::numeric as sigma_qty,
      min(f.min_qty)::numeric as min_qty,
      max(f.max_qty)::numeric as max_qty,
      min(f.min_rev)::numeric as min_rev,
      max(f.max_rev)::numeric as max_rev
    from fam_enriched f
    group by f.fascia, f.categoria, f.week_52
  ),
  cat_enriched as (
    select s.*,
      ('categoria::' || s.fascia || '::' || s.categoria) as node_id,
      ('fascia::' || s.fascia) as parent_id,
      s.categoria as label
    from cat_stats s
  ),
  fascia_stats as (
    select
      'roll4'::text as mode,
      'fascia'::text as level,
      c.fascia,
      null::text as categoria,
      null::text as famiglia,
      null::text as fascia_prezzo,
      c.week_52,
      max(c.active_years)::int as active_years,
      sum(c.avg_qty)::numeric as avg_qty,
      sum(c.avg_rev)::numeric as avg_rev,
      sum(c.avg_days_active)::numeric as avg_days_active,
      sum(c.avg_days_zero)::numeric as avg_days_zero,
      sqrt(sum(power(coalesce(c.sigma_qty,0), 2)))::numeric as sigma_qty,
      min(c.min_qty)::numeric as min_qty,
      max(c.max_qty)::numeric as max_qty,
      min(c.min_rev)::numeric as min_rev,
      max(c.max_rev)::numeric as max_rev
    from cat_enriched c
    group by c.fascia, c.week_52
  ),
  fascia_enriched as (
    select s.*,
      ('fascia::' || s.fascia) as node_id,
      null::text as parent_id,
      s.fascia as label
    from fascia_stats s
  ),
  unioned as (
    select * from fascia_enriched
    union all select * from cat_enriched
    union all select * from fam_enriched
    union all select * from fp_enriched
  ),
  with_share as (
    select
      u.*,
      case
        when (
          case u.level
            when 'fascia'        then sum(u.avg_rev) over (partition by u.week_52, u.level)
            when 'categoria'     then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia)
            when 'famiglia'      then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria)
            when 'fascia_prezzo' then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria, u.famiglia)
          end
        ) = 0 then 0
        else
          u.avg_rev /
          (
            case u.level
              when 'fascia'        then sum(u.avg_rev) over (partition by u.week_52, u.level)
              when 'categoria'     then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia)
              when 'famiglia'      then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria)
              when 'fascia_prezzo' then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria, u.famiglia)
            end
          )
      end::numeric as share_rev
    from unioned u
  ),
  with_color as (
    select
      s.*,
      percent_rank() over (partition by s.node_id order by s.avg_qty) as color_score
    from with_share s
  )
  insert into public.t_core_planner__heat_cells (
    mode, level,
    fascia, categoria, famiglia, fascia_prezzo,
    node_id, parent_id, label,
    week_52,
    avg_qty, avg_rev, share_rev,
    sigma_qty, avg_days_active, avg_days_zero,
    min_qty, max_qty, min_rev, max_rev,
    color_score,
    updated_at
  )
  select
    mode, level,
    fascia, categoria, famiglia, fascia_prezzo,
    node_id, parent_id, label,
    week_52,
    coalesce(avg_qty,0), coalesce(avg_rev,0), coalesce(share_rev,0),
    coalesce(sigma_qty,0), coalesce(avg_days_active,0), coalesce(avg_days_zero,0),
    coalesce(min_qty,0), coalesce(max_qty,0), coalesce(min_rev,0), coalesce(max_rev,0),
    coalesce(color_score,0),
    now()
  from with_color;
end;
$$;

--
-- Name: core_planner__refresh_heat_week(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_heat_week() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
  -- ✅ NO TIMEOUT (solo per questa funzione)
  begin
    execute 'set local statement_timeout = 0';
  exception when others then
    null;
  end;

  -- 1) pulizia (solo mode='week')
  delete from public.t_core_planner__heat_cells
  where mode = 'week';

  with base as (
    select
      fw.iso_year,
      fw.week_52,
      fw.fascia,
      fw.categoria,
      fw.famiglia,
      fw.fascia_prezzo,
      fw.qty,
      fw.rev,
      fw.days_active,
      fw.days_zero
    from public.t_core_planner__fact_weekly fw
  ),

  fp_yearly as (
    select
      iso_year,
      week_52,
      fascia, categoria, famiglia, fascia_prezzo,
      sum(qty)::numeric as qty,
      sum(rev)::numeric as rev,
      sum(days_active)::numeric as days_active,
      sum(days_zero)::numeric as days_zero
    from base
    group by iso_year, week_52, fascia, categoria, famiglia, fascia_prezzo
  ),

  fp_stats as (
    select
      'week'::text as mode,
      'fascia_prezzo'::text as level,

      y.fascia,
      y.categoria,
      y.famiglia,
      y.fascia_prezzo,

      y.week_52,

      count(distinct y.iso_year)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0))::int as active_years,

      coalesce(avg(y.qty)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_qty,
      coalesce(avg(y.rev)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_rev,

      coalesce(avg(y.days_active)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_days_active,
      coalesce(avg(y.days_zero)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_days_zero,

      case
        when count(distinct y.iso_year)
             filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)) >= 2
          then coalesce(stddev_samp(y.qty)
               filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)
        else 0
      end::numeric as sigma_qty,

      coalesce(min(y.qty)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as min_qty,
      coalesce(max(y.qty)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as max_qty,
      coalesce(min(y.rev)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as min_rev,
      coalesce(max(y.rev)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as max_rev

    from fp_yearly y
    group by y.fascia, y.categoria, y.famiglia, y.fascia_prezzo, y.week_52
  ),

  fp_enriched as (
    select
      s.*,
      ('fascia_prezzo::' || s.fascia || '::' || s.categoria || '::' || s.famiglia || '::' || s.fascia_prezzo) as node_id,
      ('famiglia::' || s.fascia || '::' || s.categoria || '::' || s.famiglia) as parent_id,
      s.fascia_prezzo as label
    from fp_stats s
  ),

  fam_stats as (
    select
      'week'::text as mode,
      'famiglia'::text as level,
      fp.fascia,
      fp.categoria,
      fp.famiglia,
      null::text as fascia_prezzo,
      fp.week_52,

      max(fp.active_years)::int as active_years,

      sum(fp.avg_qty)::numeric as avg_qty,
      sum(fp.avg_rev)::numeric as avg_rev,
      sum(fp.avg_days_active)::numeric as avg_days_active,
      sum(fp.avg_days_zero)::numeric as avg_days_zero,

      sqrt(sum(power(coalesce(fp.sigma_qty,0), 2)))::numeric as sigma_qty,

      min(fp.min_qty)::numeric as min_qty,
      max(fp.max_qty)::numeric as max_qty,
      min(fp.min_rev)::numeric as min_rev,
      max(fp.max_rev)::numeric as max_rev

    from fp_enriched fp
    group by fp.fascia, fp.categoria, fp.famiglia, fp.week_52
  ),

  fam_enriched as (
    select
      s.*,
      ('famiglia::' || s.fascia || '::' || s.categoria || '::' || s.famiglia) as node_id,
      ('categoria::' || s.fascia || '::' || s.categoria) as parent_id,
      s.famiglia as label
    from fam_stats s
  ),

  cat_stats as (
    select
      'week'::text as mode,
      'categoria'::text as level,
      f.fascia,
      f.categoria,
      null::text as famiglia,
      null::text as fascia_prezzo,
      f.week_52,

      max(f.active_years)::int as active_years,

      sum(f.avg_qty)::numeric as avg_qty,
      sum(f.avg_rev)::numeric as avg_rev,
      sum(f.avg_days_active)::numeric as avg_days_active,
      sum(f.avg_days_zero)::numeric as avg_days_zero,

      sqrt(sum(power(coalesce(f.sigma_qty,0), 2)))::numeric as sigma_qty,

      min(f.min_qty)::numeric as min_qty,
      max(f.max_qty)::numeric as max_qty,
      min(f.min_rev)::numeric as min_rev,
      max(f.max_rev)::numeric as max_rev

    from fam_enriched f
    group by f.fascia, f.categoria, f.week_52
  ),

  cat_enriched as (
    select
      s.*,
      ('categoria::' || s.fascia || '::' || s.categoria) as node_id,
      ('fascia::' || s.fascia) as parent_id,
      s.categoria as label
    from cat_stats s
  ),

  fascia_stats as (
    select
      'week'::text as mode,
      'fascia'::text as level,
      c.fascia,
      null::text as categoria,
      null::text as famiglia,
      null::text as fascia_prezzo,
      c.week_52,

      max(c.active_years)::int as active_years,

      sum(c.avg_qty)::numeric as avg_qty,
      sum(c.avg_rev)::numeric as avg_rev,
      sum(c.avg_days_active)::numeric as avg_days_active,
      sum(c.avg_days_zero)::numeric as avg_days_zero,

      sqrt(sum(power(coalesce(c.sigma_qty,0), 2)))::numeric as sigma_qty,

      min(c.min_qty)::numeric as min_qty,
      max(c.max_qty)::numeric as max_qty,
      min(c.min_rev)::numeric as min_rev,
      max(c.max_rev)::numeric as max_rev

    from cat_enriched c
    group by c.fascia, c.week_52
  ),

  fascia_enriched as (
    select
      s.*,
      ('fascia::' || s.fascia) as node_id,
      null::text as parent_id,
      s.fascia as label
    from fascia_stats s
  ),

  unioned as (
    select * from fascia_enriched
    union all
    select * from cat_enriched
    union all
    select * from fam_enriched
    union all
    select * from fp_enriched
  ),

  with_share as (
    select
      u.*,
      case
        when (
          case u.level
            when 'fascia'        then sum(u.avg_rev) over (partition by u.week_52, u.level)
            when 'categoria'     then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia)
            when 'famiglia'      then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria)
            when 'fascia_prezzo' then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria, u.famiglia)
          end
        ) = 0 then 0
        else
          u.avg_rev /
          (
            case u.level
              when 'fascia'        then sum(u.avg_rev) over (partition by u.week_52, u.level)
              when 'categoria'     then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia)
              when 'famiglia'      then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria)
              when 'fascia_prezzo' then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria, u.famiglia)
            end
          )
      end::numeric as share_rev
    from unioned u
  ),

  with_color as (
    select
      s.*,
      percent_rank() over (partition by s.node_id order by s.avg_qty) as color_score
    from with_share s
  )

  insert into public.t_core_planner__heat_cells (
    mode, level,
    fascia, categoria, famiglia, fascia_prezzo,
    node_id, parent_id, label,
    week_52,
    avg_qty, avg_rev, share_rev,
    sigma_qty, avg_days_active, avg_days_zero,
    min_qty, max_qty, min_rev, max_rev,
    color_score,
    updated_at
  )
  select
    mode, level,
    fascia, categoria, famiglia, fascia_prezzo,
    node_id, parent_id, label,
    week_52,
    coalesce(avg_qty,0), coalesce(avg_rev,0), coalesce(share_rev,0),
    coalesce(sigma_qty,0), coalesce(avg_days_active,0), coalesce(avg_days_zero,0),
    coalesce(min_qty,0), coalesce(max_qty,0), coalesce(min_rev,0), coalesce(max_rev,0),
    coalesce(color_score,0),
    now()
  from with_color;

end;
$$;

--
-- Name: core_planner__refresh_heat_week_step(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_heat_week_step(p_weeks_per_run integer DEFAULT 2) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_cur int;
  v_i int := 0;
begin
  -- evita timeout lato DB (non risolve upstream, ma aiuta)
  begin
    execute 'set local statement_timeout = 0';
  exception when others then null;
  end;

  -- init state (solo cursor, niente "init" wipe)
  insert into public.t_core_planner__orchestrator_state(pipeline, step, cursor_int)
  values ('heat_week','weeks',1)
  on conflict (pipeline) do nothing;

  select cursor_int
  into v_cur
  from public.t_core_planner__orchestrator_state
  where pipeline='heat_week';

  if v_cur is null or v_cur < 1 or v_cur > 52 then
    v_cur := 1;
  end if;

  -- process N weeks
  while v_i < greatest(1, p_weeks_per_run) loop
    perform public.core_planner__refresh_heat_week_week(v_cur);

    v_cur := v_cur + 1;
    if v_cur > 52 then
      v_cur := 1;  -- wrap
    end if;

    v_i := v_i + 1;
  end loop;

  update public.t_core_planner__orchestrator_state
  set step='weeks', cursor_int=v_cur, updated_at=now()
  where pipeline='heat_week';

  return jsonb_build_object(
    'ok', true,
    'status', 'running',
    'next_week', v_cur,
    'weeks_processed', v_i
  );

exception when others then
  return jsonb_build_object('ok', false, 'status','failed', 'error', sqlerrm);
end;
$$;

--
-- Name: core_planner__refresh_heat_week_week(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_heat_week_week(p_week_52 integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  v_w int := p_week_52;
begin
  if v_w < 1 or v_w > 52 then
    raise exception 'p_week_52 deve essere 1..52';
  end if;

  -- evita timeout lato DB (non risolve upstream, ma aiuta)
  begin
    execute 'set local statement_timeout = 0';
  exception when others then null;
  end;

  -- pulisci SOLO la week target
  delete from public.t_core_planner__heat_cells
  where mode='week' and week_52=v_w;

  with base as (
    select
      fw.iso_year,
      fw.week_52,
      fw.fascia,
      fw.categoria,
      fw.famiglia,
      fw.fascia_prezzo,
      fw.qty,
      fw.rev,
      fw.days_active,
      fw.days_zero
    from public.t_core_planner__fact_weekly fw
    where fw.week_52 = v_w
  ),

  fp_yearly as (
    select
      iso_year,
      week_52,
      fascia, categoria, famiglia, fascia_prezzo,
      sum(qty)::numeric as qty,
      sum(rev)::numeric as rev,
      sum(days_active)::numeric as days_active,
      sum(days_zero)::numeric as days_zero
    from base
    group by iso_year, week_52, fascia, categoria, famiglia, fascia_prezzo
  ),

  fp_stats as (
    select
      'week'::text as mode,
      'fascia_prezzo'::text as level,

      y.fascia,
      y.categoria,
      y.famiglia,
      y.fascia_prezzo,
      y.week_52,

      count(distinct y.iso_year)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0))::int as active_years,

      coalesce(avg(y.qty)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_qty,
      coalesce(avg(y.rev)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_rev,

      coalesce(avg(y.days_active)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_days_active,
      coalesce(avg(y.days_zero)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as avg_days_zero,

      case
        when count(distinct y.iso_year)
             filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)) >= 2
          then coalesce(stddev_samp(y.qty)
               filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)
        else 0
      end::numeric as sigma_qty,

      coalesce(min(y.qty)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as min_qty,
      coalesce(max(y.qty)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as max_qty,
      coalesce(min(y.rev)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as min_rev,
      coalesce(max(y.rev)
        filter (where (coalesce(y.qty,0) > 0 or coalesce(y.rev,0) > 0)), 0)::numeric as max_rev
    from fp_yearly y
    group by y.fascia, y.categoria, y.famiglia, y.fascia_prezzo, y.week_52
  ),

  fp_enriched as (
    select
      s.*,
      ('fascia_prezzo::' || s.fascia || '::' || s.categoria || '::' || s.famiglia || '::' || s.fascia_prezzo) as node_id,
      ('famiglia::' || s.fascia || '::' || s.categoria || '::' || s.famiglia) as parent_id,
      s.fascia_prezzo as label
    from fp_stats s
  ),

  fam_stats as (
    select
      'week'::text as mode,
      'famiglia'::text as level,
      fp.fascia,
      fp.categoria,
      fp.famiglia,
      null::text as fascia_prezzo,
      fp.week_52,

      max(fp.active_years)::int as active_years,

      sum(fp.avg_qty)::numeric as avg_qty,
      sum(fp.avg_rev)::numeric as avg_rev,
      sum(fp.avg_days_active)::numeric as avg_days_active,
      sum(fp.avg_days_zero)::numeric as avg_days_zero,

      sqrt(sum(power(coalesce(fp.sigma_qty,0), 2)))::numeric as sigma_qty,

      min(fp.min_qty)::numeric as min_qty,
      max(fp.max_qty)::numeric as max_qty,
      min(fp.min_rev)::numeric as min_rev,
      max(fp.max_rev)::numeric as max_rev
    from fp_enriched fp
    group by fp.fascia, fp.categoria, fp.famiglia, fp.week_52
  ),

  fam_enriched as (
    select
      s.*,
      ('famiglia::' || s.fascia || '::' || s.categoria || '::' || s.famiglia) as node_id,
      ('categoria::' || s.fascia || '::' || s.categoria) as parent_id,
      s.famiglia as label
    from fam_stats s
  ),

  cat_stats as (
    select
      'week'::text as mode,
      'categoria'::text as level,
      f.fascia,
      f.categoria,
      null::text as famiglia,
      null::text as fascia_prezzo,
      f.week_52,

      max(f.active_years)::int as active_years,

      sum(f.avg_qty)::numeric as avg_qty,
      sum(f.avg_rev)::numeric as avg_rev,
      sum(f.avg_days_active)::numeric as avg_days_active,
      sum(f.avg_days_zero)::numeric as avg_days_zero,

      sqrt(sum(power(coalesce(f.sigma_qty,0), 2)))::numeric as sigma_qty,

      min(f.min_qty)::numeric as min_qty,
      max(f.max_qty)::numeric as max_qty,
      min(f.min_rev)::numeric as min_rev,
      max(f.max_rev)::numeric as max_rev
    from fam_enriched f
    group by f.fascia, f.categoria, f.week_52
  ),

  cat_enriched as (
    select
      s.*,
      ('categoria::' || s.fascia || '::' || s.categoria) as node_id,
      ('fascia::' || s.fascia) as parent_id,
      s.categoria as label
    from cat_stats s
  ),

  fascia_stats as (
    select
      'week'::text as mode,
      'fascia'::text as level,
      c.fascia,
      null::text as categoria,
      null::text as famiglia,
      null::text as fascia_prezzo,
      c.week_52,

      max(c.active_years)::int as active_years,

      sum(c.avg_qty)::numeric as avg_qty,
      sum(c.avg_rev)::numeric as avg_rev,
      sum(c.avg_days_active)::numeric as avg_days_active,
      sum(c.avg_days_zero)::numeric as avg_days_zero,

      sqrt(sum(power(coalesce(c.sigma_qty,0), 2)))::numeric as sigma_qty,

      min(c.min_qty)::numeric as min_qty,
      max(c.max_qty)::numeric as max_qty,
      min(c.min_rev)::numeric as min_rev,
      max(c.max_rev)::numeric as max_rev
    from cat_enriched c
    group by c.fascia, c.week_52
  ),

  fascia_enriched as (
    select
      s.*,
      ('fascia::' || s.fascia) as node_id,
      null::text as parent_id,
      s.fascia as label
    from fascia_stats s
  ),

  unioned as (
    select * from fascia_enriched
    union all
    select * from cat_enriched
    union all
    select * from fam_enriched
    union all
    select * from fp_enriched
  ),

  with_share as (
    select
      u.*,
      case
        when (
          case u.level
            when 'fascia'        then sum(u.avg_rev) over (partition by u.week_52, u.level)
            when 'categoria'     then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia)
            when 'famiglia'      then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria)
            when 'fascia_prezzo' then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria, u.famiglia)
          end
        ) = 0 then 0
        else
          u.avg_rev /
          (
            case u.level
              when 'fascia'        then sum(u.avg_rev) over (partition by u.week_52, u.level)
              when 'categoria'     then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia)
              when 'famiglia'      then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria)
              when 'fascia_prezzo' then sum(u.avg_rev) over (partition by u.week_52, u.level, u.fascia, u.categoria, u.famiglia)
            end
          )
      end::numeric as share_rev
    from unioned u
  ),

  with_color as (
    select
      s.*,
      percent_rank() over (partition by s.node_id order by s.avg_qty) as color_score
    from with_share s
  )

  insert into public.t_core_planner__heat_cells (
    mode, level,
    fascia, categoria, famiglia, fascia_prezzo,
    node_id, parent_id, label,
    week_52,
    avg_qty, avg_rev, share_rev,
    sigma_qty, avg_days_active, avg_days_zero,
    min_qty, max_qty, min_rev, max_rev,
    color_score,
    updated_at
  )
  select
    mode, level,
    fascia, categoria, famiglia, fascia_prezzo,
    node_id, parent_id, label,
    week_52,
    coalesce(avg_qty,0), coalesce(avg_rev,0), coalesce(share_rev,0),
    coalesce(sigma_qty,0), coalesce(avg_days_active,0), coalesce(avg_days_zero,0),
    coalesce(min_qty,0), coalesce(max_qty,0), coalesce(min_rev,0), coalesce(max_rev,0),
    coalesce(color_score,0),
    now()
  from with_color;

end;
$$;

--
-- Name: core_planner__refresh_nightly(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_nightly() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_now timestamptz := now();
begin
  -- prova a togliere timeout locale (se permesso)
  begin
    execute 'set local statement_timeout = 0';
  exception when others then
    null;
  end;

  -- 1) heat roll4
  perform public.core_planner__refresh_heat_roll4();

  -- 2) space_from_heat(roll4)
  perform public.core_planner__refresh_space_from_heat('roll4');

  -- 3) space_budget roll4 (famiglia + categoria)
  perform public.core_planner__refresh_space_budget('roll4','famiglia');
  perform public.core_planner__refresh_space_budget('roll4','categoria');

  -- 4) assortment_calendar roll4 (famiglia + categoria)
  perform public.core_planner__refresh_assortment_calendar('roll4','famiglia');
  perform public.core_planner__refresh_assortment_calendar('roll4','categoria');

  return jsonb_build_object(
    'ok', true,
    'pipeline', 'nightly',
    'ts', v_now,
    'heat', jsonb_build_object('roll4', true),
    'space_from_heat', jsonb_build_object('roll4', true),
    'space_budget', jsonb_build_object('roll4_famiglia', true, 'roll4_categoria', true),
    'assortment_calendar', jsonb_build_object('roll4_famiglia', true, 'roll4_categoria', true)
  );

exception when others then
  return jsonb_build_object(
    'ok', false,
    'pipeline', 'nightly',
    'ts', v_now,
    'error', sqlerrm
  );
end;
$$;

--
-- Name: core_planner__refresh_nightly_full(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_nightly_full() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_w int;
  v_now timestamptz := now();
begin
  -- niente timeout lato DB (se permesso)
  begin
    execute 'set local statement_timeout = 0';
  exception when others then null;
  end;

  -- reset cursor
  insert into public.t_core_planner__orchestrator_state(pipeline, step, cursor_int)
  values ('nightly_roll4','roll4_weeks',1)
  on conflict (pipeline)
  do update set step='roll4_weeks', cursor_int=1, updated_at=now();

  -- rebuild roll4 week by week (anti-timeout)
  for v_w in 1..52 loop
    perform public.core_planner__refresh_heat_roll4_week(v_w);
  end loop;

  -- derivati roll4 (una volta)
  perform public.core_planner__refresh_space_from_heat('roll4');
  perform public.core_planner__refresh_space_budget('roll4','famiglia');
  perform public.core_planner__refresh_space_budget('roll4','categoria');
  perform public.core_planner__refresh_assortment_calendar('roll4','famiglia');
  perform public.core_planner__refresh_assortment_calendar('roll4','categoria');

  update public.t_core_planner__orchestrator_state
  set step='done', cursor_int=52, updated_at=now()
  where pipeline='nightly_roll4';

  return jsonb_build_object('ok', true, 'pipeline','nightly_full', 'ts', v_now);
exception when others then
  return jsonb_build_object('ok', false, 'pipeline','nightly_full', 'ts', v_now, 'error', sqlerrm);
end;
$$;

--
-- Name: core_planner__refresh_nightly_step(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_nightly_step(p_weeks_per_run integer DEFAULT 1) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_cur int;
  v_i int := 0;
begin
  insert into public.t_core_planner__orchestrator_state(pipeline, step, cursor_int)
  values ('nightly_roll4', 'roll4_weeks', 1)
  on conflict (pipeline) do nothing;

  select cursor_int into v_cur
  from public.t_core_planner__orchestrator_state
  where pipeline='nightly_roll4';

  if v_cur is null then v_cur := 1; end if;

  while v_i < greatest(1,p_weeks_per_run) loop
    if v_cur > 52 then
      -- finito: derivati roll4 una volta sola
      perform public.core_planner__refresh_space_from_heat('roll4');
      perform public.core_planner__refresh_space_budget('roll4','famiglia');
      perform public.core_planner__refresh_space_budget('roll4','categoria');
      perform public.core_planner__refresh_assortment_calendar('roll4','famiglia');
      perform public.core_planner__refresh_assortment_calendar('roll4','categoria');

      update public.t_core_planner__orchestrator_state
      set step='done', cursor_int=52, updated_at=now()
      where pipeline='nightly_roll4';

      return jsonb_build_object('ok', true, 'pipeline','nightly_step', 'status','done');
    end if;

    perform public.core_planner__refresh_heat_roll4_week(v_cur);

    v_cur := v_cur + 1;
    v_i := v_i + 1;
  end loop;

  update public.t_core_planner__orchestrator_state
  set step='roll4_weeks', cursor_int=v_cur, updated_at=now()
  where pipeline='nightly_roll4';

  return jsonb_build_object('ok', true, 'pipeline','nightly_step', 'status','running', 'next_week', v_cur);

exception when others then
  return jsonb_build_object('ok', false, 'pipeline','nightly_step', 'error', sqlerrm);
end;
$$;

--
-- Name: core_planner__refresh_potsize_profile(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_potsize_profile(p_years integer DEFAULT 5) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_cutoff date := (current_date - make_interval(years => greatest(1, p_years)));
begin
  truncate table public.t_core_planner__potsize_profile;

  /*
    STEP 1
    Estrazione vaso principale per riga:
    - JSON → mode (più frequente)
    - TEXT → mapping diretto
  */
  with base as (
    select
      s.famiglia,
      s.fascia_prezzo_iva_inc as fascia_prezzo,
      coalesce(s.qty_venduta,0)::numeric as qty,
      s.pot_sizes_json,
      s.pot_sizes_text
    from public.greenhouse_sales_family_daily_dense s
    where s.data >= v_cutoff
      and coalesce(s.qty_venduta,0) > 0
  ),

  pot_from_json as (
    select
      b.famiglia,
      b.fascia_prezzo,
      b.qty,
      public.core_planner__map_pot_size_group(j.value::text) as pot_group
    from base b
    cross join lateral jsonb_array_elements_text(b.pot_sizes_json) j
    where jsonb_array_length(b.pot_sizes_json) > 0
  ),

  json_mode as (
    select
      famiglia,
      fascia_prezzo,
      qty,
      pot_group,
      row_number() over (
        partition by famiglia, fascia_prezzo, qty
        order by count(*) desc
      ) as rn
    from pot_from_json
    group by famiglia, fascia_prezzo, qty, pot_group
  ),

  pot_json_main as (
    select
      famiglia,
      fascia_prezzo,
      qty,
      pot_group
    from json_mode
    where rn = 1
  ),

  pot_text_main as (
    select
      b.famiglia,
      b.fascia_prezzo,
      b.qty,
      public.core_planner__map_pot_size_group(b.pot_sizes_text) as pot_group
    from base b
    where jsonb_array_length(b.pot_sizes_json) = 0
      and b.pot_sizes_text is not null
  ),

  unified as (
    select * from pot_json_main
    union all
    select * from pot_text_main
  ),

  /*
    STEP 2
    Aggregazione per profilo
  */
  src as (
    select
      coalesce(nullif(trim(famiglia),''),'n/d') as famiglia,
      coalesce(nullif(trim(fascia_prezzo),''),'n/d') as fascia_prezzo,
      coalesce(pot_group,'DEFAULT') as pot_group,
      sum(qty)::numeric as qty
    from unified
    group by 1,2,3
  ),

  -- PROFILO famiglia + fascia_prezzo
  ranked_fp as (
    select
      'fascia_prezzo'::text as level,
      famiglia,
      fascia_prezzo,
      pot_group,
      qty,
      sum(qty) over (partition by famiglia, fascia_prezzo) as total_qty,
      row_number() over (
        partition by famiglia, fascia_prezzo
        order by qty desc, pot_group
      ) as rn
    from src
  ),

  best_fp as (
    select
      level,
      famiglia,
      fascia_prezzo,
      pot_group as pot_size_group_main,
      qty as sample_qty,
      total_qty,
      case when total_qty=0 then 0 else qty/total_qty end as share_qty
    from ranked_fp
    where rn = 1
  ),

  -- PROFILO famiglia (roll-up)
  ranked_fam as (
    select
      'famiglia'::text as level,
      famiglia,
      'ALL'::text as fascia_prezzo,
      pot_group,
      sum(qty)::numeric as qty,
      sum(sum(qty)) over (partition by famiglia) as total_qty,
      row_number() over (
        partition by famiglia
        order by sum(qty) desc, pot_group
      ) as rn
    from src
    group by famiglia, pot_group
  ),

  best_fam as (
    select
      level,
      famiglia,
      fascia_prezzo,
      pot_group as pot_size_group_main,
      qty as sample_qty,
      total_qty,
      case when total_qty=0 then 0 else qty/total_qty end as share_qty
    from ranked_fam
    where rn = 1
  ),

  unioned as (
    select * from best_fp
    union all
    select * from best_fam
  )

  insert into public.t_core_planner__potsize_profile (
    level,
    famiglia,
    fascia_prezzo,
    pot_size_group_main,
    units_per_m2_est,
    sample_qty,
    total_qty,
    share_qty,
    updated_at
  )
  select
    u.level,
    u.famiglia,
    u.fascia_prezzo,
    u.pot_size_group_main,
    coalesce(
      d.units_per_m2,
      (select units_per_m2 from public.t_core_planner__density where pot_size_group='DEFAULT' limit 1),
      20
    )::numeric as units_per_m2_est,
    u.sample_qty,
    u.total_qty,
    u.share_qty,
    now()
  from unioned u
  left join public.t_core_planner__density d
    on d.pot_size_group = u.pot_size_group_main;

end;
$$;

--
-- Name: core_planner__refresh_space_budget(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_space_budget(p_mode text, p_level text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_mode  text := coalesce(nullif(p_mode,''),'week');
  v_level text := coalesce(nullif(p_level,''),'famiglia');
begin
  if v_mode not in ('week','roll4') then
    raise exception 'p_mode deve essere week o roll4';
  end if;

  if v_level not in ('famiglia','categoria') then
    raise exception 'p_level deve essere famiglia o categoria';
  end if;

  -- pulizia subset
  delete from public.t_core_planner__space_budget
  where mode = v_mode and level = v_level;

  with base as (
    select
      hc.mode,
      hc.level,
      hc.node_id,
      hc.week_52,
      sum(coalesce(hc.space_m2,0))::numeric as space_m2_raw
    from public.t_core_planner__heat_cells hc
    where hc.mode = v_mode
      and hc.level = v_level
    group by 1,2,3,4
  ),
  totals as (
    select
      mode, level, week_52,
      sum(space_m2_raw)::numeric as total_space
    from base
    group by 1,2,3
  ),
  final as (
    select
      b.mode,
      b.level,
      b.node_id,
      b.week_52,
      b.space_m2_raw,
      case when t.total_space = 0 then 0 else (b.space_m2_raw / t.total_space) end::numeric as space_share
    from base b
    join totals t
      on t.mode=b.mode and t.level=b.level and t.week_52=b.week_52
  )
  insert into public.t_core_planner__space_budget (
    mode, level, node_id, week_52,
    space_m2_raw, space_share,
    updated_at
  )
  select
    mode, level, node_id, week_52,
    space_m2_raw, space_share,
    now()
  from final;

end;
$$;

--
-- Name: core_planner__refresh_space_from_heat(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_planner__refresh_space_from_heat(p_mode text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_mode text := coalesce(nullif(p_mode,''),'week');
begin
  if v_mode not in ('week','roll4') then
    raise exception 'p_mode deve essere week o roll4';
  end if;

  /* ===============================
     1) fascia_prezzo: calcolo diretto
     =============================== */
  with params_fp as (
    select *
    from public.t_core_planner__params_level
    where level='fascia_prezzo'
  ),
  fp_calc as (
    select
      hc.mode,
      hc.node_id,
      hc.week_52,

      coalesce(
        pp_fp.units_per_m2_est,
        pp_fam.units_per_m2_est,
        (select units_per_m2
         from public.t_core_planner__density
         where pot_size_group='DEFAULT'
         limit 1),
        20
      )::numeric as units_per_m2_est,

      (select buffer_pct from params_fp)::numeric as buffer_pct,
      (select cover_days from params_fp)::numeric as cover_days,
      (select service_level_z from params_fp)::numeric as z,
      (select max_days_on_floor from params_fp)::numeric as max_days_on_floor,

      coalesce(hc.avg_qty,0)::numeric as avg_qty,
      coalesce(hc.sigma_qty,0)::numeric as sigma_qty
    from public.t_core_planner__heat_cells hc

    left join public.t_core_planner__potsize_profile pp_fp
      on pp_fp.level='fascia_prezzo'
     and pp_fp.famiglia = hc.famiglia
     and pp_fp.fascia_prezzo = hc.fascia_prezzo

    left join public.t_core_planner__potsize_profile pp_fam
      on pp_fam.level='famiglia'
     and pp_fam.famiglia = hc.famiglia
     and pp_fam.fascia_prezzo = 'ALL'   -- ✅ allineato

    where hc.mode=v_mode
      and hc.level='fascia_prezzo'
  ),
  fp_final as (
    select
      mode,
      node_id,
      week_52,

      least(
        ((avg_qty/7.0)*cover_days + z*sigma_qty),
        ((avg_qty/7.0)*max_days_on_floor)
      )::numeric as stock_target,

      (
        least(
          ((avg_qty/7.0)*cover_days + z*sigma_qty),
          ((avg_qty/7.0)*max_days_on_floor)
        )
        / nullif(units_per_m2_est,0)
      ) * (1 + buffer_pct) as space_m2
    from fp_calc
  )
  update public.t_core_planner__heat_cells hc
  set
    stock_target = f.stock_target,
    space_m2 = f.space_m2,
    updated_at = now()
  from fp_final f
  where hc.mode=f.mode
    and hc.node_id=f.node_id
    and hc.week_52=f.week_52;

  /* ===============================
     2) roll-up gerarchico
     =============================== */

  -- famiglia = somma fascia_prezzo
  with fam as (
    select
      hc.mode,
      ('famiglia::' || hc.fascia || '::' || hc.categoria || '::' || hc.famiglia) as node_id,
      hc.week_52,
      sum(coalesce(hc.stock_target,0)) as stock_target,
      sum(coalesce(hc.space_m2,0)) as space_m2
    from public.t_core_planner__heat_cells hc
    where hc.mode=v_mode
      and hc.level='fascia_prezzo'
    group by 1,2,3
  )
  update public.t_core_planner__heat_cells h
  set stock_target=fam.stock_target,
      space_m2=fam.space_m2,
      updated_at=now()
  from fam
  where h.mode=v_mode
    and h.level='famiglia'
    and h.node_id=fam.node_id
    and h.week_52=fam.week_52;

  -- categoria = somma famiglia
  with cat as (
    select
      hc.mode,
      ('categoria::' || hc.fascia || '::' || hc.categoria) as node_id,
      hc.week_52,
      sum(coalesce(hc.stock_target,0)) as stock_target,
      sum(coalesce(hc.space_m2,0)) as space_m2
    from public.t_core_planner__heat_cells hc
    where hc.mode=v_mode
      and hc.level='famiglia'
    group by 1,2,3
  )
  update public.t_core_planner__heat_cells h
  set stock_target=cat.stock_target,
      space_m2=cat.space_m2,
      updated_at=now()
  from cat
  where h.mode=v_mode
    and h.level='categoria'
    and h.node_id=cat.node_id
    and h.week_52=cat.week_52;

  -- fascia = somma categoria
  with fas as (
    select
      hc.mode,
      ('fascia::' || hc.fascia) as node_id,
      hc.week_52,
      sum(coalesce(hc.stock_target,0)) as stock_target,
      sum(coalesce(hc.space_m2,0)) as space_m2
    from public.t_core_planner__heat_cells hc
    where hc.mode=v_mode
      and hc.level='categoria'
    group by 1,2,3
  )
  update public.t_core_planner__heat_cells h
  set stock_target=fas.stock_target,
      space_m2=fas.space_m2,
      updated_at=now()
  from fas
  where h.mode=v_mode
    and h.level='fascia'
    and h.node_id=fas.node_id
    and h.week_52=fas.week_52;

end;
$$;

--
-- Name: daily_etl_postprocess_v3(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.daily_etl_postprocess_v3(p_rebuild_days integer DEFAULT 7) RETURNS TABLE(target_last date, start_day date, fact_rows_upserted bigint, series_rows_upserted bigint, dense_days_refreshed integer, features_days_refreshed integer, articoli_da_normalizzare bigint, sales_raw_last date, sales_raw_is_stale boolean)
    LANGUAGE plpgsql
    AS $$DECLARE
  v_target_last date;
  v_start_day date;
  v_fact_rows bigint := 0;
  v_series_rows bigint := 0;
  v_articoli_missing bigint := 0;
  v_today date := CURRENT_DATE;
  v_is_stale boolean := false;
BEGIN
  -- target_last da sales_raw
  SELECT MAX(s.data_movimento)::date
  INTO v_target_last
  FROM public.greenhouse_sales_raw s;

  IF v_target_last IS NULL THEN
    INSERT INTO public.greenhouse_alerts(level, code, message, payload)
    VALUES ('ERROR', 'SALES_RAW_EMPTY', 'greenhouse_sales_raw è vuota: impossibile determinare target_last', '{}'::jsonb)
    ON CONFLICT (alert_day, code) DO UPDATE
      SET created_at = now(), level = EXCLUDED.level, message = EXCLUDED.message,
          payload = EXCLUDED.payload, is_sent = false, sent_at = null;

    RAISE EXCEPTION 'sales_raw è vuota';
  END IF;

  v_start_day := v_target_last - (p_rebuild_days - 1);

  -- alert stale (dedup)
  v_is_stale := (v_target_last < v_today);
  IF v_is_stale THEN
    INSERT INTO public.greenhouse_alerts(level, code, message, payload)
    VALUES (
      'WARN',
      'SALES_RAW_STALE',
      'sales_raw non aggiornata oggi (ETL non girato / PC spento?)',
      jsonb_build_object('today', v_today, 'sales_raw_last', v_target_last)
    )
    ON CONFLICT (alert_day, code) DO UPDATE
      SET created_at = now(), level = EXCLUDED.level, message = EXCLUDED.message,
          payload = EXCLUDED.payload, is_sent = false, sent_at = null;
  END IF;

  -- articoli da normalizzare (dedup)
  SELECT COUNT(*) INTO v_articoli_missing
  FROM public.greenhouse_articoli_da_normalizzare;

  IF v_articoli_missing > 0 THEN
    INSERT INTO public.greenhouse_alerts(level, code, message, payload)
    VALUES (
      CASE WHEN v_articoli_missing > 100 THEN 'WARN' ELSE 'INFO' END,
      'ARTICOLI_DA_NORMALIZZARE',
      'Ci sono codart piante non normalizzati',
      jsonb_build_object('count', v_articoli_missing)
    )
    ON CONFLICT (alert_day, code) DO UPDATE
      SET created_at = now(), level = EXCLUDED.level, message = EXCLUDED.message,
          payload = EXCLUDED.payload, is_sent = false, sent_at = null;
  END IF;

  -- UPSERT FACT (range rebuild) da view v2
  WITH src AS (
    SELECT *
    FROM public.greenhouse_sales_family_daily_v2
    WHERE data BETWEEN v_start_day AND v_target_last
  ),
  ins AS (
    INSERT INTO public.greenhouse_sales_family_daily_fact (
      data, famiglia, fascia_prezzo_iva_inc,
      qty_venduta, imponibile_netto_tot, num_articoli,
      fascia_corretta, categoria_corretta,
      pot_sizes_text, pot_sizes_json,
      articoli_inclusi, articoli_json
    )
    SELECT
      data, famiglia, fascia_prezzo_iva_inc,
      qty_venduta, imponibile_netto_tot, num_articoli,
      fascia_corretta, categoria_corretta,
      COALESCE(pot_sizes_text,''),
      COALESCE(pot_sizes_json,'[]'::jsonb),
      articoli_inclusi,
      COALESCE(articoli_json,'[]'::jsonb)
    FROM src
    ON CONFLICT (data, famiglia, fascia_prezzo_iva_inc)
    DO UPDATE SET
      qty_venduta = EXCLUDED.qty_venduta,
      imponibile_netto_tot = EXCLUDED.imponibile_netto_tot,
      num_articoli = EXCLUDED.num_articoli,
      fascia_corretta = EXCLUDED.fascia_corretta,
      categoria_corretta = EXCLUDED.categoria_corretta,
      pot_sizes_text = EXCLUDED.pot_sizes_text,
      pot_sizes_json = EXCLUDED.pot_sizes_json,
      articoli_inclusi = EXCLUDED.articoli_inclusi,
      articoli_json = EXCLUDED.articoli_json
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_fact_rows FROM ins;

  -- UPSERT series_list_fact (range rebuild)
  WITH src AS (
    SELECT
      famiglia,
      fascia_prezzo_iva_inc,
      MIN(fascia_corretta::text) AS fascia_corretta,
      MIN(categoria_corretta::text) AS categoria_corretta,
      MIN(data)::date AS first_seen,
      MAX(data)::date AS last_seen
    FROM public.greenhouse_sales_family_daily_fact
    WHERE data BETWEEN v_start_day AND v_target_last
    GROUP BY 1,2
  ),
  ins AS (
    INSERT INTO public.greenhouse_series_list_fact (
      famiglia, fascia_prezzo_iva_inc,
      fascia_corretta, categoria_corretta,
      first_seen, last_seen, updated_at
    )
    SELECT
      famiglia, fascia_prezzo_iva_inc,
      fascia_corretta, categoria_corretta,
      first_seen, last_seen, now()
    FROM src
    ON CONFLICT (famiglia, fascia_prezzo_iva_inc)
    DO UPDATE SET
      fascia_corretta = COALESCE(EXCLUDED.fascia_corretta, public.greenhouse_series_list_fact.fascia_corretta),
      categoria_corretta = COALESCE(EXCLUDED.categoria_corretta, public.greenhouse_series_list_fact.categoria_corretta),
      first_seen = LEAST(public.greenhouse_series_list_fact.first_seen, EXCLUDED.first_seen),
      last_seen  = GREATEST(public.greenhouse_series_list_fact.last_seen, EXCLUDED.last_seen),
      updated_at = now()
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_series_rows FROM ins;

  -- refresh DENSE da FACT (la tua funzione già esiste)
  PERFORM public.refresh_dense_range_from_fact(v_start_day, v_target_last);

  -- refresh FEATURES da DENSE (nuova)
  PERFORM public.refresh_forecast_features_dense_range(v_start_day, v_target_last);

  -- refresh analytics aggregates (serving tables)
  PERFORM public.refresh_analytics_aggregates_range(v_start_day, v_target_last);

  RETURN QUERY
  SELECT
    v_target_last,
    v_start_day,
    v_fact_rows,
    v_series_rows,
    p_rebuild_days,
    p_rebuild_days,
    v_articoli_missing,
    v_target_last,
    v_is_stale;
END;$$;

--
-- Name: dashboard__kpis_v1(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.dashboard__kpis_v1() RETURNS TABLE(sales_week numeric, sales_trend numeric, stock_out_risk integer, products_monitored integer, forecast_14d numeric)
    LANGUAGE sql STABLE
    AS $$
with bounds as (
  select max(data)::date as max_day
  from public.t_dashboard_sales_daily
),
w as (
  select
    (select max_day from bounds) as to_day,
    ((select max_day from bounds) - interval '6 days')::date as from_day,
    ((select max_day from bounds) - interval '13 days')::date as prev_from_day,
    ((select max_day from bounds) - interval '7 days')::date as prev_to_day
),
sales as (
  select
    coalesce(sum(d.imp_tot),0) as this_week,
    coalesce((
      select sum(d2.imp_tot)
      from public.t_dashboard_sales_daily d2, w
      where d2.data between w.prev_from_day and w.prev_to_day
    ),0) as prev_week
  from public.t_dashboard_sales_daily d, w
  where d.data between w.from_day and w.to_day
),
stock as (
  select
    (select max(data_rilevazione) from public.greenhouse_stock_raw_upload) as last_stock_day
),
stock_kpi as (
  select
    count(*) filter (where s.qty_giacenza <= 0) as stock_out_risk,
    count(*) as products_monitored
  from public.greenhouse_stock_raw_upload s
  join stock st on s.data_rilevazione = st.last_stock_day
),
forecast14 as (
  -- MVP: forecast totale prossimi 14 giorni (se hai forecast per fam+fp)
  select
    coalesce(sum(r.qty_forecast),0)::numeric as forecast_14d
  from public.greenhouse_forecast_results_v2 r, bounds b
  where r.data > b.max_day and r.data <= (b.max_day + interval '14 days')::date
)
select
  sales.this_week as sales_week,
  case
    when sales.prev_week = 0 then null
    else round(((sales.this_week - sales.prev_week) / abs(sales.prev_week)) * 100, 2)
  end as sales_trend,
  stock_kpi.stock_out_risk,
  stock_kpi.products_monitored,
  forecast14.forecast_14d
from sales, stock_kpi, forecast14;
$$;

--
-- Name: dashboard__kpis_v2(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.dashboard__kpis_v2() RETURNS TABLE(sales_week numeric, sales_trend numeric, stock_out_risk bigint, products_monitored bigint, forecast_14d numeric, reorder_lines bigint, reorder_risk_lines bigint, reorder_qty_tot numeric, sales_ytd numeric, sales_ytd_trend numeric)
    LANGUAGE sql STABLE
    AS $$
with bounds as (
  select max(data)::date as max_day
  from public.t_dashboard_sales_daily
),

/* -------------------------
   WEEK (ultimi 7 gg vs 7 gg precedenti)
   ------------------------- */
w as (
  select
    (select max_day from bounds) as to_day,
    ((select max_day from bounds) - interval '6 days')::date as from_day,
    ((select max_day from bounds) - interval '13 days')::date as prev_from_day,
    ((select max_day from bounds) - interval '7 days')::date as prev_to_day
),
sales as (
  select
    coalesce(sum(d.imp_tot),0)::numeric as this_week,
    coalesce((
      select sum(d2.imp_tot)
      from public.t_dashboard_sales_daily d2, w
      where d2.data between w.prev_from_day and w.prev_to_day
    ),0)::numeric as prev_week
  from public.t_dashboard_sales_daily d, w
  where d.data between w.from_day and w.to_day
),

/* -------------------------
   YTD (dal 1/1 al max_day) vs stesso periodo anno precedente
   ------------------------- */
ytd_bounds as (
  select
    (select max_day from bounds) as max_day,
    date_trunc('year', (select max_day from bounds)::timestamp)::date as ytd_from,
    (date_trunc('year', (select max_day from bounds)::timestamp) - interval '1 year')::date as prev_ytd_from,
    ((select max_day from bounds) - interval '1 year')::date as prev_ytd_to
),
sales_ytd as (
  select
    coalesce((
      select sum(d.imp_tot)
      from public.t_dashboard_sales_daily d, ytd_bounds y
      where d.data between y.ytd_from and y.max_day
    ),0)::numeric as this_ytd,
    coalesce((
      select sum(d.imp_tot)
      from public.t_dashboard_sales_daily d, ytd_bounds y
      where d.data between y.prev_ytd_from and y.prev_ytd_to
    ),0)::numeric as prev_ytd
),

/* -------------------------
   STOCK KPI
   ------------------------- */
stock as (
  select max(data_rilevazione) as last_stock_day
  from public.greenhouse_stock_raw_upload
),
stock_kpi as (
  select
    count(*) filter (where s.qty_giacenza <= 0) as stock_out_risk,
    count(*) as products_monitored
  from public.greenhouse_stock_raw_upload s
  join stock st on s.data_rilevazione = st.last_stock_day
),

/* -------------------------
   FORECAST 14d
   ------------------------- */
forecast14 as (
  select
    coalesce(sum(r.qty_forecast),0)::numeric as forecast_14d
  from public.greenhouse_forecast_results_v2 r, bounds b
  where r.data > b.max_day
    and r.data <= (b.max_day + interval '14 days')::date
),

/* -------------------------
   REORDER KPI
   ------------------------- */
reorder_kpi as (
  select
    count(*) filter (where coalesce(qty_da_ordinare,0) > 0) as reorder_lines,
    count(*) filter (
      where coalesce(qty_da_ordinare,0) > 0
        and coalesce(rischio_stockout_prima_di_arrivo,false)
    ) as reorder_risk_lines,
    coalesce(
      sum(qty_da_ordinare) filter (where coalesce(qty_da_ordinare,0) > 0),
      0
    )::numeric as reorder_qty_tot
  from public.greenhouse_order_suggestions_enriched_v2
)

select
  /* week */
  sales.this_week as sales_week,
  case
    when sales.prev_week = 0 then null
    else round(((sales.this_week - sales.prev_week) / abs(sales.prev_week)) * 100, 2)
  end as sales_trend,

  /* stock */
  stock_kpi.stock_out_risk,
  stock_kpi.products_monitored,

  /* forecast */
  forecast14.forecast_14d,

  /* reorder */
  reorder_kpi.reorder_lines,
  reorder_kpi.reorder_risk_lines,
  reorder_kpi.reorder_qty_tot,

  /* ytd */
  sales_ytd.this_ytd as sales_ytd,
  case
    when sales_ytd.prev_ytd = 0 then null
    else round(((sales_ytd.this_ytd - sales_ytd.prev_ytd) / abs(sales_ytd.prev_ytd)) * 100, 2)
  end as sales_ytd_trend
from sales, stock_kpi, forecast14, reorder_kpi, sales_ytd;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: get_order_suggestions_enriched_v2(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_order_suggestions_enriched_v2() RETURNS SETOF public.greenhouse_order_suggestions_enriched_v2
    LANGUAGE sql STABLE
    AS $$
  select * from public.greenhouse_order_suggestions_enriched_v2;
$$;

--
-- Name: gh_clean_famiglia_txt(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gh_clean_famiglia_txt(x text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT btrim(regexp_replace(coalesce(x,''), E'[\\s\\u00A0]+', ' ', 'g'));
$$;

--
-- Name: ops_maybe_run_daily_pipeline(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ops_maybe_run_daily_pipeline() RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  v_raw_max_day date;
  v_raw_last_load_ts timestamp;

  v_last_success_target_last date;
  v_last_success_status text;

  v_now_utc timestamp := (now() at time zone 'UTC');
  v_raw_is_stable boolean := false;
  v_already_done boolean := false;
begin
  -- RAW max day + last load timestamp
  select max(data_movimento)::date, max(load_timestamp)::timestamp
  into v_raw_max_day, v_raw_last_load_ts
  from public.greenhouse_sales_raw;

  if v_raw_max_day is null or v_raw_last_load_ts is null then
    return;
  end if;

  -- stabile se non scrive da 20 minuti
  v_raw_is_stable := (v_now_utc - v_raw_last_load_ts) >= interval '20 minutes';

  -- ultimo ETL SUCCESS target_last
  select
    (payload->>'target_last')::date,
    status
  into v_last_success_target_last, v_last_success_status
  from etl.t_etl_runs
  where pipeline='greenhouse_daily_full'
    and status='success'
  order by started_at desc
  limit 1;

  v_already_done :=
    (v_last_success_status = 'success')
    and (v_last_success_target_last = v_raw_max_day);

  if v_raw_is_stable and not v_already_done then
    begin
      execute 'set local statement_timeout = 0';
    exception when others then
      null;
    end;

    call public.run_greenhouse_daily_pipeline_full(40,14,2);

    -- snapshot monitor
    perform public.ops_refresh_pipeline_monitor_snapshot();
  end if;

  return;
end;
$$;

--
-- Name: ops_pipeline_monitor_snapshot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ops_pipeline_monitor_snapshot() RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  v_raw_max_day date;
  v_raw_rows bigint;
  v_raw_last_load_ts timestamp;

  v_run_id uuid;
  v_etl_status text;
  v_etl_message text;
  v_etl_started_at timestamptz;
  v_etl_ended_at timestamptz;
  v_etl_target_last date;

  v_planner_last_day date;
  v_roll4_step text;
  v_roll4_cursor int;
  v_roll4_updated_at timestamptz;

  v_dash_daily date;
  v_dash_weekly date;
  v_dash_monthly date;

  v_dense_max_data date;     -- ✅ NEW

  v_ok boolean := false;
  v_notes text := null;
begin
  -- RAW
  select max(data_movimento), max(load_timestamp)
  into v_raw_max_day, v_raw_last_load_ts
  from public.greenhouse_sales_raw;

  select count(*)
  into v_raw_rows
  from public.greenhouse_sales_raw
  where data_movimento = v_raw_max_day;

  -- ETL: ultimo SUCCESS
  select
    run_id,
    status,
    message,
    started_at,
    ended_at,
    (payload->>'target_last')::date
  into v_run_id, v_etl_status, v_etl_message, v_etl_started_at, v_etl_ended_at, v_etl_target_last
  from etl.t_etl_runs
  where pipeline = 'greenhouse_daily_full'
    and status = 'success'
  order by started_at desc
  limit 1;

  -- Planner state
  select last_day
  into v_planner_last_day
  from public.t_core_planner__refresh_state
  where pipeline = 'planner_weekly';

  -- Roll4 state
  select step, cursor_int, updated_at
  into v_roll4_step, v_roll4_cursor, v_roll4_updated_at
  from public.t_core_planner__orchestrator_state
  where pipeline = 'nightly_roll4';

  -- Dashboard freshness
  select max(data) into v_dash_daily from public.t_dashboard_sales_daily;
  select max(period_start) into v_dash_weekly from public.t_dashboard_sales_weekly;
  select max(period_start) into v_dash_monthly from public.t_dashboard_sales_monthly;

  -- ✅ DENSE sentinel
  select max(data)::date into v_dense_max_data
  from public.greenhouse_sales_family_daily_dense;

  -- OK logic (base + dense)
  v_ok :=
    (v_raw_max_day is not null)
    and (v_etl_target_last is not null)
    and (v_etl_target_last = v_raw_max_day)
    and (v_dash_daily is not null and v_dash_daily >= v_raw_max_day)
    and (v_planner_last_day is not null and v_planner_last_day >= (v_raw_max_day - 1))
    and (v_dense_max_data = v_raw_max_day);

  if not v_ok then
    v_notes := concat_ws(' | ',
      case when v_raw_max_day is null then 'RAW empty' end,
      case when v_etl_target_last is null then 'No successful ETL run found' end,
      case when (v_etl_target_last is not null and v_etl_target_last <> v_raw_max_day) then 'ETL target_last != RAW max day' end,
      case when (v_dash_daily is null or v_dash_daily < v_raw_max_day) then 'Dashboard daily not updated to RAW max day' end,
      case when (v_dense_max_data is null or v_dense_max_data <> v_raw_max_day) then 'DENSE not aligned' end,
      case when v_planner_last_day is null then 'planner_weekly missing' end
    );
  end if;

  insert into public.t_ops_pipeline_monitor (
    raw_max_data, raw_rows_max_day, raw_last_load_ts,
    etl_last_run_id, etl_last_status, etl_last_message, etl_last_started_at, etl_last_ended_at, etl_last_target_last,
    planner_weekly_last_day,
    roll4_step, roll4_cursor_int, roll4_updated_at,
    dash_daily_max_date, dash_weekly_max_period_start, dash_monthly_max_period_start,
    ok, notes
  )
  values (
    v_raw_max_day, v_raw_rows, v_raw_last_load_ts,
    v_run_id, v_etl_status, v_etl_message, v_etl_started_at, v_etl_ended_at, v_etl_target_last,
    v_planner_last_day,
    v_roll4_step, v_roll4_cursor, v_roll4_updated_at,
    v_dash_daily, v_dash_weekly, v_dash_monthly,
    v_ok, v_notes
  );
end;
$$;

--
-- Name: ops_refresh_pipeline_monitor_snapshot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ops_refresh_pipeline_monitor_snapshot() RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$declare
  v_snap_ts timestamptz := now();
  v_now_utc timestamp := (now() at time zone 'UTC');  -- raw_last_load_ts è timestamp senza tz

  /* -------------------------
     RAW
     ------------------------- */
  v_raw_max_data date;
  v_raw_last_load_ts timestamp;
  v_raw_rows_max_day bigint := 0;
  v_raw_stable_20m boolean := null;

  /* -------------------------
     ETL last run (ultima riga, anche skipped)
     ------------------------- */
  v_etl_run_id uuid;
  v_etl_started_at timestamptz;
  v_etl_ended_at timestamptz;
  v_etl_status text;
  v_etl_message text;
  v_etl_target_last date;

  v_started_after_raw_stable boolean := null;

  /* -------------------------
     ETL last SUCCESS
     ------------------------- */
  v_etl_success_run_id uuid;
  v_etl_success_started_at timestamptz;
  v_etl_success_ended_at timestamptz;
  v_etl_success_message text;
  v_etl_success_target_last date;

  v_success_started_after_raw_stable boolean := null;

  /* -------------------------
     Roll4 orchestrator state
     ------------------------- */
  v_roll4_step text;
  v_roll4_cursor_int int;
  v_roll4_updated_at timestamptz;

  /* -------------------------
     Planner state
     ------------------------- */
  v_planner_weekly_last_day date;

  /* -------------------------
     Planner data sentinel
     ------------------------- */
  v_planner_weekly_fact_max_week_start date;

  /* -------------------------
     Outputs sentinels
     ------------------------- */
  v_fact_max_data date;
  v_dense_max_data date;                 -- ✅ NEW: DENSE sentinel (non persistito in tabella)
  v_features_dense_max_data date;

  /* -------------------------
     Analytics sentinel
     ------------------------- */
  v_analytics_daily_max_data date;

  /* -------------------------
     Dash
     ------------------------- */
  v_dash_daily_max date;
  v_dash_weekly_max date;
  v_dash_monthly_max date;

  /* -------------------------
     OK / notes
     ------------------------- */
  v_ok boolean := false;
  v_notes text := '';
begin
  /* -------------------------
     RAW
     ------------------------- */
  select
    max(s.data_movimento)::date,
    max(s.load_timestamp)::timestamp
  into v_raw_max_data, v_raw_last_load_ts
  from public.greenhouse_sales_raw s;

  if v_raw_max_data is not null then
    select count(*) into v_raw_rows_max_day
    from public.greenhouse_sales_raw
    where data_movimento = v_raw_max_data;
  end if;

  if v_raw_last_load_ts is not null then
    v_raw_stable_20m := (v_now_utc - v_raw_last_load_ts) >= interval '20 minutes';
  end if;

  /* -------------------------
     ETL last run (anche skipped)
     ------------------------- */
  select
    run_id,
    started_at,
    ended_at,
    status,
    message,
    (payload->>'target_last')::date
  into
    v_etl_run_id,
    v_etl_started_at,
    v_etl_ended_at,
    v_etl_status,
    v_etl_message,
    v_etl_target_last
  from etl.t_etl_runs
  where pipeline = 'greenhouse_daily_full'
  order by started_at desc
  limit 1;

  if v_etl_started_at is not null and v_raw_last_load_ts is not null then
    v_started_after_raw_stable :=
      v_etl_started_at >= ((v_raw_last_load_ts + interval '20 minutes') at time zone 'UTC');
  end if;

  /* -------------------------
     ETL last SUCCESS
     ------------------------- */
  select
    run_id,
    started_at,
    ended_at,
    message,
    (payload->>'target_last')::date
  into
    v_etl_success_run_id,
    v_etl_success_started_at,
    v_etl_success_ended_at,
    v_etl_success_message,
    v_etl_success_target_last
  from etl.t_etl_runs
  where pipeline = 'greenhouse_daily_full'
    and status = 'success'
  order by started_at desc
  limit 1;

  if v_etl_success_started_at is not null and v_raw_last_load_ts is not null then
    v_success_started_after_raw_stable :=
      v_etl_success_started_at >= ((v_raw_last_load_ts + interval '20 minutes') at time zone 'UTC');
  end if;

  /* -------------------------
     Roll4 orchestrator state
     ------------------------- */
  begin
    select step, cursor_int, updated_at
    into v_roll4_step, v_roll4_cursor_int, v_roll4_updated_at
    from public.t_core_planner__orchestrator_state
    where pipeline = 'nightly_roll4';
  exception when undefined_table then
    v_notes := v_notes || 'roll4 orchestrator_state missing | ';
  end;

  /* -------------------------
     Planner refresh state
     ------------------------- */
  begin
    select last_day
    into v_planner_weekly_last_day
    from public.t_core_planner__refresh_state
    where pipeline = 'planner_weekly';
  exception when undefined_table then
    v_notes := v_notes || 'planner_weekly refresh_state missing | ';
  end;

  /* -------------------------
     Planner DATA sentinel
     ------------------------- */
  begin
    select max(week_start)::date
    into v_planner_weekly_fact_max_week_start
    from public.t_core_planner__fact_weekly;
  exception when undefined_table then
    v_notes := v_notes || 'planner_weekly fact table missing | ';
  end;

  /* -------------------------
     Outputs: FACT / DENSE / FEATURES
     ------------------------- */
  begin
    select max(data)::date into v_fact_max_data
    from public.greenhouse_sales_family_daily_fact;
  exception when undefined_table then
    v_notes := v_notes || 'fact missing | ';
  end;

  begin
    select max(data)::date into v_dense_max_data
    from public.greenhouse_sales_family_daily_dense;
  exception when undefined_table then
    v_notes := v_notes || 'dense missing | ';
  end;

  begin
    select max(data)::date into v_features_dense_max_data
    from public.greenhouse_forecast_features_dense;
  exception when undefined_table then
    v_notes := v_notes || 'features_dense missing | ';
  end;

  /* -------------------------
     Analytics sentinel
     ------------------------- */
  begin
    select max(data)::date into v_analytics_daily_max_data
    from public.t_core_analytics__series_daily_famiglia;
  exception when undefined_table then
    v_notes := v_notes || 'analytics_daily table missing | ';
  end;

  /* -------------------------
     Dash
     ------------------------- */
  begin
    select max(data)::date into v_dash_daily_max
    from public.t_dashboard_sales_daily;
  exception when undefined_table then
    v_notes := v_notes || 'dash_daily missing | ';
  end;

  begin
    select max(period_start)::date into v_dash_weekly_max
    from public.t_dashboard_sales_weekly;
  exception when undefined_table then
    v_notes := v_notes || 'dash_weekly missing | ';
  end;

  begin
    select max(period_start)::date into v_dash_monthly_max
    from public.t_dashboard_sales_monthly;
  exception when undefined_table then
    v_notes := v_notes || 'dash_monthly missing | ';
  end;

  /* -------------------------
     OK logic (robusta)
     usa LAST SUCCESS, non last-run
     ------------------------- */
  v_ok :=
    -- RAW
    (v_raw_max_data is not null)
    and (v_raw_last_load_ts is not null)
    and (v_raw_stable_20m is true)

    -- ETL SUCCESS: target_last allineato
    and (v_etl_success_target_last = v_raw_max_data)
    and coalesce(v_success_started_after_raw_stable, true)

    -- Dati principali
    and (v_fact_max_data = v_raw_max_data)
    and (v_dense_max_data = v_raw_max_data)                 -- ✅ NEW
    and (v_features_dense_max_data = v_raw_max_data)

    -- Analytics + dashboard
    and (v_analytics_daily_max_data = v_raw_max_data)
    and (v_dash_daily_max = v_raw_max_data)

    -- Planner: deve coprire almeno la settimana del raw_max_data
    and (
      v_planner_weekly_fact_max_week_start is not null
      and (v_planner_weekly_fact_max_week_start >= date_trunc('week', v_raw_max_data)::date)
    );

  /* -------------------------
     Notes diagnostiche
     ------------------------- */
  if v_raw_max_data is null then
    v_notes := v_notes || 'raw empty | ';
  end if;

  if v_raw_stable_20m is not true then
    v_notes := v_notes || 'raw not stable 20m | ';
  end if;

  if v_etl_status is distinct from 'success' then
    v_notes := v_notes || 'etl last run not success | ';
  end if;

  if v_etl_success_target_last is null then
    v_notes := v_notes || 'no successful etl run found | ';
  end if;

  if v_etl_success_target_last is distinct from v_raw_max_data then
    v_notes := v_notes || 'etl last success target_last != raw_max_data | ';
  end if;

  if v_fact_max_data is distinct from v_raw_max_data then
    v_notes := v_notes || 'fact not aligned | ';
  end if;

  if v_dense_max_data is distinct from v_raw_max_data then
    v_notes := v_notes || 'dense not aligned | ';
  end if;

  if v_features_dense_max_data is distinct from v_raw_max_data then
    v_notes := v_notes || 'features_dense not aligned | ';
  end if;

  if v_analytics_daily_max_data is distinct from v_raw_max_data then
    v_notes := v_notes || 'analytics not aligned | ';
  end if;

  if v_dash_daily_max is distinct from v_raw_max_data then
    v_notes := v_notes || 'dashboard daily not aligned | ';
  end if;

  if v_planner_weekly_fact_max_week_start is null
     or v_planner_weekly_fact_max_week_start < date_trunc('week', v_raw_max_data)::date then
    v_notes := v_notes || 'planner_weekly facts not aligned | ';
  end if;

  if v_success_started_after_raw_stable is false then
    v_notes := v_notes || 'etl success started before raw stable 20m | ';
  end if;

  -- se tutto ok, non scrivere note diagnostiche
  if v_ok then
    v_notes := null;
  else
    v_notes := nullif(btrim(v_notes), '');
  end if;

  /* -------------------------
     Insert snapshot (match DDL che mi hai dato)
     ------------------------- */
  insert into public.t_ops_pipeline_monitor (
    snap_ts,
    raw_max_data,
    raw_rows_max_day,
    raw_last_load_ts,

    -- last run (anche skipped)
    etl_last_run_id,
    etl_last_status,
    etl_last_message,
    etl_last_started_at,
    etl_last_ended_at,
    etl_last_target_last,

    -- last SUCCESS
    etl_last_success_run_id,
    etl_last_success_started_at,
    etl_last_success_ended_at,
    etl_last_success_target_last,
    etl_last_success_message,

    planner_weekly_last_day,

    roll4_step,
    roll4_cursor_int,
    roll4_updated_at,

    dash_daily_max_date,
    dash_weekly_max_period_start,
    dash_monthly_max_period_start,

    ok,
    notes,

    fact_max_data,
    dense_max_data, 
    features_dense_max_data,
    analytics_daily_max_data,

    planner_weekly_fact_max_week_start
  )
  values (
    v_snap_ts,
    v_raw_max_data,
    v_raw_rows_max_day,
    v_raw_last_load_ts,

    v_etl_run_id,
    v_etl_status,
    v_etl_message,
    v_etl_started_at,
    v_etl_ended_at,
    v_etl_target_last,

    v_etl_success_run_id,
    v_etl_success_started_at,
    v_etl_success_ended_at,
    v_etl_success_target_last,
    v_etl_success_message,

    v_planner_weekly_last_day,

    v_roll4_step,
    v_roll4_cursor_int,
    v_roll4_updated_at,

    v_dash_daily_max,
    v_dash_weekly_max,
    v_dash_monthly_max,

    v_ok,
    nullif(btrim(v_notes), ''),

    v_fact_max_data,
    v_dense_max_data, 
    v_features_dense_max_data,
    v_analytics_daily_max_data,

    v_planner_weekly_fact_max_week_start
  );

  return v_snap_ts;
end;$$;

--
-- Name: patch_features_holidays_range(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.patch_features_holidays_range(p_start date, p_end date) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start > p_end THEN
    RAISE EXCEPTION 'range non valido: % - %', p_start, p_end;
  END IF;

  -- timeout più alto solo per questa funzione
  PERFORM set_config('statement_timeout', '600000', true); -- 10 min

  -- 1) spegni holiday SOLO dove oggi risulta holiday ma in tabella holidays NON c'è
  UPDATE public.greenhouse_forecast_features_dense f
  SET
    is_holiday = false,
    holiday_name = NULL,
    updated_at = now()
  WHERE f.data BETWEEN p_start AND p_end
    AND (f.is_holiday = true OR f.holiday_name IS NOT NULL)
    AND NOT EXISTS (
      SELECT 1
      FROM public.greenhouse_holidays h
      WHERE h.data = f.data
    );

  -- 2) accendi holiday SOLO dove c'è match e differisce (is_holiday o name)
  UPDATE public.greenhouse_forecast_features_dense f
  SET
    is_holiday = true,
    holiday_name = h.holiday_name,
    updated_at = now()
  FROM public.greenhouse_holidays h
  WHERE f.data = h.data
    AND f.data BETWEEN p_start AND p_end
    AND (
      f.is_holiday IS DISTINCT FROM true
      OR f.holiday_name IS DISTINCT FROM h.holiday_name
    );

END;
$$;

--
-- Name: refresh_analytics_aggregates_range(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_analytics_aggregates_range(p_start date, p_end date) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
  if p_start is null or p_end is null or p_start > p_end then
    raise exception 'Invalid range: % - %', p_start, p_end;
  end if;

  -- =========================
  -- SERIE: FAMIGLIA (tabella già esistente)
  -- =========================
  insert into public.t_core_analytics__series_daily_famiglia (
    data, entity_key,
    qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot,
    is_holiday, holiday_name, dow
  )
  select
    g.data,
    lower(g.famiglia) as entity_key,
    sum(g.qty_venduta) as qty_venduta_tot,
    sum(g.imponibile_netto_tot) as imponibile_netto_tot,
    sum(coalesce(fc.qty_forecast, 0)) as qty_forecast_tot,
    bool_or(coalesce(g.is_holiday,false)) as is_holiday,
    max(g.holiday_name) as holiday_name,
    max(g.dow) as dow
  from public.greenhouse_forecast_features_dense g
  left join public.greenhouse_forecast_results_v2 fc
    on fc.data = g.data
   and lower(fc.famiglia) = lower(g.famiglia)
   and fc.fascia_prezzo_iva_inc = g.fascia_prezzo_iva_inc
  where g.data between p_start and p_end
  group by 1,2
  on conflict (data, entity_key) do update
  set
    qty_venduta_tot = excluded.qty_venduta_tot,
    imponibile_netto_tot = excluded.imponibile_netto_tot,
    qty_forecast_tot = excluded.qty_forecast_tot,
    is_holiday = excluded.is_holiday,
    holiday_name = excluded.holiday_name,
    dow = excluded.dow;

  -- =========================
  -- SERIE: CATEGORIA
  -- =========================
  insert into public.t_core_analytics__series_daily_categoria (
    data, entity_key,
    qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot,
    is_holiday, holiday_name, dow
  )
  select
    g.data,
    lower(g.categoria_corretta) as entity_key,
    sum(g.qty_venduta) as qty_venduta_tot,
    sum(g.imponibile_netto_tot) as imponibile_netto_tot,
    sum(coalesce(fc.qty_forecast, 0)) as qty_forecast_tot,
    bool_or(coalesce(g.is_holiday,false)) as is_holiday,
    max(g.holiday_name) as holiday_name,
    max(g.dow) as dow
  from public.greenhouse_forecast_features_dense g
  left join public.greenhouse_forecast_results_v2 fc
    on fc.data = g.data
   and lower(fc.famiglia) = lower(g.famiglia)
   and fc.fascia_prezzo_iva_inc = g.fascia_prezzo_iva_inc
  where g.data between p_start and p_end
    and g.categoria_corretta is not null
    and btrim(g.categoria_corretta) <> ''
  group by 1,2
  on conflict (data, entity_key) do update
  set
    qty_venduta_tot = excluded.qty_venduta_tot,
    imponibile_netto_tot = excluded.imponibile_netto_tot,
    qty_forecast_tot = excluded.qty_forecast_tot,
    is_holiday = excluded.is_holiday,
    holiday_name = excluded.holiday_name,
    dow = excluded.dow;

  -- =========================
  -- SERIE: FASCIA
  -- =========================
  insert into public.t_core_analytics__series_daily_fascia (
    data, entity_key,
    qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot,
    is_holiday, holiday_name, dow
  )
  select
    g.data,
    lower(g.fascia_corretta) as entity_key,
    sum(g.qty_venduta) as qty_venduta_tot,
    sum(g.imponibile_netto_tot) as imponibile_netto_tot,
    sum(coalesce(fc.qty_forecast, 0)) as qty_forecast_tot,
    bool_or(coalesce(g.is_holiday,false)) as is_holiday,
    max(g.holiday_name) as holiday_name,
    max(g.dow) as dow
  from public.greenhouse_forecast_features_dense g
  left join public.greenhouse_forecast_results_v2 fc
    on fc.data = g.data
   and lower(fc.famiglia) = lower(g.famiglia)
   and fc.fascia_prezzo_iva_inc = g.fascia_prezzo_iva_inc
  where g.data between p_start and p_end
    and g.fascia_corretta is not null
    and btrim(g.fascia_corretta) <> ''
  group by 1,2
  on conflict (data, entity_key) do update
  set
    qty_venduta_tot = excluded.qty_venduta_tot,
    imponibile_netto_tot = excluded.imponibile_netto_tot,
    qty_forecast_tot = excluded.qty_forecast_tot,
    is_holiday = excluded.is_holiday,
    holiday_name = excluded.holiday_name,
    dow = excluded.dow;

  -- =========================
  -- SERIE: FASCIA PREZZO
  -- =========================
  insert into public.t_core_analytics__series_daily_fascia_prezzo (
    data, entity_key,
    qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot,
    is_holiday, holiday_name, dow
  )
  select
    g.data,
    lower(g.fascia_prezzo_iva_inc) as entity_key,
    sum(g.qty_venduta) as qty_venduta_tot,
    sum(g.imponibile_netto_tot) as imponibile_netto_tot,
    sum(coalesce(fc.qty_forecast, 0)) as qty_forecast_tot,
    bool_or(coalesce(g.is_holiday,false)) as is_holiday,
    max(g.holiday_name) as holiday_name,
    max(g.dow) as dow
  from public.greenhouse_forecast_features_dense g
  left join public.greenhouse_forecast_results_v2 fc
    on fc.data = g.data
   and lower(fc.famiglia) = lower(g.famiglia)
   and fc.fascia_prezzo_iva_inc = g.fascia_prezzo_iva_inc
  where g.data between p_start and p_end
    and g.fascia_prezzo_iva_inc is not null
    and btrim(g.fascia_prezzo_iva_inc) <> ''
  group by 1,2
  on conflict (data, entity_key) do update
  set
    qty_venduta_tot = excluded.qty_venduta_tot,
    imponibile_netto_tot = excluded.imponibile_netto_tot,
    qty_forecast_tot = excluded.qty_forecast_tot,
    is_holiday = excluded.is_holiday,
    holiday_name = excluded.holiday_name,
    dow = excluded.dow;

  -- =========================
  -- BREAKDOWN: FAMIGLIA -> FP
  -- =========================
  insert into public.t_core_analytics__breakdown_daily_famiglia_fp (
    data, entity_key_lc, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    is_holiday, holiday_name, dow, qty_forecast
  )
  select
    g.data,
    lower(g.famiglia) as entity_key_lc,
    g.fascia_prezzo_iva_inc,
    sum(g.qty_venduta)::numeric(12,3) as qty_venduta,
    sum(g.imponibile_netto_tot)::numeric(12,2) as imponibile_netto_tot,
    sum(g.num_articoli)::int as num_articoli,
    bool_or(coalesce(g.is_holiday,false)) as is_holiday,
    max(g.holiday_name) as holiday_name,
    max(g.dow) as dow,
    sum(coalesce(fc.qty_forecast,0))::numeric(12,3) as qty_forecast
  from public.greenhouse_forecast_features_dense g
  left join public.greenhouse_forecast_results_v2 fc
    on fc.data = g.data
   and lower(fc.famiglia) = lower(g.famiglia)
   and fc.fascia_prezzo_iva_inc = g.fascia_prezzo_iva_inc
  where g.data between p_start and p_end
  group by 1,2,3
  on conflict (data, entity_key_lc, fascia_prezzo_iva_inc) do update
  set
    qty_venduta = excluded.qty_venduta,
    imponibile_netto_tot = excluded.imponibile_netto_tot,
    num_articoli = excluded.num_articoli,
    is_holiday = excluded.is_holiday,
    holiday_name = excluded.holiday_name,
    dow = excluded.dow,
    qty_forecast = excluded.qty_forecast;

  -- =========================
  -- BREAKDOWN: CATEGORIA -> FP
  -- =========================
  insert into public.t_core_analytics__breakdown_daily_categoria_fp (
    data, entity_key_lc, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    is_holiday, holiday_name, dow, qty_forecast
  )
  select
    g.data,
    lower(g.categoria_corretta) as entity_key_lc,
    g.fascia_prezzo_iva_inc,
    sum(g.qty_venduta)::numeric(12,3) as qty_venduta,
    sum(g.imponibile_netto_tot)::numeric(12,2) as imponibile_netto_tot,
    sum(g.num_articoli)::int as num_articoli,
    bool_or(coalesce(g.is_holiday,false)) as is_holiday,
    max(g.holiday_name) as holiday_name,
    max(g.dow) as dow,
    sum(coalesce(fc.qty_forecast,0))::numeric(12,3) as qty_forecast
  from public.greenhouse_forecast_features_dense g
  left join public.greenhouse_forecast_results_v2 fc
    on fc.data = g.data
   and lower(fc.famiglia) = lower(g.famiglia)
   and fc.fascia_prezzo_iva_inc = g.fascia_prezzo_iva_inc
  where g.data between p_start and p_end
    and g.categoria_corretta is not null
    and btrim(g.categoria_corretta) <> ''
  group by 1,2,3
  on conflict (data, entity_key_lc, fascia_prezzo_iva_inc) do update
  set
    qty_venduta = excluded.qty_venduta,
    imponibile_netto_tot = excluded.imponibile_netto_tot,
    num_articoli = excluded.num_articoli,
    is_holiday = excluded.is_holiday,
    holiday_name = excluded.holiday_name,
    dow = excluded.dow,
    qty_forecast = excluded.qty_forecast;

end;
$$;

--
-- Name: refresh_dashboard_from_dense_range(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_dashboard_from_dense_range(p_from date, p_to date) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$-- ==========================================
-- refresh_dashboard_from_dense_range(p_from, p_to)
-- ✅ FIX: weekly/monthly/yearly ricalcolati su bucket calendario COMPLETI
-- ==========================================
declare
  v_daily_upserted   bigint := 0;
  v_weekly_upserted  bigint := 0;
  v_monthly_upserted bigint := 0;
  v_yearly_upserted  bigint := 0;

  v_week_from  date;
  v_week_to    date;
  v_month_from date;
  v_month_to   date;
  v_year_from  date;
  v_year_to    date;
begin
  -- no timeout (se permesso)
  begin
    execute 'set local statement_timeout = 0';
  exception when others then
    null;
  end;

  if p_from is null or p_to is null then
    raise exception 'p_from and p_to cannot be null';
  end if;

  if p_from > p_to then
    raise exception 'p_from (%) > p_to (%)', p_from, p_to;
  end if;

  -- ✅ calcolo range estesi per bucket completi
  v_week_from  := date_trunc('week',  p_from::timestamp)::date;
  v_week_to    := (date_trunc('week', p_to::timestamp)::date + 6); -- lun..dom

  v_month_from := date_trunc('month', p_from::timestamp)::date;
  v_month_to   := (date_trunc('month', p_to::timestamp) + interval '1 month - 1 day')::date;

  v_year_from  := date_trunc('year',  p_from::timestamp)::date;
  v_year_to    := (date_trunc('year', p_to::timestamp) + interval '1 year - 1 day')::date;

  /* -------------------------
     1) DAILY  (range preciso)
     ------------------------- */
  with agg as (
    select
      d.data::date as data,
      sum(d.qty_venduta)::numeric(18,3) as qty_tot,
      sum(d.imponibile_netto_tot)::numeric(18,2) as imp_tot,
      sum(d.num_articoli)::int as num_articoli_tot
    from public.greenhouse_sales_family_daily_dense d
    where d.data between p_from and p_to
    group by d.data
  ),
  up as (
    insert into public.t_dashboard_sales_daily (data, qty_tot, imp_tot, num_articoli_tot)
    select data, qty_tot, imp_tot, num_articoli_tot
    from agg
    on conflict (data) do update
      set qty_tot = excluded.qty_tot,
          imp_tot = excluded.imp_tot,
          num_articoli_tot = excluded.num_articoli_tot
    returning 1
  )
  select count(*) into v_daily_upserted from up;

  /* -------------------------
     2) WEEKLY (bucket completi lun..dom)
     ------------------------- */
with agg as (
  select
    date_trunc('week', d.data::timestamp)::date as period_start,
    sum(d.qty_tot)::numeric(18,3) as qty_tot,
    sum(d.imp_tot)::numeric(18,2) as imp_tot
  from public.t_dashboard_sales_daily d
  where d.data between v_week_from and v_week_to
  group by 1
),
up as (
  insert into public.t_dashboard_sales_weekly (period_start, qty_tot, imp_tot)
  select period_start, qty_tot, imp_tot
  from agg
  on conflict (period_start) do update
    set qty_tot = excluded.qty_tot,
        imp_tot = excluded.imp_tot
  returning 1
)
select count(*) into v_weekly_upserted from up;

  /* -------------------------
     3) MONTHLY (bucket completi mese)
     ------------------------- */
with agg as (
  select
    date_trunc('month', d.data::timestamp)::date as period_start,
    sum(d.qty_tot)::numeric(18,3) as qty_tot,
    sum(d.imp_tot)::numeric(18,2) as imp_tot
  from public.t_dashboard_sales_daily d
  where d.data between v_month_from and v_month_to
  group by 1
),
up as (
  insert into public.t_dashboard_sales_monthly (period_start, qty_tot, imp_tot)
  select period_start, qty_tot, imp_tot
  from agg
  on conflict (period_start) do update
    set qty_tot = excluded.qty_tot,
        imp_tot = excluded.imp_tot
  returning 1
)
select count(*) into v_monthly_upserted from up;

  /* -------------------------
     4) YEARLY (bucket completi anno)
     ------------------------- */
with agg as (
  select
    date_trunc('year', d.data::timestamp)::date as period_start,
    sum(d.qty_tot)::numeric(18,3) as qty_tot,
    sum(d.imp_tot)::numeric(18,2) as imp_tot
  from public.t_dashboard_sales_daily d
  where d.data between v_year_from and v_year_to
  group by 1
),
up as (
  insert into public.t_dashboard_sales_yearly (period_start, qty_tot, imp_tot)
  select period_start, qty_tot, imp_tot
  from agg
  on conflict (period_start) do update
    set qty_tot = excluded.qty_tot,
        imp_tot = excluded.imp_tot
  returning 1
)
select count(*) into v_yearly_upserted from up;

  return jsonb_build_object(
    'ok', true,
    'from', p_from,
    'to', p_to,
    'bucket_ranges', jsonb_build_object(
      'week_from',  v_week_from,  'week_to',  v_week_to,
      'month_from', v_month_from, 'month_to', v_month_to,
      'year_from',  v_year_from,  'year_to',  v_year_to
    ),
    'dashboard_upserted', jsonb_build_object(
      'daily', v_daily_upserted,
      'weekly', v_weekly_upserted,
      'monthly', v_monthly_upserted,
      'yearly', v_yearly_upserted
    )
  );
end;$$;

--
-- Name: refresh_dashboard_sales_range(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_dashboard_sales_range(p_start date, p_end date) RETURNS void
    LANGUAGE plpgsql
    AS $$-- ==========================================
-- refresh_dashboard_sales_range(p_start, p_end)
-- ✅ FIX: weekly/monthly/yearly ricalcolati su bucket calendario COMPLETI
-- ==========================================
begin
  -- NO TIMEOUT anche qui
  begin
    execute 'set local statement_timeout = 0';
  exception when others then null;
  end;

  -- -------------------------
  -- 1) DAILY (range preciso)
  -- -------------------------
  insert into public.t_dashboard_sales_daily (data, qty_tot, imp_tot, num_articoli_tot)
  select
    d.data::date as data,
    coalesce(sum(d.qty_venduta),0)::numeric(18,3) as qty_tot,
    coalesce(sum(d.imponibile_netto_tot),0)::numeric(18,2) as imp_tot,
    coalesce(sum(d.num_articoli),0)::int as num_articoli_tot
  from public.greenhouse_sales_family_daily_dense d
  where d.data between p_start and p_end
  group by 1
  on conflict (data) do update
    set qty_tot = excluded.qty_tot,
        imp_tot = excluded.imp_tot,
        num_articoli_tot = excluded.num_articoli_tot;

  -- -------------------------
  -- 2) WEEKLY (bucket completi lun..dom)
  -- -------------------------
insert into public.t_dashboard_sales_weekly (period_start, qty_tot, imp_tot)
select
  date_trunc('week', d.data::timestamp)::date as period_start,
  coalesce(sum(d.qty_tot),0)::numeric(18,3) as qty_tot,
  coalesce(sum(d.imp_tot),0)::numeric(18,2) as imp_tot
from public.t_dashboard_sales_daily d
where d.data between date_trunc('week', p_start::timestamp)::date
               and (date_trunc('week', p_end::timestamp)::date + 6)
group by 1
on conflict (period_start) do update
  set qty_tot = excluded.qty_tot,
      imp_tot = excluded.imp_tot;

  -- -------------------------
  -- 3) MONTHLY (bucket completi mese)
  -- -------------------------
insert into public.t_dashboard_sales_monthly (period_start, qty_tot, imp_tot)
select
  date_trunc('month', d.data::timestamp)::date as period_start,
  coalesce(sum(d.qty_tot),0)::numeric(18,3) as qty_tot,
  coalesce(sum(d.imp_tot),0)::numeric(18,2) as imp_tot
from public.t_dashboard_sales_daily d
where d.data between date_trunc('month', p_start::timestamp)::date
               and (date_trunc('month', p_end::timestamp) + interval '1 month - 1 day')::date
group by 1
on conflict (period_start) do update
  set qty_tot = excluded.qty_tot,
      imp_tot = excluded.imp_tot;

  -- -------------------------
  -- 4) YEARLY (bucket completi anno)
  -- -------------------------
insert into public.t_dashboard_sales_yearly (period_start, qty_tot, imp_tot)
select
  date_trunc('year', d.data::timestamp)::date as period_start,
  coalesce(sum(d.qty_tot),0)::numeric(18,3) as qty_tot,
  coalesce(sum(d.imp_tot),0)::numeric(18,2) as imp_tot
from public.t_dashboard_sales_daily d
where d.data between date_trunc('year', p_start::timestamp)::date
               and (date_trunc('year', p_end::timestamp) + interval '1 year - 1 day')::date
group by 1
on conflict (period_start) do update
  set qty_tot = excluded.qty_tot,
      imp_tot = excluded.imp_tot;

end;$$;

--
-- Name: refresh_dense_range(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_dense_range(p_start date, p_end date) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- aumenta un po' il timeout SOLO per questa chiamata (opzionale)
  -- se Supabase ti blocca, puoi alzare a 120s
  PERFORM set_config('statement_timeout', '120000', true);

  INSERT INTO public.greenhouse_sales_family_daily_dense (
    data, famiglia, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    fascia_corretta, categoria_corretta,
    pot_sizes_text, pot_sizes_json,
    articoli_inclusi, articoli_json
  )
  SELECT
    c.data,
    s.famiglia,
    s.fascia_prezzo_iva_inc,

    COALESCE(f.qty_venduta, 0),
    COALESCE(f.imponibile_netto_tot, 0),
    COALESCE(f.num_articoli, 0),

    COALESCE(f.fascia_corretta, s.fascia_corretta),
    COALESCE(f.categoria_corretta, s.categoria_corretta),

    COALESCE(f.pot_sizes_text, ''),
    COALESCE(f.pot_sizes_json, '[]'::jsonb),

    f.articoli_inclusi,
    COALESCE(f.articoli_json, '[]'::jsonb)

  FROM (
    SELECT gs::date AS data
    FROM generate_series(p_start, p_end, interval '1 day') gs
  ) c
  CROSS JOIN public.greenhouse_series_list_fact s
  LEFT JOIN (
    SELECT *
    FROM public.greenhouse_sales_family_daily_fact
    WHERE data BETWEEN p_start AND p_end
  ) f
    ON f.data = c.data
   AND f.famiglia = s.famiglia
   AND f.fascia_prezzo_iva_inc = s.fascia_prezzo_iva_inc

  ON CONFLICT (data, famiglia, fascia_prezzo_iva_inc)
  DO UPDATE SET
    qty_venduta = EXCLUDED.qty_venduta,
    imponibile_netto_tot = EXCLUDED.imponibile_netto_tot,
    num_articoli = EXCLUDED.num_articoli,
    fascia_corretta = EXCLUDED.fascia_corretta,
    categoria_corretta = EXCLUDED.categoria_corretta,
    pot_sizes_text = EXCLUDED.pot_sizes_text,
    pot_sizes_json = EXCLUDED.pot_sizes_json,
    articoli_inclusi = EXCLUDED.articoli_inclusi,
    articoli_json = EXCLUDED.articoli_json;
END;
$$;

--
-- Name: refresh_dense_range_from_fact(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_dense_range_from_fact(p_start date, p_end date) RETURNS void
    LANGUAGE sql
    AS $$
  INSERT INTO public.greenhouse_sales_family_daily_dense (
    data, famiglia, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    fascia_corretta, categoria_corretta,
    pot_sizes_text, pot_sizes_json,
    articoli_inclusi, articoli_json
  )
  SELECT
    c.data,
    s.famiglia,
    s.fascia_prezzo_iva_inc,

    COALESCE(f.qty_venduta, 0),
    COALESCE(f.imponibile_netto_tot, 0),
    COALESCE(f.num_articoli, 0),

    s.fascia_corretta,
    s.categoria_corretta,

    COALESCE(f.pot_sizes_text, ''),
    COALESCE(f.pot_sizes_json, '[]'::jsonb),

    f.articoli_inclusi,
    COALESCE(f.articoli_json, '[]'::jsonb)

  FROM (
    SELECT gs::date AS data
    FROM generate_series(p_start, p_end, interval '1 day') gs
  ) c
  CROSS JOIN public.greenhouse_series_list_fact s
  LEFT JOIN public.greenhouse_sales_family_daily_fact f
    ON f.data = c.data
   AND f.famiglia = s.famiglia
   AND f.fascia_prezzo_iva_inc = s.fascia_prezzo_iva_inc

  ON CONFLICT (data, famiglia, fascia_prezzo_iva_inc)
  DO UPDATE SET
    qty_venduta = EXCLUDED.qty_venduta,
    imponibile_netto_tot = EXCLUDED.imponibile_netto_tot,
    num_articoli = EXCLUDED.num_articoli,
    fascia_corretta = EXCLUDED.fascia_corretta,
    categoria_corretta = EXCLUDED.categoria_corretta,
    pot_sizes_text = EXCLUDED.pot_sizes_text,
    pot_sizes_json = EXCLUDED.pot_sizes_json,
    articoli_inclusi = EXCLUDED.articoli_inclusi,
    articoli_json = EXCLUDED.articoli_json;
$$;

--
-- Name: refresh_forecast_features_dense_range(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_forecast_features_dense_range(p_start date, p_end date) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_lb date;
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start > p_end THEN
    RAISE EXCEPTION 'range non valido: % - %', p_start, p_end;
  END IF;

  -- lookback per MA_28 e lag (serve contesto prima di p_start)
  v_lb := (p_start - INTERVAL '28 days')::date;

  PERFORM set_config('statement_timeout', '600000', true); -- 10 min

  INSERT INTO public.greenhouse_forecast_features_dense (
    data, famiglia, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    fascia_corretta, categoria_corretta,
    pot_sizes_text, pot_sizes_json,
    articoli_inclusi, articoli_json,
    tmin_c, tmax_c, tavg_c, rain_mm, sun_hours,
    is_holiday, holiday_name,
    dow, week_num, month_num, year_num,
    qty_lag_1, qty_lag_2, qty_lag_3, qty_lag_7, qty_lag_10, qty_lag_14,
    qty_ma_3, qty_ma_7, qty_ma_10, qty_ma_14, qty_ma_28,
    created_at, updated_at
  )
  WITH base AS (
    SELECT
      d.data, d.famiglia, d.fascia_prezzo_iva_inc,
      d.qty_venduta, d.imponibile_netto_tot, d.num_articoli,
      d.fascia_corretta, d.categoria_corretta,
      d.pot_sizes_text, d.pot_sizes_json,
      d.articoli_inclusi, d.articoli_json
    FROM public.greenhouse_sales_family_daily_dense d
    WHERE d.data BETWEEN v_lb AND p_end
  ),
  feat AS (
    SELECT
      b.*,
      w.tmin_c, w.tmax_c, w.tavg_c, w.rain_mm, w.sun_hours,
      COALESCE(h.is_holiday, false) AS is_holiday,
      h.holiday_name,
      EXTRACT(dow   FROM b.data)::int AS dow,
      EXTRACT(week  FROM b.data)::int AS week_num,
      EXTRACT(month FROM b.data)::int AS month_num,
      EXTRACT(year  FROM b.data)::int AS year_num,

      lag(b.qty_venduta, 1)  OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_1,
      lag(b.qty_venduta, 2)  OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_2,
      lag(b.qty_venduta, 3)  OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_3,
      lag(b.qty_venduta, 7)  OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_7,
      lag(b.qty_venduta, 10) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_10,
      lag(b.qty_venduta, 14) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_14,

      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 3  PRECEDING AND 1 PRECEDING) AS qty_ma_3,
      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 7  PRECEDING AND 1 PRECEDING) AS qty_ma_7,
      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 10 PRECEDING AND 1 PRECEDING) AS qty_ma_10,
      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS qty_ma_14,
      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING) AS qty_ma_28
    FROM base b
    LEFT JOIN public.greenhouse_weather_daily w ON w.data = b.data
    LEFT JOIN public.greenhouse_holidays h     ON h.data = b.data
  )
  SELECT
    data, famiglia, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    fascia_corretta, categoria_corretta,
    pot_sizes_text, pot_sizes_json,
    articoli_inclusi, articoli_json,
    tmin_c, tmax_c, tavg_c, rain_mm, sun_hours,
    is_holiday, holiday_name,
    dow, week_num, month_num, year_num,
    qty_lag_1, qty_lag_2, qty_lag_3, qty_lag_7, qty_lag_10, qty_lag_14,
    qty_ma_3, qty_ma_7, qty_ma_10, qty_ma_14, qty_ma_28,
    now(), now()
  FROM feat
  WHERE data BETWEEN p_start AND p_end
  ON CONFLICT (data, famiglia, fascia_prezzo_iva_inc)
  DO UPDATE SET
    qty_venduta = EXCLUDED.qty_venduta,
    imponibile_netto_tot = EXCLUDED.imponibile_netto_tot,
    num_articoli = EXCLUDED.num_articoli,
    fascia_corretta = EXCLUDED.fascia_corretta,
    categoria_corretta = EXCLUDED.categoria_corretta,
    pot_sizes_text = EXCLUDED.pot_sizes_text,
    pot_sizes_json = EXCLUDED.pot_sizes_json,
    articoli_inclusi = EXCLUDED.articoli_inclusi,
    articoli_json = EXCLUDED.articoli_json,
    tmin_c = EXCLUDED.tmin_c,
    tmax_c = EXCLUDED.tmax_c,
    tavg_c = EXCLUDED.tavg_c,
    rain_mm = EXCLUDED.rain_mm,
    sun_hours = EXCLUDED.sun_hours,
    is_holiday = EXCLUDED.is_holiday,
    holiday_name = EXCLUDED.holiday_name,
    dow = EXCLUDED.dow,
    week_num = EXCLUDED.week_num,
    month_num = EXCLUDED.month_num,
    year_num = EXCLUDED.year_num,
    qty_lag_1 = EXCLUDED.qty_lag_1,
    qty_lag_2 = EXCLUDED.qty_lag_2,
    qty_lag_3 = EXCLUDED.qty_lag_3,
    qty_lag_7 = EXCLUDED.qty_lag_7,
    qty_lag_10 = EXCLUDED.qty_lag_10,
    qty_lag_14 = EXCLUDED.qty_lag_14,
    qty_ma_3 = EXCLUDED.qty_ma_3,
    qty_ma_7 = EXCLUDED.qty_ma_7,
    qty_ma_10 = EXCLUDED.qty_ma_10,
    qty_ma_14 = EXCLUDED.qty_ma_14,
    qty_ma_28 = EXCLUDED.qty_ma_28,
    updated_at = now();
END;
$$;

--
-- Name: refresh_planner_week_and_roll4_tick(date, integer, integer, boolean, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.refresh_planner_week_and_roll4_tick(IN p_last_day date, IN p_week_buffer_days integer DEFAULT 14, IN p_roll4_weeks_per_run integer DEFAULT 2, IN p_force_potsize boolean DEFAULT false, IN p_potsize_years integer DEFAULT 5)
    LANGUAGE plpgsql
    AS $$
declare
  v_res jsonb;
  v_tick jsonb;
begin
  if p_last_day is null then
    raise exception 'p_last_day is required';
  end if;

  -- WEEK planner (incrementale robusto)
  v_res := public.core_planner__refresh_after_import(
    p_buffer_days := greatest(1, coalesce(p_week_buffer_days,14)),
    p_force_potsize := coalesce(p_force_potsize,false),
    p_potsize_years := greatest(1, coalesce(p_potsize_years,5))
  );

  if coalesce((v_res->>'ok')::boolean,false) is false then
    raise exception 'core_planner__refresh_after_import failed: %', coalesce(v_res->>'error','unknown');
  end if;

  -- ROLL4 tick (chunked)
  v_tick := public.core_planner__nightly_roll4_tick(greatest(1, coalesce(p_roll4_weeks_per_run,2)));

  if coalesce((v_tick->>'ok')::boolean,false) is false then
    raise exception 'core_planner__nightly_roll4_tick failed: %', coalesce(v_tick->>'error','unknown');
  end if;

end;
$$;

--
-- Name: rpc_heatmap_week_pivot(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_heatmap_week_pivot(metric text) RETURNS TABLE(fascia text, categoria text, famiglia text, fascia_prezzo text, node_id text, label text, w01 numeric, w02 numeric, w03 numeric, w04 numeric, w05 numeric, w06 numeric, w07 numeric, w08 numeric, w09 numeric, w10 numeric, w11 numeric, w12 numeric, w13 numeric, w14 numeric, w15 numeric, w16 numeric, w17 numeric, w18 numeric, w19 numeric, w20 numeric, w21 numeric, w22 numeric, w23 numeric, w24 numeric, w25 numeric, w26 numeric, w27 numeric, w28 numeric, w29 numeric, w30 numeric, w31 numeric, w32 numeric, w33 numeric, w34 numeric, w35 numeric, w36 numeric, w37 numeric, w38 numeric, w39 numeric, w40 numeric, w41 numeric, w42 numeric, w43 numeric, w44 numeric, w45 numeric, w46 numeric, w47 numeric, w48 numeric, w49 numeric, w50 numeric, w51 numeric, w52 numeric)
    LANGUAGE sql STABLE
    AS $$
  with base as (
    select
      fascia, categoria, famiglia, fascia_prezzo, node_id, label, week_52,
      case metric
        when 'avg_qty' then avg_qty
        when 'avg_rev' then avg_rev
        when 'share_rev' then share_rev
        when 'stock_target' then stock_target
        when 'space_m2' then space_m2
        else avg_qty
      end as v
    from public.t_core_planner__heat_cells
    where mode = 'week'
  )
  select
    fascia, categoria, famiglia, fascia_prezzo, node_id, label,
    max(v) filter (where week_52 = 1)  as w01,
    max(v) filter (where week_52 = 2)  as w02,
    max(v) filter (where week_52 = 3)  as w03,
    max(v) filter (where week_52 = 4)  as w04,
    max(v) filter (where week_52 = 5)  as w05,
    max(v) filter (where week_52 = 6)  as w06,
    max(v) filter (where week_52 = 7)  as w07,
    max(v) filter (where week_52 = 8)  as w08,
    max(v) filter (where week_52 = 9)  as w09,
    max(v) filter (where week_52 = 10) as w10,
    max(v) filter (where week_52 = 11) as w11,
    max(v) filter (where week_52 = 12) as w12,
    max(v) filter (where week_52 = 13) as w13,
    max(v) filter (where week_52 = 14) as w14,
    max(v) filter (where week_52 = 15) as w15,
    max(v) filter (where week_52 = 16) as w16,
    max(v) filter (where week_52 = 17) as w17,
    max(v) filter (where week_52 = 18) as w18,
    max(v) filter (where week_52 = 19) as w19,
    max(v) filter (where week_52 = 20) as w20,
    max(v) filter (where week_52 = 21) as w21,
    max(v) filter (where week_52 = 22) as w22,
    max(v) filter (where week_52 = 23) as w23,
    max(v) filter (where week_52 = 24) as w24,
    max(v) filter (where week_52 = 25) as w25,
    max(v) filter (where week_52 = 26) as w26,
    max(v) filter (where week_52 = 27) as w27,
    max(v) filter (where week_52 = 28) as w28,
    max(v) filter (where week_52 = 29) as w29,
    max(v) filter (where week_52 = 30) as w30,
    max(v) filter (where week_52 = 31) as w31,
    max(v) filter (where week_52 = 32) as w32,
    max(v) filter (where week_52 = 33) as w33,
    max(v) filter (where week_52 = 34) as w34,
    max(v) filter (where week_52 = 35) as w35,
    max(v) filter (where week_52 = 36) as w36,
    max(v) filter (where week_52 = 37) as w37,
    max(v) filter (where week_52 = 38) as w38,
    max(v) filter (where week_52 = 39) as w39,
    max(v) filter (where week_52 = 40) as w40,
    max(v) filter (where week_52 = 41) as w41,
    max(v) filter (where week_52 = 42) as w42,
    max(v) filter (where week_52 = 43) as w43,
    max(v) filter (where week_52 = 44) as w44,
    max(v) filter (where week_52 = 45) as w45,
    max(v) filter (where week_52 = 46) as w46,
    max(v) filter (where week_52 = 47) as w47,
    max(v) filter (where week_52 = 48) as w48,
    max(v) filter (where week_52 = 49) as w49,
    max(v) filter (where week_52 = 50) as w50,
    max(v) filter (where week_52 = 51) as w51,
    max(v) filter (where week_52 = 52) as w52
  from base
  group by fascia, categoria, famiglia, fascia_prezzo, node_id, label
  order by fascia nulls last, categoria nulls last, famiglia nulls last, fascia_prezzo nulls last, node_id;
$$;

--
-- Name: slugify_family(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.slugify_family(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select trim(both '-' from
    regexp_replace(
      regexp_replace(lower(trim(p)), '[^a-z0-9]+', '-', 'g'),
      '-{2,}', '-', 'g'
    )
  );
$$;

--
-- Name: trg_clean_famiglia_fact(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_clean_famiglia_fact() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.famiglia := public.gh_clean_famiglia_txt(NEW.famiglia);
  RETURN NEW;
END;
$$;

--
-- Name: trg_clean_famiglia_series_list(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_clean_famiglia_series_list() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.famiglia := public.gh_clean_famiglia_txt(NEW.famiglia);
  RETURN NEW;
END;
$$;

