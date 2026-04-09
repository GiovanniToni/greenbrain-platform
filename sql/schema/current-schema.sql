--
-- PostgreSQL database dump
--

\restrict ZuYoL18kYYYOlnoyZ34yiO5ALxPXDJRURYogWJ59vPtHrgXrOaN050s8Eg0qLLn

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.9 (Debian 17.9-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auth;


--
-- Name: pg_cron; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION pg_cron; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL';


--
-- Name: etl; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA etl;


--
-- Name: extensions; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA extensions;


--
-- Name: graphql; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA graphql;


--
-- Name: graphql_public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA graphql_public;


--
-- Name: ml_diag; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA ml_diag;


--
-- Name: ml_forecast; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA ml_forecast;


--
-- Name: ml_ops; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA ml_ops;


--
-- Name: pgbouncer; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA pgbouncer;


--
-- Name: realtime; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA realtime;


--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA storage;


--
-- Name: vault; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA vault;


--
-- Name: pg_graphql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA graphql;


--
-- Name: EXTENSION pg_graphql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_graphql IS 'pg_graphql: GraphQL support';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: supabase_vault; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;


--
-- Name: EXTENSION supabase_vault; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION supabase_vault IS 'Supabase Vault Extension';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: aal_level; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.aal_level AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


--
-- Name: code_challenge_method; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.code_challenge_method AS ENUM (
    's256',
    'plain'
);


--
-- Name: factor_status; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.factor_status AS ENUM (
    'unverified',
    'verified'
);


--
-- Name: factor_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.factor_type AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


--
-- Name: oauth_authorization_status; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_authorization_status AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


--
-- Name: oauth_client_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_client_type AS ENUM (
    'public',
    'confidential'
);


--
-- Name: oauth_registration_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_registration_type AS ENUM (
    'dynamic',
    'manual'
);


--
-- Name: oauth_response_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.oauth_response_type AS ENUM (
    'code'
);


--
-- Name: one_time_token_type; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.one_time_token_type AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


--
-- Name: action; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.action AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE',
    'TRUNCATE',
    'ERROR'
);


--
-- Name: equality_op; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.equality_op AS ENUM (
    'eq',
    'neq',
    'lt',
    'lte',
    'gt',
    'gte',
    'in'
);


--
-- Name: user_defined_filter; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.user_defined_filter AS (
	column_name text,
	op realtime.equality_op,
	value text
);


--
-- Name: wal_column; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.wal_column AS (
	name text,
	type_name text,
	type_oid oid,
	value jsonb,
	is_pkey boolean,
	is_selectable boolean
);


--
-- Name: wal_rls; Type: TYPE; Schema: realtime; Owner: -
--

CREATE TYPE realtime.wal_rls AS (
	wal jsonb,
	is_rls_enabled boolean,
	subscription_ids uuid[],
	errors text[]
);


--
-- Name: buckettype; Type: TYPE; Schema: storage; Owner: -
--

CREATE TYPE storage.buckettype AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


--
-- Name: email(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.email() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


--
-- Name: FUNCTION email(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.email() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';


--
-- Name: jwt(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


--
-- Name: FUNCTION role(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.role() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


--
-- Name: FUNCTION uid(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.uid() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';


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
-- Name: grant_pg_cron_access(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.grant_pg_cron_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;

    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  END IF;
END;
$$;


--
-- Name: FUNCTION grant_pg_cron_access(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.grant_pg_cron_access() IS 'Grants access to pg_cron';


--
-- Name: grant_pg_graphql_access(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.grant_pg_graphql_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    func_is_graphql_resolve bool;
BEGIN
    func_is_graphql_resolve = (
        SELECT n.proname = 'resolve'
        FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n
        ON ev.objid = n.oid
    );

    IF func_is_graphql_resolve
    THEN
        -- Update public wrapper to pass all arguments through to the pg_graphql resolve func
        DROP FUNCTION IF EXISTS graphql_public.graphql;
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language sql
        as $$
            select graphql.resolve(
                query := query,
                variables := coalesce(variables, '{}'),
                "operationName" := "operationName",
                extensions := extensions
            );
        $$;

        -- This hook executes when `graphql.resolve` is created. That is not necessarily the last
        -- function in the extension so we need to grant permissions on existing entities AND
        -- update default permissions to any others that are created after `graphql.resolve`
        grant usage on schema graphql to postgres, anon, authenticated, service_role;
        grant select on all tables in schema graphql to postgres, anon, authenticated, service_role;
        grant execute on all functions in schema graphql to postgres, anon, authenticated, service_role;
        grant all on all sequences in schema graphql to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on tables to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on functions to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on sequences to postgres, anon, authenticated, service_role;

        -- Allow postgres role to allow granting usage on graphql and graphql_public schemas to custom roles
        grant usage on schema graphql_public to postgres with grant option;
        grant usage on schema graphql to postgres with grant option;
    END IF;

END;
$_$;


--
-- Name: FUNCTION grant_pg_graphql_access(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.grant_pg_graphql_access() IS 'Grants access to pg_graphql';


--
-- Name: grant_pg_net_access(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.grant_pg_net_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$$;


--
-- Name: FUNCTION grant_pg_net_access(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.grant_pg_net_access() IS 'Grants access to pg_net';


--
-- Name: pgrst_ddl_watch(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.pgrst_ddl_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


--
-- Name: pgrst_drop_watch(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.pgrst_drop_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


--
-- Name: set_graphql_placeholder(); Type: FUNCTION; Schema: extensions; Owner: -
--

CREATE FUNCTION extensions.set_graphql_placeholder() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$_$;


--
-- Name: FUNCTION set_graphql_placeholder(); Type: COMMENT; Schema: extensions; Owner: -
--

COMMENT ON FUNCTION extensions.set_graphql_placeholder() IS 'Reintroduces placeholder function for graphql_public.graphql';


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
-- Name: refresh_foundations_and_registry_v1(); Type: FUNCTION; Schema: ml_ops; Owner: -
--

CREATE FUNCTION ml_ops.refresh_foundations_and_registry_v1() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
    refresh materialized view ml_diag.mv_family_day_base;
    refresh materialized view ml_diag.mv_family_stats;
    refresh materialized view ml_diag.mv_family_metrics_v5;
    refresh materialized view ml_diag.mv_family_importance;
    refresh materialized view ml_diag.mv_family_intermittency;

    -- la v_family_diagnostics_v7_2_quater e' una view, quindi non si refresh-a:
    -- viene ricalcolata leggendo gli oggetti sopra.

    perform ml_forecast.refresh_family_model_registry_v2();
    perform ml_forecast.sync_family_model_state_v1();
end;
$$;


--
-- Name: get_auth(text); Type: FUNCTION; Schema: pgbouncer; Owner: -
--

CREATE FUNCTION pgbouncer.get_auth(p_usename text) RETURNS TABLE(username text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
  BEGIN
      RAISE DEBUG 'PgBouncer auth request: %', p_usename;

      RETURN QUERY
      SELECT
          rolname::text,
          CASE WHEN rolvaliduntil < now()
              THEN null
              ELSE rolpassword::text
          END
      FROM pg_authid
      WHERE rolname=$1 and rolcanlogin;
  END;
  $_$;


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
-- Name: core_analytics__future_window_stats_v2(text, text, date, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__future_window_stats_v2(p_entity_type text, p_entity_key text, p_anchor_to date DEFAULT CURRENT_DATE, p_windows integer[] DEFAULT ARRAY[7, 14, 30, 60]) RETURNS TABLE(window_days integer, min_qty numeric, max_qty numeric, avg_qty numeric)
    LANGUAGE plpgsql STABLE
    AS $$declare
  m int := extract(month from p_anchor_to)::int;
  d int := extract(day from p_anchor_to)::int;
begin
  -- finestra anni: dagli anni presenti nei dati (ultimi 20 bastano)
  return query
  with years as (
    select generate_series(extract(year from (p_anchor_to - interval '20 years'))::int,
                           extract(year from p_anchor_to)::int - 1) as y
  ),
  starts as (
    select
      y,
      -- giorno “safe” (gestisce 29 feb ecc)
      (make_date(y, m, 1)
        + (least(
            d,
            extract(day from (date_trunc('month', make_date(y,m,1)) + interval '1 month - 1 day'))::int
          ) - 1
         ) * interval '1 day'
      )::date as start_date
    from years
  ),
  w as (select unnest(p_windows)::int as window_days),
  base as (
    select
      w.window_days,
      s.y,
      (
        case
          when p_entity_type = 'famiglia' then (
            select coalesce(sum(qty_venduta_tot),0)
            from public.t_core_analytics__series_daily_famiglia t
            where lower(t.entity_key) = lower(p_entity_key)
              and t.data > s.start_date
              and t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          when p_entity_type = 'categoria' then (
            select coalesce(sum(qty_venduta_tot),0)
            from public.mv_core_analytics__series_daily_categoria t
            where lower(t.entity_key) = lower(p_entity_key)
              and t.data > s.start_date
              and t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          when p_entity_type = 'fascia' then (
            select coalesce(sum(qty_venduta_tot),0)
            from public.mv_core_analytics__series_daily_fascia t
            where lower(t.entity_key) = lower(p_entity_key)
              and t.data > s.start_date
              and t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          when p_entity_type = 'fascia_prezzo' then (
            select coalesce(sum(qty_venduta_tot),0)
            from public.mv_core_analytics__series_daily_fascia_prezzo t
            where lower(t.entity_key) = lower(p_entity_key)
              and t.data > s.start_date
              and t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          else 0
        end
      )::numeric as qty
    from starts s
    cross join w
  )
  select
    base.window_days as window_days,
    min(base.qty) as min_qty,
    max(base.qty) as max_qty,
    avg(base.qty) as avg_qty
  from base
  group by base.window_days
  order by base.window_days;
end$$;


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
-- Name: core_analytics__search_catalog_rich(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__search_catalog_rich(term text, limit_n integer DEFAULT 50) RETURNS TABLE(entity_type text, entity_key text, label text, score real, fascia text, categoria text, famiglia text, fascia_prezzo text, codart text, articolo_nome text, pot_size text, prezzo_iva_inclusa numeric)
    LANGUAGE sql STABLE
    AS $$
with params as (
  select
    lower(trim(term)) as t,
    greatest(coalesce(limit_n, 50), 1) as lim
),

-- ======================================================
-- ENTITÀ (fascia / categoria / famiglia / fascia_prezzo)
-- pesca dalla MV indicizzata
-- ======================================================
base_entities as (
  select
    e.entity_type::text as entity_type,
    e.entity_key::text  as entity_key,
    e.label::text       as label,
    similarity(lower(e.label), p.t)::real as score,
    e.fascia::text        as fascia,
    e.categoria::text     as categoria,
    e.famiglia::text      as famiglia,
    e.fascia_prezzo::text as fascia_prezzo,
    null::text    as codart,
    null::text    as articolo_nome,
    null::text    as pot_size,
    null::numeric as prezzo_iva_inclusa
  from public.mv_core_analytics__catalog_entities e
  cross join params p
  where e.label is not null
    and (
      lower(e.label) % p.t
      or lower(e.label) like '%' || p.t || '%'
    )
),

-- =========================
-- ARTICOLI
-- =========================
base_articles as (
  select
    'articolo'::text as entity_type,
    a.codart as entity_key,
    (a.codart || ' — ' || coalesce(a.articolo_nome,'(senza descrizione)')) as label,
    greatest(
      similarity(lower(a.codart), p.t),
      similarity(lower(coalesce(a.articolo_nome,'')), p.t)
    )::real as score,
    a.fascia_corretta        as fascia,
    a.categoria_corretta     as categoria,
    a.famiglia               as famiglia,
    a.fascia_prezzo_iva_inc  as fascia_prezzo,
    a.codart,
    a.articolo_nome,
    a.pot_size,
    a.prezzo_iva_inclusa
  from public.core_analytics__components_articles a
  cross join params p
  where a.codart is not null
    and (
      lower(a.codart) % p.t
      or lower(a.codart) like '%' || p.t || '%'
      or lower(coalesce(a.articolo_nome,'')) % p.t
      or lower(coalesce(a.articolo_nome,'')) like '%' || p.t || '%'
    )
),

-- =========================
-- UNION + RANK
-- =========================
all_hits as (
  select * from base_entities
  union all
  select * from base_articles
),

ranked as (
  select
    *,
    row_number() over (order by score desc, label asc) as rn
  from all_hits
)

select
  entity_type,
  entity_key,
  label,
  score,
  fascia,
  categoria,
  famiglia,
  fascia_prezzo,
  codart,
  articolo_nome,
  pot_size,
  prezzo_iva_inclusa
from ranked, params p
where rn <= p.lim
order by score desc, label asc;
$$;


--
-- Name: core_analytics__seasonality_month_v2(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.core_analytics__seasonality_month_v2(p_entity_type text, p_entity_key text) RETURNS TABLE(month_num integer, avg_qty_per_day numeric, sum_qty numeric, avg_rev_per_day numeric, sum_rev numeric)
    LANGUAGE plpgsql STABLE
    AS $$
begin
  if p_entity_type = 'famiglia' then
    return query
    select
      extract(month from data)::int as month_num,
      (sum(qty_venduta_tot) / nullif(count(*),0))::numeric as avg_qty_per_day,
      sum(qty_venduta_tot)::numeric as sum_qty,
      (sum(imponibile_netto_tot) / nullif(count(*),0))::numeric as avg_rev_per_day,
      sum(imponibile_netto_tot)::numeric as sum_rev
    from public.t_core_analytics__series_daily_famiglia
    where lower(entity_key) = lower(p_entity_key)
    group by 1
    order by 1;

  elsif p_entity_type = 'categoria' then
    return query
    select
      extract(month from data)::int,
      (sum(qty_venduta_tot) / nullif(count(*),0))::numeric,
      sum(qty_venduta_tot)::numeric,
      (sum(imponibile_netto_tot) / nullif(count(*),0))::numeric,
      sum(imponibile_netto_tot)::numeric
    from public.mv_core_analytics__series_daily_categoria
    where lower(entity_key) = lower(p_entity_key)
    group by 1
    order by 1;

  elsif p_entity_type = 'fascia' then
    return query
    select
      extract(month from data)::int,
      (sum(qty_venduta_tot) / nullif(count(*),0))::numeric,
      sum(qty_venduta_tot)::numeric,
      (sum(imponibile_netto_tot) / nullif(count(*),0))::numeric,
      sum(imponibile_netto_tot)::numeric
    from public.mv_core_analytics__series_daily_fascia
    where lower(entity_key) = lower(p_entity_key)
    group by 1
    order by 1;

  elsif p_entity_type = 'fascia_prezzo' then
    return query
    select
      extract(month from data)::int,
      (sum(qty_venduta_tot) / nullif(count(*),0))::numeric,
      sum(qty_venduta_tot)::numeric,
      (sum(imponibile_netto_tot) / nullif(count(*),0))::numeric,
      sum(imponibile_netto_tot)::numeric
    from public.mv_core_analytics__series_daily_fascia_prezzo
    where lower(entity_key) = lower(p_entity_key)
    group by 1
    order by 1;

  else
    return;
  end if;
end $$;


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
-- Name: VIEW greenhouse_order_suggestions_enriched_v2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.greenhouse_order_suggestions_enriched_v2 IS 'touch';


--
-- Name: get_order_suggestions_enriched_v2(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_order_suggestions_enriched_v2() RETURNS SETOF public.greenhouse_order_suggestions_enriched_v2
    LANGUAGE sql STABLE
    AS $$
  select * from public.greenhouse_order_suggestions_enriched_v2;
$$;


--
-- Name: FUNCTION get_order_suggestions_enriched_v2(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_order_suggestions_enriched_v2() IS 'touch';


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
-- Name: refresh_analytics_rollups_range(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_analytics_rollups_range(p_start date, p_end date) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  w_start date;
  w_end_excl date;  -- exclusive end (Mon after last week)
  m_start date;
  m_end_excl date;  -- exclusive end (1st of month after last month)
begin
  if p_start is null or p_end is null or p_start > p_end then
    raise exception 'Invalid range: % - %', p_start, p_end;
  end if;

  -- week boundaries (Mon start), HALF-OPEN [w_start, w_end_excl)
  w_start := date_trunc('week', p_start)::date;
  w_end_excl := (date_trunc('week', p_end)::date + 7);

  -- month boundaries, HALF-OPEN [m_start, m_end_excl)
  m_start := date_trunc('month', p_start)::date;
  m_end_excl := (date_trunc('month', p_end)::date + interval '1 month')::date;

  -- =========================
  -- WEEKLY SERIES (from daily)  [w_start, w_end_excl)
  -- =========================

  -- FAMIGLIA
  insert into public.t_core_analytics__series_weekly_famiglia(period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot)
  select
    date_trunc('week', d.data)::date as period_start,
    d.entity_key as entity_key,
    sum(d.qty_venduta_tot) as qty_venduta_tot,
    sum(d.imponibile_netto_tot) as imponibile_netto_tot,
    sum(coalesce(d.qty_forecast_tot,0)) as qty_forecast_tot
  from public.t_core_analytics__series_daily_famiglia d
  where d.data >= w_start and d.data < w_end_excl
  group by 1,2
  on conflict (period_start, entity_key) do update
  set qty_venduta_tot = excluded.qty_venduta_tot,
      imponibile_netto_tot = excluded.imponibile_netto_tot,
      qty_forecast_tot = excluded.qty_forecast_tot;

  -- CATEGORIA
  insert into public.t_core_analytics__series_weekly_categoria(period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot)
  select
    date_trunc('week', d.data)::date,
    d.entity_key,
    sum(d.qty_venduta_tot),
    sum(d.imponibile_netto_tot),
    sum(coalesce(d.qty_forecast_tot,0))
  from public.t_core_analytics__series_daily_categoria d
  where d.data >= w_start and d.data < w_end_excl
  group by 1,2
  on conflict (period_start, entity_key) do update
  set qty_venduta_tot = excluded.qty_venduta_tot,
      imponibile_netto_tot = excluded.imponibile_netto_tot,
      qty_forecast_tot = excluded.qty_forecast_tot;

  -- FASCIA
  insert into public.t_core_analytics__series_weekly_fascia(period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot)
  select
    date_trunc('week', d.data)::date,
    d.entity_key,
    sum(d.qty_venduta_tot),
    sum(d.imponibile_netto_tot),
    sum(coalesce(d.qty_forecast_tot,0))
  from public.t_core_analytics__series_daily_fascia d
  where d.data >= w_start and d.data < w_end_excl
  group by 1,2
  on conflict (period_start, entity_key) do update
  set qty_venduta_tot = excluded.qty_venduta_tot,
      imponibile_netto_tot = excluded.imponibile_netto_tot,
      qty_forecast_tot = excluded.qty_forecast_tot;

  -- FASCIA PREZZO
  insert into public.t_core_analytics__series_weekly_fascia_prezzo(period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot)
  select
    date_trunc('week', d.data)::date,
    d.entity_key,
    sum(d.qty_venduta_tot),
    sum(d.imponibile_netto_tot),
    sum(coalesce(d.qty_forecast_tot,0))
  from public.t_core_analytics__series_daily_fascia_prezzo d
  where d.data >= w_start and d.data < w_end_excl
  group by 1,2
  on conflict (period_start, entity_key) do update
  set qty_venduta_tot = excluded.qty_venduta_tot,
      imponibile_netto_tot = excluded.imponibile_netto_tot,
      qty_forecast_tot = excluded.qty_forecast_tot;

  -- =========================
  -- WEEKLY BREAKDOWN (from daily breakdown) [w_start, w_end_excl)
  -- =========================

  -- FAMIGLIA -> FP
  insert into public.t_core_analytics__breakdown_weekly_famiglia_fp(period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, qty_forecast)
  select
    date_trunc('week', b.data)::date,
    b.entity_key_lc,
    b.fascia_prezzo_iva_inc,
    sum(b.qty_venduta)::numeric(18,3),
    sum(coalesce(b.qty_forecast,0))::numeric(18,3)
  from public.t_core_analytics__breakdown_daily_famiglia_fp b
  where b.data >= w_start and b.data < w_end_excl
  group by 1,2,3
  on conflict (period_start, entity_key_lc, fascia_prezzo_iva_inc) do update
  set qty_venduta = excluded.qty_venduta,
      qty_forecast = excluded.qty_forecast;

  -- CATEGORIA -> FP
  insert into public.t_core_analytics__breakdown_weekly_categoria_fp(period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, qty_forecast)
  select
    date_trunc('week', b.data)::date,
    b.entity_key_lc,
    b.fascia_prezzo_iva_inc,
    sum(b.qty_venduta)::numeric(18,3),
    sum(coalesce(b.qty_forecast,0))::numeric(18,3)
  from public.t_core_analytics__breakdown_daily_categoria_fp b
  where b.data >= w_start and b.data < w_end_excl
  group by 1,2,3
  on conflict (period_start, entity_key_lc, fascia_prezzo_iva_inc) do update
  set qty_venduta = excluded.qty_venduta,
      qty_forecast = excluded.qty_forecast;

  -- FASCIA -> FP (se la MV esiste)
  insert into public.t_core_analytics__breakdown_weekly_fascia_fp(period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, qty_forecast)
  select
    date_trunc('week', b.data)::date,
    b.entity_key_lc,
    b.fascia_prezzo_iva_inc,
    sum(b.qty_venduta)::numeric(18,3),
    sum(coalesce(b.qty_forecast,0))::numeric(18,3)
  from public.mv_core_analytics__breakdown_daily_fascia_fp b
  where b.data >= w_start and b.data < w_end_excl
  group by 1,2,3
  on conflict (period_start, entity_key_lc, fascia_prezzo_iva_inc) do update
  set qty_venduta = excluded.qty_venduta,
      qty_forecast = excluded.qty_forecast;

  -- =========================
  -- MONTHLY SERIES [m_start, m_end_excl)
  -- =========================

  insert into public.t_core_analytics__series_monthly_famiglia(period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot)
  select
    date_trunc('month', d.data)::date,
    d.entity_key,
    sum(d.qty_venduta_tot),
    sum(d.imponibile_netto_tot),
    sum(coalesce(d.qty_forecast_tot,0))
  from public.t_core_analytics__series_daily_famiglia d
  where d.data >= m_start and d.data < m_end_excl
  group by 1,2
  on conflict (period_start, entity_key) do update
  set qty_venduta_tot = excluded.qty_venduta_tot,
      imponibile_netto_tot = excluded.imponibile_netto_tot,
      qty_forecast_tot = excluded.qty_forecast_tot;

  insert into public.t_core_analytics__series_monthly_categoria(period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot)
  select
    date_trunc('month', d.data)::date,
    d.entity_key,
    sum(d.qty_venduta_tot),
    sum(d.imponibile_netto_tot),
    sum(coalesce(d.qty_forecast_tot,0))
  from public.t_core_analytics__series_daily_categoria d
  where d.data >= m_start and d.data < m_end_excl
  group by 1,2
  on conflict (period_start, entity_key) do update
  set qty_venduta_tot = excluded.qty_venduta_tot,
      imponibile_netto_tot = excluded.imponibile_netto_tot,
      qty_forecast_tot = excluded.qty_forecast_tot;

  insert into public.t_core_analytics__series_monthly_fascia(period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot)
  select
    date_trunc('month', d.data)::date,
    d.entity_key,
    sum(d.qty_venduta_tot),
    sum(d.imponibile_netto_tot),
    sum(coalesce(d.qty_forecast_tot,0))
  from public.t_core_analytics__series_daily_fascia d
  where d.data >= m_start and d.data < m_end_excl
  group by 1,2
  on conflict (period_start, entity_key) do update
  set qty_venduta_tot = excluded.qty_venduta_tot,
      imponibile_netto_tot = excluded.imponibile_netto_tot,
      qty_forecast_tot = excluded.qty_forecast_tot;

  insert into public.t_core_analytics__series_monthly_fascia_prezzo(period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot)
  select
    date_trunc('month', d.data)::date,
    d.entity_key,
    sum(d.qty_venduta_tot),
    sum(d.imponibile_netto_tot),
    sum(coalesce(d.qty_forecast_tot,0))
  from public.t_core_analytics__series_daily_fascia_prezzo d
  where d.data >= m_start and d.data < m_end_excl
  group by 1,2
  on conflict (period_start, entity_key) do update
  set qty_venduta_tot = excluded.qty_venduta_tot,
      imponibile_netto_tot = excluded.imponibile_netto_tot,
      qty_forecast_tot = excluded.qty_forecast_tot;

  -- =========================
  -- MONTHLY BREAKDOWN [m_start, m_end_excl)
  -- =========================

  insert into public.t_core_analytics__breakdown_monthly_famiglia_fp(period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, qty_forecast)
  select
    date_trunc('month', b.data)::date,
    b.entity_key_lc,
    b.fascia_prezzo_iva_inc,
    sum(b.qty_venduta)::numeric(18,3),
    sum(coalesce(b.qty_forecast,0))::numeric(18,3)
  from public.t_core_analytics__breakdown_daily_famiglia_fp b
  where b.data >= m_start and b.data < m_end_excl
  group by 1,2,3
  on conflict (period_start, entity_key_lc, fascia_prezzo_iva_inc) do update
  set qty_venduta = excluded.qty_venduta,
      qty_forecast = excluded.qty_forecast;

  insert into public.t_core_analytics__breakdown_monthly_categoria_fp(period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, qty_forecast)
  select
    date_trunc('month', b.data)::date,
    b.entity_key_lc,
    b.fascia_prezzo_iva_inc,
    sum(b.qty_venduta)::numeric(18,3),
    sum(coalesce(b.qty_forecast,0))::numeric(18,3)
  from public.t_core_analytics__breakdown_daily_categoria_fp b
  where b.data >= m_start and b.data < m_end_excl
  group by 1,2,3
  on conflict (period_start, entity_key_lc, fascia_prezzo_iva_inc) do update
  set qty_venduta = excluded.qty_venduta,
      qty_forecast = excluded.qty_forecast;

  insert into public.t_core_analytics__breakdown_monthly_fascia_fp(period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, qty_forecast)
  select
    date_trunc('month', b.data)::date,
    b.entity_key_lc,
    b.fascia_prezzo_iva_inc,
    sum(b.qty_venduta)::numeric(18,3),
    sum(coalesce(b.qty_forecast,0))::numeric(18,3)
  from public.mv_core_analytics__breakdown_daily_fascia_fp b
  where b.data >= m_start and b.data < m_end_excl
  group by 1,2,3
  on conflict (period_start, entity_key_lc, fascia_prezzo_iva_inc) do update
  set qty_venduta = excluded.qty_venduta,
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
-- Name: run_greenhouse_daily_pipeline_full(integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.run_greenhouse_daily_pipeline_full(IN p_rebuild_days integer DEFAULT 40, IN p_week_buffer_days integer DEFAULT 14, IN p_roll4_weeks_per_run integer DEFAULT 2)
    LANGUAGE plpgsql
    AS $$
declare
  v_run_id uuid;
  v_step bigint;

  v_target_last date;
  v_start_day date;

  v_post jsonb;
  v_lock_ok boolean;

  v_rows_daily bigint := 0;
  v_rows_weekly bigint := 0;
  v_rows_monthly bigint := 0;

  -- gate raw
  v_raw_last_load_ts timestamptz;
  v_raw_stable boolean := false;

  -- planner step output (optional)
  v_planner_step jsonb;
begin
  -- Anti-overlap lock (pipeline unica)
  v_lock_ok := pg_try_advisory_lock(hashtext('run_greenhouse_daily_pipeline_full'));
  if not v_lock_ok then
    v_run_id := etl._start_run(
      'greenhouse_daily_full',
      jsonb_build_object('skipped',true,'reason','already_running')
    );
    call etl._end_run(v_run_id, 'skipped', 'already_running');
    return;
  end if;

  -- NO TIMEOUT per tutta la run
  begin
    execute 'set local statement_timeout = 0';
  exception when others then
    null;
  end;

  v_run_id := etl._start_run(
    'greenhouse_daily_full',
    jsonb_build_object(
      'rebuild_days', p_rebuild_days,
      'week_buffer_days', p_week_buffer_days,
      'roll4_weeks_per_run', p_roll4_weeks_per_run
    )
  );

  begin
    /* ---------------------------
       A) Determina range target
       --------------------------- */
    v_step := etl._start_step(v_run_id, 'A) detect_target_last_from_raw');

    select
      max(s.data_movimento)::date,
      max(s.load_timestamp)::timestamptz
    into
      v_target_last,
      v_raw_last_load_ts
    from public.greenhouse_sales_raw s;

    if v_target_last is null then
      call etl._end_step(v_step,'failed','sales_raw empty');
      raise exception 'sales_raw empty: cannot compute target_last';
    end if;

    -- safety: se load_timestamp fosse NULL (caso raro), non bloccare la pipeline per quello
    if v_raw_last_load_ts is null then
      v_raw_last_load_ts := now() - interval '1 day';
    end if;

    v_start_day := v_target_last - (greatest(1,p_rebuild_days) - 1);

    call etl._end_step(
      v_step,'success','OK',
      jsonb_build_object(
        'target_last',v_target_last,
        'start_day',v_start_day,
        'raw_last_load_ts', v_raw_last_load_ts
      )
    );

    /* ---------------------------
       A2) RAW STABLE GATE (20 minutes)
       Se RAW ha scritto negli ultimi 20 minuti -> SKIP
       --------------------------- */
    v_step := etl._start_step(v_run_id, 'A2) raw_stable_gate_20m');

    v_raw_stable := (now() - v_raw_last_load_ts) >= interval '20 minutes';

    if not v_raw_stable then
      call etl._end_step(
        v_step,
        'skipped',
        'raw_still_loading',
        jsonb_build_object(
          'raw_last_load_ts', v_raw_last_load_ts,
          'since_last_raw_write', (now() - v_raw_last_load_ts),
          'required_stability', '20 minutes'
        )
      );

      call etl._end_run(
        v_run_id,
        'skipped',
        'raw_still_loading',
        jsonb_build_object(
          'target_last', v_target_last,
          'raw_last_load_ts', v_raw_last_load_ts,
          'required_stability', '20 minutes'
        )
      );

      perform pg_advisory_unlock(hashtext('run_greenhouse_daily_pipeline_full'));
      return;
    end if;

    call etl._end_step(
      v_step,
      'success',
      'OK',
      jsonb_build_object(
        'raw_last_load_ts', v_raw_last_load_ts,
        'since_last_raw_write', (now() - v_raw_last_load_ts),
        'required_stability', '20 minutes'
      )
    );

    /* ---------------------------
       B) daily_etl_postprocess_v3
       (fact rebuild + dense + features dense + analytics aggregates)
       --------------------------- */
    v_step := etl._start_step(v_run_id, 'B) daily_etl_postprocess_v3');

    select to_jsonb(x)
    into v_post
    from public.daily_etl_postprocess_v3(p_rebuild_days) x;

    call etl._end_step(v_step,'success','OK',coalesce(v_post,'{}'::jsonb));

    /* ---------------------------
       B2) DASHBOARD refresh da DENSE
       --------------------------- */
    v_step := etl._start_step(v_run_id, 'B2) dashboard_refresh_from_dense');

    -- DAILY
    with d as (
      select
        g.data,
        sum(g.qty_venduta)::numeric(18,3) as qty_tot,
        sum(g.imponibile_netto_tot)::numeric(18,2) as imp_tot,
        sum(g.num_articoli)::int as num_articoli_tot
      from public.greenhouse_sales_family_daily_dense g
      where g.data between v_start_day and v_target_last
      group by g.data
    ),
    up as (
      insert into public.t_dashboard_sales_daily (data, qty_tot, imp_tot, num_articoli_tot)
      select data, qty_tot, imp_tot, num_articoli_tot
      from d
      on conflict (data) do update
        set qty_tot = excluded.qty_tot,
            imp_tot = excluded.imp_tot,
            num_articoli_tot = excluded.num_articoli_tot
      returning 1
    )
    select count(*) into v_rows_daily from up;

    -- WEEKLY
    with w as (
      select
        date_trunc('week', g.data)::date as period_start,
        sum(g.qty_venduta)::numeric(18,3) as qty_tot,
        sum(g.imponibile_netto_tot)::numeric(18,2) as imp_tot
      from public.greenhouse_sales_family_daily_dense g
      where g.data between v_start_day and v_target_last
      group by date_trunc('week', g.data)::date
    ),
    up as (
      insert into public.t_dashboard_sales_weekly (period_start, qty_tot, imp_tot)
      select period_start, qty_tot, imp_tot
      from w
      on conflict (period_start) do update
        set qty_tot = excluded.qty_tot,
            imp_tot = excluded.imp_tot
      returning 1
    )
    select count(*) into v_rows_weekly from up;

    -- MONTHLY
    with m as (
      select
        date_trunc('month', g.data)::date as period_start,
        sum(g.qty_venduta)::numeric(18,3) as qty_tot,
        sum(g.imponibile_netto_tot)::numeric(18,2) as imp_tot
      from public.greenhouse_sales_family_daily_dense g
      where g.data between v_start_day and v_target_last
      group by date_trunc('month', g.data)::date
    ),
    up as (
      insert into public.t_dashboard_sales_monthly (period_start, qty_tot, imp_tot)
      select period_start, qty_tot, imp_tot
      from m
      on conflict (period_start) do update
        set qty_tot = excluded.qty_tot,
            imp_tot = excluded.imp_tot
      returning 1
    )
    select count(*) into v_rows_monthly from up;

    call etl._end_step(
      v_step,
      'success',
      'OK',
      jsonb_build_object(
        'range', jsonb_build_object('from', v_start_day, 'to', v_target_last),
        'upserted', jsonb_build_object(
          'daily', v_rows_daily,
          'weekly', v_rows_weekly,
          'monthly', v_rows_monthly
        )
      )
    );

    /* ---------------------------
       C0) refresh MV breakdown fascia (serve per rollups fascia->fp)
       --------------------------- */
    v_step := etl._start_step(v_run_id, 'C0) refresh MV breakdown_daily_fascia_fp');

    begin
      execute 'REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_core_analytics__breakdown_daily_fascia_fp';
      call etl._end_step(v_step,'success','OK');
    exception when others then
      begin
        execute 'REFRESH MATERIALIZED VIEW public.mv_core_analytics__breakdown_daily_fascia_fp';
        call etl._end_step(v_step,'success','OK (fallback non-concurrent)');
      exception when others then
        call etl._end_step(v_step,'failed',sqlerrm);
        raise;
      end;
    end;

    /* ---------------------------
       C) refresh_analytics_rollups_range
       --------------------------- */
    v_step := etl._start_step(v_run_id, 'C) refresh_analytics_rollups_range');
    perform public.refresh_analytics_rollups_range(v_start_day, v_target_last);
    call etl._end_step(v_step,'success','OK');

    /* ---------------------------
       D) dashboard optional (non serve più)
       --------------------------- */
    v_step := etl._start_step(v_run_id, 'D) dashboard_refresh_optional');
    call etl._end_step(v_step,'skipped','dashboard handled in B2');

    /* ---------------------------
       E) Planner week + roll4 tick (legacy)
       --------------------------- */
    v_step := etl._start_step(v_run_id, 'E) planner_week + roll4_tick');

    call public.refresh_planner_week_and_roll4_tick(
      p_last_day := v_target_last,
      p_week_buffer_days := p_week_buffer_days,
      p_roll4_weeks_per_run := p_roll4_weeks_per_run,
      p_force_potsize := false,
      p_potsize_years := 5
    );

    call etl._end_step(v_step,'success','OK');

    /* ---------------------------
       E2) Planner after_import STEP (no timeout upstream)
       --------------------------- */
    v_step := etl._start_step(v_run_id, 'E2) planner_after_import_step');

    select public.core_planner__refresh_after_import_step(
      p_buffer_days := p_week_buffer_days,
      p_weeks_per_run := p_roll4_weeks_per_run,
      p_force_potsize := false,
      p_potsize_years := 5,
      p_run_derived_on_cycle := true
    )
    into v_planner_step;

    call etl._end_step(
      v_step,
      'success',
      'OK',
      coalesce(v_planner_step,'{}'::jsonb)
    );

    /* ---------------------------
       DONE
       --------------------------- */
    call etl._end_run(
      v_run_id,
      'success',
      'OK',
      jsonb_build_object(
        'target_last', v_target_last,
        'start_day', v_start_day,
        'rebuild_days', p_rebuild_days,
        'week_buffer_days', p_week_buffer_days,
        'roll4_weeks_per_run', p_roll4_weeks_per_run,
        'raw_last_load_ts', v_raw_last_load_ts,
        'dashboard_upserted', jsonb_build_object(
          'daily', v_rows_daily,
          'weekly', v_rows_weekly,
          'monthly', v_rows_monthly
        ),
        'planner_after_import_step', v_planner_step
      )
    );

  exception when others then
    call etl._end_run(v_run_id,'failed',sqlerrm,null);
    raise;
  end;

  perform pg_advisory_unlock(hashtext('run_greenhouse_daily_pipeline_full'));

exception when others then
  begin
    perform pg_advisory_unlock(hashtext('run_greenhouse_daily_pipeline_full'));
  exception when others then
    null;
  end;
  raise;
end;
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


--
-- Name: apply_rls(jsonb, integer); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer DEFAULT (1024 * 1024)) RETURNS SETOF realtime.wal_rls
    LANGUAGE plpgsql
    AS $$
declare
-- Regclass of the table e.g. public.notes
entity_ regclass = (quote_ident(wal ->> 'schema') || '.' || quote_ident(wal ->> 'table'))::regclass;

-- I, U, D, T: insert, update ...
action realtime.action = (
    case wal ->> 'action'
        when 'I' then 'INSERT'
        when 'U' then 'UPDATE'
        when 'D' then 'DELETE'
        else 'ERROR'
    end
);

-- Is row level security enabled for the table
is_rls_enabled bool = relrowsecurity from pg_class where oid = entity_;

subscriptions realtime.subscription[] = array_agg(subs)
    from
        realtime.subscription subs
    where
        subs.entity = entity_
        -- Filter by action early - only get subscriptions interested in this action
        -- action_filter column can be: '*' (all), 'INSERT', 'UPDATE', or 'DELETE'
        and (subs.action_filter = '*' or subs.action_filter = action::text);

-- Subscription vars
roles regrole[] = array_agg(distinct us.claims_role::text)
    from
        unnest(subscriptions) us;

working_role regrole;
claimed_role regrole;
claims jsonb;

subscription_id uuid;
subscription_has_access bool;
visible_to_subscription_ids uuid[] = '{}';

-- structured info for wal's columns
columns realtime.wal_column[];
-- previous identity values for update/delete
old_columns realtime.wal_column[];

error_record_exceeds_max_size boolean = octet_length(wal::text) > max_record_bytes;

-- Primary jsonb output for record
output jsonb;

begin
perform set_config('role', null, true);

columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'columns') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

old_columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'identity') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

for working_role in select * from unnest(roles) loop

    -- Update `is_selectable` for columns and old_columns
    columns =
        array_agg(
            (
                c.name,
                c.type_name,
                c.type_oid,
                c.value,
                c.is_pkey,
                pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
            )::realtime.wal_column
        )
        from
            unnest(columns) c;

    old_columns =
            array_agg(
                (
                    c.name,
                    c.type_name,
                    c.type_oid,
                    c.value,
                    c.is_pkey,
                    pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                )::realtime.wal_column
            )
            from
                unnest(old_columns) c;

    if action <> 'DELETE' and count(1) = 0 from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            -- subscriptions is already filtered by entity
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 400: Bad Request, no primary key']
        )::realtime.wal_rls;

    -- The claims role does not have SELECT permission to the primary key of entity
    elsif action <> 'DELETE' and sum(c.is_selectable::int) <> count(1) from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 401: Unauthorized']
        )::realtime.wal_rls;

    else
        output = jsonb_build_object(
            'schema', wal ->> 'schema',
            'table', wal ->> 'table',
            'type', action,
            'commit_timestamp', to_char(
                ((wal ->> 'timestamp')::timestamptz at time zone 'utc'),
                'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
            ),
            'columns', (
                select
                    jsonb_agg(
                        jsonb_build_object(
                            'name', pa.attname,
                            'type', pt.typname
                        )
                        order by pa.attnum asc
                    )
                from
                    pg_attribute pa
                    join pg_type pt
                        on pa.atttypid = pt.oid
                where
                    attrelid = entity_
                    and attnum > 0
                    and pg_catalog.has_column_privilege(working_role, entity_, pa.attname, 'SELECT')
            )
        )
        -- Add "record" key for insert and update
        || case
            when action in ('INSERT', 'UPDATE') then
                jsonb_build_object(
                    'record',
                    (
                        select
                            jsonb_object_agg(
                                -- if unchanged toast, get column name and value from old record
                                coalesce((c).name, (oc).name),
                                case
                                    when (c).name is null then (oc).value
                                    else (c).value
                                end
                            )
                        from
                            unnest(columns) c
                            full outer join unnest(old_columns) oc
                                on (c).name = (oc).name
                        where
                            coalesce((c).is_selectable, (oc).is_selectable)
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                    )
                )
            else '{}'::jsonb
        end
        -- Add "old_record" key for update and delete
        || case
            when action = 'UPDATE' then
                jsonb_build_object(
                        'old_record',
                        (
                            select jsonb_object_agg((c).name, (c).value)
                            from unnest(old_columns) c
                            where
                                (c).is_selectable
                                and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                        )
                    )
            when action = 'DELETE' then
                jsonb_build_object(
                    'old_record',
                    (
                        select jsonb_object_agg((c).name, (c).value)
                        from unnest(old_columns) c
                        where
                            (c).is_selectable
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                            and ( not is_rls_enabled or (c).is_pkey ) -- if RLS enabled, we can't secure deletes so filter to pkey
                    )
                )
            else '{}'::jsonb
        end;

        -- Create the prepared statement
        if is_rls_enabled and action <> 'DELETE' then
            if (select 1 from pg_prepared_statements where name = 'walrus_rls_stmt' limit 1) > 0 then
                deallocate walrus_rls_stmt;
            end if;
            execute realtime.build_prepared_statement_sql('walrus_rls_stmt', entity_, columns);
        end if;

        visible_to_subscription_ids = '{}';

        for subscription_id, claims in (
                select
                    subs.subscription_id,
                    subs.claims
                from
                    unnest(subscriptions) subs
                where
                    subs.entity = entity_
                    and subs.claims_role = working_role
                    and (
                        realtime.is_visible_through_filters(columns, subs.filters)
                        or (
                          action = 'DELETE'
                          and realtime.is_visible_through_filters(old_columns, subs.filters)
                        )
                    )
        ) loop

            if not is_rls_enabled or action = 'DELETE' then
                visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
            else
                -- Check if RLS allows the role to see the record
                perform
                    -- Trim leading and trailing quotes from working_role because set_config
                    -- doesn't recognize the role as valid if they are included
                    set_config('role', trim(both '"' from working_role::text), true),
                    set_config('request.jwt.claims', claims::text, true);

                execute 'execute walrus_rls_stmt' into subscription_has_access;

                if subscription_has_access then
                    visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
                end if;
            end if;
        end loop;

        perform set_config('role', null, true);

        return next (
            output,
            is_rls_enabled,
            visible_to_subscription_ids,
            case
                when error_record_exceeds_max_size then array['Error 413: Payload Too Large']
                else '{}'
            end
        )::realtime.wal_rls;

    end if;
end loop;

perform set_config('role', null, true);
end;
$$;


--
-- Name: broadcast_changes(text, text, text, text, text, record, record, text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    -- Declare a variable to hold the JSONB representation of the row
    row_data jsonb := '{}'::jsonb;
BEGIN
    IF level = 'STATEMENT' THEN
        RAISE EXCEPTION 'function can only be triggered for each row, not for each statement';
    END IF;
    -- Check the operation type and handle accordingly
    IF operation = 'INSERT' OR operation = 'UPDATE' OR operation = 'DELETE' THEN
        row_data := jsonb_build_object('old_record', OLD, 'record', NEW, 'operation', operation, 'table', table_name, 'schema', table_schema);
        PERFORM realtime.send (row_data, event_name, topic_name);
    ELSE
        RAISE EXCEPTION 'Unexpected operation type: %', operation;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to process the row: %', SQLERRM;
END;

$$;


--
-- Name: build_prepared_statement_sql(text, regclass, realtime.wal_column[]); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) RETURNS text
    LANGUAGE sql
    AS $$
      /*
      Builds a sql string that, if executed, creates a prepared statement to
      tests retrive a row from *entity* by its primary key columns.
      Example
          select realtime.build_prepared_statement_sql('public.notes', '{"id"}'::text[], '{"bigint"}'::text[])
      */
          select
      'prepare ' || prepared_statement_name || ' as
          select
              exists(
                  select
                      1
                  from
                      ' || entity || '
                  where
                      ' || string_agg(quote_ident(pkc.name) || '=' || quote_nullable(pkc.value #>> '{}') , ' and ') || '
              )'
          from
              unnest(columns) pkc
          where
              pkc.is_pkey
          group by
              entity
      $$;


--
-- Name: cast(text, regtype); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime."cast"(val text, type_ regtype) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  res jsonb;
begin
  if type_::text = 'bytea' then
    return to_jsonb(val);
  end if;
  execute format('select to_jsonb(%L::'|| type_::text || ')', val) into res;
  return res;
end
$$;


--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
      /*
      Casts *val_1* and *val_2* as type *type_* and check the *op* condition for truthiness
      */
      declare
          op_symbol text = (
              case
                  when op = 'eq' then '='
                  when op = 'neq' then '!='
                  when op = 'lt' then '<'
                  when op = 'lte' then '<='
                  when op = 'gt' then '>'
                  when op = 'gte' then '>='
                  when op = 'in' then '= any'
                  else 'UNKNOWN OP'
              end
          );
          res boolean;
      begin
          execute format(
              'select %L::'|| type_::text || ' ' || op_symbol
              || ' ( %L::'
              || (
                  case
                      when op = 'in' then type_::text || '[]'
                      else type_::text end
              )
              || ')', val_1, val_2) into res;
          return res;
      end;
      $$;


--
-- Name: is_visible_through_filters(realtime.wal_column[], realtime.user_defined_filter[]); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
    /*
    Should the record be visible (true) or filtered out (false) after *filters* are applied
    */
        select
            -- Default to allowed when no filters present
            $2 is null -- no filters. this should not happen because subscriptions has a default
            or array_length($2, 1) is null -- array length of an empty array is null
            or bool_and(
                coalesce(
                    realtime.check_equality_op(
                        op:=f.op,
                        type_:=coalesce(
                            col.type_oid::regtype, -- null when wal2json version <= 2.4
                            col.type_name::regtype
                        ),
                        -- cast jsonb to text
                        val_1:=col.value #>> '{}',
                        val_2:=f.value
                    ),
                    false -- if null, filter does not match
                )
            )
        from
            unnest(filters) f
            join unnest(columns) col
                on f.column_name = col.name;
    $_$;


--
-- Name: list_changes(name, name, integer, integer); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) RETURNS SETOF realtime.wal_rls
    LANGUAGE sql
    SET log_min_messages TO 'fatal'
    AS $$
      with pub as (
        select
          concat_ws(
            ',',
            case when bool_or(pubinsert) then 'insert' else null end,
            case when bool_or(pubupdate) then 'update' else null end,
            case when bool_or(pubdelete) then 'delete' else null end
          ) as w2j_actions,
          coalesce(
            string_agg(
              realtime.quote_wal2json(format('%I.%I', schemaname, tablename)::regclass),
              ','
            ) filter (where ppt.tablename is not null and ppt.tablename not like '% %'),
            ''
          ) w2j_add_tables
        from
          pg_publication pp
          left join pg_publication_tables ppt
            on pp.pubname = ppt.pubname
        where
          pp.pubname = publication
        group by
          pp.pubname
        limit 1
      ),
      w2j as (
        select
          x.*, pub.w2j_add_tables
        from
          pub,
          pg_logical_slot_get_changes(
            slot_name, null, max_changes,
            'include-pk', 'true',
            'include-transaction', 'false',
            'include-timestamp', 'true',
            'include-type-oids', 'true',
            'format-version', '2',
            'actions', pub.w2j_actions,
            'add-tables', pub.w2j_add_tables
          ) x
      )
      select
        xyz.wal,
        xyz.is_rls_enabled,
        xyz.subscription_ids,
        xyz.errors
      from
        w2j,
        realtime.apply_rls(
          wal := w2j.data::jsonb,
          max_record_bytes := max_record_bytes
        ) xyz(wal, is_rls_enabled, subscription_ids, errors)
      where
        w2j.w2j_add_tables <> ''
        and xyz.subscription_ids[1] is not null
    $$;


--
-- Name: quote_wal2json(regclass); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.quote_wal2json(entity regclass) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
      select
        (
          select string_agg('' || ch,'')
          from unnest(string_to_array(nsp.nspname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
        )
        || '.'
        || (
          select string_agg('' || ch,'')
          from unnest(string_to_array(pc.relname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
          )
      from
        pg_class pc
        join pg_namespace nsp
          on pc.relnamespace = nsp.oid
      where
        pc.oid = entity
    $$;


--
-- Name: send(jsonb, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
  final_payload jsonb;
BEGIN
  BEGIN
    -- Generate a new UUID for the id
    generated_id := gen_random_uuid();

    -- Check if payload has an 'id' key, if not, add the generated UUID
    IF payload ? 'id' THEN
      final_payload := payload;
    ELSE
      final_payload := jsonb_set(payload, '{id}', to_jsonb(generated_id));
    END IF;

    -- Set the topic configuration
    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    -- Attempt to insert the message
    INSERT INTO realtime.messages (id, payload, event, topic, private, extension)
    VALUES (generated_id, final_payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      -- Capture and notify the error
      RAISE WARNING 'ErrorSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


--
-- Name: subscription_check_filters(); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.subscription_check_filters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    /*
    Validates that the user defined filters for a subscription:
    - refer to valid columns that the claimed role may access
    - values are coercable to the correct column type
    */
    declare
        col_names text[] = coalesce(
                array_agg(c.column_name order by c.ordinal_position),
                '{}'::text[]
            )
            from
                information_schema.columns c
            where
                format('%I.%I', c.table_schema, c.table_name)::regclass = new.entity
                and pg_catalog.has_column_privilege(
                    (new.claims ->> 'role'),
                    format('%I.%I', c.table_schema, c.table_name)::regclass,
                    c.column_name,
                    'SELECT'
                );
        filter realtime.user_defined_filter;
        col_type regtype;

        in_val jsonb;
    begin
        for filter in select * from unnest(new.filters) loop
            -- Filtered column is valid
            if not filter.column_name = any(col_names) then
                raise exception 'invalid column for filter %', filter.column_name;
            end if;

            -- Type is sanitized and safe for string interpolation
            col_type = (
                select atttypid::regtype
                from pg_catalog.pg_attribute
                where attrelid = new.entity
                      and attname = filter.column_name
            );
            if col_type is null then
                raise exception 'failed to lookup type for column %', filter.column_name;
            end if;

            -- Set maximum number of entries for in filter
            if filter.op = 'in'::realtime.equality_op then
                in_val = realtime.cast(filter.value, (col_type::text || '[]')::regtype);
                if coalesce(jsonb_array_length(in_val), 0) > 100 then
                    raise exception 'too many values for `in` filter. Maximum 100';
                end if;
            else
                -- raises an exception if value is not coercable to type
                perform realtime.cast(filter.value, col_type);
            end if;

        end loop;

        -- Apply consistent order to filters so the unique constraint on
        -- (subscription_id, entity, filters) can't be tricked by a different filter order
        new.filters = coalesce(
            array_agg(f order by f.column_name, f.op, f.value),
            '{}'
        ) from unnest(new.filters) f;

        return new;
    end;
    $$;


--
-- Name: to_regrole(text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.to_regrole(role_name text) RETURNS regrole
    LANGUAGE sql IMMUTABLE
    AS $$ select role_name::regrole $$;


--
-- Name: topic(); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.topic() RETURNS text
    LANGUAGE sql STABLE
    AS $$
select nullif(current_setting('realtime.topic', true), '')::text;
$$;


--
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


--
-- Name: delete_leaf_prefixes(text[], text[]); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_rows_deleted integer;
BEGIN
    LOOP
        WITH candidates AS (
            SELECT DISTINCT
                t.bucket_id,
                unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        ),
        uniq AS (
             SELECT
                 bucket_id,
                 name,
                 storage.get_level(name) AS level
             FROM candidates
             WHERE name <> ''
             GROUP BY bucket_id, name
        ),
        leaf AS (
             SELECT
                 p.bucket_id,
                 p.name,
                 p.level
             FROM storage.prefixes AS p
                  JOIN uniq AS u
                       ON u.bucket_id = p.bucket_id
                           AND u.name = p.name
                           AND u.level = p.level
             WHERE NOT EXISTS (
                 SELECT 1
                 FROM storage.objects AS o
                 WHERE o.bucket_id = p.bucket_id
                   AND o.level = p.level + 1
                   AND o.name COLLATE "C" LIKE p.name || '/%'
             )
             AND NOT EXISTS (
                 SELECT 1
                 FROM storage.prefixes AS c
                 WHERE c.bucket_id = p.bucket_id
                   AND c.level = p.level + 1
                   AND c.name COLLATE "C" LIKE p.name || '/%'
             )
        )
        DELETE
        FROM storage.prefixes AS p
            USING leaf AS l
        WHERE p.bucket_id = l.bucket_id
          AND p.name = l.name
          AND p.level = l.level;

        GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;
        EXIT WHEN v_rows_deleted = 0;
    END LOOP;
END;
$$;


--
-- Name: enforce_bucket_name_length(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.enforce_bucket_name_length() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


--
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


--
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


--
-- Name: get_common_prefix(text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT CASE
    WHEN position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(p_key, length(p_prefix) + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)))
    ELSE NULL
END;
$$;


--
-- Name: get_level(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_level(name text) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT array_length(string_to_array("name", '/'), 1);
$$;


--
-- Name: get_prefix(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_prefix(name text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT
    CASE WHEN strpos("name", '/') > 0 THEN
             regexp_replace("name", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$_$;


--
-- Name: get_prefixes(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_prefixes(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array("name", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$$;


--
-- Name: get_size_by_bucket(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_size_by_bucket() RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


--
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


--
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix, 1) = delimiter_param THEN
        v_upper_bound := left(v_prefix, -1) || chr(ascii(delimiter_param) + 1);
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'AND o.name COLLATE "C" < $3 ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'AND o.name COLLATE "C" >= $3 ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor: find the last item in range
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Cursor provided: determine if it refers to a folder or leaf
        IF EXISTS (
            SELECT 1 FROM storage.objects o
            WHERE o.bucket_id = _bucket_id
              AND o.name COLLATE "C" LIKE v_start || delimiter_param || '%'
            LIMIT 1
        ) THEN
            -- Cursor refers to a folder
            IF v_is_asc THEN
                v_next_seek := v_start || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_start || delimiter_param;
            END IF;
        ELSE
            -- Cursor refers to a leaf object
            IF v_is_asc THEN
                v_next_seek := v_start || delimiter_param;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := rtrim(v_common_prefix, delimiter_param);
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1) || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := v_current.name;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                RETURN NEXT;
                v_count := v_count + 1;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := v_current.name || delimiter_param;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


--
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


--
-- Name: protect_delete(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.protect_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: search(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;
    v_skipped INT := 0;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach (unchanged)
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT path_tokens[$1] AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $2 || '%%'
                  AND bucket_id = $3
                  AND array_length(objects.path_tokens, 1) <> $1
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata FROM folders)
            UNION ALL
            (SELECT path_tokens[$1] AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata
             FROM storage.objects
             WHERE objects.name ILIKE $2 || '%%'
               AND bucket_id = $3
               AND array_length(objects.path_tokens, 1) = $1
             ORDER BY %I %s)
            LIMIT $4 OFFSET $5
            $sql$, v_sort_order, v_order_by, v_sort_order
        ) USING levels, v_prefix, bucketname, v_limit, offsets;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'AND lower(o.name) COLLATE "C" < $3 ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'AND lower(o.name) COLLATE "C" >= $3 ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC: find the last item in range first (static SQL)
        IF v_upper_bound IS NOT NULL THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower AND lower(o.name) COLLATE "C" < v_upper_bound
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSIF v_prefix_lower <> '' THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSE
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        END IF;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix_lower <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := split_part(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter), v_delimiter, levels);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := lower(v_current.name);
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := split_part(v_current.name, v_delimiter, levels);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := lower(v_current.name) || v_delimiter;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


--
-- Name: search_by_timestamp(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
BEGIN
    v_prefix := coalesce(p_prefix, '');

    IF p_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $1 || '%%'
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                rtrim(common_prefix, '/') AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    date_trunc('milliseconds', %I),
                    name COLLATE "C"
                ) %s ROW(
                    COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz),
                    $5
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s
        LIMIT $4
    $sql$,
        p_sort_column,
        v_cursor_op,
        p_sort_column,
        p_sort_order,
        p_sort_order
    );

    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after;
END;
$_$;


--
-- Name: search_legacy_v1(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


--
-- Name: search_v2(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, sort_column text DEFAULT 'name'::text, sort_column_after text DEFAULT ''::text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            start_after,
            '',
            v_sort_ord
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after
        );
    END IF;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


--
-- Name: audit_log_entries; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid NOT NULL,
    payload json,
    created_at timestamp with time zone,
    ip_address character varying(64) DEFAULT ''::character varying NOT NULL
);


--
-- Name: TABLE audit_log_entries; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.audit_log_entries IS 'Auth: Audit trail for user actions.';


--
-- Name: custom_oauth_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.custom_oauth_providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider_type text NOT NULL,
    identifier text NOT NULL,
    name text NOT NULL,
    client_id text NOT NULL,
    client_secret text NOT NULL,
    acceptable_client_ids text[] DEFAULT '{}'::text[] NOT NULL,
    scopes text[] DEFAULT '{}'::text[] NOT NULL,
    pkce_enabled boolean DEFAULT true NOT NULL,
    attribute_mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    authorization_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    email_optional boolean DEFAULT false NOT NULL,
    issuer text,
    discovery_url text,
    skip_nonce_check boolean DEFAULT false NOT NULL,
    cached_discovery jsonb,
    discovery_cached_at timestamp with time zone,
    authorization_url text,
    token_url text,
    userinfo_url text,
    jwks_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT custom_oauth_providers_authorization_url_https CHECK (((authorization_url IS NULL) OR (authorization_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_authorization_url_length CHECK (((authorization_url IS NULL) OR (char_length(authorization_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_client_id_length CHECK (((char_length(client_id) >= 1) AND (char_length(client_id) <= 512))),
    CONSTRAINT custom_oauth_providers_discovery_url_length CHECK (((discovery_url IS NULL) OR (char_length(discovery_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_identifier_format CHECK ((identifier ~ '^[a-z0-9][a-z0-9:-]{0,48}[a-z0-9]$'::text)),
    CONSTRAINT custom_oauth_providers_issuer_length CHECK (((issuer IS NULL) OR ((char_length(issuer) >= 1) AND (char_length(issuer) <= 2048)))),
    CONSTRAINT custom_oauth_providers_jwks_uri_https CHECK (((jwks_uri IS NULL) OR (jwks_uri ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_jwks_uri_length CHECK (((jwks_uri IS NULL) OR (char_length(jwks_uri) <= 2048))),
    CONSTRAINT custom_oauth_providers_name_length CHECK (((char_length(name) >= 1) AND (char_length(name) <= 100))),
    CONSTRAINT custom_oauth_providers_oauth2_requires_endpoints CHECK (((provider_type <> 'oauth2'::text) OR ((authorization_url IS NOT NULL) AND (token_url IS NOT NULL) AND (userinfo_url IS NOT NULL)))),
    CONSTRAINT custom_oauth_providers_oidc_discovery_url_https CHECK (((provider_type <> 'oidc'::text) OR (discovery_url IS NULL) OR (discovery_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_issuer_https CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NULL) OR (issuer ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_requires_issuer CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NOT NULL))),
    CONSTRAINT custom_oauth_providers_provider_type_check CHECK ((provider_type = ANY (ARRAY['oauth2'::text, 'oidc'::text]))),
    CONSTRAINT custom_oauth_providers_token_url_https CHECK (((token_url IS NULL) OR (token_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_token_url_length CHECK (((token_url IS NULL) OR (char_length(token_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_userinfo_url_https CHECK (((userinfo_url IS NULL) OR (userinfo_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_userinfo_url_length CHECK (((userinfo_url IS NULL) OR (char_length(userinfo_url) <= 2048)))
);


--
-- Name: flow_state; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.flow_state (
    id uuid NOT NULL,
    user_id uuid,
    auth_code text,
    code_challenge_method auth.code_challenge_method,
    code_challenge text,
    provider_type text NOT NULL,
    provider_access_token text,
    provider_refresh_token text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    authentication_method text NOT NULL,
    auth_code_issued_at timestamp with time zone,
    invite_token text,
    referrer text,
    oauth_client_state_id uuid,
    linking_target_id uuid,
    email_optional boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE flow_state; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.flow_state IS 'Stores metadata for all OAuth/SSO login flows';


--
-- Name: identities; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.identities (
    provider_id text NOT NULL,
    user_id uuid NOT NULL,
    identity_data jsonb NOT NULL,
    provider text NOT NULL,
    last_sign_in_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    email text GENERATED ALWAYS AS (lower((identity_data ->> 'email'::text))) STORED,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: TABLE identities; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.identities IS 'Auth: Stores identities associated to a user.';


--
-- Name: COLUMN identities.email; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.identities.email IS 'Auth: Email is a generated column that references the optional email property in the identity_data';


--
-- Name: instances; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.instances (
    id uuid NOT NULL,
    uuid uuid,
    raw_base_config text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


--
-- Name: TABLE instances; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.instances IS 'Auth: Manages users across multiple sites.';


--
-- Name: mfa_amr_claims; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_amr_claims (
    session_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    authentication_method text NOT NULL,
    id uuid NOT NULL
);


--
-- Name: TABLE mfa_amr_claims; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_amr_claims IS 'auth: stores authenticator method reference claims for multi factor authentication';


--
-- Name: mfa_challenges; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_challenges (
    id uuid NOT NULL,
    factor_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    verified_at timestamp with time zone,
    ip_address inet NOT NULL,
    otp_code text,
    web_authn_session_data jsonb
);


--
-- Name: TABLE mfa_challenges; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_challenges IS 'auth: stores metadata about challenge requests made';


--
-- Name: mfa_factors; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_factors (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    friendly_name text,
    factor_type auth.factor_type NOT NULL,
    status auth.factor_status NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    secret text,
    phone text,
    last_challenged_at timestamp with time zone,
    web_authn_credential jsonb,
    web_authn_aaguid uuid,
    last_webauthn_challenge_data jsonb
);


--
-- Name: TABLE mfa_factors; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_factors IS 'auth: stores metadata about factors';


--
-- Name: COLUMN mfa_factors.last_webauthn_challenge_data; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.mfa_factors.last_webauthn_challenge_data IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';


--
-- Name: oauth_authorizations; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_authorizations (
    id uuid NOT NULL,
    authorization_id text NOT NULL,
    client_id uuid NOT NULL,
    user_id uuid,
    redirect_uri text NOT NULL,
    scope text NOT NULL,
    state text,
    resource text,
    code_challenge text,
    code_challenge_method auth.code_challenge_method,
    response_type auth.oauth_response_type DEFAULT 'code'::auth.oauth_response_type NOT NULL,
    status auth.oauth_authorization_status DEFAULT 'pending'::auth.oauth_authorization_status NOT NULL,
    authorization_code text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:03:00'::interval) NOT NULL,
    approved_at timestamp with time zone,
    nonce text,
    CONSTRAINT oauth_authorizations_authorization_code_length CHECK ((char_length(authorization_code) <= 255)),
    CONSTRAINT oauth_authorizations_code_challenge_length CHECK ((char_length(code_challenge) <= 128)),
    CONSTRAINT oauth_authorizations_expires_at_future CHECK ((expires_at > created_at)),
    CONSTRAINT oauth_authorizations_nonce_length CHECK ((char_length(nonce) <= 255)),
    CONSTRAINT oauth_authorizations_redirect_uri_length CHECK ((char_length(redirect_uri) <= 2048)),
    CONSTRAINT oauth_authorizations_resource_length CHECK ((char_length(resource) <= 2048)),
    CONSTRAINT oauth_authorizations_scope_length CHECK ((char_length(scope) <= 4096)),
    CONSTRAINT oauth_authorizations_state_length CHECK ((char_length(state) <= 4096))
);


--
-- Name: oauth_client_states; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_client_states (
    id uuid NOT NULL,
    provider_type text NOT NULL,
    code_verifier text,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE oauth_client_states; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.oauth_client_states IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';


--
-- Name: oauth_clients; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_clients (
    id uuid NOT NULL,
    client_secret_hash text,
    registration_type auth.oauth_registration_type NOT NULL,
    redirect_uris text NOT NULL,
    grant_types text NOT NULL,
    client_name text,
    client_uri text,
    logo_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    client_type auth.oauth_client_type DEFAULT 'confidential'::auth.oauth_client_type NOT NULL,
    token_endpoint_auth_method text NOT NULL,
    CONSTRAINT oauth_clients_client_name_length CHECK ((char_length(client_name) <= 1024)),
    CONSTRAINT oauth_clients_client_uri_length CHECK ((char_length(client_uri) <= 2048)),
    CONSTRAINT oauth_clients_logo_uri_length CHECK ((char_length(logo_uri) <= 2048)),
    CONSTRAINT oauth_clients_token_endpoint_auth_method_check CHECK ((token_endpoint_auth_method = ANY (ARRAY['client_secret_basic'::text, 'client_secret_post'::text, 'none'::text])))
);


--
-- Name: oauth_consents; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_consents (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    scopes text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT oauth_consents_revoked_after_granted CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))),
    CONSTRAINT oauth_consents_scopes_length CHECK ((char_length(scopes) <= 2048)),
    CONSTRAINT oauth_consents_scopes_not_empty CHECK ((char_length(TRIM(BOTH FROM scopes)) > 0))
);


--
-- Name: one_time_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.one_time_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_type auth.one_time_token_type NOT NULL,
    token_hash text NOT NULL,
    relates_to text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT one_time_tokens_token_hash_check CHECK ((char_length(token_hash) > 0))
);


--
-- Name: refresh_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.refresh_tokens (
    instance_id uuid,
    id bigint NOT NULL,
    token character varying(255),
    user_id character varying(255),
    revoked boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    parent character varying(255),
    session_id uuid
);


--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.refresh_tokens IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: auth; Owner: -
--

CREATE SEQUENCE auth.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: auth; Owner: -
--

ALTER SEQUENCE auth.refresh_tokens_id_seq OWNED BY auth.refresh_tokens.id;


--
-- Name: saml_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.saml_providers (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    entity_id text NOT NULL,
    metadata_xml text NOT NULL,
    metadata_url text,
    attribute_mapping jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    name_id_format text,
    CONSTRAINT "entity_id not empty" CHECK ((char_length(entity_id) > 0)),
    CONSTRAINT "metadata_url not empty" CHECK (((metadata_url = NULL::text) OR (char_length(metadata_url) > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK ((char_length(metadata_xml) > 0))
);


--
-- Name: TABLE saml_providers; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.saml_providers IS 'Auth: Manages SAML Identity Provider connections.';


--
-- Name: saml_relay_states; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.saml_relay_states (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    request_id text NOT NULL,
    for_email text,
    redirect_to text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    flow_state_id uuid,
    CONSTRAINT "request_id not empty" CHECK ((char_length(request_id) > 0))
);


--
-- Name: TABLE saml_relay_states; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.saml_relay_states IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';


--
-- Name: schema_migrations; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.schema_migrations (
    version character varying(255) NOT NULL
);


--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.schema_migrations IS 'Auth: Manages updates to the auth system.';


--
-- Name: sessions; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    factor_id uuid,
    aal auth.aal_level,
    not_after timestamp with time zone,
    refreshed_at timestamp without time zone,
    user_agent text,
    ip inet,
    tag text,
    oauth_client_id uuid,
    refresh_token_hmac_key text,
    refresh_token_counter bigint,
    scopes text,
    CONSTRAINT sessions_scopes_length CHECK ((char_length(scopes) <= 4096))
);


--
-- Name: TABLE sessions; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sessions IS 'Auth: Stores session data associated to a user.';


--
-- Name: COLUMN sessions.not_after; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.not_after IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';


--
-- Name: COLUMN sessions.refresh_token_hmac_key; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.refresh_token_hmac_key IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';


--
-- Name: COLUMN sessions.refresh_token_counter; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.refresh_token_counter IS 'Holds the ID (counter) of the last issued refresh token.';


--
-- Name: sso_domains; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sso_domains (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    domain text NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK ((char_length(domain) > 0))
);


--
-- Name: TABLE sso_domains; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sso_domains IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';


--
-- Name: sso_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sso_providers (
    id uuid NOT NULL,
    resource_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    disabled boolean,
    CONSTRAINT "resource_id not empty" CHECK (((resource_id = NULL::text) OR (char_length(resource_id) > 0)))
);


--
-- Name: TABLE sso_providers; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sso_providers IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';


--
-- Name: COLUMN sso_providers.resource_id; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sso_providers.resource_id IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';


--
-- Name: users; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    email_confirmed_at timestamp with time zone,
    invited_at timestamp with time zone,
    confirmation_token character varying(255),
    confirmation_sent_at timestamp with time zone,
    recovery_token character varying(255),
    recovery_sent_at timestamp with time zone,
    email_change_token_new character varying(255),
    email_change character varying(255),
    email_change_sent_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    is_super_admin boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    phone text DEFAULT NULL::character varying,
    phone_confirmed_at timestamp with time zone,
    phone_change text DEFAULT ''::character varying,
    phone_change_token character varying(255) DEFAULT ''::character varying,
    phone_change_sent_at timestamp with time zone,
    confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current character varying(255) DEFAULT ''::character varying,
    email_change_confirm_status smallint DEFAULT 0,
    banned_until timestamp with time zone,
    reauthentication_token character varying(255) DEFAULT ''::character varying,
    reauthentication_sent_at timestamp with time zone,
    is_sso_user boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    is_anonymous boolean DEFAULT false NOT NULL,
    CONSTRAINT users_email_change_confirm_status_check CHECK (((email_change_confirm_status >= 0) AND (email_change_confirm_status <= 2)))
);


--
-- Name: TABLE users; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';


--
-- Name: COLUMN users.is_sso_user; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.users.is_sso_user IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';


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
-- Name: t_etl_steps_step_id_seq; Type: SEQUENCE; Schema: etl; Owner: -
--

CREATE SEQUENCE etl.t_etl_steps_step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_etl_steps_step_id_seq; Type: SEQUENCE OWNED BY; Schema: etl; Owner: -
--

ALTER SEQUENCE etl.t_etl_steps_step_id_seq OWNED BY etl.t_etl_steps.step_id;


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
-- Name: mv_family_day_base; Type: MATERIALIZED VIEW; Schema: ml_diag; Owner: -
--

CREATE MATERIALIZED VIEW ml_diag.mv_family_day_base AS
 SELECT data,
    lower(TRIM(BOTH FROM famiglia)) AS family_name,
    (sum(COALESCE(qty_venduta, (0)::numeric)))::numeric(14,3) AS qty_total,
    (sum(COALESCE(imponibile_netto_tot, (0)::numeric)))::numeric(14,2) AS value_total,
    (sum(COALESCE(num_articoli, 0)))::integer AS num_articoli_total
   FROM public.greenhouse_sales_family_daily_dense
  WHERE ((famiglia IS NOT NULL) AND (TRIM(BOTH FROM famiglia) <> ''::text))
  GROUP BY data, (lower(TRIM(BOTH FROM famiglia)))
  WITH NO DATA;


--
-- Name: mv_family_stats; Type: MATERIALIZED VIEW; Schema: ml_diag; Owner: -
--

CREATE MATERIALIZED VIEW ml_diag.mv_family_stats AS
 WITH fam AS (
         SELECT mv_family_day_base.family_name,
            count(*) AS days_total,
            sum(
                CASE
                    WHEN (mv_family_day_base.qty_total > (0)::numeric) THEN 1
                    ELSE 0
                END) AS pos_days,
            sum(
                CASE
                    WHEN (mv_family_day_base.qty_total = (0)::numeric) THEN 1
                    ELSE 0
                END) AS zero_days,
            (sum(mv_family_day_base.qty_total))::numeric(16,3) AS qty_total,
            (sum(mv_family_day_base.value_total))::numeric(16,2) AS value_total,
            (avg(mv_family_day_base.qty_total))::numeric(16,6) AS qty_avg_all_days,
            (avg(
                CASE
                    WHEN (mv_family_day_base.qty_total > (0)::numeric) THEN mv_family_day_base.qty_total
                    ELSE NULL::numeric
                END))::numeric(16,6) AS qty_avg_pos_days,
            (stddev_samp(
                CASE
                    WHEN (mv_family_day_base.qty_total > (0)::numeric) THEN mv_family_day_base.qty_total
                    ELSE NULL::numeric
                END))::numeric(16,6) AS qty_std_pos_days,
            (avg(mv_family_day_base.value_total))::numeric(16,6) AS value_avg_all_days,
            (avg(
                CASE
                    WHEN (mv_family_day_base.value_total > (0)::numeric) THEN mv_family_day_base.value_total
                    ELSE NULL::numeric
                END))::numeric(16,6) AS value_avg_pos_days,
            (stddev_samp(
                CASE
                    WHEN (mv_family_day_base.value_total > (0)::numeric) THEN mv_family_day_base.value_total
                    ELSE NULL::numeric
                END))::numeric(16,6) AS value_std_pos_days,
            min(mv_family_day_base.data) AS min_date,
            max(mv_family_day_base.data) AS max_date,
            (count(DISTINCT EXTRACT(year FROM mv_family_day_base.data)))::integer AS years_count,
            (count(DISTINCT
                CASE
                    WHEN (mv_family_day_base.qty_total > (0)::numeric) THEN EXTRACT(month FROM mv_family_day_base.data)
                    ELSE NULL::numeric
                END))::integer AS active_months,
            (count(DISTINCT
                CASE
                    WHEN (mv_family_day_base.value_total > (0)::numeric) THEN EXTRACT(month FROM mv_family_day_base.data)
                    ELSE NULL::numeric
                END))::integer AS active_value_months
           FROM ml_diag.mv_family_day_base
          GROUP BY mv_family_day_base.family_name
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    round(((zero_days)::numeric / (NULLIF(days_total, 0))::numeric), 4) AS zero_rate,
    round(((pos_days)::numeric / (NULLIF(days_total, 0))::numeric), 4) AS pos_rate,
    qty_total,
    round(qty_avg_all_days, 4) AS qty_avg_all_days,
    round(qty_avg_pos_days, 4) AS qty_avg_pos_days,
    round(qty_std_pos_days, 4) AS qty_std_pos_days,
    value_total,
    round(value_avg_all_days, 4) AS value_avg_all_days,
    round(value_avg_pos_days, 4) AS value_avg_pos_days,
    round(value_std_pos_days, 4) AS value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    min_date,
    max_date
   FROM fam
  WITH NO DATA;


--
-- Name: mv_family_importance; Type: MATERIALIZED VIEW; Schema: ml_diag; Owner: -
--

CREATE MATERIALIZED VIEW ml_diag.mv_family_importance AS
 WITH base AS (
         SELECT mv_family_stats.family_name,
            mv_family_stats.qty_total,
            mv_family_stats.value_total
           FROM ml_diag.mv_family_stats
        ), qty_ranked AS (
         SELECT base.family_name,
            base.qty_total,
            sum(base.qty_total) OVER () AS total_qty,
            sum(base.qty_total) OVER (ORDER BY base.qty_total DESC, base.family_name) AS cum_qty
           FROM base
        ), value_ranked AS (
         SELECT base.family_name,
            base.value_total,
            sum(base.value_total) OVER () AS total_value,
            sum(base.value_total) OVER (ORDER BY base.value_total DESC, base.family_name) AS cum_value
           FROM base
        )
 SELECT q.family_name,
    q.qty_total,
    round(((q.qty_total / NULLIF(q.total_qty, (0)::numeric)) * (100)::numeric), 4) AS qty_pct_total,
    round(((q.cum_qty / NULLIF(q.total_qty, (0)::numeric)) * (100)::numeric), 4) AS qty_cum_pct,
        CASE
            WHEN ((q.cum_qty / NULLIF(q.total_qty, (0)::numeric)) <= 0.80) THEN 'core_80'::text
            WHEN ((q.cum_qty / NULLIF(q.total_qty, (0)::numeric)) <= 0.95) THEN 'mid_95'::text
            ELSE 'tail'::text
        END AS qty_tier,
    v.value_total,
    round(((v.value_total / NULLIF(v.total_value, (0)::numeric)) * (100)::numeric), 4) AS value_pct_total,
    round(((v.cum_value / NULLIF(v.total_value, (0)::numeric)) * (100)::numeric), 4) AS value_cum_pct,
        CASE
            WHEN ((v.cum_value / NULLIF(v.total_value, (0)::numeric)) <= 0.80) THEN 'core_80'::text
            WHEN ((v.cum_value / NULLIF(v.total_value, (0)::numeric)) <= 0.95) THEN 'mid_95'::text
            ELSE 'tail'::text
        END AS value_tier,
        CASE
            WHEN (((q.cum_qty / NULLIF(q.total_qty, (0)::numeric)) <= 0.80) OR ((v.cum_value / NULLIF(v.total_value, (0)::numeric)) <= 0.80)) THEN 'core'::text
            WHEN (((q.cum_qty / NULLIF(q.total_qty, (0)::numeric)) <= 0.95) OR ((v.cum_value / NULLIF(v.total_value, (0)::numeric)) <= 0.95)) THEN 'important'::text
            ELSE 'tail'::text
        END AS business_tier
   FROM (qty_ranked q
     JOIN value_ranked v ON ((v.family_name = q.family_name)))
  WITH NO DATA;


--
-- Name: mv_family_intermittency; Type: MATERIALIZED VIEW; Schema: ml_diag; Owner: -
--

CREATE MATERIALIZED VIEW ml_diag.mv_family_intermittency AS
 WITH pos AS (
         SELECT mv_family_day_base.family_name,
            mv_family_day_base.data,
            mv_family_day_base.qty_total,
            lag(mv_family_day_base.data) OVER (PARTITION BY mv_family_day_base.family_name ORDER BY mv_family_day_base.data) AS prev_data
           FROM ml_diag.mv_family_day_base
          WHERE (mv_family_day_base.qty_total > (0)::numeric)
        ), intervals AS (
         SELECT pos.family_name,
            ((pos.data - pos.prev_data))::numeric AS interval_days
           FROM pos
          WHERE (pos.prev_data IS NOT NULL)
        ), adi AS (
         SELECT intervals.family_name,
            round(avg(intervals.interval_days), 4) AS adi
           FROM intervals
          GROUP BY intervals.family_name
        ), cv2 AS (
         SELECT mv_family_day_base.family_name,
            round(power((stddev_samp(mv_family_day_base.qty_total) / NULLIF(avg(mv_family_day_base.qty_total), (0)::numeric)), (2)::numeric), 4) AS cv2_pos
           FROM ml_diag.mv_family_day_base
          WHERE (mv_family_day_base.qty_total > (0)::numeric)
          GROUP BY mv_family_day_base.family_name
        )
 SELECT s.family_name,
    a.adi,
    c.cv2_pos
   FROM ((( SELECT DISTINCT mv_family_day_base.family_name
           FROM ml_diag.mv_family_day_base) s
     LEFT JOIN adi a ON ((a.family_name = s.family_name)))
     LEFT JOIN cv2 c ON ((c.family_name = s.family_name)))
  WITH NO DATA;


--
-- Name: mv_family_metrics_v3; Type: MATERIALIZED VIEW; Schema: ml_diag; Owner: -
--

CREATE MATERIALIZED VIEW ml_diag.mv_family_metrics_v3 AS
 WITH base AS (
         SELECT mv_family_day_base.family_name,
            mv_family_day_base.data,
            mv_family_day_base.qty_total,
            mv_family_day_base.value_total,
            EXTRACT(month FROM mv_family_day_base.data) AS mm
           FROM ml_diag.mv_family_day_base
        ), month_qty AS (
         SELECT base.family_name,
            base.mm,
            sum(base.qty_total) AS qty_month
           FROM base
          GROUP BY base.family_name, base.mm
        ), month_rank AS (
         SELECT month_qty.family_name,
            month_qty.qty_month,
            row_number() OVER (PARTITION BY month_qty.family_name ORDER BY month_qty.qty_month DESC) AS rn
           FROM month_qty
        ), month_concentration AS (
         SELECT month_rank.family_name,
            sum(month_rank.qty_month) FILTER (WHERE (month_rank.rn <= 3)) AS top3_month_qty
           FROM month_rank
          GROUP BY month_rank.family_name
        ), top_days AS (
         SELECT x.family_name,
            sum(x.qty_total) FILTER (WHERE (x.rank <= 10)) AS top10_days_qty
           FROM ( SELECT base.family_name,
                    base.qty_total,
                    row_number() OVER (PARTITION BY base.family_name ORDER BY base.qty_total DESC) AS rank
                   FROM base) x
          GROUP BY x.family_name
        ), stats AS (
         SELECT base.family_name,
            sum(base.qty_total) AS qty_total,
            sum(base.value_total) AS value_total,
            avg(base.qty_total) AS avg_qty,
            stddev_samp(base.qty_total) AS std_qty,
            avg(base.value_total) AS avg_value,
            stddev_samp(base.value_total) AS std_value
           FROM base
          GROUP BY base.family_name
        )
 SELECT s.family_name,
    s.qty_total,
    s.value_total,
    round((s.std_qty / NULLIF(s.avg_qty, (0)::numeric)), 4) AS cv_total_qty,
    round((s.std_value / NULLIF(s.avg_value, (0)::numeric)), 4) AS cv_total_value,
    round((m.top3_month_qty / NULLIF(s.qty_total, (0)::numeric)), 4) AS season_concentration,
    round((d.top10_days_qty / NULLIF(s.qty_total, (0)::numeric)), 4) AS peak_concentration
   FROM ((stats s
     LEFT JOIN month_concentration m ON ((m.family_name = s.family_name)))
     LEFT JOIN top_days d ON ((d.family_name = s.family_name)))
  WITH NO DATA;


--
-- Name: mv_family_metrics_v3b; Type: MATERIALIZED VIEW; Schema: ml_diag; Owner: -
--

CREATE MATERIALIZED VIEW ml_diag.mv_family_metrics_v3b AS
 WITH day_base AS (
         SELECT mv_family_day_base.family_name,
            mv_family_day_base.data,
            mv_family_day_base.qty_total,
            mv_family_day_base.value_total,
            (EXTRACT(month FROM mv_family_day_base.data))::integer AS mm,
            (EXTRACT(isodow FROM mv_family_day_base.data))::integer AS isodow,
            (date_trunc('week'::text, (mv_family_day_base.data)::timestamp with time zone))::date AS week_start,
            (date_trunc('month'::text, (mv_family_day_base.data)::timestamp with time zone))::date AS month_start
           FROM ml_diag.mv_family_day_base
        ), totals AS (
         SELECT day_base.family_name,
            sum(day_base.qty_total) AS qty_total,
            sum(day_base.value_total) AS value_total
           FROM day_base
          GROUP BY day_base.family_name
        ), pos_day_stats AS (
         SELECT day_base.family_name,
            avg(
                CASE
                    WHEN (day_base.qty_total > (0)::numeric) THEN day_base.qty_total
                    ELSE NULL::numeric
                END) AS avg_qty_pos,
            stddev_samp(
                CASE
                    WHEN (day_base.qty_total > (0)::numeric) THEN day_base.qty_total
                    ELSE NULL::numeric
                END) AS std_qty_pos,
            avg(
                CASE
                    WHEN (day_base.value_total > (0)::numeric) THEN day_base.value_total
                    ELSE NULL::numeric
                END) AS avg_value_pos,
            stddev_samp(
                CASE
                    WHEN (day_base.value_total > (0)::numeric) THEN day_base.value_total
                    ELSE NULL::numeric
                END) AS std_value_pos
           FROM day_base
          GROUP BY day_base.family_name
        ), week_base AS (
         SELECT day_base.family_name,
            day_base.week_start,
            sum(day_base.qty_total) AS qty_week,
            sum(day_base.value_total) AS value_week
           FROM day_base
          GROUP BY day_base.family_name, day_base.week_start
        ), week_stats AS (
         SELECT week_base.family_name,
            avg(week_base.qty_week) AS avg_qty_week,
            stddev_samp(week_base.qty_week) AS std_qty_week,
            avg(week_base.value_week) AS avg_value_week,
            stddev_samp(week_base.value_week) AS std_value_week
           FROM week_base
          GROUP BY week_base.family_name
        ), month_base AS (
         SELECT day_base.family_name,
            day_base.month_start,
            sum(day_base.qty_total) AS qty_month,
            sum(day_base.value_total) AS value_month
           FROM day_base
          GROUP BY day_base.family_name, day_base.month_start
        ), month_stats AS (
         SELECT month_base.family_name,
            avg(month_base.qty_month) AS avg_qty_month,
            stddev_samp(month_base.qty_month) AS std_qty_month,
            avg(month_base.value_month) AS avg_value_month,
            stddev_samp(month_base.value_month) AS std_value_month
           FROM month_base
          GROUP BY month_base.family_name
        ), month_qty_ranked AS (
         SELECT month_base.family_name,
            month_base.month_start,
            month_base.qty_month,
            row_number() OVER (PARTITION BY month_base.family_name ORDER BY month_base.qty_month DESC, month_base.month_start) AS rn
           FROM month_base
        ), month_value_ranked AS (
         SELECT month_base.family_name,
            month_base.month_start,
            month_base.value_month,
            row_number() OVER (PARTITION BY month_base.family_name ORDER BY month_base.value_month DESC, month_base.month_start) AS rn
           FROM month_base
        ), top3_month_qty AS (
         SELECT month_qty_ranked.family_name,
            sum(month_qty_ranked.qty_month) FILTER (WHERE (month_qty_ranked.rn <= 3)) AS top3_month_qty
           FROM month_qty_ranked
          GROUP BY month_qty_ranked.family_name
        ), top3_month_value AS (
         SELECT month_value_ranked.family_name,
            sum(month_value_ranked.value_month) FILTER (WHERE (month_value_ranked.rn <= 3)) AS top3_month_value
           FROM month_value_ranked
          GROUP BY month_value_ranked.family_name
        ), day_qty_ranked AS (
         SELECT day_base.family_name,
            day_base.data,
            day_base.qty_total,
            row_number() OVER (PARTITION BY day_base.family_name ORDER BY day_base.qty_total DESC, day_base.data) AS rn
           FROM day_base
        ), day_value_ranked AS (
         SELECT day_base.family_name,
            day_base.data,
            day_base.value_total,
            row_number() OVER (PARTITION BY day_base.family_name ORDER BY day_base.value_total DESC, day_base.data) AS rn
           FROM day_base
        ), top10_day_qty AS (
         SELECT day_qty_ranked.family_name,
            sum(day_qty_ranked.qty_total) FILTER (WHERE (day_qty_ranked.rn <= 10)) AS top10_day_qty
           FROM day_qty_ranked
          GROUP BY day_qty_ranked.family_name
        ), top10_day_value AS (
         SELECT day_value_ranked.family_name,
            sum(day_value_ranked.value_total) FILTER (WHERE (day_value_ranked.rn <= 10)) AS top10_day_value
           FROM day_value_ranked
          GROUP BY day_value_ranked.family_name
        ), weekday_base AS (
         SELECT day_base.family_name,
            day_base.isodow,
            sum(day_base.qty_total) AS qty_wd,
            sum(day_base.value_total) AS value_wd
           FROM day_base
          GROUP BY day_base.family_name, day_base.isodow
        ), weekday_stats AS (
         SELECT weekday_base.family_name,
            avg(weekday_base.qty_wd) AS avg_qty_wd,
            stddev_samp(weekday_base.qty_wd) AS std_qty_wd,
            avg(weekday_base.value_wd) AS avg_value_wd,
            stddev_samp(weekday_base.value_wd) AS std_value_wd
           FROM weekday_base
          GROUP BY weekday_base.family_name
        )
 SELECT t.family_name,
    round(t.qty_total, 3) AS qty_total,
    round(t.value_total, 2) AS value_total,
    round((p.std_qty_pos / NULLIF(p.avg_qty_pos, (0)::numeric)), 4) AS cv_pos_qty,
    round((p.std_value_pos / NULLIF(p.avg_value_pos, (0)::numeric)), 4) AS cv_pos_value,
    round((w.std_qty_week / NULLIF(w.avg_qty_week, (0)::numeric)), 4) AS cv_week_qty,
    round((w.std_value_week / NULLIF(w.avg_value_week, (0)::numeric)), 4) AS cv_week_value,
    round((m.std_qty_month / NULLIF(m.avg_qty_month, (0)::numeric)), 4) AS cv_month_qty,
    round((m.std_value_month / NULLIF(m.avg_value_month, (0)::numeric)), 4) AS cv_month_value,
    round((wd.std_qty_wd / NULLIF(wd.avg_qty_wd, (0)::numeric)), 4) AS cv_weekday_qty,
    round((wd.std_value_wd / NULLIF(wd.avg_value_wd, (0)::numeric)), 4) AS cv_weekday_value,
    round((q3.top3_month_qty / NULLIF(t.qty_total, (0)::numeric)), 4) AS season_conc_qty,
    round((v3.top3_month_value / NULLIF(t.value_total, (0)::numeric)), 4) AS season_conc_value,
    round((dq.top10_day_qty / NULLIF(t.qty_total, (0)::numeric)), 4) AS peak_conc_qty,
    round((dv.top10_day_value / NULLIF(t.value_total, (0)::numeric)), 4) AS peak_conc_value
   FROM ((((((((totals t
     LEFT JOIN pos_day_stats p ON ((p.family_name = t.family_name)))
     LEFT JOIN week_stats w ON ((w.family_name = t.family_name)))
     LEFT JOIN month_stats m ON ((m.family_name = t.family_name)))
     LEFT JOIN weekday_stats wd ON ((wd.family_name = t.family_name)))
     LEFT JOIN top3_month_qty q3 ON ((q3.family_name = t.family_name)))
     LEFT JOIN top3_month_value v3 ON ((v3.family_name = t.family_name)))
     LEFT JOIN top10_day_qty dq ON ((dq.family_name = t.family_name)))
     LEFT JOIN top10_day_value dv ON ((dv.family_name = t.family_name)))
  WITH NO DATA;


--
-- Name: mv_family_metrics_v4; Type: MATERIALIZED VIEW; Schema: ml_diag; Owner: -
--

CREATE MATERIALIZED VIEW ml_diag.mv_family_metrics_v4 AS
 WITH day_base AS (
         SELECT mv_family_day_base.family_name,
            mv_family_day_base.data,
            mv_family_day_base.qty_total,
            mv_family_day_base.value_total,
            (EXTRACT(year FROM mv_family_day_base.data))::integer AS yy,
            (EXTRACT(month FROM mv_family_day_base.data))::integer AS mm,
            (EXTRACT(week FROM mv_family_day_base.data))::integer AS ww,
            (EXTRACT(isodow FROM mv_family_day_base.data))::integer AS isodow,
            (EXTRACT(doy FROM mv_family_day_base.data))::integer AS doy,
            (date_trunc('week'::text, (mv_family_day_base.data)::timestamp with time zone))::date AS week_start,
            (date_trunc('month'::text, (mv_family_day_base.data)::timestamp with time zone))::date AS month_start
           FROM ml_diag.mv_family_day_base
        ), totals AS (
         SELECT day_base.family_name,
            sum(day_base.qty_total) AS qty_total,
            sum(day_base.value_total) AS value_total,
            count(*) AS n_days,
            count(*) FILTER (WHERE (day_base.qty_total > (0)::numeric)) AS pos_days_qty,
            count(*) FILTER (WHERE (day_base.value_total > (0)::numeric)) AS pos_days_value
           FROM day_base
          GROUP BY day_base.family_name
        ), pos_days AS (
         SELECT day_base.family_name,
            day_base.data,
            day_base.qty_total,
            day_base.value_total,
            lag(day_base.data) OVER (PARTITION BY day_base.family_name ORDER BY day_base.data) AS prev_data
           FROM day_base
          WHERE ((day_base.qty_total > (0)::numeric) OR (day_base.value_total > (0)::numeric))
        ), gap_stats AS (
         SELECT pos_days.family_name,
            (avg((pos_days.data - pos_days.prev_data)))::numeric(12,4) AS avg_gap_days,
            (percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY (((pos_days.data - pos_days.prev_data))::double precision)))::numeric(12,4) AS median_gap_days,
            (percentile_cont((0.9)::double precision) WITHIN GROUP (ORDER BY (((pos_days.data - pos_days.prev_data))::double precision)))::numeric(12,4) AS p90_gap_days,
            (max((pos_days.data - pos_days.prev_data)))::numeric(12,4) AS max_gap_days
           FROM pos_days
          WHERE (pos_days.prev_data IS NOT NULL)
          GROUP BY pos_days.family_name
        ), pos_day_stats AS (
         SELECT day_base.family_name,
            (avg(
                CASE
                    WHEN (day_base.qty_total > (0)::numeric) THEN day_base.qty_total
                    ELSE NULL::numeric
                END))::numeric(18,6) AS avg_qty_pos,
            (stddev_samp(
                CASE
                    WHEN (day_base.qty_total > (0)::numeric) THEN day_base.qty_total
                    ELSE NULL::numeric
                END))::numeric(18,6) AS std_qty_pos,
            (avg(
                CASE
                    WHEN (day_base.value_total > (0)::numeric) THEN day_base.value_total
                    ELSE NULL::numeric
                END))::numeric(18,6) AS avg_value_pos,
            (stddev_samp(
                CASE
                    WHEN (day_base.value_total > (0)::numeric) THEN day_base.value_total
                    ELSE NULL::numeric
                END))::numeric(18,6) AS std_value_pos
           FROM day_base
          GROUP BY day_base.family_name
        ), week_base AS (
         SELECT day_base.family_name,
            day_base.yy,
            day_base.week_start,
            sum(day_base.qty_total) AS qty_week,
            sum(day_base.value_total) AS value_week
           FROM day_base
          GROUP BY day_base.family_name, day_base.yy, day_base.week_start
        ), week_stats AS (
         SELECT week_base.family_name,
            (avg(week_base.qty_week))::numeric(18,6) AS avg_qty_week,
            (stddev_samp(week_base.qty_week))::numeric(18,6) AS std_qty_week,
            (avg(week_base.value_week))::numeric(18,6) AS avg_value_week,
            (stddev_samp(week_base.value_week))::numeric(18,6) AS std_value_week,
            ((count(*) FILTER (WHERE (week_base.qty_week > (0)::numeric)))::numeric(18,6) / (NULLIF(count(*), 0))::numeric) AS weeks_active_ratio
           FROM week_base
          GROUP BY week_base.family_name
        ), month_base AS (
         SELECT day_base.family_name,
            day_base.yy,
            day_base.mm,
            day_base.month_start,
            sum(day_base.qty_total) AS qty_month,
            sum(day_base.value_total) AS value_month
           FROM day_base
          GROUP BY day_base.family_name, day_base.yy, day_base.mm, day_base.month_start
        ), month_stats AS (
         SELECT month_base.family_name,
            (avg(month_base.qty_month))::numeric(18,6) AS avg_qty_month,
            (stddev_samp(month_base.qty_month))::numeric(18,6) AS std_qty_month,
            (avg(month_base.value_month))::numeric(18,6) AS avg_value_month,
            (stddev_samp(month_base.value_month))::numeric(18,6) AS std_value_month,
            ((count(*) FILTER (WHERE (month_base.qty_month > (0)::numeric)))::numeric(18,6) / (NULLIF(count(*), 0))::numeric) AS months_active_ratio
           FROM month_base
          GROUP BY month_base.family_name
        ), year_base AS (
         SELECT day_base.family_name,
            day_base.yy,
            sum(day_base.qty_total) AS qty_year,
            sum(day_base.value_total) AS value_year
           FROM day_base
          GROUP BY day_base.family_name, day_base.yy
        ), year_stats AS (
         SELECT year_base.family_name,
            (avg(year_base.qty_year))::numeric(18,6) AS avg_qty_year,
            (stddev_samp(year_base.qty_year))::numeric(18,6) AS std_qty_year,
            (avg(year_base.value_year))::numeric(18,6) AS avg_value_year,
            (stddev_samp(year_base.value_year))::numeric(18,6) AS std_value_year,
            ((count(*) FILTER (WHERE (year_base.qty_year > (0)::numeric)))::numeric(18,6) / (NULLIF(count(*), 0))::numeric) AS years_active_ratio
           FROM year_base
          GROUP BY year_base.family_name
        ), weekday_base AS (
         SELECT day_base.family_name,
            day_base.isodow,
            sum(day_base.qty_total) AS qty_weekday,
            sum(day_base.value_total) AS value_weekday
           FROM day_base
          GROUP BY day_base.family_name, day_base.isodow
        ), weekday_stats AS (
         SELECT weekday_base.family_name,
            (avg(weekday_base.qty_weekday))::numeric(18,6) AS avg_qty_weekday,
            (stddev_samp(weekday_base.qty_weekday))::numeric(18,6) AS std_qty_weekday,
            (avg(weekday_base.value_weekday))::numeric(18,6) AS avg_value_weekday,
            (stddev_samp(weekday_base.value_weekday))::numeric(18,6) AS std_value_weekday
           FROM weekday_base
          GROUP BY weekday_base.family_name
        ), month_totals AS (
         SELECT day_base.family_name,
            day_base.mm,
            sum(day_base.qty_total) AS qty_month_total,
            sum(day_base.value_total) AS value_month_total
           FROM day_base
          GROUP BY day_base.family_name, day_base.mm
        ), month_rank AS (
         SELECT month_totals.family_name,
            month_totals.mm,
            month_totals.qty_month_total,
            month_totals.value_month_total,
            row_number() OVER (PARTITION BY month_totals.family_name ORDER BY month_totals.qty_month_total DESC, month_totals.mm) AS rn_qty,
            row_number() OVER (PARTITION BY month_totals.family_name ORDER BY month_totals.value_month_total DESC, month_totals.mm) AS rn_value
           FROM month_totals
        ), month_conc AS (
         SELECT mr.family_name,
            (sum(mr.qty_month_total) FILTER (WHERE (mr.rn_qty <= 3)) / NULLIF(t_1.qty_total, (0)::numeric)) AS top3_months_qty_share,
            (sum(mr.qty_month_total) FILTER (WHERE (mr.rn_qty <= 6)) / NULLIF(t_1.qty_total, (0)::numeric)) AS top6_months_qty_share,
            (sum(mr.value_month_total) FILTER (WHERE (mr.rn_value <= 3)) / NULLIF(t_1.value_total, (0)::numeric)) AS top3_months_value_share,
            (sum(mr.value_month_total) FILTER (WHERE (mr.rn_value <= 6)) / NULLIF(t_1.value_total, (0)::numeric)) AS top6_months_value_share
           FROM (month_rank mr
             JOIN totals t_1 ON ((t_1.family_name = mr.family_name)))
          GROUP BY mr.family_name, t_1.qty_total, t_1.value_total
        ), week_totals AS (
         SELECT day_base.family_name,
            day_base.week_start,
            sum(day_base.qty_total) AS qty_week_total,
            sum(day_base.value_total) AS value_week_total
           FROM day_base
          GROUP BY day_base.family_name, day_base.week_start
        ), week_rank AS (
         SELECT week_totals.family_name,
            week_totals.week_start,
            week_totals.qty_week_total,
            week_totals.value_week_total,
            row_number() OVER (PARTITION BY week_totals.family_name ORDER BY week_totals.qty_week_total DESC, week_totals.week_start) AS rn_qty,
            row_number() OVER (PARTITION BY week_totals.family_name ORDER BY week_totals.value_week_total DESC, week_totals.week_start) AS rn_value
           FROM week_totals
        ), week_conc AS (
         SELECT wr.family_name,
            (sum(wr.qty_week_total) FILTER (WHERE (wr.rn_qty <= 4)) / NULLIF(t_1.qty_total, (0)::numeric)) AS top4_weeks_qty_share,
            (sum(wr.qty_week_total) FILTER (WHERE (wr.rn_qty <= 8)) / NULLIF(t_1.qty_total, (0)::numeric)) AS top8_weeks_qty_share,
            (sum(wr.value_week_total) FILTER (WHERE (wr.rn_value <= 4)) / NULLIF(t_1.value_total, (0)::numeric)) AS top4_weeks_value_share,
            (sum(wr.value_week_total) FILTER (WHERE (wr.rn_value <= 8)) / NULLIF(t_1.value_total, (0)::numeric)) AS top8_weeks_value_share
           FROM (week_rank wr
             JOIN totals t_1 ON ((t_1.family_name = wr.family_name)))
          GROUP BY wr.family_name, t_1.qty_total, t_1.value_total
        ), day_rank AS (
         SELECT day_base.family_name,
            day_base.data,
            day_base.qty_total,
            day_base.value_total,
            row_number() OVER (PARTITION BY day_base.family_name ORDER BY day_base.qty_total DESC, day_base.data) AS rn_qty,
            row_number() OVER (PARTITION BY day_base.family_name ORDER BY day_base.value_total DESC, day_base.data) AS rn_value
           FROM day_base
        ), day_conc AS (
         SELECT dr.family_name,
            (sum(dr.qty_total) FILTER (WHERE (dr.rn_qty <= 10)) / NULLIF(t_1.qty_total, (0)::numeric)) AS top10_days_qty_share,
            (sum(dr.qty_total) FILTER (WHERE (dr.rn_qty <= 30)) / NULLIF(t_1.qty_total, (0)::numeric)) AS top30_days_qty_share,
            (sum(dr.value_total) FILTER (WHERE (dr.rn_value <= 10)) / NULLIF(t_1.value_total, (0)::numeric)) AS top10_days_value_share,
            (sum(dr.value_total) FILTER (WHERE (dr.rn_value <= 30)) / NULLIF(t_1.value_total, (0)::numeric)) AS top30_days_value_share
           FROM (day_rank dr
             JOIN totals t_1 ON ((t_1.family_name = dr.family_name)))
          GROUP BY dr.family_name, t_1.qty_total, t_1.value_total
        ), peak_month_by_year AS (
         SELECT month_base.family_name,
            month_base.yy,
            month_base.mm,
            month_base.qty_month,
            row_number() OVER (PARTITION BY month_base.family_name, month_base.yy ORDER BY month_base.qty_month DESC, month_base.mm) AS rn
           FROM month_base
        ), peak_month_stability AS (
         SELECT peak_month_by_year.family_name,
            (stddev_samp(peak_month_by_year.mm))::numeric(18,6) AS peak_month_std,
            (avg(peak_month_by_year.mm))::numeric(18,6) AS peak_month_avg
           FROM peak_month_by_year
          WHERE (peak_month_by_year.rn = 1)
          GROUP BY peak_month_by_year.family_name
        ), holiday_windows AS (
         SELECT day_base.family_name,
            (sum(
                CASE
                    WHEN (day_base.mm = 12) THEN day_base.qty_total
                    ELSE (0)::numeric
                END) / NULLIF(sum(day_base.qty_total), (0)::numeric)) AS xmas_qty_share,
            (sum(
                CASE
                    WHEN (day_base.mm = 12) THEN day_base.value_total
                    ELSE (0)::numeric
                END) / NULLIF(sum(day_base.value_total), (0)::numeric)) AS xmas_value_share,
            (sum(
                CASE
                    WHEN (day_base.mm = ANY (ARRAY[3, 4])) THEN day_base.qty_total
                    ELSE (0)::numeric
                END) / NULLIF(sum(day_base.qty_total), (0)::numeric)) AS spring_qty_share,
            (sum(
                CASE
                    WHEN (day_base.mm = ANY (ARRAY[3, 4, 5])) THEN day_base.value_total
                    ELSE (0)::numeric
                END) / NULLIF(sum(day_base.value_total), (0)::numeric)) AS spring_value_share
           FROM day_base
          GROUP BY day_base.family_name
        )
 SELECT t.family_name,
    pds.avg_qty_pos,
    pds.std_qty_pos,
        CASE
            WHEN ((pds.avg_qty_pos IS NOT NULL) AND (pds.avg_qty_pos <> (0)::numeric)) THEN round((pds.std_qty_pos / pds.avg_qty_pos), 6)
            ELSE NULL::numeric
        END AS cv_pos_qty,
    pds.avg_value_pos,
    pds.std_value_pos,
        CASE
            WHEN ((pds.avg_value_pos IS NOT NULL) AND (pds.avg_value_pos <> (0)::numeric)) THEN round((pds.std_value_pos / pds.avg_value_pos), 6)
            ELSE NULL::numeric
        END AS cv_pos_value,
    ws.avg_qty_week,
    ws.std_qty_week,
        CASE
            WHEN ((ws.avg_qty_week IS NOT NULL) AND (ws.avg_qty_week <> (0)::numeric)) THEN round((ws.std_qty_week / ws.avg_qty_week), 6)
            ELSE NULL::numeric
        END AS cv_week_qty,
    ws.avg_value_week,
    ws.std_value_week,
        CASE
            WHEN ((ws.avg_value_week IS NOT NULL) AND (ws.avg_value_week <> (0)::numeric)) THEN round((ws.std_value_week / ws.avg_value_week), 6)
            ELSE NULL::numeric
        END AS cv_week_value,
    ms.avg_qty_month,
    ms.std_qty_month,
        CASE
            WHEN ((ms.avg_qty_month IS NOT NULL) AND (ms.avg_qty_month <> (0)::numeric)) THEN round((ms.std_qty_month / ms.avg_qty_month), 6)
            ELSE NULL::numeric
        END AS cv_month_qty,
    ms.avg_value_month,
    ms.std_value_month,
        CASE
            WHEN ((ms.avg_value_month IS NOT NULL) AND (ms.avg_value_month <> (0)::numeric)) THEN round((ms.std_value_month / ms.avg_value_month), 6)
            ELSE NULL::numeric
        END AS cv_month_value,
    ys.avg_qty_year,
    ys.std_qty_year,
        CASE
            WHEN ((ys.avg_qty_year IS NOT NULL) AND (ys.avg_qty_year <> (0)::numeric)) THEN round((ys.std_qty_year / ys.avg_qty_year), 6)
            ELSE NULL::numeric
        END AS cv_year_qty,
    ys.avg_value_year,
    ys.std_value_year,
        CASE
            WHEN ((ys.avg_value_year IS NOT NULL) AND (ys.avg_value_year <> (0)::numeric)) THEN round((ys.std_value_year / ys.avg_value_year), 6)
            ELSE NULL::numeric
        END AS cv_year_value,
    wds.avg_qty_weekday,
    wds.std_qty_weekday,
        CASE
            WHEN ((wds.avg_qty_weekday IS NOT NULL) AND (wds.avg_qty_weekday <> (0)::numeric)) THEN round((wds.std_qty_weekday / wds.avg_qty_weekday), 6)
            ELSE NULL::numeric
        END AS cv_weekday_qty,
    wds.avg_value_weekday,
    wds.std_value_weekday,
        CASE
            WHEN ((wds.avg_value_weekday IS NOT NULL) AND (wds.avg_value_weekday <> (0)::numeric)) THEN round((wds.std_value_weekday / wds.avg_value_weekday), 6)
            ELSE NULL::numeric
        END AS cv_weekday_value,
    round(gs.avg_gap_days, 4) AS avg_gap_days,
    round(gs.median_gap_days, 4) AS median_gap_days,
    round(gs.p90_gap_days, 4) AS p90_gap_days,
    round(gs.max_gap_days, 4) AS max_gap_days,
    round(ws.weeks_active_ratio, 6) AS weeks_active_ratio,
    round(ms.months_active_ratio, 6) AS months_active_ratio,
    round(ys.years_active_ratio, 6) AS years_active_ratio,
    round(mc.top3_months_qty_share, 6) AS top3_months_qty_share,
    round(mc.top6_months_qty_share, 6) AS top6_months_qty_share,
    round(mc.top3_months_value_share, 6) AS top3_months_value_share,
    round(mc.top6_months_value_share, 6) AS top6_months_value_share,
    round(wc.top4_weeks_qty_share, 6) AS top4_weeks_qty_share,
    round(wc.top8_weeks_qty_share, 6) AS top8_weeks_qty_share,
    round(wc.top4_weeks_value_share, 6) AS top4_weeks_value_share,
    round(wc.top8_weeks_value_share, 6) AS top8_weeks_value_share,
    round(dc.top10_days_qty_share, 6) AS top10_days_qty_share,
    round(dc.top30_days_qty_share, 6) AS top30_days_qty_share,
    round(dc.top10_days_value_share, 6) AS top10_days_value_share,
    round(dc.top30_days_value_share, 6) AS top30_days_value_share,
    round((pms.peak_month_std)::numeric, 6) AS peak_month_std,
    round((pms.peak_month_avg)::numeric, 6) AS peak_month_avg,
    round(hw.xmas_qty_share, 6) AS xmas_qty_share,
    round(hw.xmas_value_share, 6) AS xmas_value_share,
    round(hw.spring_qty_share, 6) AS spring_qty_share,
    round(hw.spring_value_share, 6) AS spring_value_share
   FROM (((((((((((totals t
     LEFT JOIN pos_day_stats pds ON ((pds.family_name = t.family_name)))
     LEFT JOIN week_stats ws ON ((ws.family_name = t.family_name)))
     LEFT JOIN month_stats ms ON ((ms.family_name = t.family_name)))
     LEFT JOIN year_stats ys ON ((ys.family_name = t.family_name)))
     LEFT JOIN weekday_stats wds ON ((wds.family_name = t.family_name)))
     LEFT JOIN gap_stats gs ON ((gs.family_name = t.family_name)))
     LEFT JOIN month_conc mc ON ((mc.family_name = t.family_name)))
     LEFT JOIN week_conc wc ON ((wc.family_name = t.family_name)))
     LEFT JOIN day_conc dc ON ((dc.family_name = t.family_name)))
     LEFT JOIN peak_month_stability pms ON ((pms.family_name = t.family_name)))
     LEFT JOIN holiday_windows hw ON ((hw.family_name = t.family_name)))
  WITH NO DATA;


--
-- Name: mv_family_metrics_v5; Type: MATERIALIZED VIEW; Schema: ml_diag; Owner: -
--

CREATE MATERIALIZED VIEW ml_diag.mv_family_metrics_v5 AS
 WITH day_base AS (
         SELECT mv_family_day_base.family_name,
            mv_family_day_base.data,
            mv_family_day_base.qty_total,
            mv_family_day_base.value_total,
            (EXTRACT(year FROM mv_family_day_base.data))::integer AS yy,
            (EXTRACT(month FROM mv_family_day_base.data))::integer AS mm
           FROM ml_diag.mv_family_day_base
        ), totals AS (
         SELECT day_base.family_name,
            sum(day_base.qty_total) AS qty_total,
            sum(day_base.value_total) AS value_total
           FROM day_base
          GROUP BY day_base.family_name
        ), month_of_year AS (
         SELECT day_base.family_name,
            day_base.mm,
            sum(day_base.qty_total) AS qty_month,
            sum(day_base.value_total) AS value_month
           FROM day_base
          GROUP BY day_base.family_name, day_base.mm
        ), month_rank_qty AS (
         SELECT m.family_name,
            m.mm,
            m.qty_month,
            row_number() OVER (PARTITION BY m.family_name ORDER BY m.qty_month DESC, m.mm) AS rn_qty,
            (sum(m.qty_month) OVER (PARTITION BY m.family_name ORDER BY m.qty_month DESC, m.mm ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / NULLIF(t_1.qty_total, (0)::numeric)) AS cum_qty_share
           FROM (month_of_year m
             JOIN totals t_1 ON ((t_1.family_name = m.family_name)))
        ), month_rank_value AS (
         SELECT m.family_name,
            m.mm,
            m.value_month,
            row_number() OVER (PARTITION BY m.family_name ORDER BY m.value_month DESC, m.mm) AS rn_value,
            (sum(m.value_month) OVER (PARTITION BY m.family_name ORDER BY m.value_month DESC, m.mm ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / NULLIF(t_1.value_total, (0)::numeric)) AS cum_value_share
           FROM (month_of_year m
             JOIN totals t_1 ON ((t_1.family_name = m.family_name)))
        ), season_width_qty AS (
         SELECT month_rank_qty.family_name,
            min(month_rank_qty.rn_qty) FILTER (WHERE (month_rank_qty.cum_qty_share >= 0.80)) AS months_to_80_qty,
            min(month_rank_qty.rn_qty) FILTER (WHERE (month_rank_qty.cum_qty_share >= 0.90)) AS months_to_90_qty
           FROM month_rank_qty
          GROUP BY month_rank_qty.family_name
        ), season_width_value AS (
         SELECT month_rank_value.family_name,
            min(month_rank_value.rn_value) FILTER (WHERE (month_rank_value.cum_value_share >= 0.80)) AS months_to_80_value,
            min(month_rank_value.rn_value) FILTER (WHERE (month_rank_value.cum_value_share >= 0.90)) AS months_to_90_value
           FROM month_rank_value
          GROUP BY month_rank_value.family_name
        ), year_month AS (
         SELECT day_base.family_name,
            day_base.yy,
            day_base.mm,
            sum(day_base.qty_total) AS qty_month,
            sum(day_base.value_total) AS value_month
           FROM day_base
          GROUP BY day_base.family_name, day_base.yy, day_base.mm
        ), year_peak_qty AS (
         SELECT x.family_name,
            x.yy,
            x.mm AS peak_month_qty
           FROM ( SELECT year_month.family_name,
                    year_month.yy,
                    year_month.mm,
                    year_month.qty_month,
                    row_number() OVER (PARTITION BY year_month.family_name, year_month.yy ORDER BY year_month.qty_month DESC, year_month.mm) AS rn
                   FROM year_month) x
          WHERE (x.rn = 1)
        ), year_peak_value AS (
         SELECT x.family_name,
            x.yy,
            x.mm AS peak_month_value
           FROM ( SELECT year_month.family_name,
                    year_month.yy,
                    year_month.mm,
                    year_month.value_month,
                    row_number() OVER (PARTITION BY year_month.family_name, year_month.yy ORDER BY year_month.value_month DESC, year_month.mm) AS rn
                   FROM year_month) x
          WHERE (x.rn = 1)
        ), peak_repeat_qty AS (
         SELECT s.family_name,
            (stddev_samp(s.peak_month_qty))::numeric(12,6) AS peak_month_std_qty,
            ((max(s.cnt))::numeric(12,6) / NULLIF(sum(s.cnt), (0)::numeric)) AS dominant_peak_month_share_qty
           FROM ( SELECT year_peak_qty.family_name,
                    year_peak_qty.peak_month_qty,
                    count(*) AS cnt
                   FROM year_peak_qty
                  GROUP BY year_peak_qty.family_name, year_peak_qty.peak_month_qty) s
          GROUP BY s.family_name
        ), peak_repeat_value AS (
         SELECT s.family_name,
            (stddev_samp(s.peak_month_value))::numeric(12,6) AS peak_month_std_value,
            ((max(s.cnt))::numeric(12,6) / NULLIF(sum(s.cnt), (0)::numeric)) AS dominant_peak_month_share_value
           FROM ( SELECT year_peak_value.family_name,
                    year_peak_value.peak_month_value,
                    count(*) AS cnt
                   FROM year_peak_value
                  GROUP BY year_peak_value.family_name, year_peak_value.peak_month_value) s
          GROUP BY s.family_name
        ), qty_run_marks AS (
         SELECT day_base.family_name,
            day_base.data,
                CASE
                    WHEN (day_base.qty_total > (0)::numeric) THEN 1
                    ELSE 0
                END AS flag,
            (row_number() OVER (PARTITION BY day_base.family_name ORDER BY day_base.data) - row_number() OVER (PARTITION BY day_base.family_name,
                CASE
                    WHEN (day_base.qty_total > (0)::numeric) THEN 1
                    ELSE 0
                END ORDER BY day_base.data)) AS grp
           FROM day_base
        ), qty_runs AS (
         SELECT qty_run_marks.family_name,
            qty_run_marks.flag,
            qty_run_marks.grp,
            count(*) AS run_len
           FROM qty_run_marks
          GROUP BY qty_run_marks.family_name, qty_run_marks.flag, qty_run_marks.grp
        ), qty_run_stats AS (
         SELECT qty_runs.family_name,
            avg((qty_runs.run_len)::numeric) FILTER (WHERE (qty_runs.flag = 1)) AS avg_pos_run_len_qty,
            percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((qty_runs.run_len)::double precision)) FILTER (WHERE (qty_runs.flag = 1)) AS median_pos_run_len_qty,
            max(qty_runs.run_len) FILTER (WHERE (qty_runs.flag = 1)) AS max_pos_run_len_qty,
            avg((qty_runs.run_len)::numeric) FILTER (WHERE (qty_runs.flag = 0)) AS avg_zero_run_len_qty,
            percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((qty_runs.run_len)::double precision)) FILTER (WHERE (qty_runs.flag = 0)) AS median_zero_run_len_qty,
            max(qty_runs.run_len) FILTER (WHERE (qty_runs.flag = 0)) AS max_zero_run_len_qty
           FROM qty_runs
          GROUP BY qty_runs.family_name
        ), value_run_marks AS (
         SELECT day_base.family_name,
            day_base.data,
                CASE
                    WHEN (day_base.value_total > (0)::numeric) THEN 1
                    ELSE 0
                END AS flag,
            (row_number() OVER (PARTITION BY day_base.family_name ORDER BY day_base.data) - row_number() OVER (PARTITION BY day_base.family_name,
                CASE
                    WHEN (day_base.value_total > (0)::numeric) THEN 1
                    ELSE 0
                END ORDER BY day_base.data)) AS grp
           FROM day_base
        ), value_runs AS (
         SELECT value_run_marks.family_name,
            value_run_marks.flag,
            value_run_marks.grp,
            count(*) AS run_len
           FROM value_run_marks
          GROUP BY value_run_marks.family_name, value_run_marks.flag, value_run_marks.grp
        ), value_run_stats AS (
         SELECT value_runs.family_name,
            avg((value_runs.run_len)::numeric) FILTER (WHERE (value_runs.flag = 1)) AS avg_pos_run_len_value,
            percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((value_runs.run_len)::double precision)) FILTER (WHERE (value_runs.flag = 1)) AS median_pos_run_len_value,
            max(value_runs.run_len) FILTER (WHERE (value_runs.flag = 1)) AS max_pos_run_len_value,
            avg((value_runs.run_len)::numeric) FILTER (WHERE (value_runs.flag = 0)) AS avg_zero_run_len_value,
            percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((value_runs.run_len)::double precision)) FILTER (WHERE (value_runs.flag = 0)) AS median_zero_run_len_value,
            max(value_runs.run_len) FILTER (WHERE (value_runs.flag = 0)) AS max_zero_run_len_value
           FROM value_runs
          GROUP BY value_runs.family_name
        ), qty_pos_days AS (
         SELECT day_base.family_name,
            day_base.data,
            lag(day_base.data) OVER (PARTITION BY day_base.family_name ORDER BY day_base.data) AS prev_data
           FROM day_base
          WHERE (day_base.qty_total > (0)::numeric)
        ), qty_gap_stats AS (
         SELECT qty_pos_days.family_name,
            (avg((qty_pos_days.data - qty_pos_days.prev_data)))::numeric(12,6) AS avg_gap_days_qty,
            (percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY (((qty_pos_days.data - qty_pos_days.prev_data))::double precision)))::numeric(12,6) AS median_gap_days_qty,
            (percentile_cont((0.9)::double precision) WITHIN GROUP (ORDER BY (((qty_pos_days.data - qty_pos_days.prev_data))::double precision)))::numeric(12,6) AS p90_gap_days_qty,
            (max((qty_pos_days.data - qty_pos_days.prev_data)))::numeric(12,6) AS max_gap_days_qty
           FROM qty_pos_days
          WHERE (qty_pos_days.prev_data IS NOT NULL)
          GROUP BY qty_pos_days.family_name
        ), value_pos_days AS (
         SELECT day_base.family_name,
            day_base.data,
            lag(day_base.data) OVER (PARTITION BY day_base.family_name ORDER BY day_base.data) AS prev_data
           FROM day_base
          WHERE (day_base.value_total > (0)::numeric)
        ), value_gap_stats AS (
         SELECT value_pos_days.family_name,
            (avg((value_pos_days.data - value_pos_days.prev_data)))::numeric(12,6) AS avg_gap_days_value,
            (percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY (((value_pos_days.data - value_pos_days.prev_data))::double precision)))::numeric(12,6) AS median_gap_days_value,
            (percentile_cont((0.9)::double precision) WITHIN GROUP (ORDER BY (((value_pos_days.data - value_pos_days.prev_data))::double precision)))::numeric(12,6) AS p90_gap_days_value,
            (max((value_pos_days.data - value_pos_days.prev_data)))::numeric(12,6) AS max_gap_days_value
           FROM value_pos_days
          WHERE (value_pos_days.prev_data IS NOT NULL)
          GROUP BY value_pos_days.family_name
        ), alignment AS (
         SELECT t_1.family_name,
            (abs((COALESCE(v4.top3_months_qty_share, (0)::numeric) - COALESCE(v4.top3_months_value_share, (0)::numeric))))::numeric(12,6) AS top3_months_gap_qty_value,
            (abs((COALESCE(v4.top4_weeks_qty_share, (0)::numeric) - COALESCE(v4.top4_weeks_value_share, (0)::numeric))))::numeric(12,6) AS top4_weeks_gap_qty_value,
            (abs((COALESCE(v4.top10_days_qty_share, (0)::numeric) - COALESCE(v4.top10_days_value_share, (0)::numeric))))::numeric(12,6) AS top10_days_gap_qty_value,
                CASE
                    WHEN (COALESCE(t_1.qty_total, (0)::numeric) > (0)::numeric) THEN ((t_1.value_total / t_1.qty_total))::numeric(12,6)
                    ELSE NULL::numeric
                END AS avg_unit_value
           FROM (totals t_1
             LEFT JOIN ml_diag.mv_family_metrics_v4 v4 ON ((v4.family_name = t_1.family_name)))
        )
 SELECT t.family_name,
    swq.months_to_80_qty,
    swq.months_to_90_qty,
    swv.months_to_80_value,
    swv.months_to_90_value,
    prq.peak_month_std_qty,
    prv.peak_month_std_value,
    prq.dominant_peak_month_share_qty,
    prv.dominant_peak_month_share_value,
    (qrs.avg_pos_run_len_qty)::numeric(12,6) AS avg_pos_run_len_qty,
    (qrs.median_pos_run_len_qty)::numeric(12,6) AS median_pos_run_len_qty,
    qrs.max_pos_run_len_qty,
    (qrs.avg_zero_run_len_qty)::numeric(12,6) AS avg_zero_run_len_qty,
    (qrs.median_zero_run_len_qty)::numeric(12,6) AS median_zero_run_len_qty,
    qrs.max_zero_run_len_qty,
    (vrs.avg_pos_run_len_value)::numeric(12,6) AS avg_pos_run_len_value,
    (vrs.median_pos_run_len_value)::numeric(12,6) AS median_pos_run_len_value,
    vrs.max_pos_run_len_value,
    (vrs.avg_zero_run_len_value)::numeric(12,6) AS avg_zero_run_len_value,
    (vrs.median_zero_run_len_value)::numeric(12,6) AS median_zero_run_len_value,
    vrs.max_zero_run_len_value,
    qgs.avg_gap_days_qty,
    qgs.median_gap_days_qty,
    qgs.p90_gap_days_qty,
    qgs.max_gap_days_qty,
    vgs.avg_gap_days_value,
    vgs.median_gap_days_value,
    vgs.p90_gap_days_value,
    vgs.max_gap_days_value,
    a.top3_months_gap_qty_value,
    a.top4_weeks_gap_qty_value,
    a.top10_days_gap_qty_value,
    a.avg_unit_value
   FROM (((((((((totals t
     LEFT JOIN season_width_qty swq ON ((swq.family_name = t.family_name)))
     LEFT JOIN season_width_value swv ON ((swv.family_name = t.family_name)))
     LEFT JOIN peak_repeat_qty prq ON ((prq.family_name = t.family_name)))
     LEFT JOIN peak_repeat_value prv ON ((prv.family_name = t.family_name)))
     LEFT JOIN qty_run_stats qrs ON ((qrs.family_name = t.family_name)))
     LEFT JOIN value_run_stats vrs ON ((vrs.family_name = t.family_name)))
     LEFT JOIN qty_gap_stats qgs ON ((qgs.family_name = t.family_name)))
     LEFT JOIN value_gap_stats vgs ON ((vgs.family_name = t.family_name)))
     LEFT JOIN alignment a ON ((a.family_name = t.family_name)))
  WITH NO DATA;


--
-- Name: mv_family_seasonality; Type: MATERIALIZED VIEW; Schema: ml_diag; Owner: -
--

CREATE MATERIALIZED VIEW ml_diag.mv_family_seasonality AS
 WITH pos AS (
         SELECT mv_family_day_base.family_name,
            (EXTRACT(year FROM mv_family_day_base.data))::integer AS yy,
            (EXTRACT(doy FROM mv_family_day_base.data))::integer AS doy,
            mv_family_day_base.qty_total
           FROM ml_diag.mv_family_day_base
          WHERE (mv_family_day_base.qty_total > (0)::numeric)
        ), first_sale AS (
         SELECT pos.family_name,
            pos.yy,
            min(pos.doy) AS first_doy
           FROM pos
          GROUP BY pos.family_name, pos.yy
        ), peak_doy AS (
         SELECT x.family_name,
            x.doy AS peak_doy
           FROM ( SELECT pos.family_name,
                    pos.doy,
                    sum(pos.qty_total) AS qty_on_doy,
                    row_number() OVER (PARTITION BY pos.family_name ORDER BY (sum(pos.qty_total)) DESC, pos.doy) AS rn
                   FROM pos
                  GROUP BY pos.family_name, pos.doy) x
          WHERE (x.rn = 1)
        )
 SELECT f.family_name,
    (count(*))::integer AS years_with_sales,
    round((percentile_cont((0.25)::double precision) WITHIN GROUP (ORDER BY ((f.first_doy)::double precision)))::numeric, 1) AS season_start_p25,
    round((percentile_cont((0.50)::double precision) WITHIN GROUP (ORDER BY ((f.first_doy)::double precision)))::numeric, 1) AS season_start_p50,
    round((percentile_cont((0.75)::double precision) WITHIN GROUP (ORDER BY ((f.first_doy)::double precision)))::numeric, 1) AS season_start_p75,
    p.peak_doy
   FROM (first_sale f
     LEFT JOIN peak_doy p ON ((p.family_name = f.family_name)))
  GROUP BY f.family_name, p.peak_doy
  WITH NO DATA;


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
-- Name: v_family_diagnostics; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics AS
 WITH base AS (
         SELECT lower(TRIM(BOTH FROM greenhouse_forecast_features_dense.famiglia)) AS family_name,
            greenhouse_forecast_features_dense.data,
            sum(COALESCE(greenhouse_forecast_features_dense.qty_venduta, (0)::numeric)) AS qty
           FROM public.greenhouse_forecast_features_dense
          WHERE ((greenhouse_forecast_features_dense.famiglia IS NOT NULL) AND (TRIM(BOTH FROM greenhouse_forecast_features_dense.famiglia) <> ''::text) AND (greenhouse_forecast_features_dense.data >= '2009-01-01'::date))
          GROUP BY (lower(TRIM(BOTH FROM greenhouse_forecast_features_dense.famiglia))), greenhouse_forecast_features_dense.data
        ), fam AS (
         SELECT base.family_name,
            count(*) AS days_total,
            sum(
                CASE
                    WHEN (base.qty > (0)::numeric) THEN 1
                    ELSE 0
                END) AS pos_days,
            sum(
                CASE
                    WHEN (base.qty = (0)::numeric) THEN 1
                    ELSE 0
                END) AS zero_days,
            sum(base.qty) AS qty_total,
            avg(base.qty) AS qty_avg_all_days,
            avg(
                CASE
                    WHEN (base.qty > (0)::numeric) THEN base.qty
                    ELSE NULL::numeric
                END) AS qty_avg_pos_days,
            stddev_samp(
                CASE
                    WHEN (base.qty > (0)::numeric) THEN base.qty
                    ELSE NULL::numeric
                END) AS qty_std_pos_days,
            min(base.data) AS min_date,
            max(base.data) AS max_date,
            count(DISTINCT EXTRACT(year FROM base.data)) AS years_count,
            count(DISTINCT
                CASE
                    WHEN (base.qty > (0)::numeric) THEN EXTRACT(month FROM base.data)
                    ELSE NULL::numeric
                END) AS active_months
           FROM base
          GROUP BY base.family_name
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    round(((zero_days)::numeric / (NULLIF(days_total, 0))::numeric), 4) AS zero_rate,
    round(((pos_days)::numeric / (NULLIF(days_total, 0))::numeric), 4) AS pos_rate,
    round(qty_total, 2) AS qty_total,
    round(qty_avg_all_days, 4) AS qty_avg_all_days,
    round(qty_avg_pos_days, 4) AS qty_avg_pos_days,
    round(qty_std_pos_days, 4) AS qty_std_pos_days,
    years_count,
    active_months,
    min_date,
    max_date
   FROM fam;


--
-- Name: v_family_diagnostics_final; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_final AS
 SELECT s.family_name,
    s.days_total,
    s.pos_days,
    s.zero_days,
    s.zero_rate,
    s.pos_rate,
    s.qty_total,
    s.qty_avg_all_days,
    s.qty_avg_pos_days,
    s.qty_std_pos_days,
    s.value_total,
    s.value_avg_all_days,
    s.value_avg_pos_days,
    s.value_std_pos_days,
    s.years_count,
    s.active_months,
    s.active_value_months,
    i.adi,
    i.cv2_pos,
    sea.years_with_sales,
    sea.season_start_p25,
    sea.season_start_p50,
    sea.season_start_p75,
    sea.peak_doy,
    imp.qty_pct_total,
    imp.qty_cum_pct,
    imp.qty_tier,
    imp.value_pct_total,
    imp.value_cum_pct,
    imp.value_tier,
    imp.business_tier,
        CASE
            WHEN (s.pos_days < 2) THEN 'insufficient'::text
            WHEN ((i.adi >= 1.32) AND (i.cv2_pos >= 0.49)) THEN 'lumpy'::text
            WHEN ((i.adi >= 1.32) AND (COALESCE(i.cv2_pos, (0)::numeric) < 0.49)) THEN 'intermittent'::text
            WHEN ((i.adi < 1.32) AND (s.active_months <= 8)) THEN 'seasonal'::text
            ELSE 'dense'::text
        END AS demand_class,
        CASE
            WHEN ((s.pos_days < 5) OR (s.qty_total < (10)::numeric)) THEN 'weak'::text
            WHEN ((s.pos_days < 30) OR (s.qty_total < (100)::numeric)) THEN 'medium'::text
            ELSE 'strong'::text
        END AS data_quality_class,
        CASE
            WHEN (s.active_months <= 2) THEN 'very_narrow'::text
            WHEN (s.active_months <= 4) THEN 'seasonal'::text
            WHEN (s.active_months <= 8) THEN 'broad_seasonal'::text
            ELSE 'all_year'::text
        END AS seasonality_span_class,
    concat(imp.business_tier, '_',
        CASE
            WHEN (s.pos_days < 2) THEN 'insufficient'::text
            WHEN ((i.adi >= 1.32) AND (i.cv2_pos >= 0.49)) THEN 'lumpy'::text
            WHEN ((i.adi >= 1.32) AND (COALESCE(i.cv2_pos, (0)::numeric) < 0.49)) THEN 'intermittent'::text
            WHEN ((i.adi < 1.32) AND (s.active_months <= 8)) THEN 'seasonal'::text
            ELSE 'dense'::text
        END) AS combined_segment
   FROM (((ml_diag.mv_family_stats s
     LEFT JOIN ml_diag.mv_family_intermittency i ON ((i.family_name = s.family_name)))
     LEFT JOIN ml_diag.mv_family_seasonality sea ON ((sea.family_name = s.family_name)))
     LEFT JOIN ml_diag.mv_family_importance imp ON ((imp.family_name = s.family_name)));


--
-- Name: v_family_diagnostics_v2; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v2 AS
 WITH base AS (
         SELECT s.family_name,
            s.days_total,
            s.pos_days,
            s.zero_days,
            s.zero_rate,
            s.pos_rate,
            s.qty_total,
            s.qty_avg_all_days,
            s.qty_avg_pos_days,
            s.qty_std_pos_days,
            s.value_total,
            s.value_avg_all_days,
            s.value_avg_pos_days,
            s.value_std_pos_days,
            s.years_count,
            s.active_months,
            s.active_value_months,
            i.adi,
            i.cv2_pos,
            sea.years_with_sales,
            sea.season_start_p25,
            sea.season_start_p50,
            sea.season_start_p75,
            sea.peak_doy,
            imp.qty_pct_total,
            imp.qty_cum_pct,
            imp.qty_tier,
            imp.value_pct_total,
            imp.value_cum_pct,
            imp.value_tier,
            imp.business_tier,
                CASE
                    WHEN ((sea.season_start_p25 IS NOT NULL) AND (sea.season_start_p75 IS NOT NULL)) THEN round((sea.season_start_p75 - sea.season_start_p25), 1)
                    ELSE NULL::numeric
                END AS season_start_iqr
           FROM (((ml_diag.mv_family_stats s
             LEFT JOIN ml_diag.mv_family_intermittency i ON ((i.family_name = s.family_name)))
             LEFT JOIN ml_diag.mv_family_seasonality sea ON ((sea.family_name = s.family_name)))
             LEFT JOIN ml_diag.mv_family_importance imp ON ((imp.family_name = s.family_name)))
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
        CASE
            WHEN (pos_days < 2) THEN 'insufficient'::text
            WHEN ((adi >= 1.32) AND (cv2_pos >= 0.49)) THEN 'lumpy'::text
            WHEN ((adi >= 1.32) AND (COALESCE(cv2_pos, (0)::numeric) < 0.49)) THEN 'intermittent'::text
            ELSE 'dense'::text
        END AS intermittency_class,
        CASE
            WHEN (active_months <= 2) THEN 'very_narrow'::text
            WHEN (active_months <= 4) THEN 'seasonal'::text
            WHEN (active_months <= 8) THEN 'broad_seasonal'::text
            ELSE 'all_year'::text
        END AS seasonality_class,
        CASE
            WHEN (pos_days < 2) THEN 'insufficient'::text
            WHEN ((active_months <= 4) AND (zero_rate >= 0.60)) THEN 'seasonal'::text
            WHEN ((active_months <= 6) AND (season_start_iqr IS NOT NULL) AND (season_start_iqr <= (60)::numeric) AND (zero_rate >= 0.40)) THEN 'seasonal'::text
            WHEN ((adi >= 1.32) AND (cv2_pos >= 0.49)) THEN 'lumpy'::text
            WHEN ((adi >= 1.32) AND (COALESCE(cv2_pos, (0)::numeric) < 0.49)) THEN 'intermittent'::text
            ELSE 'dense'::text
        END AS demand_class_v2,
        CASE
            WHEN ((pos_days < 5) OR (qty_total < (10)::numeric) OR (value_total < (100)::numeric)) THEN 'weak'::text
            WHEN ((pos_days < 30) OR (qty_total < (100)::numeric) OR (value_total < (1000)::numeric)) THEN 'medium'::text
            ELSE 'strong'::text
        END AS data_quality_class_v2,
    concat(business_tier, '_',
        CASE
            WHEN (pos_days < 2) THEN 'insufficient'::text
            WHEN ((active_months <= 4) AND (zero_rate >= 0.60)) THEN 'seasonal'::text
            WHEN ((active_months <= 6) AND (season_start_iqr IS NOT NULL) AND (season_start_iqr <= (60)::numeric) AND (zero_rate >= 0.40)) THEN 'seasonal'::text
            WHEN ((adi >= 1.32) AND (cv2_pos >= 0.49)) THEN 'lumpy'::text
            WHEN ((adi >= 1.32) AND (COALESCE(cv2_pos, (0)::numeric) < 0.49)) THEN 'intermittent'::text
            ELSE 'dense'::text
        END) AS combined_segment_v2
   FROM base;


--
-- Name: v_family_diagnostics_v3; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v3 AS
 SELECT f.family_name,
    f.days_total,
    f.pos_days,
    f.zero_days,
    f.zero_rate,
    f.pos_rate,
    f.qty_total,
    f.qty_avg_all_days,
    f.qty_avg_pos_days,
    f.qty_std_pos_days,
    f.value_total,
    f.value_avg_all_days,
    f.value_avg_pos_days,
    f.value_std_pos_days,
    f.years_count,
    f.active_months,
    f.active_value_months,
    f.adi,
    f.cv2_pos,
    f.years_with_sales,
    f.season_start_p25,
    f.season_start_p50,
    f.season_start_p75,
    f.peak_doy,
    f.qty_pct_total,
    f.qty_cum_pct,
    f.qty_tier,
    f.value_pct_total,
    f.value_cum_pct,
    f.value_tier,
    f.business_tier,
    f.season_start_iqr,
    f.intermittency_class,
    f.seasonality_class,
    f.demand_class_v2,
    f.data_quality_class_v2,
    f.combined_segment_v2,
    m.cv_total_qty,
    m.cv_total_value,
    m.season_concentration,
    m.peak_concentration,
        CASE
            WHEN (m.season_concentration >= 0.70) THEN 'strong'::text
            WHEN (m.season_concentration >= 0.50) THEN 'moderate'::text
            WHEN (m.season_concentration >= 0.30) THEN 'weak'::text
            ELSE 'none'::text
        END AS seasonality_strength,
        CASE
            WHEN (m.peak_concentration >= 0.40) THEN 'extreme'::text
            WHEN (m.peak_concentration >= 0.25) THEN 'high'::text
            WHEN (m.peak_concentration >= 0.15) THEN 'moderate'::text
            ELSE 'low'::text
        END AS peakiness_class,
        CASE
            WHEN (m.cv_total_qty <= 0.8) THEN 'stable'::text
            WHEN (m.cv_total_qty <= 1.5) THEN 'volatile'::text
            ELSE 'chaotic'::text
        END AS predictability_class
   FROM (ml_diag.v_family_diagnostics_v2 f
     LEFT JOIN ml_diag.mv_family_metrics_v3 m ON ((m.family_name = f.family_name)));


--
-- Name: v_family_diagnostics_v3b; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v3b AS
 WITH base AS (
         SELECT v2.family_name,
            v2.days_total,
            v2.pos_days,
            v2.zero_days,
            v2.zero_rate,
            v2.pos_rate,
            v2.qty_total,
            v2.qty_avg_all_days,
            v2.qty_avg_pos_days,
            v2.qty_std_pos_days,
            v2.value_total,
            v2.value_avg_all_days,
            v2.value_avg_pos_days,
            v2.value_std_pos_days,
            v2.years_count,
            v2.active_months,
            v2.active_value_months,
            v2.adi,
            v2.cv2_pos,
            v2.years_with_sales,
            v2.season_start_p25,
            v2.season_start_p50,
            v2.season_start_p75,
            v2.peak_doy,
            v2.qty_pct_total,
            v2.qty_cum_pct,
            v2.qty_tier,
            v2.value_pct_total,
            v2.value_cum_pct,
            v2.value_tier,
            v2.business_tier,
            v2.season_start_iqr,
            v2.intermittency_class,
            v2.seasonality_class,
            v2.demand_class_v2,
            v2.data_quality_class_v2,
            v2.combined_segment_v2,
            m.cv_pos_qty,
            m.cv_pos_value,
            m.cv_week_qty,
            m.cv_week_value,
            m.cv_month_qty,
            m.cv_month_value,
            m.cv_weekday_qty,
            m.cv_weekday_value,
            m.season_conc_qty,
            m.season_conc_value,
            m.peak_conc_qty,
            m.peak_conc_value,
            GREATEST(COALESCE(m.season_conc_qty, (0)::numeric), COALESCE(m.season_conc_value, (0)::numeric)) AS season_conc_max,
            GREATEST(COALESCE(m.peak_conc_qty, (0)::numeric), COALESCE(m.peak_conc_value, (0)::numeric)) AS peak_conc_max,
            GREATEST(COALESCE(m.cv_pos_qty, (0)::numeric), COALESCE(m.cv_pos_value, (0)::numeric)) AS cv_pos_max,
            GREATEST(COALESCE(m.cv_week_qty, (0)::numeric), COALESCE(m.cv_week_value, (0)::numeric)) AS cv_week_max,
            GREATEST(COALESCE(m.cv_month_qty, (0)::numeric), COALESCE(m.cv_month_value, (0)::numeric)) AS cv_month_max,
            GREATEST(COALESCE(m.cv_weekday_qty, (0)::numeric), COALESCE(m.cv_weekday_value, (0)::numeric)) AS cv_weekday_max
           FROM (ml_diag.v_family_diagnostics_v2 v2
             LEFT JOIN ml_diag.mv_family_metrics_v3b m ON ((m.family_name = v2.family_name)))
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_weekday_qty,
    cv_weekday_value,
    season_conc_qty,
    season_conc_value,
    peak_conc_qty,
    peak_conc_value,
    season_conc_max,
    peak_conc_max,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_weekday_max,
        CASE
            WHEN (season_conc_max >= 0.75) THEN 'very_strong'::text
            WHEN (season_conc_max >= 0.60) THEN 'strong'::text
            WHEN (season_conc_max >= 0.45) THEN 'moderate'::text
            WHEN (season_conc_max >= 0.30) THEN 'weak'::text
            ELSE 'diffuse'::text
        END AS seasonality_strength_v3,
        CASE
            WHEN (peak_conc_max >= 0.50) THEN 'extreme'::text
            WHEN (peak_conc_max >= 0.30) THEN 'high'::text
            WHEN (peak_conc_max >= 0.18) THEN 'moderate'::text
            ELSE 'low'::text
        END AS peakiness_class_v3,
        CASE
            WHEN ((cv_pos_max <= 0.60) AND (cv_week_max <= 0.70) AND (cv_month_max <= 0.80)) THEN 'stable'::text
            WHEN ((cv_pos_max <= 1.00) AND (cv_week_max <= 1.10) AND (cv_month_max <= 1.20)) THEN 'variable'::text
            ELSE 'unstable'::text
        END AS predictability_class_v3,
        CASE
            WHEN ((pos_days < 5) OR (qty_total < (10)::numeric) OR (value_total < (50)::numeric)) THEN 'weak'::text
            WHEN ((pos_days < 30) OR (qty_total < (100)::numeric) OR (value_total < (1000)::numeric)) THEN 'medium'::text
            ELSE 'strong'::text
        END AS reliability_class_v3,
        CASE
            WHEN (pos_days < 2) THEN 'insufficient'::text
            WHEN ((seasonality_class = ANY (ARRAY['seasonal'::text, 'broad_seasonal'::text, 'very_narrow'::text])) AND (season_conc_max >= 0.45) AND (season_start_iqr IS NOT NULL) AND (season_start_iqr <= (60)::numeric) AND (active_months <= 8) AND (intermittency_class = 'intermittent'::text)) THEN 'seasonal_intermittent'::text
            WHEN ((seasonality_class = ANY (ARRAY['seasonal'::text, 'broad_seasonal'::text, 'very_narrow'::text])) AND (season_conc_max >= 0.45) AND (season_start_iqr IS NOT NULL) AND (season_start_iqr <= (60)::numeric) AND (active_months <= 8) AND (intermittency_class = 'lumpy'::text)) THEN 'seasonal_lumpy'::text
            WHEN ((seasonality_class = ANY (ARRAY['seasonal'::text, 'broad_seasonal'::text])) AND (season_conc_max >= 0.45) AND (season_start_iqr IS NOT NULL) AND (season_start_iqr <= (60)::numeric) AND (active_months <= 8)) THEN 'seasonal'::text
            WHEN (intermittency_class = 'dense'::text) THEN 'dense'::text
            WHEN (intermittency_class = 'intermittent'::text) THEN 'intermittent'::text
            WHEN (intermittency_class = 'lumpy'::text) THEN 'lumpy'::text
            ELSE 'insufficient'::text
        END AS demand_class_v3
   FROM base b;


--
-- Name: v_family_diagnostics_v4; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v4 AS
 WITH base AS (
         SELECT v2.family_name,
            v2.days_total,
            v2.pos_days,
            v2.zero_days,
            v2.zero_rate,
            v2.pos_rate,
            v2.qty_total,
            v2.qty_avg_all_days,
            v2.qty_avg_pos_days,
            v2.qty_std_pos_days,
            v2.value_total,
            v2.value_avg_all_days,
            v2.value_avg_pos_days,
            v2.value_std_pos_days,
            v2.years_count,
            v2.active_months,
            v2.active_value_months,
            v2.adi,
            v2.cv2_pos,
            v2.years_with_sales,
            v2.season_start_p25,
            v2.season_start_p50,
            v2.season_start_p75,
            v2.peak_doy,
            v2.qty_pct_total,
            v2.qty_cum_pct,
            v2.qty_tier,
            v2.value_pct_total,
            v2.value_cum_pct,
            v2.value_tier,
            v2.business_tier,
            v2.season_start_iqr,
            v2.intermittency_class,
            v2.seasonality_class,
            v2.demand_class_v2,
            v2.data_quality_class_v2,
            v2.combined_segment_v2,
            m.cv_pos_qty,
            m.cv_pos_value,
            m.cv_week_qty,
            m.cv_week_value,
            m.cv_month_qty,
            m.cv_month_value,
            m.cv_year_qty,
            m.cv_year_value,
            m.cv_weekday_qty,
            m.cv_weekday_value,
            m.avg_gap_days,
            m.median_gap_days,
            m.p90_gap_days,
            m.max_gap_days,
            m.weeks_active_ratio,
            m.months_active_ratio,
            m.years_active_ratio,
            m.top3_months_qty_share,
            m.top6_months_qty_share,
            m.top3_months_value_share,
            m.top6_months_value_share,
            m.top4_weeks_qty_share,
            m.top8_weeks_qty_share,
            m.top4_weeks_value_share,
            m.top8_weeks_value_share,
            m.top10_days_qty_share,
            m.top30_days_qty_share,
            m.top10_days_value_share,
            m.top30_days_value_share,
            m.peak_month_std,
            m.peak_month_avg,
            m.xmas_qty_share,
            m.xmas_value_share,
            m.spring_qty_share,
            m.spring_value_share,
            GREATEST(COALESCE(m.cv_pos_qty, (0)::numeric), COALESCE(m.cv_pos_value, (0)::numeric)) AS cv_pos_max,
            GREATEST(COALESCE(m.cv_week_qty, (0)::numeric), COALESCE(m.cv_week_value, (0)::numeric)) AS cv_week_max,
            GREATEST(COALESCE(m.cv_month_qty, (0)::numeric), COALESCE(m.cv_month_value, (0)::numeric)) AS cv_month_max,
            GREATEST(COALESCE(m.cv_year_qty, (0)::numeric), COALESCE(m.cv_year_value, (0)::numeric)) AS cv_year_max,
            GREATEST(COALESCE(m.cv_weekday_qty, (0)::numeric), COALESCE(m.cv_weekday_value, (0)::numeric)) AS cv_weekday_max,
            GREATEST(COALESCE(m.top3_months_qty_share, (0)::numeric), COALESCE(m.top3_months_value_share, (0)::numeric)) AS top3_months_share_max,
            GREATEST(COALESCE(m.top6_months_qty_share, (0)::numeric), COALESCE(m.top6_months_value_share, (0)::numeric)) AS top6_months_share_max,
            GREATEST(COALESCE(m.top4_weeks_qty_share, (0)::numeric), COALESCE(m.top4_weeks_value_share, (0)::numeric)) AS top4_weeks_share_max,
            GREATEST(COALESCE(m.top8_weeks_qty_share, (0)::numeric), COALESCE(m.top8_weeks_value_share, (0)::numeric)) AS top8_weeks_share_max,
            GREATEST(COALESCE(m.top10_days_qty_share, (0)::numeric), COALESCE(m.top10_days_value_share, (0)::numeric)) AS top10_days_share_max,
            GREATEST(COALESCE(m.top30_days_qty_share, (0)::numeric), COALESCE(m.top30_days_value_share, (0)::numeric)) AS top30_days_share_max,
            GREATEST(COALESCE(m.spring_qty_share, (0)::numeric), COALESCE(m.spring_value_share, (0)::numeric)) AS spring_share_max,
            GREATEST(COALESCE(m.xmas_qty_share, (0)::numeric), COALESCE(m.xmas_value_share, (0)::numeric)) AS xmas_share_max
           FROM (ml_diag.v_family_diagnostics_v2 v2
             LEFT JOIN ml_diag.mv_family_metrics_v4 m ON ((m.family_name = v2.family_name)))
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
        CASE
            WHEN ((pos_days < 5) OR (qty_total < (10)::numeric) OR (value_total < (50)::numeric)) THEN 'weak'::text
            WHEN ((pos_days < 30) OR (qty_total < (100)::numeric) OR (value_total < (1000)::numeric)) THEN 'medium'::text
            ELSE 'strong'::text
        END AS reliability_class_v4,
        CASE
            WHEN ((cv_pos_max <= 0.60) AND (cv_week_max <= 0.75) AND (cv_month_max <= 0.85) AND (cv_year_max <= 0.90)) THEN 'stable'::text
            WHEN ((cv_pos_max <= 1.00) AND (cv_week_max <= 1.20) AND (cv_month_max <= 1.35) AND (cv_year_max <= 1.50)) THEN 'variable'::text
            ELSE 'unstable'::text
        END AS predictability_class_v4,
        CASE
            WHEN (top3_months_share_max >= 0.75) THEN 'very_strong'::text
            WHEN (top3_months_share_max >= 0.60) THEN 'strong'::text
            WHEN (top3_months_share_max >= 0.45) THEN 'moderate'::text
            WHEN (top3_months_share_max >= 0.33) THEN 'weak'::text
            ELSE 'diffuse'::text
        END AS seasonality_strength_v4,
        CASE
            WHEN (top10_days_share_max >= 0.50) THEN 'extreme'::text
            WHEN (top10_days_share_max >= 0.30) THEN 'high'::text
            WHEN (top10_days_share_max >= 0.18) THEN 'moderate'::text
            ELSE 'low'::text
        END AS day_peakiness_class_v4,
        CASE
            WHEN (top4_weeks_share_max >= 0.60) THEN 'extreme'::text
            WHEN (top4_weeks_share_max >= 0.40) THEN 'high'::text
            WHEN (top4_weeks_share_max >= 0.25) THEN 'moderate'::text
            ELSE 'low'::text
        END AS week_peakiness_class_v4,
        CASE
            WHEN (peak_month_std IS NULL) THEN 'unknown'::text
            WHEN (peak_month_std <= 0.75) THEN 'very_stable'::text
            WHEN (peak_month_std <= 1.50) THEN 'stable'::text
            WHEN (peak_month_std <= 2.50) THEN 'mobile'::text
            ELSE 'erratic'::text
        END AS peak_month_stability_class_v4,
        CASE
            WHEN (xmas_share_max >= 0.45) THEN 'xmas_driven'::text
            WHEN (spring_share_max >= 0.50) THEN 'spring_driven'::text
            ELSE 'none'::text
        END AS holiday_profile_v4,
        CASE
            WHEN (top10_days_share_max >= 0.50) THEN 'daily'::text
            WHEN (top4_weeks_share_max >= 0.45) THEN 'weekly'::text
            WHEN (top3_months_share_max >= 0.50) THEN 'monthly'::text
            ELSE 'diffuse'::text
        END AS dominant_concentration_scale_v4,
        CASE
            WHEN (pos_days < 2) THEN 'insufficient'::text
            WHEN ((top3_months_share_max >= 0.60) AND (COALESCE(peak_month_std, (99)::numeric) <= 1.50) AND ((seasonality_class = ANY (ARRAY['seasonal'::text, 'broad_seasonal'::text])) OR (active_months <= 8) OR (months_active_ratio <= 0.70)) AND (intermittency_class = 'dense'::text)) THEN 'seasonal_dense'::text
            WHEN ((top3_months_share_max >= 0.60) AND (COALESCE(peak_month_std, (99)::numeric) <= 1.75) AND ((seasonality_class = ANY (ARRAY['seasonal'::text, 'broad_seasonal'::text])) OR (active_months <= 8) OR (months_active_ratio <= 0.70)) AND (intermittency_class = 'intermittent'::text)) THEN 'seasonal_intermittent'::text
            WHEN ((top3_months_share_max >= 0.60) AND (COALESCE(peak_month_std, (99)::numeric) <= 2.00) AND ((seasonality_class = ANY (ARRAY['seasonal'::text, 'broad_seasonal'::text])) OR (active_months <= 8) OR (months_active_ratio <= 0.75)) AND (intermittency_class = 'lumpy'::text)) THEN 'seasonal_lumpy'::text
            WHEN (intermittency_class = 'dense'::text) THEN 'dense'::text
            WHEN (intermittency_class = 'intermittent'::text) THEN 'intermittent'::text
            WHEN (intermittency_class = 'lumpy'::text) THEN 'lumpy'::text
            ELSE 'other'::text
        END AS demand_class_v4
   FROM base b;


--
-- Name: v_family_diagnostics_v4_1; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v4_1 AS
 WITH base AS (
         SELECT v4.family_name,
            v4.days_total,
            v4.pos_days,
            v4.zero_days,
            v4.zero_rate,
            v4.pos_rate,
            v4.qty_total,
            v4.qty_avg_all_days,
            v4.qty_avg_pos_days,
            v4.qty_std_pos_days,
            v4.value_total,
            v4.value_avg_all_days,
            v4.value_avg_pos_days,
            v4.value_std_pos_days,
            v4.years_count,
            v4.active_months,
            v4.active_value_months,
            v4.adi,
            v4.cv2_pos,
            v4.years_with_sales,
            v4.season_start_p25,
            v4.season_start_p50,
            v4.season_start_p75,
            v4.peak_doy,
            v4.qty_pct_total,
            v4.qty_cum_pct,
            v4.qty_tier,
            v4.value_pct_total,
            v4.value_cum_pct,
            v4.value_tier,
            v4.business_tier,
            v4.season_start_iqr,
            v4.intermittency_class,
            v4.seasonality_class,
            v4.demand_class_v2,
            v4.data_quality_class_v2,
            v4.combined_segment_v2,
            v4.cv_pos_qty,
            v4.cv_pos_value,
            v4.cv_week_qty,
            v4.cv_week_value,
            v4.cv_month_qty,
            v4.cv_month_value,
            v4.cv_year_qty,
            v4.cv_year_value,
            v4.cv_weekday_qty,
            v4.cv_weekday_value,
            v4.avg_gap_days,
            v4.median_gap_days,
            v4.p90_gap_days,
            v4.max_gap_days,
            v4.weeks_active_ratio,
            v4.months_active_ratio,
            v4.years_active_ratio,
            v4.top3_months_qty_share,
            v4.top6_months_qty_share,
            v4.top3_months_value_share,
            v4.top6_months_value_share,
            v4.top4_weeks_qty_share,
            v4.top8_weeks_qty_share,
            v4.top4_weeks_value_share,
            v4.top8_weeks_value_share,
            v4.top10_days_qty_share,
            v4.top30_days_qty_share,
            v4.top10_days_value_share,
            v4.top30_days_value_share,
            v4.peak_month_std,
            v4.peak_month_avg,
            v4.xmas_qty_share,
            v4.xmas_value_share,
            v4.spring_qty_share,
            v4.spring_value_share,
            v4.cv_pos_max,
            v4.cv_week_max,
            v4.cv_month_max,
            v4.cv_year_max,
            v4.cv_weekday_max,
            v4.top3_months_share_max,
            v4.top6_months_share_max,
            v4.top4_weeks_share_max,
            v4.top8_weeks_share_max,
            v4.top10_days_share_max,
            v4.top30_days_share_max,
            v4.spring_share_max,
            v4.xmas_share_max,
            v4.reliability_class_v4,
            v4.predictability_class_v4,
            v4.seasonality_strength_v4,
            v4.day_peakiness_class_v4,
            v4.week_peakiness_class_v4,
            v4.peak_month_stability_class_v4,
            v4.holiday_profile_v4,
            v4.dominant_concentration_scale_v4,
            v4.demand_class_v4,
                CASE
                    WHEN (COALESCE(v4.top3_months_share_max, (0)::numeric) >= 0.88) THEN 'very_narrow'::text
                    WHEN (COALESCE(v4.top3_months_share_max, (0)::numeric) >= 0.75) THEN 'narrow'::text
                    WHEN (COALESCE(v4.top3_months_share_max, (0)::numeric) >= 0.60) THEN 'medium'::text
                    WHEN (COALESCE(v4.top3_months_share_max, (0)::numeric) >= 0.45) THEN 'broad'::text
                    ELSE 'diffuse'::text
                END AS season_width_class_v4_1,
                CASE
                    WHEN (COALESCE(v4.top10_days_share_max, (0)::numeric) >= 0.25) THEN 'extreme'::text
                    WHEN (COALESCE(v4.top10_days_share_max, (0)::numeric) >= 0.15) THEN 'high'::text
                    WHEN (COALESCE(v4.top10_days_share_max, (0)::numeric) >= 0.08) THEN 'moderate'::text
                    ELSE 'low'::text
                END AS day_peakiness_class_v4_1,
                CASE
                    WHEN (COALESCE(v4.top4_weeks_share_max, (0)::numeric) >= 0.35) THEN 'extreme'::text
                    WHEN (COALESCE(v4.top4_weeks_share_max, (0)::numeric) >= 0.22) THEN 'high'::text
                    WHEN (COALESCE(v4.top4_weeks_share_max, (0)::numeric) >= 0.12) THEN 'moderate'::text
                    ELSE 'low'::text
                END AS week_peakiness_class_v4_1,
                CASE
                    WHEN ((COALESCE(v4.weeks_active_ratio, (0)::numeric) >= 0.80) AND (COALESCE(v4.months_active_ratio, (0)::numeric) >= 0.85)) THEN 'continuous'::text
                    WHEN ((COALESCE(v4.weeks_active_ratio, (0)::numeric) >= 0.55) AND (COALESCE(v4.months_active_ratio, (0)::numeric) >= 0.65)) THEN 'frequent'::text
                    WHEN ((COALESCE(v4.weeks_active_ratio, (0)::numeric) >= 0.30) AND (COALESCE(v4.months_active_ratio, (0)::numeric) >= 0.40)) THEN 'discontinuous'::text
                    ELSE 'sporadic'::text
                END AS continuity_class_v4_1,
                CASE
                    WHEN (COALESCE(v4.peak_month_std, (999)::numeric) <= 0.90) THEN 'very_stable'::text
                    WHEN (COALESCE(v4.peak_month_std, (999)::numeric) <= 1.50) THEN 'stable'::text
                    WHEN (COALESCE(v4.peak_month_std, (999)::numeric) <= 2.50) THEN 'mobile'::text
                    ELSE 'erratic'::text
                END AS peak_month_stability_class_v4_1,
                CASE
                    WHEN ((COALESCE(v4.spring_value_share, (0)::numeric) >= 0.45) OR (COALESCE(v4.spring_qty_share, (0)::numeric) >= 0.45)) THEN 'spring_driven'::text
                    WHEN ((COALESCE(v4.xmas_value_share, (0)::numeric) >= 0.40) OR (COALESCE(v4.xmas_qty_share, (0)::numeric) >= 0.40)) THEN 'xmas_driven'::text
                    ELSE 'none'::text
                END AS holiday_profile_v4_1,
                CASE
                    WHEN ((COALESCE(v4.top10_days_share_max, (0)::numeric) >= (0.75 * COALESCE(v4.top3_months_share_max, (0)::numeric))) AND (COALESCE(v4.top10_days_share_max, (0)::numeric) >= 0.12)) THEN 'daily'::text
                    WHEN ((COALESCE(v4.top4_weeks_share_max, (0)::numeric) >= (0.55 * COALESCE(v4.top3_months_share_max, (0)::numeric))) AND (COALESCE(v4.top4_weeks_share_max, (0)::numeric) >= 0.10)) THEN 'weekly'::text
                    WHEN (COALESCE(v4.top3_months_share_max, (0)::numeric) >= 0.45) THEN 'monthly'::text
                    ELSE 'diffuse'::text
                END AS dominant_concentration_scale_v4_1,
            ((((((0.30 * LEAST(COALESCE(v4.cv_pos_max, (0)::numeric), (10)::numeric)) + (0.25 * LEAST(COALESCE(v4.cv_week_max, (0)::numeric), (10)::numeric))) + (0.20 * LEAST(COALESCE(v4.cv_month_max, (0)::numeric), (10)::numeric))) + (0.15 * LEAST(COALESCE(v4.cv_year_max, (0)::numeric), (10)::numeric))) + (0.10 * LEAST((COALESCE(v4.top10_days_share_max, (0)::numeric) * (10)::numeric), (10)::numeric))))::numeric(12,4) AS instability_score_v4_1
           FROM ml_diag.v_family_diagnostics_v4 v4
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
        CASE
            WHEN ((pos_days < 5) OR (qty_total < (10)::numeric) OR (value_total < (50)::numeric)) THEN 'weak'::text
            WHEN ((pos_days < 30) OR (qty_total < (100)::numeric) OR (value_total < (1000)::numeric)) THEN 'medium'::text
            ELSE 'strong'::text
        END AS reliability_class_v4_1,
        CASE
            WHEN (COALESCE(instability_score_v4_1, (0)::numeric) <= 0.85) THEN 'stable'::text
            WHEN (COALESCE(instability_score_v4_1, (0)::numeric) <= 1.60) THEN 'variable'::text
            ELSE 'unstable'::text
        END AS predictability_class_v4_1,
        CASE
            WHEN (pos_days < 2) THEN 'insufficient'::text
            WHEN (intermittency_class = 'dense'::text) THEN 'dense'::text
            WHEN ((intermittency_class = 'intermittent'::text) AND ((COALESCE(top3_months_share_max, (0)::numeric) >= 0.72) AND (COALESCE(months_active_ratio, (0)::numeric) <= 0.70) AND (COALESCE(weeks_active_ratio, (0)::numeric) <= 0.55) AND (COALESCE(peak_month_std, (999)::numeric) <= 2.00))) THEN 'seasonal_intermittent'::text
            WHEN (intermittency_class = 'intermittent'::text) THEN 'intermittent'::text
            WHEN ((intermittency_class = 'lumpy'::text) AND (((COALESCE(top3_months_share_max, (0)::numeric) >= 0.72) AND (COALESCE(months_active_ratio, (0)::numeric) <= 0.75) AND (COALESCE(weeks_active_ratio, (0)::numeric) <= 0.60) AND (COALESCE(peak_month_std, (999)::numeric) <= 2.20)) OR ((COALESCE(top3_months_share_max, (0)::numeric) >= 0.80) AND (COALESCE(top4_weeks_share_max, (0)::numeric) >= 0.08)) OR ((seasonality_class = ANY (ARRAY['broad_seasonal'::text, 'seasonal'::text, 'very_narrow'::text])) AND (COALESCE(top3_months_share_max, (0)::numeric) >= 0.68) AND (COALESCE(months_active_ratio, (0)::numeric) <= 0.80)))) THEN 'seasonal_lumpy'::text
            WHEN (intermittency_class = 'lumpy'::text) THEN 'lumpy'::text
            ELSE 'insufficient'::text
        END AS demand_class_v4_1
   FROM base b;


--
-- Name: v_family_diagnostics_v5; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v5 AS
 WITH base AS (
         SELECT v41.family_name,
            v41.days_total,
            v41.pos_days,
            v41.zero_days,
            v41.zero_rate,
            v41.pos_rate,
            v41.qty_total,
            v41.qty_avg_all_days,
            v41.qty_avg_pos_days,
            v41.qty_std_pos_days,
            v41.value_total,
            v41.value_avg_all_days,
            v41.value_avg_pos_days,
            v41.value_std_pos_days,
            v41.years_count,
            v41.active_months,
            v41.active_value_months,
            v41.adi,
            v41.cv2_pos,
            v41.years_with_sales,
            v41.season_start_p25,
            v41.season_start_p50,
            v41.season_start_p75,
            v41.peak_doy,
            v41.qty_pct_total,
            v41.qty_cum_pct,
            v41.qty_tier,
            v41.value_pct_total,
            v41.value_cum_pct,
            v41.value_tier,
            v41.business_tier,
            v41.season_start_iqr,
            v41.intermittency_class,
            v41.seasonality_class,
            v41.demand_class_v2,
            v41.data_quality_class_v2,
            v41.combined_segment_v2,
            v41.cv_pos_qty,
            v41.cv_pos_value,
            v41.cv_week_qty,
            v41.cv_week_value,
            v41.cv_month_qty,
            v41.cv_month_value,
            v41.cv_year_qty,
            v41.cv_year_value,
            v41.cv_weekday_qty,
            v41.cv_weekday_value,
            v41.avg_gap_days,
            v41.median_gap_days,
            v41.p90_gap_days,
            v41.max_gap_days,
            v41.weeks_active_ratio,
            v41.months_active_ratio,
            v41.years_active_ratio,
            v41.top3_months_qty_share,
            v41.top6_months_qty_share,
            v41.top3_months_value_share,
            v41.top6_months_value_share,
            v41.top4_weeks_qty_share,
            v41.top8_weeks_qty_share,
            v41.top4_weeks_value_share,
            v41.top8_weeks_value_share,
            v41.top10_days_qty_share,
            v41.top30_days_qty_share,
            v41.top10_days_value_share,
            v41.top30_days_value_share,
            v41.peak_month_std,
            v41.peak_month_avg,
            v41.xmas_qty_share,
            v41.xmas_value_share,
            v41.spring_qty_share,
            v41.spring_value_share,
            v41.cv_pos_max,
            v41.cv_week_max,
            v41.cv_month_max,
            v41.cv_year_max,
            v41.cv_weekday_max,
            v41.top3_months_share_max,
            v41.top6_months_share_max,
            v41.top4_weeks_share_max,
            v41.top8_weeks_share_max,
            v41.top10_days_share_max,
            v41.top30_days_share_max,
            v41.spring_share_max,
            v41.xmas_share_max,
            v41.reliability_class_v4,
            v41.predictability_class_v4,
            v41.seasonality_strength_v4,
            v41.day_peakiness_class_v4,
            v41.week_peakiness_class_v4,
            v41.peak_month_stability_class_v4,
            v41.holiday_profile_v4,
            v41.dominant_concentration_scale_v4,
            v41.demand_class_v4,
            v41.season_width_class_v4_1,
            v41.day_peakiness_class_v4_1,
            v41.week_peakiness_class_v4_1,
            v41.continuity_class_v4_1,
            v41.peak_month_stability_class_v4_1,
            v41.holiday_profile_v4_1,
            v41.dominant_concentration_scale_v4_1,
            v41.instability_score_v4_1,
            v41.reliability_class_v4_1,
            v41.predictability_class_v4_1,
            v41.demand_class_v4_1,
            m5.months_to_80_qty,
            m5.months_to_90_qty,
            m5.months_to_80_value,
            m5.months_to_90_value,
            m5.peak_month_std_qty,
            m5.peak_month_std_value,
            m5.dominant_peak_month_share_qty,
            m5.dominant_peak_month_share_value,
            m5.avg_pos_run_len_qty,
            m5.median_pos_run_len_qty,
            m5.max_pos_run_len_qty,
            m5.avg_zero_run_len_qty,
            m5.median_zero_run_len_qty,
            m5.max_zero_run_len_qty,
            m5.avg_pos_run_len_value,
            m5.median_pos_run_len_value,
            m5.max_pos_run_len_value,
            m5.avg_zero_run_len_value,
            m5.median_zero_run_len_value,
            m5.max_zero_run_len_value,
            m5.avg_gap_days_qty,
            m5.median_gap_days_qty,
            m5.p90_gap_days_qty,
            m5.max_gap_days_qty,
            m5.avg_gap_days_value,
            m5.median_gap_days_value,
            m5.p90_gap_days_value,
            m5.max_gap_days_value,
            m5.top3_months_gap_qty_value,
            m5.top4_weeks_gap_qty_value,
            m5.top10_days_gap_qty_value,
            m5.avg_unit_value,
            GREATEST(COALESCE(v41.top3_months_qty_share, (0)::numeric), COALESCE(v41.top3_months_value_share, (0)::numeric)) AS top3_months_share_max_v5,
            GREATEST(COALESCE(v41.top4_weeks_qty_share, (0)::numeric), COALESCE(v41.top4_weeks_value_share, (0)::numeric)) AS top4_weeks_share_max_v5,
            GREATEST(COALESCE(v41.top10_days_qty_share, (0)::numeric), COALESCE(v41.top10_days_value_share, (0)::numeric)) AS top10_days_share_max_v5
           FROM (ml_diag.v_family_diagnostics_v4_1 v41
             LEFT JOIN ml_diag.mv_family_metrics_v5 m5 ON ((m5.family_name = v41.family_name)))
        ), enriched AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
                CASE
                    WHEN (COALESCE(b.months_to_80_qty, (99)::bigint) <= 2) THEN 'very_narrow'::text
                    WHEN (COALESCE(b.months_to_80_qty, (99)::bigint) <= 3) THEN 'narrow'::text
                    WHEN (COALESCE(b.months_to_80_qty, (99)::bigint) <= 5) THEN 'medium'::text
                    WHEN (COALESCE(b.months_to_80_qty, (99)::bigint) <= 7) THEN 'broad'::text
                    ELSE 'diffuse'::text
                END AS season_width_qty_class_v5,
                CASE
                    WHEN (COALESCE(b.months_to_80_value, (99)::bigint) <= 2) THEN 'very_narrow'::text
                    WHEN (COALESCE(b.months_to_80_value, (99)::bigint) <= 3) THEN 'narrow'::text
                    WHEN (COALESCE(b.months_to_80_value, (99)::bigint) <= 5) THEN 'medium'::text
                    WHEN (COALESCE(b.months_to_80_value, (99)::bigint) <= 7) THEN 'broad'::text
                    ELSE 'diffuse'::text
                END AS season_width_value_class_v5,
                CASE
                    WHEN ((COALESCE(b.dominant_peak_month_share_qty, (0)::numeric) >= 0.80) AND (COALESCE(b.peak_month_std_qty, (99)::numeric) <= 1.00)) THEN 'very_repeatable'::text
                    WHEN ((COALESCE(b.dominant_peak_month_share_qty, (0)::numeric) >= 0.60) AND (COALESCE(b.peak_month_std_qty, (99)::numeric) <= 1.75)) THEN 'repeatable'::text
                    WHEN (COALESCE(b.dominant_peak_month_share_qty, (0)::numeric) >= 0.40) THEN 'mixed'::text
                    ELSE 'erratic'::text
                END AS season_repeatability_qty_class_v5,
                CASE
                    WHEN ((COALESCE(b.dominant_peak_month_share_value, (0)::numeric) >= 0.80) AND (COALESCE(b.peak_month_std_value, (99)::numeric) <= 1.00)) THEN 'very_repeatable'::text
                    WHEN ((COALESCE(b.dominant_peak_month_share_value, (0)::numeric) >= 0.60) AND (COALESCE(b.peak_month_std_value, (99)::numeric) <= 1.75)) THEN 'repeatable'::text
                    WHEN (COALESCE(b.dominant_peak_month_share_value, (0)::numeric) >= 0.40) THEN 'mixed'::text
                    ELSE 'erratic'::text
                END AS season_repeatability_value_class_v5,
                CASE
                    WHEN (COALESCE(b.avg_pos_run_len_qty, (0)::numeric) >= (21)::numeric) THEN 'long_campaign'::text
                    WHEN (COALESCE(b.avg_pos_run_len_qty, (0)::numeric) >= (10)::numeric) THEN 'medium_campaign'::text
                    WHEN (COALESCE(b.avg_pos_run_len_qty, (0)::numeric) >= (4)::numeric) THEN 'short_campaign'::text
                    WHEN (COALESCE(b.avg_pos_run_len_qty, (0)::numeric) > (0)::numeric) THEN 'burst'::text
                    ELSE 'none'::text
                END AS burstiness_qty_class_v5,
                CASE
                    WHEN (COALESCE(b.avg_pos_run_len_value, (0)::numeric) >= (21)::numeric) THEN 'long_campaign'::text
                    WHEN (COALESCE(b.avg_pos_run_len_value, (0)::numeric) >= (10)::numeric) THEN 'medium_campaign'::text
                    WHEN (COALESCE(b.avg_pos_run_len_value, (0)::numeric) >= (4)::numeric) THEN 'short_campaign'::text
                    WHEN (COALESCE(b.avg_pos_run_len_value, (0)::numeric) > (0)::numeric) THEN 'burst'::text
                    ELSE 'none'::text
                END AS burstiness_value_class_v5,
                CASE
                    WHEN ((COALESCE(b.top3_months_gap_qty_value, (0)::numeric) >= 0.20) OR (COALESCE(b.top4_weeks_gap_qty_value, (0)::numeric) >= 0.15) OR (COALESCE(b.top10_days_gap_qty_value, (0)::numeric) >= 0.10)) THEN 'misaligned'::text
                    WHEN ((COALESCE(b.top3_months_gap_qty_value, (0)::numeric) >= 0.10) OR (COALESCE(b.top4_weeks_gap_qty_value, (0)::numeric) >= 0.07) OR (COALESCE(b.top10_days_gap_qty_value, (0)::numeric) >= 0.05)) THEN 'partially_aligned'::text
                    ELSE 'aligned'::text
                END AS qty_value_alignment_class_v5,
                CASE
                    WHEN ((COALESCE(b.cv_pos_qty, (99)::numeric) <= 0.90) AND (COALESCE(b.cv_week_qty, (99)::numeric) <= 1.00) AND (COALESCE(b.cv_month_qty, (99)::numeric) <= 1.10) AND (COALESCE(b.weeks_active_ratio, (0)::numeric) >= 0.80) AND (COALESCE(b.months_active_ratio, (0)::numeric) >= 0.90) AND (COALESCE(b.top3_months_qty_share, (0)::numeric) <= 0.50)) THEN 'dense_qty'::text
                    WHEN ((COALESCE(b.top3_months_qty_share, (0)::numeric) >= 0.75) AND (COALESCE(b.weeks_active_ratio, (0)::numeric) < 0.70)) THEN 'seasonal_qty'::text
                    WHEN ((COALESCE(b.top10_days_qty_share, (0)::numeric) >= 0.15) AND (COALESCE(b.avg_pos_run_len_qty, (99)::numeric) <= (4)::numeric) AND (COALESCE(b.weeks_active_ratio, (0)::numeric) < 0.35)) THEN 'burst_qty'::text
                    WHEN (b.intermittency_class = 'intermittent'::text) THEN 'intermittent_qty'::text
                    ELSE 'lumpy_qty'::text
                END AS logistics_profile_v5,
                CASE
                    WHEN ((COALESCE(b.cv_pos_value, (99)::numeric) <= 0.90) AND (COALESCE(b.cv_week_value, (99)::numeric) <= 1.00) AND (COALESCE(b.cv_month_value, (99)::numeric) <= 1.10) AND (COALESCE(b.weeks_active_ratio, (0)::numeric) >= 0.80) AND (COALESCE(b.months_active_ratio, (0)::numeric) >= 0.90) AND (COALESCE(b.top3_months_value_share, (0)::numeric) <= 0.50)) THEN 'dense_value'::text
                    WHEN ((COALESCE(b.top3_months_value_share, (0)::numeric) >= 0.75) AND (COALESCE(b.weeks_active_ratio, (0)::numeric) < 0.70)) THEN 'seasonal_value'::text
                    WHEN ((COALESCE(b.top10_days_value_share, (0)::numeric) >= 0.15) AND (COALESCE(b.avg_pos_run_len_value, (99)::numeric) <= (4)::numeric) AND (COALESCE(b.weeks_active_ratio, (0)::numeric) < 0.35)) THEN 'burst_value'::text
                    WHEN (b.intermittency_class = 'intermittent'::text) THEN 'intermittent_value'::text
                    ELSE 'lumpy_value'::text
                END AS economic_profile_v5
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
        CASE
            WHEN (pos_days < 2) THEN 'insufficient'::text
            WHEN ((logistics_profile_v5 = 'dense_qty'::text) AND (economic_profile_v5 = 'dense_value'::text)) THEN 'dense'::text
            WHEN (((logistics_profile_v5 = 'burst_qty'::text) OR (economic_profile_v5 = 'burst_value'::text)) AND (reliability_class_v4_1 <> 'weak'::text)) THEN 'burst_lumpy'::text
            WHEN ((logistics_profile_v5 = 'seasonal_qty'::text) AND (economic_profile_v5 = 'seasonal_value'::text)) THEN 'seasonal_lumpy'::text
            WHEN ((intermittency_class = 'intermittent'::text) AND ((COALESCE(top3_months_share_max_v5, (0)::numeric) >= 0.75) OR (COALESCE(months_to_80_qty, (99)::bigint) <= 3) OR (COALESCE(months_to_80_value, (99)::bigint) <= 3)) AND (COALESCE(weeks_active_ratio, (0)::numeric) < 0.65)) THEN 'seasonal_intermittent'::text
            WHEN (intermittency_class = 'intermittent'::text) THEN 'intermittent'::text
            ELSE 'lumpy'::text
        END AS demand_class_v5
   FROM enriched e;


--
-- Name: v_family_diagnostics_v5_1; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v5_1 AS
 WITH base AS (
         SELECT v5.family_name,
            v5.days_total,
            v5.pos_days,
            v5.zero_days,
            v5.zero_rate,
            v5.pos_rate,
            v5.qty_total,
            v5.qty_avg_all_days,
            v5.qty_avg_pos_days,
            v5.qty_std_pos_days,
            v5.value_total,
            v5.value_avg_all_days,
            v5.value_avg_pos_days,
            v5.value_std_pos_days,
            v5.years_count,
            v5.active_months,
            v5.active_value_months,
            v5.adi,
            v5.cv2_pos,
            v5.years_with_sales,
            v5.season_start_p25,
            v5.season_start_p50,
            v5.season_start_p75,
            v5.peak_doy,
            v5.qty_pct_total,
            v5.qty_cum_pct,
            v5.qty_tier,
            v5.value_pct_total,
            v5.value_cum_pct,
            v5.value_tier,
            v5.business_tier,
            v5.season_start_iqr,
            v5.intermittency_class,
            v5.seasonality_class,
            v5.demand_class_v2,
            v5.data_quality_class_v2,
            v5.combined_segment_v2,
            v5.cv_pos_qty,
            v5.cv_pos_value,
            v5.cv_week_qty,
            v5.cv_week_value,
            v5.cv_month_qty,
            v5.cv_month_value,
            v5.cv_year_qty,
            v5.cv_year_value,
            v5.cv_weekday_qty,
            v5.cv_weekday_value,
            v5.avg_gap_days,
            v5.median_gap_days,
            v5.p90_gap_days,
            v5.max_gap_days,
            v5.weeks_active_ratio,
            v5.months_active_ratio,
            v5.years_active_ratio,
            v5.top3_months_qty_share,
            v5.top6_months_qty_share,
            v5.top3_months_value_share,
            v5.top6_months_value_share,
            v5.top4_weeks_qty_share,
            v5.top8_weeks_qty_share,
            v5.top4_weeks_value_share,
            v5.top8_weeks_value_share,
            v5.top10_days_qty_share,
            v5.top30_days_qty_share,
            v5.top10_days_value_share,
            v5.top30_days_value_share,
            v5.peak_month_std,
            v5.peak_month_avg,
            v5.xmas_qty_share,
            v5.xmas_value_share,
            v5.spring_qty_share,
            v5.spring_value_share,
            v5.cv_pos_max,
            v5.cv_week_max,
            v5.cv_month_max,
            v5.cv_year_max,
            v5.cv_weekday_max,
            v5.top3_months_share_max,
            v5.top6_months_share_max,
            v5.top4_weeks_share_max,
            v5.top8_weeks_share_max,
            v5.top10_days_share_max,
            v5.top30_days_share_max,
            v5.spring_share_max,
            v5.xmas_share_max,
            v5.reliability_class_v4,
            v5.predictability_class_v4,
            v5.seasonality_strength_v4,
            v5.day_peakiness_class_v4,
            v5.week_peakiness_class_v4,
            v5.peak_month_stability_class_v4,
            v5.holiday_profile_v4,
            v5.dominant_concentration_scale_v4,
            v5.demand_class_v4,
            v5.season_width_class_v4_1,
            v5.day_peakiness_class_v4_1,
            v5.week_peakiness_class_v4_1,
            v5.continuity_class_v4_1,
            v5.peak_month_stability_class_v4_1,
            v5.holiday_profile_v4_1,
            v5.dominant_concentration_scale_v4_1,
            v5.instability_score_v4_1,
            v5.reliability_class_v4_1,
            v5.predictability_class_v4_1,
            v5.demand_class_v4_1,
            v5.months_to_80_qty,
            v5.months_to_90_qty,
            v5.months_to_80_value,
            v5.months_to_90_value,
            v5.peak_month_std_qty,
            v5.peak_month_std_value,
            v5.dominant_peak_month_share_qty,
            v5.dominant_peak_month_share_value,
            v5.avg_pos_run_len_qty,
            v5.median_pos_run_len_qty,
            v5.max_pos_run_len_qty,
            v5.avg_zero_run_len_qty,
            v5.median_zero_run_len_qty,
            v5.max_zero_run_len_qty,
            v5.avg_pos_run_len_value,
            v5.median_pos_run_len_value,
            v5.max_pos_run_len_value,
            v5.avg_zero_run_len_value,
            v5.median_zero_run_len_value,
            v5.max_zero_run_len_value,
            v5.avg_gap_days_qty,
            v5.median_gap_days_qty,
            v5.p90_gap_days_qty,
            v5.max_gap_days_qty,
            v5.avg_gap_days_value,
            v5.median_gap_days_value,
            v5.p90_gap_days_value,
            v5.max_gap_days_value,
            v5.top3_months_gap_qty_value,
            v5.top4_weeks_gap_qty_value,
            v5.top10_days_gap_qty_value,
            v5.avg_unit_value,
            v5.top3_months_share_max_v5,
            v5.top4_weeks_share_max_v5,
            v5.top10_days_share_max_v5,
            v5.season_width_qty_class_v5,
            v5.season_width_value_class_v5,
            v5.season_repeatability_qty_class_v5,
            v5.season_repeatability_value_class_v5,
            v5.burstiness_qty_class_v5,
            v5.burstiness_value_class_v5,
            v5.qty_value_alignment_class_v5,
            v5.logistics_profile_v5,
            v5.economic_profile_v5,
            v5.demand_class_v5,
            GREATEST(COALESCE(v5.top3_months_qty_share, (0)::numeric), COALESCE(v5.top3_months_value_share, (0)::numeric)) AS top3_months_share_max_v5_1,
            GREATEST(COALESCE(v5.top4_weeks_qty_share, (0)::numeric), COALESCE(v5.top4_weeks_value_share, (0)::numeric)) AS top4_weeks_share_max_v5_1,
            GREATEST(COALESCE(v5.top10_days_qty_share, (0)::numeric), COALESCE(v5.top10_days_value_share, (0)::numeric)) AS top10_days_share_max_v5_1,
            GREATEST(COALESCE(v5.weeks_active_ratio, (0)::numeric), (0)::numeric) AS weeks_active_ratio_v5_1,
            GREATEST(COALESCE(v5.months_active_ratio, (0)::numeric), (0)::numeric) AS months_active_ratio_v5_1,
            LEAST(COALESCE(v5.months_to_80_qty, (12)::bigint), COALESCE(v5.months_to_80_value, (12)::bigint)) AS months_to_80_min_v5_1,
            GREATEST(COALESCE(v5.months_to_80_qty, (0)::bigint), COALESCE(v5.months_to_80_value, (0)::bigint)) AS months_to_80_max_v5_1,
            LEAST(COALESCE(v5.avg_pos_run_len_qty, (999)::numeric), COALESCE(v5.avg_pos_run_len_value, (999)::numeric)) AS avg_pos_run_len_min_v5_1,
            GREATEST(COALESCE(v5.avg_pos_run_len_qty, (0)::numeric), COALESCE(v5.avg_pos_run_len_value, (0)::numeric)) AS avg_pos_run_len_max_v5_1,
            GREATEST(COALESCE(v5.avg_zero_run_len_qty, (0)::numeric), COALESCE(v5.avg_zero_run_len_value, (0)::numeric)) AS avg_zero_run_len_max_v5_1,
                CASE
                    WHEN ((COALESCE(v5.top3_months_qty_share, (0)::numeric) >= 0.88) OR (COALESCE(v5.top3_months_value_share, (0)::numeric) >= 0.88)) THEN 'very_narrow'::text
                    WHEN ((COALESCE(v5.top3_months_qty_share, (0)::numeric) >= 0.75) OR (COALESCE(v5.top3_months_value_share, (0)::numeric) >= 0.75)) THEN 'narrow'::text
                    WHEN ((COALESCE(v5.top3_months_qty_share, (0)::numeric) >= 0.60) OR (COALESCE(v5.top3_months_value_share, (0)::numeric) >= 0.60)) THEN 'medium'::text
                    WHEN ((COALESCE(v5.top3_months_qty_share, (0)::numeric) >= 0.45) OR (COALESCE(v5.top3_months_value_share, (0)::numeric) >= 0.45)) THEN 'broad'::text
                    ELSE 'diffuse'::text
                END AS season_width_class_v5_1,
                CASE
                    WHEN ((COALESCE(v5.weeks_active_ratio, (0)::numeric) >= 0.85) AND (COALESCE(v5.months_active_ratio, (0)::numeric) >= 0.90)) THEN 'continuous'::text
                    WHEN ((COALESCE(v5.weeks_active_ratio, (0)::numeric) >= 0.60) AND (COALESCE(v5.months_active_ratio, (0)::numeric) >= 0.70)) THEN 'frequent'::text
                    WHEN ((COALESCE(v5.weeks_active_ratio, (0)::numeric) >= 0.30) AND (COALESCE(v5.months_active_ratio, (0)::numeric) >= 0.40)) THEN 'discontinuous'::text
                    ELSE 'sporadic'::text
                END AS continuity_class_v5_1,
                CASE
                    WHEN ((COALESCE(v5.avg_pos_run_len_qty, (999)::numeric) <= 1.30) OR (COALESCE(v5.avg_pos_run_len_value, (999)::numeric) <= 1.30)) THEN 'very_bursty'::text
                    WHEN ((COALESCE(v5.avg_pos_run_len_qty, (999)::numeric) <= 2.20) OR (COALESCE(v5.avg_pos_run_len_value, (999)::numeric) <= 2.20)) THEN 'bursty'::text
                    WHEN ((COALESCE(v5.avg_pos_run_len_qty, (999)::numeric) <= 5.00) OR (COALESCE(v5.avg_pos_run_len_value, (999)::numeric) <= 5.00)) THEN 'campaign'::text
                    WHEN ((COALESCE(v5.avg_pos_run_len_qty, (999)::numeric) <= 12.00) OR (COALESCE(v5.avg_pos_run_len_value, (999)::numeric) <= 12.00)) THEN 'medium_run'::text
                    ELSE 'long_run'::text
                END AS burstiness_class_v5_1,
                CASE
                    WHEN ((COALESCE(v5.season_repeatability_qty_class_v5, ''::text) = ANY (ARRAY['repeatable'::text, 'very_repeatable'::text])) OR (COALESCE(v5.season_repeatability_value_class_v5, ''::text) = ANY (ARRAY['repeatable'::text, 'very_repeatable'::text]))) THEN 'repeatable'::text
                    WHEN ((COALESCE(v5.season_repeatability_qty_class_v5, ''::text) = 'mixed'::text) OR (COALESCE(v5.season_repeatability_value_class_v5, ''::text) = 'mixed'::text)) THEN 'mixed'::text
                    ELSE 'erratic'::text
                END AS repeatability_class_v5_1
           FROM ml_diag.v_family_diagnostics_v5 v5
        ), classified AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
            b.season_width_qty_class_v5,
            b.season_width_value_class_v5,
            b.season_repeatability_qty_class_v5,
            b.season_repeatability_value_class_v5,
            b.burstiness_qty_class_v5,
            b.burstiness_value_class_v5,
            b.qty_value_alignment_class_v5,
            b.logistics_profile_v5,
            b.economic_profile_v5,
            b.demand_class_v5,
            b.top3_months_share_max_v5_1,
            b.top4_weeks_share_max_v5_1,
            b.top10_days_share_max_v5_1,
            b.weeks_active_ratio_v5_1,
            b.months_active_ratio_v5_1,
            b.months_to_80_min_v5_1,
            b.months_to_80_max_v5_1,
            b.avg_pos_run_len_min_v5_1,
            b.avg_pos_run_len_max_v5_1,
            b.avg_zero_run_len_max_v5_1,
            b.season_width_class_v5_1,
            b.continuity_class_v5_1,
            b.burstiness_class_v5_1,
            b.repeatability_class_v5_1,
                CASE
                    WHEN ((b.pos_days < 5) OR (b.qty_total < (10)::numeric) OR (b.value_total < (50)::numeric)) THEN 'insufficient'::text
                    WHEN ((b.weeks_active_ratio_v5_1 >= 0.82) AND (b.months_active_ratio_v5_1 >= 0.90) AND (b.avg_pos_run_len_max_v5_1 >= 4.0) AND (b.top10_days_share_max_v5_1 <= 0.08) AND (b.top4_weeks_share_max_v5_1 <= 0.12) AND (b.months_to_80_min_v5_1 >= 6) AND (COALESCE(b.zero_rate, (1)::numeric) <= 0.45)) THEN 'dense'::text
                    WHEN ((COALESCE(b.zero_rate, (1)::numeric) >= 0.78) AND (b.weeks_active_ratio_v5_1 <= 0.55) AND (b.top10_days_share_max_v5_1 < 0.18) AND (b.months_to_80_min_v5_1 >= 5) AND (b.top3_months_share_max_v5_1 < 0.78)) THEN 'intermittent'::text
                    WHEN ((b.months_to_80_min_v5_1 <= 3) AND (b.top3_months_share_max_v5_1 >= 0.82) AND (b.weeks_active_ratio_v5_1 <= 0.22) AND (COALESCE(b.zero_rate, (1)::numeric) >= 0.88)) THEN 'seasonal_intermittent'::text
                    WHEN ((b.avg_pos_run_len_max_v5_1 <= 2.20) AND (b.weeks_active_ratio_v5_1 <= 0.18) AND (b.months_active_ratio_v5_1 <= 0.35) AND ((b.top10_days_share_max_v5_1 >= 0.18) OR (b.top4_weeks_share_max_v5_1 >= 0.22)) AND (b.months_to_80_min_v5_1 > 3)) THEN 'burst_lumpy'::text
                    WHEN ((b.months_to_80_min_v5_1 <= 4) AND (b.top3_months_share_max_v5_1 >= 0.72) AND (b.weeks_active_ratio_v5_1 <= 0.65) AND (b.months_active_ratio_v5_1 <= 0.80) AND ((b.repeatability_class_v5_1 = ANY (ARRAY['repeatable'::text, 'mixed'::text])) OR (COALESCE(b.holiday_profile_v4_1, 'none'::text) <> 'none'::text) OR (COALESCE(b.holiday_profile_v4, 'none'::text) <> 'none'::text))) THEN 'seasonal_lumpy'::text
                    ELSE 'lumpy'::text
                END AS demand_class_v5_1
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
    demand_class_v5,
    top3_months_share_max_v5_1,
    top4_weeks_share_max_v5_1,
    top10_days_share_max_v5_1,
    weeks_active_ratio_v5_1,
    months_active_ratio_v5_1,
    months_to_80_min_v5_1,
    months_to_80_max_v5_1,
    avg_pos_run_len_min_v5_1,
    avg_pos_run_len_max_v5_1,
    avg_zero_run_len_max_v5_1,
    season_width_class_v5_1,
    continuity_class_v5_1,
    burstiness_class_v5_1,
    repeatability_class_v5_1,
    demand_class_v5_1
   FROM classified c;


--
-- Name: v_family_diagnostics_v5_2; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v5_2 AS
 WITH base AS (
         SELECT v51.family_name,
            v51.days_total,
            v51.pos_days,
            v51.zero_days,
            v51.zero_rate,
            v51.pos_rate,
            v51.qty_total,
            v51.qty_avg_all_days,
            v51.qty_avg_pos_days,
            v51.qty_std_pos_days,
            v51.value_total,
            v51.value_avg_all_days,
            v51.value_avg_pos_days,
            v51.value_std_pos_days,
            v51.years_count,
            v51.active_months,
            v51.active_value_months,
            v51.adi,
            v51.cv2_pos,
            v51.years_with_sales,
            v51.season_start_p25,
            v51.season_start_p50,
            v51.season_start_p75,
            v51.peak_doy,
            v51.qty_pct_total,
            v51.qty_cum_pct,
            v51.qty_tier,
            v51.value_pct_total,
            v51.value_cum_pct,
            v51.value_tier,
            v51.business_tier,
            v51.season_start_iqr,
            v51.intermittency_class,
            v51.seasonality_class,
            v51.demand_class_v2,
            v51.data_quality_class_v2,
            v51.combined_segment_v2,
            v51.cv_pos_qty,
            v51.cv_pos_value,
            v51.cv_week_qty,
            v51.cv_week_value,
            v51.cv_month_qty,
            v51.cv_month_value,
            v51.cv_year_qty,
            v51.cv_year_value,
            v51.cv_weekday_qty,
            v51.cv_weekday_value,
            v51.avg_gap_days,
            v51.median_gap_days,
            v51.p90_gap_days,
            v51.max_gap_days,
            v51.weeks_active_ratio,
            v51.months_active_ratio,
            v51.years_active_ratio,
            v51.top3_months_qty_share,
            v51.top6_months_qty_share,
            v51.top3_months_value_share,
            v51.top6_months_value_share,
            v51.top4_weeks_qty_share,
            v51.top8_weeks_qty_share,
            v51.top4_weeks_value_share,
            v51.top8_weeks_value_share,
            v51.top10_days_qty_share,
            v51.top30_days_qty_share,
            v51.top10_days_value_share,
            v51.top30_days_value_share,
            v51.peak_month_std,
            v51.peak_month_avg,
            v51.xmas_qty_share,
            v51.xmas_value_share,
            v51.spring_qty_share,
            v51.spring_value_share,
            v51.cv_pos_max,
            v51.cv_week_max,
            v51.cv_month_max,
            v51.cv_year_max,
            v51.cv_weekday_max,
            v51.top3_months_share_max,
            v51.top6_months_share_max,
            v51.top4_weeks_share_max,
            v51.top8_weeks_share_max,
            v51.top10_days_share_max,
            v51.top30_days_share_max,
            v51.spring_share_max,
            v51.xmas_share_max,
            v51.reliability_class_v4,
            v51.predictability_class_v4,
            v51.seasonality_strength_v4,
            v51.day_peakiness_class_v4,
            v51.week_peakiness_class_v4,
            v51.peak_month_stability_class_v4,
            v51.holiday_profile_v4,
            v51.dominant_concentration_scale_v4,
            v51.demand_class_v4,
            v51.season_width_class_v4_1,
            v51.day_peakiness_class_v4_1,
            v51.week_peakiness_class_v4_1,
            v51.continuity_class_v4_1,
            v51.peak_month_stability_class_v4_1,
            v51.holiday_profile_v4_1,
            v51.dominant_concentration_scale_v4_1,
            v51.instability_score_v4_1,
            v51.reliability_class_v4_1,
            v51.predictability_class_v4_1,
            v51.demand_class_v4_1,
            v51.months_to_80_qty,
            v51.months_to_90_qty,
            v51.months_to_80_value,
            v51.months_to_90_value,
            v51.peak_month_std_qty,
            v51.peak_month_std_value,
            v51.dominant_peak_month_share_qty,
            v51.dominant_peak_month_share_value,
            v51.avg_pos_run_len_qty,
            v51.median_pos_run_len_qty,
            v51.max_pos_run_len_qty,
            v51.avg_zero_run_len_qty,
            v51.median_zero_run_len_qty,
            v51.max_zero_run_len_qty,
            v51.avg_pos_run_len_value,
            v51.median_pos_run_len_value,
            v51.max_pos_run_len_value,
            v51.avg_zero_run_len_value,
            v51.median_zero_run_len_value,
            v51.max_zero_run_len_value,
            v51.avg_gap_days_qty,
            v51.median_gap_days_qty,
            v51.p90_gap_days_qty,
            v51.max_gap_days_qty,
            v51.avg_gap_days_value,
            v51.median_gap_days_value,
            v51.p90_gap_days_value,
            v51.max_gap_days_value,
            v51.top3_months_gap_qty_value,
            v51.top4_weeks_gap_qty_value,
            v51.top10_days_gap_qty_value,
            v51.avg_unit_value,
            v51.top3_months_share_max_v5,
            v51.top4_weeks_share_max_v5,
            v51.top10_days_share_max_v5,
            v51.season_width_qty_class_v5,
            v51.season_width_value_class_v5,
            v51.season_repeatability_qty_class_v5,
            v51.season_repeatability_value_class_v5,
            v51.burstiness_qty_class_v5,
            v51.burstiness_value_class_v5,
            v51.qty_value_alignment_class_v5,
            v51.logistics_profile_v5,
            v51.economic_profile_v5,
            v51.demand_class_v5,
            v51.top3_months_share_max_v5_1,
            v51.top4_weeks_share_max_v5_1,
            v51.top10_days_share_max_v5_1,
            v51.weeks_active_ratio_v5_1,
            v51.months_active_ratio_v5_1,
            v51.months_to_80_min_v5_1,
            v51.months_to_80_max_v5_1,
            v51.avg_pos_run_len_min_v5_1,
            v51.avg_pos_run_len_max_v5_1,
            v51.avg_zero_run_len_max_v5_1,
            v51.season_width_class_v5_1,
            v51.continuity_class_v5_1,
            v51.burstiness_class_v5_1,
            v51.repeatability_class_v5_1,
            v51.demand_class_v5_1,
            GREATEST(COALESCE(v51.top3_months_qty_share, (0)::numeric), COALESCE(v51.top3_months_value_share, (0)::numeric)) AS top3_months_share_max_v5_2,
            GREATEST(COALESCE(v51.top4_weeks_qty_share, (0)::numeric), COALESCE(v51.top4_weeks_value_share, (0)::numeric)) AS top4_weeks_share_max_v5_2,
            GREATEST(COALESCE(v51.top10_days_qty_share, (0)::numeric), COALESCE(v51.top10_days_value_share, (0)::numeric)) AS top10_days_share_max_v5_2,
            GREATEST(COALESCE(v51.avg_pos_run_len_qty, (0)::numeric), COALESCE(v51.avg_pos_run_len_value, (0)::numeric)) AS avg_pos_run_len_max_v5_2,
            LEAST(COALESCE(v51.avg_pos_run_len_qty, (999999)::numeric), COALESCE(v51.avg_pos_run_len_value, (999999)::numeric)) AS avg_pos_run_len_min_v5_2,
            LEAST(COALESCE(v51.months_to_80_qty, (99)::bigint), COALESCE(v51.months_to_80_value, (99)::bigint)) AS months_to_80_min_v5_2,
            GREATEST(COALESCE(v51.months_to_80_qty, (0)::bigint), COALESCE(v51.months_to_80_value, (0)::bigint)) AS months_to_80_max_v5_2,
                CASE
                    WHEN (GREATEST(COALESCE(v51.months_to_80_qty, (99)::bigint), COALESCE(v51.months_to_80_value, (99)::bigint)) <= 2) THEN 'very_narrow'::text
                    WHEN (GREATEST(COALESCE(v51.months_to_80_qty, (99)::bigint), COALESCE(v51.months_to_80_value, (99)::bigint)) <= 3) THEN 'narrow'::text
                    WHEN (GREATEST(COALESCE(v51.months_to_80_qty, (99)::bigint), COALESCE(v51.months_to_80_value, (99)::bigint)) <= 5) THEN 'medium'::text
                    WHEN (GREATEST(COALESCE(v51.months_to_80_qty, (99)::bigint), COALESCE(v51.months_to_80_value, (99)::bigint)) <= 7) THEN 'broad'::text
                    ELSE 'diffuse'::text
                END AS season_width_class_v5_2,
                CASE
                    WHEN ((COALESCE(v51.weeks_active_ratio, (0)::numeric) >= 0.90) AND (COALESCE(v51.months_active_ratio, (0)::numeric) >= 0.96)) THEN 'continuous'::text
                    WHEN ((COALESCE(v51.weeks_active_ratio, (0)::numeric) >= 0.65) AND (COALESCE(v51.months_active_ratio, (0)::numeric) >= 0.80)) THEN 'frequent'::text
                    WHEN ((COALESCE(v51.weeks_active_ratio, (0)::numeric) >= 0.30) AND (COALESCE(v51.months_active_ratio, (0)::numeric) >= 0.45)) THEN 'discontinuous'::text
                    ELSE 'sporadic'::text
                END AS continuity_class_v5_2,
                CASE
                    WHEN (GREATEST(COALESCE(v51.avg_pos_run_len_qty, (0)::numeric), COALESCE(v51.avg_pos_run_len_value, (0)::numeric)) >= (10)::numeric) THEN 'long_run'::text
                    WHEN (GREATEST(COALESCE(v51.avg_pos_run_len_qty, (0)::numeric), COALESCE(v51.avg_pos_run_len_value, (0)::numeric)) >= (5)::numeric) THEN 'medium_run'::text
                    WHEN (GREATEST(COALESCE(v51.avg_pos_run_len_qty, (0)::numeric), COALESCE(v51.avg_pos_run_len_value, (0)::numeric)) >= 2.5) THEN 'campaign'::text
                    WHEN (GREATEST(COALESCE(v51.avg_pos_run_len_qty, (0)::numeric), COALESCE(v51.avg_pos_run_len_value, (0)::numeric)) >= 1.5) THEN 'bursty'::text
                    ELSE 'very_bursty'::text
                END AS burstiness_class_v5_2,
                CASE
                    WHEN ((COALESCE(v51.season_repeatability_qty_class_v5, ''::text) = ANY (ARRAY['very_repeatable'::text, 'repeatable'::text])) OR (COALESCE(v51.season_repeatability_value_class_v5, ''::text) = ANY (ARRAY['very_repeatable'::text, 'repeatable'::text]))) THEN 'repeatable'::text
                    WHEN ((COALESCE(v51.season_repeatability_qty_class_v5, ''::text) = 'mixed'::text) OR (COALESCE(v51.season_repeatability_value_class_v5, ''::text) = 'mixed'::text)) THEN 'mixed'::text
                    ELSE 'erratic'::text
                END AS repeatability_class_v5_2
           FROM ml_diag.v_family_diagnostics_v5_1 v51
        ), classified AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
            b.season_width_qty_class_v5,
            b.season_width_value_class_v5,
            b.season_repeatability_qty_class_v5,
            b.season_repeatability_value_class_v5,
            b.burstiness_qty_class_v5,
            b.burstiness_value_class_v5,
            b.qty_value_alignment_class_v5,
            b.logistics_profile_v5,
            b.economic_profile_v5,
            b.demand_class_v5,
            b.top3_months_share_max_v5_1,
            b.top4_weeks_share_max_v5_1,
            b.top10_days_share_max_v5_1,
            b.weeks_active_ratio_v5_1,
            b.months_active_ratio_v5_1,
            b.months_to_80_min_v5_1,
            b.months_to_80_max_v5_1,
            b.avg_pos_run_len_min_v5_1,
            b.avg_pos_run_len_max_v5_1,
            b.avg_zero_run_len_max_v5_1,
            b.season_width_class_v5_1,
            b.continuity_class_v5_1,
            b.burstiness_class_v5_1,
            b.repeatability_class_v5_1,
            b.demand_class_v5_1,
            b.top3_months_share_max_v5_2,
            b.top4_weeks_share_max_v5_2,
            b.top10_days_share_max_v5_2,
            b.avg_pos_run_len_max_v5_2,
            b.avg_pos_run_len_min_v5_2,
            b.months_to_80_min_v5_2,
            b.months_to_80_max_v5_2,
            b.season_width_class_v5_2,
            b.continuity_class_v5_2,
            b.burstiness_class_v5_2,
            b.repeatability_class_v5_2,
                CASE
                    WHEN ((COALESCE(b.pos_days, (0)::bigint) < 5) OR (COALESCE(b.qty_total, (0)::numeric) < (10)::numeric) OR (COALESCE(b.value_total, (0)::numeric) < (50)::numeric)) THEN 'insufficient'::text
                    WHEN ((COALESCE(b.weeks_active_ratio, (0)::numeric) >= 0.90) AND (COALESCE(b.months_active_ratio, (0)::numeric) >= 0.96) AND (COALESCE(b.avg_pos_run_len_max_v5_2, (0)::numeric) >= 5.0) AND (COALESCE(b.top10_days_share_max_v5_2, (1)::numeric) <= 0.035) AND (COALESCE(b.top4_weeks_share_max_v5_2, (1)::numeric) <= 0.045) AND (COALESCE(b.months_to_80_min_v5_2, (0)::bigint) >= 8) AND (COALESCE(b.zero_rate, (1)::numeric) <= 0.35) AND (COALESCE(b.top3_months_share_max_v5_2, (1)::numeric) <= 0.55)) THEN 'dense'::text
                    WHEN ((COALESCE(b.avg_pos_run_len_max_v5_2, (999)::numeric) <= 1.75) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.16) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.32) AND ((COALESCE(b.top10_days_share_max_v5_2, (0)::numeric) >= 0.18) OR (COALESCE(b.top4_weeks_share_max_v5_2, (0)::numeric) >= 0.22)) AND (COALESCE(b.months_to_80_min_v5_2, (99)::bigint) > 3)) THEN 'burst_lumpy'::text
                    WHEN ((COALESCE(b.months_to_80_min_v5_2, (99)::bigint) <= 3) AND (COALESCE(b.top3_months_share_max_v5_2, (0)::numeric) >= 0.82) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.22) AND (COALESCE(b.zero_rate, (0)::numeric) >= 0.88)) THEN 'seasonal_intermittent'::text
                    WHEN ((COALESCE(b.months_to_80_min_v5_2, (99)::bigint) <= 4) AND (COALESCE(b.top3_months_share_max_v5_2, (0)::numeric) >= 0.72) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.65) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.80) AND ((b.repeatability_class_v5_2 = ANY (ARRAY['repeatable'::text, 'mixed'::text])) OR (COALESCE(b.holiday_profile_v4_1, 'none'::text) <> 'none'::text) OR (COALESCE(b.holiday_profile_v4, 'none'::text) <> 'none'::text))) THEN 'seasonal_lumpy'::text
                    WHEN (((COALESCE(b.zero_rate, (0)::numeric) >= 0.72) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.58) AND (COALESCE(b.top10_days_share_max_v5_2, (1)::numeric) < 0.16) AND (COALESCE(b.months_to_80_min_v5_2, (0)::bigint) >= 5) AND (COALESCE(b.top3_months_share_max_v5_2, (1)::numeric) < 0.75)) OR ((COALESCE(b.continuity_class_v5_2, ''::text) = ANY (ARRAY['sporadic'::text, 'discontinuous'::text])) AND (COALESCE(b.avg_pos_run_len_max_v5_2, (999)::numeric) <= 2.20) AND (COALESCE(b.months_to_80_min_v5_2, (0)::bigint) >= 5) AND (COALESCE(b.top10_days_share_max_v5_2, (1)::numeric) < 0.18) AND (COALESCE(b.top3_months_share_max_v5_2, (1)::numeric) < 0.78))) THEN 'intermittent'::text
                    ELSE 'lumpy'::text
                END AS demand_class_v5_2
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
    demand_class_v5,
    top3_months_share_max_v5_1,
    top4_weeks_share_max_v5_1,
    top10_days_share_max_v5_1,
    weeks_active_ratio_v5_1,
    months_active_ratio_v5_1,
    months_to_80_min_v5_1,
    months_to_80_max_v5_1,
    avg_pos_run_len_min_v5_1,
    avg_pos_run_len_max_v5_1,
    avg_zero_run_len_max_v5_1,
    season_width_class_v5_1,
    continuity_class_v5_1,
    burstiness_class_v5_1,
    repeatability_class_v5_1,
    demand_class_v5_1,
    top3_months_share_max_v5_2,
    top4_weeks_share_max_v5_2,
    top10_days_share_max_v5_2,
    avg_pos_run_len_max_v5_2,
    avg_pos_run_len_min_v5_2,
    months_to_80_min_v5_2,
    months_to_80_max_v5_2,
    season_width_class_v5_2,
    continuity_class_v5_2,
    burstiness_class_v5_2,
    repeatability_class_v5_2,
    demand_class_v5_2
   FROM classified;


--
-- Name: v_family_diagnostics_v6; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v6 AS
 WITH base AS (
         SELECT v51.family_name,
            v51.days_total,
            v51.pos_days,
            v51.zero_days,
            v51.zero_rate,
            v51.pos_rate,
            v51.qty_total,
            v51.qty_avg_all_days,
            v51.qty_avg_pos_days,
            v51.qty_std_pos_days,
            v51.value_total,
            v51.value_avg_all_days,
            v51.value_avg_pos_days,
            v51.value_std_pos_days,
            v51.years_count,
            v51.active_months,
            v51.active_value_months,
            v51.adi,
            v51.cv2_pos,
            v51.years_with_sales,
            v51.season_start_p25,
            v51.season_start_p50,
            v51.season_start_p75,
            v51.peak_doy,
            v51.qty_pct_total,
            v51.qty_cum_pct,
            v51.qty_tier,
            v51.value_pct_total,
            v51.value_cum_pct,
            v51.value_tier,
            v51.business_tier,
            v51.season_start_iqr,
            v51.intermittency_class,
            v51.seasonality_class,
            v51.demand_class_v2,
            v51.data_quality_class_v2,
            v51.combined_segment_v2,
            v51.cv_pos_qty,
            v51.cv_pos_value,
            v51.cv_week_qty,
            v51.cv_week_value,
            v51.cv_month_qty,
            v51.cv_month_value,
            v51.cv_year_qty,
            v51.cv_year_value,
            v51.cv_weekday_qty,
            v51.cv_weekday_value,
            v51.avg_gap_days,
            v51.median_gap_days,
            v51.p90_gap_days,
            v51.max_gap_days,
            v51.weeks_active_ratio,
            v51.months_active_ratio,
            v51.years_active_ratio,
            v51.top3_months_qty_share,
            v51.top6_months_qty_share,
            v51.top3_months_value_share,
            v51.top6_months_value_share,
            v51.top4_weeks_qty_share,
            v51.top8_weeks_qty_share,
            v51.top4_weeks_value_share,
            v51.top8_weeks_value_share,
            v51.top10_days_qty_share,
            v51.top30_days_qty_share,
            v51.top10_days_value_share,
            v51.top30_days_value_share,
            v51.peak_month_std,
            v51.peak_month_avg,
            v51.xmas_qty_share,
            v51.xmas_value_share,
            v51.spring_qty_share,
            v51.spring_value_share,
            v51.cv_pos_max,
            v51.cv_week_max,
            v51.cv_month_max,
            v51.cv_year_max,
            v51.cv_weekday_max,
            v51.top3_months_share_max,
            v51.top6_months_share_max,
            v51.top4_weeks_share_max,
            v51.top8_weeks_share_max,
            v51.top10_days_share_max,
            v51.top30_days_share_max,
            v51.spring_share_max,
            v51.xmas_share_max,
            v51.reliability_class_v4,
            v51.predictability_class_v4,
            v51.seasonality_strength_v4,
            v51.day_peakiness_class_v4,
            v51.week_peakiness_class_v4,
            v51.peak_month_stability_class_v4,
            v51.holiday_profile_v4,
            v51.dominant_concentration_scale_v4,
            v51.demand_class_v4,
            v51.season_width_class_v4_1,
            v51.day_peakiness_class_v4_1,
            v51.week_peakiness_class_v4_1,
            v51.continuity_class_v4_1,
            v51.peak_month_stability_class_v4_1,
            v51.holiday_profile_v4_1,
            v51.dominant_concentration_scale_v4_1,
            v51.instability_score_v4_1,
            v51.reliability_class_v4_1,
            v51.predictability_class_v4_1,
            v51.demand_class_v4_1,
            v51.months_to_80_qty,
            v51.months_to_90_qty,
            v51.months_to_80_value,
            v51.months_to_90_value,
            v51.peak_month_std_qty,
            v51.peak_month_std_value,
            v51.dominant_peak_month_share_qty,
            v51.dominant_peak_month_share_value,
            v51.avg_pos_run_len_qty,
            v51.median_pos_run_len_qty,
            v51.max_pos_run_len_qty,
            v51.avg_zero_run_len_qty,
            v51.median_zero_run_len_qty,
            v51.max_zero_run_len_qty,
            v51.avg_pos_run_len_value,
            v51.median_pos_run_len_value,
            v51.max_pos_run_len_value,
            v51.avg_zero_run_len_value,
            v51.median_zero_run_len_value,
            v51.max_zero_run_len_value,
            v51.avg_gap_days_qty,
            v51.median_gap_days_qty,
            v51.p90_gap_days_qty,
            v51.max_gap_days_qty,
            v51.avg_gap_days_value,
            v51.median_gap_days_value,
            v51.p90_gap_days_value,
            v51.max_gap_days_value,
            v51.top3_months_gap_qty_value,
            v51.top4_weeks_gap_qty_value,
            v51.top10_days_gap_qty_value,
            v51.avg_unit_value,
            v51.top3_months_share_max_v5,
            v51.top4_weeks_share_max_v5,
            v51.top10_days_share_max_v5,
            v51.season_width_qty_class_v5,
            v51.season_width_value_class_v5,
            v51.season_repeatability_qty_class_v5,
            v51.season_repeatability_value_class_v5,
            v51.burstiness_qty_class_v5,
            v51.burstiness_value_class_v5,
            v51.qty_value_alignment_class_v5,
            v51.logistics_profile_v5,
            v51.economic_profile_v5,
            v51.demand_class_v5,
            v51.top3_months_share_max_v5_1,
            v51.top4_weeks_share_max_v5_1,
            v51.top10_days_share_max_v5_1,
            v51.weeks_active_ratio_v5_1,
            v51.months_active_ratio_v5_1,
            v51.months_to_80_min_v5_1,
            v51.months_to_80_max_v5_1,
            v51.avg_pos_run_len_min_v5_1,
            v51.avg_pos_run_len_max_v5_1,
            v51.avg_zero_run_len_max_v5_1,
            v51.season_width_class_v5_1,
            v51.continuity_class_v5_1,
            v51.burstiness_class_v5_1,
            v51.repeatability_class_v5_1,
            v51.demand_class_v5_1,
            GREATEST(COALESCE(v51.top3_months_qty_share, (0)::numeric), COALESCE(v51.top3_months_value_share, (0)::numeric)) AS top3_months_share_max_v6,
            GREATEST(COALESCE(v51.top4_weeks_qty_share, (0)::numeric), COALESCE(v51.top4_weeks_value_share, (0)::numeric)) AS top4_weeks_share_max_v6,
            GREATEST(COALESCE(v51.top10_days_qty_share, (0)::numeric), COALESCE(v51.top10_days_value_share, (0)::numeric)) AS top10_days_share_max_v6,
            GREATEST(COALESCE(v51.avg_pos_run_len_qty, (0)::numeric), COALESCE(v51.avg_pos_run_len_value, (0)::numeric)) AS avg_pos_run_len_max_v6,
            LEAST(COALESCE(v51.avg_pos_run_len_qty, (999999)::numeric), COALESCE(v51.avg_pos_run_len_value, (999999)::numeric)) AS avg_pos_run_len_min_v6,
            LEAST(COALESCE(v51.months_to_80_qty, (99)::bigint), COALESCE(v51.months_to_80_value, (99)::bigint)) AS months_to_80_min_v6,
            GREATEST(COALESCE(v51.months_to_80_qty, (0)::bigint), COALESCE(v51.months_to_80_value, (0)::bigint)) AS months_to_80_max_v6
           FROM ml_diag.v_family_diagnostics_v5_1 v51
        ), classified AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
            b.season_width_qty_class_v5,
            b.season_width_value_class_v5,
            b.season_repeatability_qty_class_v5,
            b.season_repeatability_value_class_v5,
            b.burstiness_qty_class_v5,
            b.burstiness_value_class_v5,
            b.qty_value_alignment_class_v5,
            b.logistics_profile_v5,
            b.economic_profile_v5,
            b.demand_class_v5,
            b.top3_months_share_max_v5_1,
            b.top4_weeks_share_max_v5_1,
            b.top10_days_share_max_v5_1,
            b.weeks_active_ratio_v5_1,
            b.months_active_ratio_v5_1,
            b.months_to_80_min_v5_1,
            b.months_to_80_max_v5_1,
            b.avg_pos_run_len_min_v5_1,
            b.avg_pos_run_len_max_v5_1,
            b.avg_zero_run_len_max_v5_1,
            b.season_width_class_v5_1,
            b.continuity_class_v5_1,
            b.burstiness_class_v5_1,
            b.repeatability_class_v5_1,
            b.demand_class_v5_1,
            b.top3_months_share_max_v6,
            b.top4_weeks_share_max_v6,
            b.top10_days_share_max_v6,
            b.avg_pos_run_len_max_v6,
            b.avg_pos_run_len_min_v6,
            b.months_to_80_min_v6,
            b.months_to_80_max_v6,
                CASE
                    WHEN ((COALESCE(b.pos_days, (0)::bigint) < 5) OR (COALESCE(b.qty_total, (0)::numeric) < (10)::numeric) OR (COALESCE(b.value_total, (0)::numeric) < (50)::numeric)) THEN 'insufficient'::text
                    WHEN ((COALESCE(b.weeks_active_ratio, (0)::numeric) >= 0.94) AND (COALESCE(b.months_active_ratio, (0)::numeric) >= 0.98) AND (COALESCE(b.avg_pos_run_len_max_v6, (0)::numeric) >= 5.0) AND (COALESCE(b.top10_days_share_max_v6, (1)::numeric) <= 0.030) AND (COALESCE(b.top4_weeks_share_max_v6, (1)::numeric) <= 0.040) AND (COALESCE(b.months_to_80_min_v6, (0)::bigint) >= 8) AND (COALESCE(b.top3_months_share_max_v6, (1)::numeric) <= 0.50) AND (COALESCE(b.zero_rate, (1)::numeric) <= 0.30)) THEN 'dense'::text
                    WHEN ((COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 1.60) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.22) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.40) AND ((COALESCE(b.top10_days_share_max_v6, (0)::numeric) >= 0.14) OR (COALESCE(b.top4_weeks_share_max_v6, (0)::numeric) >= 0.18)) AND ((COALESCE(b.logistics_profile_v5, ''::text) = 'burst_qty'::text) OR (COALESCE(b.economic_profile_v5, ''::text) = 'burst_value'::text) OR (COALESCE(b.top10_days_value_share, (0)::numeric) >= 0.16) OR (COALESCE(b.top4_weeks_value_share, (0)::numeric) >= 0.18))) THEN 'burst_lumpy'::text
                    WHEN ((COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 3) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.82) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.22) AND (COALESCE(b.zero_rate, (0)::numeric) >= 0.88)) THEN 'seasonal_intermittent'::text
                    WHEN ((COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 4) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.72) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.68) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.82) AND ((COALESCE(b.repeatability_class_v5_1, ''::text) = ANY (ARRAY['repeatable'::text, 'mixed'::text])) OR (COALESCE(b.holiday_profile_v4_1, 'none'::text) <> 'none'::text) OR (COALESCE(b.holiday_profile_v4, 'none'::text) <> 'none'::text))) THEN 'seasonal_lumpy'::text
                    WHEN ((COALESCE(b.zero_rate, (0)::numeric) >= 0.74) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.52) AND (COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 1.90) AND (COALESCE(b.top10_days_share_max_v6, (1)::numeric) < 0.14) AND (COALESCE(b.top4_weeks_share_max_v6, (1)::numeric) < 0.16) AND (COALESCE(b.top3_months_share_max_v6, (1)::numeric) < 0.72) AND (COALESCE(b.months_to_80_min_v6, (0)::bigint) >= 5) AND (COALESCE(b.season_width_class_v5_1, ''::text) <> ALL (ARRAY['very_narrow'::text, 'narrow'::text])) AND (COALESCE(b.repeatability_class_v5_1, ''::text) <> 'repeatable'::text) AND (COALESCE(b.holiday_profile_v4_1, 'none'::text) = 'none'::text)) THEN 'intermittent'::text
                    ELSE 'lumpy'::text
                END AS demand_class_v6
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
    demand_class_v5,
    top3_months_share_max_v5_1,
    top4_weeks_share_max_v5_1,
    top10_days_share_max_v5_1,
    weeks_active_ratio_v5_1,
    months_active_ratio_v5_1,
    months_to_80_min_v5_1,
    months_to_80_max_v5_1,
    avg_pos_run_len_min_v5_1,
    avg_pos_run_len_max_v5_1,
    avg_zero_run_len_max_v5_1,
    season_width_class_v5_1,
    continuity_class_v5_1,
    burstiness_class_v5_1,
    repeatability_class_v5_1,
    demand_class_v5_1,
    top3_months_share_max_v6,
    top4_weeks_share_max_v6,
    top10_days_share_max_v6,
    avg_pos_run_len_max_v6,
    avg_pos_run_len_min_v6,
    months_to_80_min_v6,
    months_to_80_max_v6,
    demand_class_v6
   FROM classified;


--
-- Name: v_family_time_metrics_v7; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_time_metrics_v7 AS
 WITH base AS (
         SELECT mv_family_day_base.family_name,
            sum(mv_family_day_base.qty_total) AS qty_total,
            count(*) FILTER (WHERE (mv_family_day_base.qty_total > (0)::numeric)) AS pos_days,
            min(mv_family_day_base.data) FILTER (WHERE (mv_family_day_base.qty_total > (0)::numeric)) AS first_day,
            max(mv_family_day_base.data) FILTER (WHERE (mv_family_day_base.qty_total > (0)::numeric)) AS last_day
           FROM ml_diag.mv_family_day_base
          GROUP BY mv_family_day_base.family_name
        ), week_dist AS (
         SELECT mv_family_day_base.family_name,
            (date_trunc('week'::text, (mv_family_day_base.data)::timestamp with time zone))::date AS week_start,
            sum(mv_family_day_base.qty_total) AS week_qty
           FROM ml_diag.mv_family_day_base
          GROUP BY mv_family_day_base.family_name, ((date_trunc('week'::text, (mv_family_day_base.data)::timestamp with time zone))::date)
        ), month_dist AS (
         SELECT mv_family_day_base.family_name,
            (date_trunc('month'::text, (mv_family_day_base.data)::timestamp with time zone))::date AS month_start,
            sum(mv_family_day_base.qty_total) AS month_qty
           FROM ml_diag.mv_family_day_base
          GROUP BY mv_family_day_base.family_name, ((date_trunc('month'::text, (mv_family_day_base.data)::timestamp with time zone))::date)
        ), max_week AS (
         SELECT week_dist.family_name,
            max(week_dist.week_qty) AS max_week_qty
           FROM week_dist
          GROUP BY week_dist.family_name
        ), max_month AS (
         SELECT month_dist.family_name,
            max(month_dist.month_qty) AS max_month_qty
           FROM month_dist
          GROUP BY month_dist.family_name
        )
 SELECT b.family_name,
    b.qty_total,
    b.pos_days,
    ((b.last_day - b.first_day) + 1) AS horizon_days,
    (b.qty_total / (NULLIF(b.pos_days, 0))::numeric) AS avg_qty_per_sale,
    ((((b.last_day - b.first_day) + 1))::numeric / (NULLIF(b.pos_days, 0))::numeric) AS adi,
    (mw.max_week_qty / NULLIF(b.qty_total, (0)::numeric)) AS max_week_share,
    (mm.max_month_qty / NULLIF(b.qty_total, (0)::numeric)) AS max_month_share
   FROM ((base b
     LEFT JOIN max_week mw USING (family_name))
     LEFT JOIN max_month mm USING (family_name));


--
-- Name: v_family_diagnostics_v7; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v7 AS
 WITH base AS (
         SELECT v6.family_name,
            v6.days_total,
            v6.pos_days,
            v6.zero_days,
            v6.zero_rate,
            v6.pos_rate,
            v6.qty_total,
            v6.qty_avg_all_days,
            v6.qty_avg_pos_days,
            v6.qty_std_pos_days,
            v6.value_total,
            v6.value_avg_all_days,
            v6.value_avg_pos_days,
            v6.value_std_pos_days,
            v6.years_count,
            v6.active_months,
            v6.active_value_months,
            v6.adi,
            v6.cv2_pos,
            v6.years_with_sales,
            v6.season_start_p25,
            v6.season_start_p50,
            v6.season_start_p75,
            v6.peak_doy,
            v6.qty_pct_total,
            v6.qty_cum_pct,
            v6.qty_tier,
            v6.value_pct_total,
            v6.value_cum_pct,
            v6.value_tier,
            v6.business_tier,
            v6.season_start_iqr,
            v6.intermittency_class,
            v6.seasonality_class,
            v6.demand_class_v2,
            v6.data_quality_class_v2,
            v6.combined_segment_v2,
            v6.cv_pos_qty,
            v6.cv_pos_value,
            v6.cv_week_qty,
            v6.cv_week_value,
            v6.cv_month_qty,
            v6.cv_month_value,
            v6.cv_year_qty,
            v6.cv_year_value,
            v6.cv_weekday_qty,
            v6.cv_weekday_value,
            v6.avg_gap_days,
            v6.median_gap_days,
            v6.p90_gap_days,
            v6.max_gap_days,
            v6.weeks_active_ratio,
            v6.months_active_ratio,
            v6.years_active_ratio,
            v6.top3_months_qty_share,
            v6.top6_months_qty_share,
            v6.top3_months_value_share,
            v6.top6_months_value_share,
            v6.top4_weeks_qty_share,
            v6.top8_weeks_qty_share,
            v6.top4_weeks_value_share,
            v6.top8_weeks_value_share,
            v6.top10_days_qty_share,
            v6.top30_days_qty_share,
            v6.top10_days_value_share,
            v6.top30_days_value_share,
            v6.peak_month_std,
            v6.peak_month_avg,
            v6.xmas_qty_share,
            v6.xmas_value_share,
            v6.spring_qty_share,
            v6.spring_value_share,
            v6.cv_pos_max,
            v6.cv_week_max,
            v6.cv_month_max,
            v6.cv_year_max,
            v6.cv_weekday_max,
            v6.top3_months_share_max,
            v6.top6_months_share_max,
            v6.top4_weeks_share_max,
            v6.top8_weeks_share_max,
            v6.top10_days_share_max,
            v6.top30_days_share_max,
            v6.spring_share_max,
            v6.xmas_share_max,
            v6.reliability_class_v4,
            v6.predictability_class_v4,
            v6.seasonality_strength_v4,
            v6.day_peakiness_class_v4,
            v6.week_peakiness_class_v4,
            v6.peak_month_stability_class_v4,
            v6.holiday_profile_v4,
            v6.dominant_concentration_scale_v4,
            v6.demand_class_v4,
            v6.season_width_class_v4_1,
            v6.day_peakiness_class_v4_1,
            v6.week_peakiness_class_v4_1,
            v6.continuity_class_v4_1,
            v6.peak_month_stability_class_v4_1,
            v6.holiday_profile_v4_1,
            v6.dominant_concentration_scale_v4_1,
            v6.instability_score_v4_1,
            v6.reliability_class_v4_1,
            v6.predictability_class_v4_1,
            v6.demand_class_v4_1,
            v6.months_to_80_qty,
            v6.months_to_90_qty,
            v6.months_to_80_value,
            v6.months_to_90_value,
            v6.peak_month_std_qty,
            v6.peak_month_std_value,
            v6.dominant_peak_month_share_qty,
            v6.dominant_peak_month_share_value,
            v6.avg_pos_run_len_qty,
            v6.median_pos_run_len_qty,
            v6.max_pos_run_len_qty,
            v6.avg_zero_run_len_qty,
            v6.median_zero_run_len_qty,
            v6.max_zero_run_len_qty,
            v6.avg_pos_run_len_value,
            v6.median_pos_run_len_value,
            v6.max_pos_run_len_value,
            v6.avg_zero_run_len_value,
            v6.median_zero_run_len_value,
            v6.max_zero_run_len_value,
            v6.avg_gap_days_qty,
            v6.median_gap_days_qty,
            v6.p90_gap_days_qty,
            v6.max_gap_days_qty,
            v6.avg_gap_days_value,
            v6.median_gap_days_value,
            v6.p90_gap_days_value,
            v6.max_gap_days_value,
            v6.top3_months_gap_qty_value,
            v6.top4_weeks_gap_qty_value,
            v6.top10_days_gap_qty_value,
            v6.avg_unit_value,
            v6.top3_months_share_max_v5,
            v6.top4_weeks_share_max_v5,
            v6.top10_days_share_max_v5,
            v6.season_width_qty_class_v5,
            v6.season_width_value_class_v5,
            v6.season_repeatability_qty_class_v5,
            v6.season_repeatability_value_class_v5,
            v6.burstiness_qty_class_v5,
            v6.burstiness_value_class_v5,
            v6.qty_value_alignment_class_v5,
            v6.logistics_profile_v5,
            v6.economic_profile_v5,
            v6.demand_class_v5,
            v6.top3_months_share_max_v5_1,
            v6.top4_weeks_share_max_v5_1,
            v6.top10_days_share_max_v5_1,
            v6.weeks_active_ratio_v5_1,
            v6.months_active_ratio_v5_1,
            v6.months_to_80_min_v5_1,
            v6.months_to_80_max_v5_1,
            v6.avg_pos_run_len_min_v5_1,
            v6.avg_pos_run_len_max_v5_1,
            v6.avg_zero_run_len_max_v5_1,
            v6.season_width_class_v5_1,
            v6.continuity_class_v5_1,
            v6.burstiness_class_v5_1,
            v6.repeatability_class_v5_1,
            v6.demand_class_v5_1,
            v6.top3_months_share_max_v6,
            v6.top4_weeks_share_max_v6,
            v6.top10_days_share_max_v6,
            v6.avg_pos_run_len_max_v6,
            v6.avg_pos_run_len_min_v6,
            v6.months_to_80_min_v6,
            v6.months_to_80_max_v6,
            v6.demand_class_v6,
            tm.horizon_days,
            tm.avg_qty_per_sale,
            tm.adi AS adi_v7,
            tm.max_week_share,
            tm.max_month_share
           FROM (ml_diag.v_family_diagnostics_v6 v6
             LEFT JOIN ml_diag.v_family_time_metrics_v7 tm USING (family_name))
        ), classified AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
            b.season_width_qty_class_v5,
            b.season_width_value_class_v5,
            b.season_repeatability_qty_class_v5,
            b.season_repeatability_value_class_v5,
            b.burstiness_qty_class_v5,
            b.burstiness_value_class_v5,
            b.qty_value_alignment_class_v5,
            b.logistics_profile_v5,
            b.economic_profile_v5,
            b.demand_class_v5,
            b.top3_months_share_max_v5_1,
            b.top4_weeks_share_max_v5_1,
            b.top10_days_share_max_v5_1,
            b.weeks_active_ratio_v5_1,
            b.months_active_ratio_v5_1,
            b.months_to_80_min_v5_1,
            b.months_to_80_max_v5_1,
            b.avg_pos_run_len_min_v5_1,
            b.avg_pos_run_len_max_v5_1,
            b.avg_zero_run_len_max_v5_1,
            b.season_width_class_v5_1,
            b.continuity_class_v5_1,
            b.burstiness_class_v5_1,
            b.repeatability_class_v5_1,
            b.demand_class_v5_1,
            b.top3_months_share_max_v6,
            b.top4_weeks_share_max_v6,
            b.top10_days_share_max_v6,
            b.avg_pos_run_len_max_v6,
            b.avg_pos_run_len_min_v6,
            b.months_to_80_min_v6,
            b.months_to_80_max_v6,
            b.demand_class_v6,
            b.horizon_days,
            b.avg_qty_per_sale,
            b.adi_v7,
            b.max_week_share,
            b.max_month_share,
                CASE
                    WHEN ((COALESCE(b.pos_days, (0)::bigint) < 5) OR (COALESCE(b.qty_total, (0)::numeric) < (10)::numeric) OR (COALESCE(b.value_total, (0)::numeric) < (50)::numeric)) THEN 'insufficient'::text
                    WHEN ((COALESCE(b.weeks_active_ratio, (0)::numeric) >= 0.94) AND (COALESCE(b.months_active_ratio, (0)::numeric) >= 0.98) AND (COALESCE(b.avg_pos_run_len_max_v6, (0)::numeric) >= 5.0) AND (COALESCE(b.top10_days_share_max_v6, (1)::numeric) <= 0.030) AND (COALESCE(b.top4_weeks_share_max_v6, (1)::numeric) <= 0.040) AND (COALESCE(b.max_week_share, (1)::numeric) <= 0.055) AND (COALESCE(b.max_month_share, (1)::numeric) <= 0.18) AND (COALESCE(b.months_to_80_min_v6, (0)::bigint) >= 8) AND (COALESCE(b.zero_rate, (1)::numeric) <= 0.30)) THEN 'dense'::text
                    WHEN (((COALESCE(b.max_week_share, (0)::numeric) >= 0.18) OR (COALESCE(b.top10_days_share_max_v6, (0)::numeric) >= 0.16)) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.28) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.55) AND (COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 2.20) AND (COALESCE(b.months_to_80_min_v6, (99)::bigint) >= 4)) THEN 'burst_lumpy'::text
                    WHEN ((COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 3) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.80) AND (COALESCE(b.max_month_share, (0)::numeric) >= 0.30) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.22) AND (COALESCE(b.zero_rate, (0)::numeric) >= 0.86)) THEN 'seasonal_intermittent'::text
                    WHEN ((COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 4) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.70) AND (COALESCE(b.max_month_share, (0)::numeric) >= 0.22) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.68) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.85) AND ((COALESCE(b.repeatability_class_v5_1, ''::text) = ANY (ARRAY['repeatable'::text, 'mixed'::text])) OR (COALESCE(b.holiday_profile_v4_1, 'none'::text) <> 'none'::text) OR (COALESCE(b.holiday_profile_v4, 'none'::text) <> 'none'::text))) THEN 'seasonal_lumpy'::text
                    WHEN ((COALESCE(b.adi_v7, (0)::numeric) >= 3.2) AND (COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 2.20) AND (COALESCE(b.top10_days_share_max_v6, (1)::numeric) < 0.18) AND (COALESCE(b.max_week_share, (1)::numeric) < 0.20) AND (COALESCE(b.top3_months_share_max_v6, (1)::numeric) < 0.78)) THEN 'intermittent'::text
                    ELSE 'lumpy'::text
                END AS demand_class_v7
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
    demand_class_v5,
    top3_months_share_max_v5_1,
    top4_weeks_share_max_v5_1,
    top10_days_share_max_v5_1,
    weeks_active_ratio_v5_1,
    months_active_ratio_v5_1,
    months_to_80_min_v5_1,
    months_to_80_max_v5_1,
    avg_pos_run_len_min_v5_1,
    avg_pos_run_len_max_v5_1,
    avg_zero_run_len_max_v5_1,
    season_width_class_v5_1,
    continuity_class_v5_1,
    burstiness_class_v5_1,
    repeatability_class_v5_1,
    demand_class_v5_1,
    top3_months_share_max_v6,
    top4_weeks_share_max_v6,
    top10_days_share_max_v6,
    avg_pos_run_len_max_v6,
    avg_pos_run_len_min_v6,
    months_to_80_min_v6,
    months_to_80_max_v6,
    demand_class_v6,
    horizon_days,
    avg_qty_per_sale,
    adi_v7,
    max_week_share,
    max_month_share,
    demand_class_v7
   FROM classified;


--
-- Name: v_family_diagnostics_v7_1; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v7_1 AS
 WITH base AS (
         SELECT v7.family_name,
            v7.days_total,
            v7.pos_days,
            v7.zero_days,
            v7.zero_rate,
            v7.pos_rate,
            v7.qty_total,
            v7.qty_avg_all_days,
            v7.qty_avg_pos_days,
            v7.qty_std_pos_days,
            v7.value_total,
            v7.value_avg_all_days,
            v7.value_avg_pos_days,
            v7.value_std_pos_days,
            v7.years_count,
            v7.active_months,
            v7.active_value_months,
            v7.adi,
            v7.cv2_pos,
            v7.years_with_sales,
            v7.season_start_p25,
            v7.season_start_p50,
            v7.season_start_p75,
            v7.peak_doy,
            v7.qty_pct_total,
            v7.qty_cum_pct,
            v7.qty_tier,
            v7.value_pct_total,
            v7.value_cum_pct,
            v7.value_tier,
            v7.business_tier,
            v7.season_start_iqr,
            v7.intermittency_class,
            v7.seasonality_class,
            v7.demand_class_v2,
            v7.data_quality_class_v2,
            v7.combined_segment_v2,
            v7.cv_pos_qty,
            v7.cv_pos_value,
            v7.cv_week_qty,
            v7.cv_week_value,
            v7.cv_month_qty,
            v7.cv_month_value,
            v7.cv_year_qty,
            v7.cv_year_value,
            v7.cv_weekday_qty,
            v7.cv_weekday_value,
            v7.avg_gap_days,
            v7.median_gap_days,
            v7.p90_gap_days,
            v7.max_gap_days,
            v7.weeks_active_ratio,
            v7.months_active_ratio,
            v7.years_active_ratio,
            v7.top3_months_qty_share,
            v7.top6_months_qty_share,
            v7.top3_months_value_share,
            v7.top6_months_value_share,
            v7.top4_weeks_qty_share,
            v7.top8_weeks_qty_share,
            v7.top4_weeks_value_share,
            v7.top8_weeks_value_share,
            v7.top10_days_qty_share,
            v7.top30_days_qty_share,
            v7.top10_days_value_share,
            v7.top30_days_value_share,
            v7.peak_month_std,
            v7.peak_month_avg,
            v7.xmas_qty_share,
            v7.xmas_value_share,
            v7.spring_qty_share,
            v7.spring_value_share,
            v7.cv_pos_max,
            v7.cv_week_max,
            v7.cv_month_max,
            v7.cv_year_max,
            v7.cv_weekday_max,
            v7.top3_months_share_max,
            v7.top6_months_share_max,
            v7.top4_weeks_share_max,
            v7.top8_weeks_share_max,
            v7.top10_days_share_max,
            v7.top30_days_share_max,
            v7.spring_share_max,
            v7.xmas_share_max,
            v7.reliability_class_v4,
            v7.predictability_class_v4,
            v7.seasonality_strength_v4,
            v7.day_peakiness_class_v4,
            v7.week_peakiness_class_v4,
            v7.peak_month_stability_class_v4,
            v7.holiday_profile_v4,
            v7.dominant_concentration_scale_v4,
            v7.demand_class_v4,
            v7.season_width_class_v4_1,
            v7.day_peakiness_class_v4_1,
            v7.week_peakiness_class_v4_1,
            v7.continuity_class_v4_1,
            v7.peak_month_stability_class_v4_1,
            v7.holiday_profile_v4_1,
            v7.dominant_concentration_scale_v4_1,
            v7.instability_score_v4_1,
            v7.reliability_class_v4_1,
            v7.predictability_class_v4_1,
            v7.demand_class_v4_1,
            v7.months_to_80_qty,
            v7.months_to_90_qty,
            v7.months_to_80_value,
            v7.months_to_90_value,
            v7.peak_month_std_qty,
            v7.peak_month_std_value,
            v7.dominant_peak_month_share_qty,
            v7.dominant_peak_month_share_value,
            v7.avg_pos_run_len_qty,
            v7.median_pos_run_len_qty,
            v7.max_pos_run_len_qty,
            v7.avg_zero_run_len_qty,
            v7.median_zero_run_len_qty,
            v7.max_zero_run_len_qty,
            v7.avg_pos_run_len_value,
            v7.median_pos_run_len_value,
            v7.max_pos_run_len_value,
            v7.avg_zero_run_len_value,
            v7.median_zero_run_len_value,
            v7.max_zero_run_len_value,
            v7.avg_gap_days_qty,
            v7.median_gap_days_qty,
            v7.p90_gap_days_qty,
            v7.max_gap_days_qty,
            v7.avg_gap_days_value,
            v7.median_gap_days_value,
            v7.p90_gap_days_value,
            v7.max_gap_days_value,
            v7.top3_months_gap_qty_value,
            v7.top4_weeks_gap_qty_value,
            v7.top10_days_gap_qty_value,
            v7.avg_unit_value,
            v7.top3_months_share_max_v5,
            v7.top4_weeks_share_max_v5,
            v7.top10_days_share_max_v5,
            v7.season_width_qty_class_v5,
            v7.season_width_value_class_v5,
            v7.season_repeatability_qty_class_v5,
            v7.season_repeatability_value_class_v5,
            v7.burstiness_qty_class_v5,
            v7.burstiness_value_class_v5,
            v7.qty_value_alignment_class_v5,
            v7.logistics_profile_v5,
            v7.economic_profile_v5,
            v7.demand_class_v5,
            v7.top3_months_share_max_v5_1,
            v7.top4_weeks_share_max_v5_1,
            v7.top10_days_share_max_v5_1,
            v7.weeks_active_ratio_v5_1,
            v7.months_active_ratio_v5_1,
            v7.months_to_80_min_v5_1,
            v7.months_to_80_max_v5_1,
            v7.avg_pos_run_len_min_v5_1,
            v7.avg_pos_run_len_max_v5_1,
            v7.avg_zero_run_len_max_v5_1,
            v7.season_width_class_v5_1,
            v7.continuity_class_v5_1,
            v7.burstiness_class_v5_1,
            v7.repeatability_class_v5_1,
            v7.demand_class_v5_1,
            v7.top3_months_share_max_v6,
            v7.top4_weeks_share_max_v6,
            v7.top10_days_share_max_v6,
            v7.avg_pos_run_len_max_v6,
            v7.avg_pos_run_len_min_v6,
            v7.months_to_80_min_v6,
            v7.months_to_80_max_v6,
            v7.demand_class_v6,
            v7.horizon_days,
            v7.avg_qty_per_sale,
            v7.adi_v7,
            v7.max_week_share,
            v7.max_month_share,
            v7.demand_class_v7
           FROM ml_diag.v_family_diagnostics_v7 v7
        ), classified AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
            b.season_width_qty_class_v5,
            b.season_width_value_class_v5,
            b.season_repeatability_qty_class_v5,
            b.season_repeatability_value_class_v5,
            b.burstiness_qty_class_v5,
            b.burstiness_value_class_v5,
            b.qty_value_alignment_class_v5,
            b.logistics_profile_v5,
            b.economic_profile_v5,
            b.demand_class_v5,
            b.top3_months_share_max_v5_1,
            b.top4_weeks_share_max_v5_1,
            b.top10_days_share_max_v5_1,
            b.weeks_active_ratio_v5_1,
            b.months_active_ratio_v5_1,
            b.months_to_80_min_v5_1,
            b.months_to_80_max_v5_1,
            b.avg_pos_run_len_min_v5_1,
            b.avg_pos_run_len_max_v5_1,
            b.avg_zero_run_len_max_v5_1,
            b.season_width_class_v5_1,
            b.continuity_class_v5_1,
            b.burstiness_class_v5_1,
            b.repeatability_class_v5_1,
            b.demand_class_v5_1,
            b.top3_months_share_max_v6,
            b.top4_weeks_share_max_v6,
            b.top10_days_share_max_v6,
            b.avg_pos_run_len_max_v6,
            b.avg_pos_run_len_min_v6,
            b.months_to_80_min_v6,
            b.months_to_80_max_v6,
            b.demand_class_v6,
            b.horizon_days,
            b.avg_qty_per_sale,
            b.adi_v7,
            b.max_week_share,
            b.max_month_share,
            b.demand_class_v7,
                CASE
                    WHEN ((COALESCE(b.pos_days, (0)::bigint) < 5) OR (COALESCE(b.qty_total, (0)::numeric) < (10)::numeric) OR (COALESCE(b.value_total, (0)::numeric) < (50)::numeric)) THEN 'insufficient'::text
                    WHEN ((COALESCE(b.weeks_active_ratio, (0)::numeric) >= 0.94) AND (COALESCE(b.months_active_ratio, (0)::numeric) >= 0.98) AND (COALESCE(b.avg_pos_run_len_max_v6, (0)::numeric) >= 5.0) AND (COALESCE(b.top10_days_share_max_v6, (1)::numeric) <= 0.030) AND (COALESCE(b.top4_weeks_share_max_v6, (1)::numeric) <= 0.040) AND (COALESCE(b.max_week_share, (1)::numeric) <= 0.055) AND (COALESCE(b.max_month_share, (1)::numeric) <= 0.18) AND (COALESCE(b.months_to_80_min_v6, (0)::bigint) >= 8) AND (COALESCE(b.zero_rate, (1)::numeric) <= 0.30)) THEN 'dense'::text
                    WHEN (((COALESCE(b.max_week_share, (0)::numeric) >= 0.18) OR (COALESCE(b.top10_days_share_max_v6, (0)::numeric) >= 0.16) OR (COALESCE(b.top4_weeks_share_max_v6, (0)::numeric) >= 0.20)) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.28) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.55) AND (COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 2.20) AND (COALESCE(b.months_to_80_min_v6, (99)::bigint) >= 4)) THEN 'burst_lumpy'::text
                    WHEN ((COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 3) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.80) AND (COALESCE(b.max_month_share, (0)::numeric) >= 0.30) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.22) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.50) AND (COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 2.00)) THEN 'seasonal_intermittent'::text
                    WHEN (((COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 4) OR (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.72) OR (COALESCE(b.max_month_share, (0)::numeric) >= 0.24)) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.65) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.90) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.75) AND ((COALESCE(b.repeatability_class_v5_1, 'erratic'::text) = ANY (ARRAY['repeatable'::text, 'mixed'::text])) OR (COALESCE(b.season_repeatability_qty_class_v5, 'erratic'::text) = ANY (ARRAY['very_repeatable'::text, 'repeatable'::text, 'mixed'::text])) OR (COALESCE(b.season_repeatability_value_class_v5, 'erratic'::text) = ANY (ARRAY['very_repeatable'::text, 'repeatable'::text, 'mixed'::text])) OR (COALESCE(b.holiday_profile_v4_1, 'none'::text) <> 'none'::text) OR (COALESCE(b.holiday_profile_v4, 'none'::text) <> 'none'::text)) AND (NOT ((COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.22) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.50) AND (COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 3)))) THEN 'seasonal_lumpy'::text
                    WHEN (((COALESCE(b.zero_rate, (0)::numeric) >= 0.72) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.58) AND (COALESCE(b.months_to_80_min_v6, (0)::bigint) >= 5) AND (COALESCE(b.top10_days_share_max_v6, (1)::numeric) < 0.16) AND (COALESCE(b.top3_months_share_max_v6, (1)::numeric) < 0.72)) OR ((COALESCE(b.continuity_class_v5_1, ''::text) = ANY (ARRAY['sporadic'::text, 'discontinuous'::text])) AND (COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 2.20) AND (COALESCE(b.months_to_80_min_v6, (0)::bigint) >= 5) AND (COALESCE(b.max_month_share, (1)::numeric) < 0.24) AND (COALESCE(b.top3_months_share_max_v6, (1)::numeric) < 0.72))) THEN 'intermittent'::text
                    ELSE 'lumpy'::text
                END AS demand_class_v7_1
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
    demand_class_v5,
    top3_months_share_max_v5_1,
    top4_weeks_share_max_v5_1,
    top10_days_share_max_v5_1,
    weeks_active_ratio_v5_1,
    months_active_ratio_v5_1,
    months_to_80_min_v5_1,
    months_to_80_max_v5_1,
    avg_pos_run_len_min_v5_1,
    avg_pos_run_len_max_v5_1,
    avg_zero_run_len_max_v5_1,
    season_width_class_v5_1,
    continuity_class_v5_1,
    burstiness_class_v5_1,
    repeatability_class_v5_1,
    demand_class_v5_1,
    top3_months_share_max_v6,
    top4_weeks_share_max_v6,
    top10_days_share_max_v6,
    avg_pos_run_len_max_v6,
    avg_pos_run_len_min_v6,
    months_to_80_min_v6,
    months_to_80_max_v6,
    demand_class_v6,
    horizon_days,
    avg_qty_per_sale,
    adi_v7,
    max_week_share,
    max_month_share,
    demand_class_v7,
    demand_class_v7_1
   FROM classified;


--
-- Name: v_family_diagnostics_v7_2; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v7_2 AS
 WITH base AS (
         SELECT v.family_name,
            v.days_total,
            v.pos_days,
            v.zero_days,
            v.zero_rate,
            v.pos_rate,
            v.qty_total,
            v.qty_avg_all_days,
            v.qty_avg_pos_days,
            v.qty_std_pos_days,
            v.value_total,
            v.value_avg_all_days,
            v.value_avg_pos_days,
            v.value_std_pos_days,
            v.years_count,
            v.active_months,
            v.active_value_months,
            v.adi,
            v.cv2_pos,
            v.years_with_sales,
            v.season_start_p25,
            v.season_start_p50,
            v.season_start_p75,
            v.peak_doy,
            v.qty_pct_total,
            v.qty_cum_pct,
            v.qty_tier,
            v.value_pct_total,
            v.value_cum_pct,
            v.value_tier,
            v.business_tier,
            v.season_start_iqr,
            v.intermittency_class,
            v.seasonality_class,
            v.demand_class_v2,
            v.data_quality_class_v2,
            v.combined_segment_v2,
            v.cv_pos_qty,
            v.cv_pos_value,
            v.cv_week_qty,
            v.cv_week_value,
            v.cv_month_qty,
            v.cv_month_value,
            v.cv_year_qty,
            v.cv_year_value,
            v.cv_weekday_qty,
            v.cv_weekday_value,
            v.avg_gap_days,
            v.median_gap_days,
            v.p90_gap_days,
            v.max_gap_days,
            v.weeks_active_ratio,
            v.months_active_ratio,
            v.years_active_ratio,
            v.top3_months_qty_share,
            v.top6_months_qty_share,
            v.top3_months_value_share,
            v.top6_months_value_share,
            v.top4_weeks_qty_share,
            v.top8_weeks_qty_share,
            v.top4_weeks_value_share,
            v.top8_weeks_value_share,
            v.top10_days_qty_share,
            v.top30_days_qty_share,
            v.top10_days_value_share,
            v.top30_days_value_share,
            v.peak_month_std,
            v.peak_month_avg,
            v.xmas_qty_share,
            v.xmas_value_share,
            v.spring_qty_share,
            v.spring_value_share,
            v.cv_pos_max,
            v.cv_week_max,
            v.cv_month_max,
            v.cv_year_max,
            v.cv_weekday_max,
            v.top3_months_share_max,
            v.top6_months_share_max,
            v.top4_weeks_share_max,
            v.top8_weeks_share_max,
            v.top10_days_share_max,
            v.top30_days_share_max,
            v.spring_share_max,
            v.xmas_share_max,
            v.reliability_class_v4,
            v.predictability_class_v4,
            v.seasonality_strength_v4,
            v.day_peakiness_class_v4,
            v.week_peakiness_class_v4,
            v.peak_month_stability_class_v4,
            v.holiday_profile_v4,
            v.dominant_concentration_scale_v4,
            v.demand_class_v4,
            v.season_width_class_v4_1,
            v.day_peakiness_class_v4_1,
            v.week_peakiness_class_v4_1,
            v.continuity_class_v4_1,
            v.peak_month_stability_class_v4_1,
            v.holiday_profile_v4_1,
            v.dominant_concentration_scale_v4_1,
            v.instability_score_v4_1,
            v.reliability_class_v4_1,
            v.predictability_class_v4_1,
            v.demand_class_v4_1,
            v.months_to_80_qty,
            v.months_to_90_qty,
            v.months_to_80_value,
            v.months_to_90_value,
            v.peak_month_std_qty,
            v.peak_month_std_value,
            v.dominant_peak_month_share_qty,
            v.dominant_peak_month_share_value,
            v.avg_pos_run_len_qty,
            v.median_pos_run_len_qty,
            v.max_pos_run_len_qty,
            v.avg_zero_run_len_qty,
            v.median_zero_run_len_qty,
            v.max_zero_run_len_qty,
            v.avg_pos_run_len_value,
            v.median_pos_run_len_value,
            v.max_pos_run_len_value,
            v.avg_zero_run_len_value,
            v.median_zero_run_len_value,
            v.max_zero_run_len_value,
            v.avg_gap_days_qty,
            v.median_gap_days_qty,
            v.p90_gap_days_qty,
            v.max_gap_days_qty,
            v.avg_gap_days_value,
            v.median_gap_days_value,
            v.p90_gap_days_value,
            v.max_gap_days_value,
            v.top3_months_gap_qty_value,
            v.top4_weeks_gap_qty_value,
            v.top10_days_gap_qty_value,
            v.avg_unit_value,
            v.top3_months_share_max_v5,
            v.top4_weeks_share_max_v5,
            v.top10_days_share_max_v5,
            v.season_width_qty_class_v5,
            v.season_width_value_class_v5,
            v.season_repeatability_qty_class_v5,
            v.season_repeatability_value_class_v5,
            v.burstiness_qty_class_v5,
            v.burstiness_value_class_v5,
            v.qty_value_alignment_class_v5,
            v.logistics_profile_v5,
            v.economic_profile_v5,
            v.demand_class_v5,
            v.top3_months_share_max_v5_1,
            v.top4_weeks_share_max_v5_1,
            v.top10_days_share_max_v5_1,
            v.weeks_active_ratio_v5_1,
            v.months_active_ratio_v5_1,
            v.months_to_80_min_v5_1,
            v.months_to_80_max_v5_1,
            v.avg_pos_run_len_min_v5_1,
            v.avg_pos_run_len_max_v5_1,
            v.avg_zero_run_len_max_v5_1,
            v.season_width_class_v5_1,
            v.continuity_class_v5_1,
            v.burstiness_class_v5_1,
            v.repeatability_class_v5_1,
            v.demand_class_v5_1,
            v.top3_months_share_max_v6,
            v.top4_weeks_share_max_v6,
            v.top10_days_share_max_v6,
            v.avg_pos_run_len_max_v6,
            v.avg_pos_run_len_min_v6,
            v.months_to_80_min_v6,
            v.months_to_80_max_v6,
            v.demand_class_v6,
            v.horizon_days,
            v.avg_qty_per_sale,
            v.adi_v7,
            v.max_week_share,
            v.max_month_share,
            v.demand_class_v7,
            v.demand_class_v7_1,
            (COALESCE(v.top3_months_share_max_v6, (0)::numeric) - (COALESCE(v.months_active_ratio, (0)::numeric) * 0.35)) AS seasonal_strength_v7_2,
            (((((COALESCE(v.top10_days_share_max_v6, (0)::numeric) * 0.45) + (COALESCE(v.top4_weeks_share_max_v6, (0)::numeric) * 0.35)) + (COALESCE(v.max_week_share, (0)::numeric) * 0.20)) - (COALESCE(v.weeks_active_ratio, (0)::numeric) * 0.25)) - (LEAST(COALESCE(v.avg_pos_run_len_max_v6, (0)::numeric), 3.0) * 0.05)) AS burst_strength_v7_2
           FROM ml_diag.v_family_diagnostics_v7_1 v
        ), reclassified AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
            b.season_width_qty_class_v5,
            b.season_width_value_class_v5,
            b.season_repeatability_qty_class_v5,
            b.season_repeatability_value_class_v5,
            b.burstiness_qty_class_v5,
            b.burstiness_value_class_v5,
            b.qty_value_alignment_class_v5,
            b.logistics_profile_v5,
            b.economic_profile_v5,
            b.demand_class_v5,
            b.top3_months_share_max_v5_1,
            b.top4_weeks_share_max_v5_1,
            b.top10_days_share_max_v5_1,
            b.weeks_active_ratio_v5_1,
            b.months_active_ratio_v5_1,
            b.months_to_80_min_v5_1,
            b.months_to_80_max_v5_1,
            b.avg_pos_run_len_min_v5_1,
            b.avg_pos_run_len_max_v5_1,
            b.avg_zero_run_len_max_v5_1,
            b.season_width_class_v5_1,
            b.continuity_class_v5_1,
            b.burstiness_class_v5_1,
            b.repeatability_class_v5_1,
            b.demand_class_v5_1,
            b.top3_months_share_max_v6,
            b.top4_weeks_share_max_v6,
            b.top10_days_share_max_v6,
            b.avg_pos_run_len_max_v6,
            b.avg_pos_run_len_min_v6,
            b.months_to_80_min_v6,
            b.months_to_80_max_v6,
            b.demand_class_v6,
            b.horizon_days,
            b.avg_qty_per_sale,
            b.adi_v7,
            b.max_week_share,
            b.max_month_share,
            b.demand_class_v7,
            b.demand_class_v7_1,
            b.seasonal_strength_v7_2,
            b.burst_strength_v7_2,
                CASE
                    WHEN (b.demand_class_v7_1 = 'insufficient'::text) THEN 'insufficient'::text
                    WHEN (b.demand_class_v7_1 = 'dense'::text) THEN 'dense'::text
                    WHEN ((b.demand_class_v7_1 = 'burst_lumpy'::text) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.92) AND (COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 2) AND (COALESCE(b.max_month_share, (0)::numeric) >= 0.28) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.12) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.20)) THEN 'seasonal_intermittent'::text
                    WHEN ((b.demand_class_v7_1 = 'lumpy'::text) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.72) AND (COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 4) AND (COALESCE(b.seasonal_strength_v7_2, ('-999'::integer)::numeric) >= 0.42) AND (COALESCE(b.max_month_share, (0)::numeric) >= 0.030) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.90)) THEN 'seasonal_lumpy'::text
                    WHEN ((b.demand_class_v7_1 = 'seasonal_lumpy'::text) AND (COALESCE(b.top3_months_share_max_v6, (1)::numeric) <= 0.74) AND (COALESCE(b.months_active_ratio, (0)::numeric) >= 0.55) AND (COALESCE(b.weeks_active_ratio, (0)::numeric) >= 0.28) AND (COALESCE(b.max_month_share, (0)::numeric) <= 0.11)) THEN 'lumpy'::text
                    WHEN ((b.demand_class_v7_1 = 'intermittent'::text) AND (COALESCE(b.top10_days_share_max_v6, (0)::numeric) >= 0.16) AND (COALESCE(b.top4_weeks_share_max_v6, (0)::numeric) >= 0.14) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.22) AND (COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 1.90)) THEN 'burst_lumpy'::text
                    WHEN ((b.demand_class_v7_1 = 'lumpy'::text) AND (COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 2.20) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.60) AND (COALESCE(b.adi_v7, (0)::numeric) >= 4.80) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) < 0.72)) THEN 'intermittent'::text
                    WHEN ((b.demand_class_v7_1 = 'seasonal_lumpy'::text) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) < 0.72) AND (COALESCE(b.avg_pos_run_len_max_v6, (999)::numeric) <= 2.00) AND (COALESCE(b.adi_v7, (0)::numeric) >= 5.20)) THEN 'intermittent'::text
                    ELSE b.demand_class_v7_1
                END AS demand_class_v7_2
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
    demand_class_v5,
    top3_months_share_max_v5_1,
    top4_weeks_share_max_v5_1,
    top10_days_share_max_v5_1,
    weeks_active_ratio_v5_1,
    months_active_ratio_v5_1,
    months_to_80_min_v5_1,
    months_to_80_max_v5_1,
    avg_pos_run_len_min_v5_1,
    avg_pos_run_len_max_v5_1,
    avg_zero_run_len_max_v5_1,
    season_width_class_v5_1,
    continuity_class_v5_1,
    burstiness_class_v5_1,
    repeatability_class_v5_1,
    demand_class_v5_1,
    top3_months_share_max_v6,
    top4_weeks_share_max_v6,
    top10_days_share_max_v6,
    avg_pos_run_len_max_v6,
    avg_pos_run_len_min_v6,
    months_to_80_min_v6,
    months_to_80_max_v6,
    demand_class_v6,
    horizon_days,
    avg_qty_per_sale,
    adi_v7,
    max_week_share,
    max_month_share,
    demand_class_v7,
    demand_class_v7_1,
    seasonal_strength_v7_2,
    burst_strength_v7_2,
    demand_class_v7_2
   FROM reclassified;


--
-- Name: v_family_diagnostics_v7_2_bis; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v7_2_bis AS
 WITH base AS (
         SELECT v.family_name,
            v.days_total,
            v.pos_days,
            v.zero_days,
            v.zero_rate,
            v.pos_rate,
            v.qty_total,
            v.qty_avg_all_days,
            v.qty_avg_pos_days,
            v.qty_std_pos_days,
            v.value_total,
            v.value_avg_all_days,
            v.value_avg_pos_days,
            v.value_std_pos_days,
            v.years_count,
            v.active_months,
            v.active_value_months,
            v.adi,
            v.cv2_pos,
            v.years_with_sales,
            v.season_start_p25,
            v.season_start_p50,
            v.season_start_p75,
            v.peak_doy,
            v.qty_pct_total,
            v.qty_cum_pct,
            v.qty_tier,
            v.value_pct_total,
            v.value_cum_pct,
            v.value_tier,
            v.business_tier,
            v.season_start_iqr,
            v.intermittency_class,
            v.seasonality_class,
            v.demand_class_v2,
            v.data_quality_class_v2,
            v.combined_segment_v2,
            v.cv_pos_qty,
            v.cv_pos_value,
            v.cv_week_qty,
            v.cv_week_value,
            v.cv_month_qty,
            v.cv_month_value,
            v.cv_year_qty,
            v.cv_year_value,
            v.cv_weekday_qty,
            v.cv_weekday_value,
            v.avg_gap_days,
            v.median_gap_days,
            v.p90_gap_days,
            v.max_gap_days,
            v.weeks_active_ratio,
            v.months_active_ratio,
            v.years_active_ratio,
            v.top3_months_qty_share,
            v.top6_months_qty_share,
            v.top3_months_value_share,
            v.top6_months_value_share,
            v.top4_weeks_qty_share,
            v.top8_weeks_qty_share,
            v.top4_weeks_value_share,
            v.top8_weeks_value_share,
            v.top10_days_qty_share,
            v.top30_days_qty_share,
            v.top10_days_value_share,
            v.top30_days_value_share,
            v.peak_month_std,
            v.peak_month_avg,
            v.xmas_qty_share,
            v.xmas_value_share,
            v.spring_qty_share,
            v.spring_value_share,
            v.cv_pos_max,
            v.cv_week_max,
            v.cv_month_max,
            v.cv_year_max,
            v.cv_weekday_max,
            v.top3_months_share_max,
            v.top6_months_share_max,
            v.top4_weeks_share_max,
            v.top8_weeks_share_max,
            v.top10_days_share_max,
            v.top30_days_share_max,
            v.spring_share_max,
            v.xmas_share_max,
            v.reliability_class_v4,
            v.predictability_class_v4,
            v.seasonality_strength_v4,
            v.day_peakiness_class_v4,
            v.week_peakiness_class_v4,
            v.peak_month_stability_class_v4,
            v.holiday_profile_v4,
            v.dominant_concentration_scale_v4,
            v.demand_class_v4,
            v.season_width_class_v4_1,
            v.day_peakiness_class_v4_1,
            v.week_peakiness_class_v4_1,
            v.continuity_class_v4_1,
            v.peak_month_stability_class_v4_1,
            v.holiday_profile_v4_1,
            v.dominant_concentration_scale_v4_1,
            v.instability_score_v4_1,
            v.reliability_class_v4_1,
            v.predictability_class_v4_1,
            v.demand_class_v4_1,
            v.months_to_80_qty,
            v.months_to_90_qty,
            v.months_to_80_value,
            v.months_to_90_value,
            v.peak_month_std_qty,
            v.peak_month_std_value,
            v.dominant_peak_month_share_qty,
            v.dominant_peak_month_share_value,
            v.avg_pos_run_len_qty,
            v.median_pos_run_len_qty,
            v.max_pos_run_len_qty,
            v.avg_zero_run_len_qty,
            v.median_zero_run_len_qty,
            v.max_zero_run_len_qty,
            v.avg_pos_run_len_value,
            v.median_pos_run_len_value,
            v.max_pos_run_len_value,
            v.avg_zero_run_len_value,
            v.median_zero_run_len_value,
            v.max_zero_run_len_value,
            v.avg_gap_days_qty,
            v.median_gap_days_qty,
            v.p90_gap_days_qty,
            v.max_gap_days_qty,
            v.avg_gap_days_value,
            v.median_gap_days_value,
            v.p90_gap_days_value,
            v.max_gap_days_value,
            v.top3_months_gap_qty_value,
            v.top4_weeks_gap_qty_value,
            v.top10_days_gap_qty_value,
            v.avg_unit_value,
            v.top3_months_share_max_v5,
            v.top4_weeks_share_max_v5,
            v.top10_days_share_max_v5,
            v.season_width_qty_class_v5,
            v.season_width_value_class_v5,
            v.season_repeatability_qty_class_v5,
            v.season_repeatability_value_class_v5,
            v.burstiness_qty_class_v5,
            v.burstiness_value_class_v5,
            v.qty_value_alignment_class_v5,
            v.logistics_profile_v5,
            v.economic_profile_v5,
            v.demand_class_v5,
            v.top3_months_share_max_v5_1,
            v.top4_weeks_share_max_v5_1,
            v.top10_days_share_max_v5_1,
            v.weeks_active_ratio_v5_1,
            v.months_active_ratio_v5_1,
            v.months_to_80_min_v5_1,
            v.months_to_80_max_v5_1,
            v.avg_pos_run_len_min_v5_1,
            v.avg_pos_run_len_max_v5_1,
            v.avg_zero_run_len_max_v5_1,
            v.season_width_class_v5_1,
            v.continuity_class_v5_1,
            v.burstiness_class_v5_1,
            v.repeatability_class_v5_1,
            v.demand_class_v5_1,
            v.top3_months_share_max_v6,
            v.top4_weeks_share_max_v6,
            v.top10_days_share_max_v6,
            v.avg_pos_run_len_max_v6,
            v.avg_pos_run_len_min_v6,
            v.months_to_80_min_v6,
            v.months_to_80_max_v6,
            v.demand_class_v6,
            v.horizon_days,
            v.avg_qty_per_sale,
            v.adi_v7,
            v.max_week_share,
            v.max_month_share,
            v.demand_class_v7,
            v.demand_class_v7_1,
            v.seasonal_strength_v7_2,
            v.burst_strength_v7_2,
            v.demand_class_v7_2,
            (COALESCE(v.top3_months_share_max_v6, (0)::numeric) - (COALESCE(v.months_active_ratio, (0)::numeric) * 0.35)) AS seasonal_strength_v7_2_bis,
            (((((COALESCE(v.top10_days_share_max_v6, (0)::numeric) * 0.45) + (COALESCE(v.top4_weeks_share_max_v6, (0)::numeric) * 0.35)) + (COALESCE(v.max_week_share, (0)::numeric) * 0.20)) - (COALESCE(v.weeks_active_ratio, (0)::numeric) * 0.25)) - (LEAST(COALESCE(v.avg_pos_run_len_max_v6, (0)::numeric), 3.0) * 0.05)) AS burst_strength_v7_2_bis
           FROM ml_diag.v_family_diagnostics_v7_2 v
        ), reclassified AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
            b.season_width_qty_class_v5,
            b.season_width_value_class_v5,
            b.season_repeatability_qty_class_v5,
            b.season_repeatability_value_class_v5,
            b.burstiness_qty_class_v5,
            b.burstiness_value_class_v5,
            b.qty_value_alignment_class_v5,
            b.logistics_profile_v5,
            b.economic_profile_v5,
            b.demand_class_v5,
            b.top3_months_share_max_v5_1,
            b.top4_weeks_share_max_v5_1,
            b.top10_days_share_max_v5_1,
            b.weeks_active_ratio_v5_1,
            b.months_active_ratio_v5_1,
            b.months_to_80_min_v5_1,
            b.months_to_80_max_v5_1,
            b.avg_pos_run_len_min_v5_1,
            b.avg_pos_run_len_max_v5_1,
            b.avg_zero_run_len_max_v5_1,
            b.season_width_class_v5_1,
            b.continuity_class_v5_1,
            b.burstiness_class_v5_1,
            b.repeatability_class_v5_1,
            b.demand_class_v5_1,
            b.top3_months_share_max_v6,
            b.top4_weeks_share_max_v6,
            b.top10_days_share_max_v6,
            b.avg_pos_run_len_max_v6,
            b.avg_pos_run_len_min_v6,
            b.months_to_80_min_v6,
            b.months_to_80_max_v6,
            b.demand_class_v6,
            b.horizon_days,
            b.avg_qty_per_sale,
            b.adi_v7,
            b.max_week_share,
            b.max_month_share,
            b.demand_class_v7,
            b.demand_class_v7_1,
            b.seasonal_strength_v7_2,
            b.burst_strength_v7_2,
            b.demand_class_v7_2,
            b.seasonal_strength_v7_2_bis,
            b.burst_strength_v7_2_bis,
                CASE
                    WHEN (b.demand_class_v7_2 = 'insufficient'::text) THEN 'insufficient'::text
                    WHEN (b.demand_class_v7_2 = 'dense'::text) THEN 'dense'::text
                    WHEN (b.demand_class_v7_2 = 'burst_lumpy'::text) THEN 'burst_lumpy'::text
                    WHEN (b.demand_class_v7_2 = 'seasonal_intermittent'::text) THEN 'seasonal_intermittent'::text
                    WHEN ((b.demand_class_v7_2 = 'seasonal_lumpy'::text) AND ((COALESCE(b.top3_months_share_max_v6, (0)::numeric) < 0.80) OR (COALESCE(b.months_to_80_min_v6, (99)::bigint) > 3) OR (COALESCE(b.months_active_ratio, (1)::numeric) > 0.38) OR (COALESCE(b.weeks_active_ratio, (1)::numeric) > 0.26))) THEN 'lumpy'::text
                    WHEN ((b.demand_class_v7_2 = 'seasonal_lumpy'::text) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.14) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.24) AND (COALESCE(b.avg_pos_run_len_max_v6, (99)::numeric) <= 1.6) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) < 0.78)) THEN 'intermittent'::text
                    WHEN ((b.demand_class_v7_2 = 'lumpy'::text) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.80) AND (COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 3) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.35) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.24) AND (COALESCE(b.avg_pos_run_len_max_v6, (99)::numeric) >= 1.45)) THEN 'seasonal_lumpy'::text
                    ELSE b.demand_class_v7_2
                END AS demand_class_v7_2_bis
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
    demand_class_v5,
    top3_months_share_max_v5_1,
    top4_weeks_share_max_v5_1,
    top10_days_share_max_v5_1,
    weeks_active_ratio_v5_1,
    months_active_ratio_v5_1,
    months_to_80_min_v5_1,
    months_to_80_max_v5_1,
    avg_pos_run_len_min_v5_1,
    avg_pos_run_len_max_v5_1,
    avg_zero_run_len_max_v5_1,
    season_width_class_v5_1,
    continuity_class_v5_1,
    burstiness_class_v5_1,
    repeatability_class_v5_1,
    demand_class_v5_1,
    top3_months_share_max_v6,
    top4_weeks_share_max_v6,
    top10_days_share_max_v6,
    avg_pos_run_len_max_v6,
    avg_pos_run_len_min_v6,
    months_to_80_min_v6,
    months_to_80_max_v6,
    demand_class_v6,
    horizon_days,
    avg_qty_per_sale,
    adi_v7,
    max_week_share,
    max_month_share,
    demand_class_v7,
    demand_class_v7_1,
    seasonal_strength_v7_2,
    burst_strength_v7_2,
    demand_class_v7_2,
    seasonal_strength_v7_2_bis,
    burst_strength_v7_2_bis,
    demand_class_v7_2_bis
   FROM reclassified;


--
-- Name: v_family_diagnostics_v7_2_quater; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v7_2_quater AS
 WITH base AS (
         SELECT v.family_name,
            v.days_total,
            v.pos_days,
            v.zero_days,
            v.zero_rate,
            v.pos_rate,
            v.qty_total,
            v.qty_avg_all_days,
            v.qty_avg_pos_days,
            v.qty_std_pos_days,
            v.value_total,
            v.value_avg_all_days,
            v.value_avg_pos_days,
            v.value_std_pos_days,
            v.years_count,
            v.active_months,
            v.active_value_months,
            v.adi,
            v.cv2_pos,
            v.years_with_sales,
            v.season_start_p25,
            v.season_start_p50,
            v.season_start_p75,
            v.peak_doy,
            v.qty_pct_total,
            v.qty_cum_pct,
            v.qty_tier,
            v.value_pct_total,
            v.value_cum_pct,
            v.value_tier,
            v.business_tier,
            v.season_start_iqr,
            v.intermittency_class,
            v.seasonality_class,
            v.demand_class_v2,
            v.data_quality_class_v2,
            v.combined_segment_v2,
            v.cv_pos_qty,
            v.cv_pos_value,
            v.cv_week_qty,
            v.cv_week_value,
            v.cv_month_qty,
            v.cv_month_value,
            v.cv_year_qty,
            v.cv_year_value,
            v.cv_weekday_qty,
            v.cv_weekday_value,
            v.avg_gap_days,
            v.median_gap_days,
            v.p90_gap_days,
            v.max_gap_days,
            v.weeks_active_ratio,
            v.months_active_ratio,
            v.years_active_ratio,
            v.top3_months_qty_share,
            v.top6_months_qty_share,
            v.top3_months_value_share,
            v.top6_months_value_share,
            v.top4_weeks_qty_share,
            v.top8_weeks_qty_share,
            v.top4_weeks_value_share,
            v.top8_weeks_value_share,
            v.top10_days_qty_share,
            v.top30_days_qty_share,
            v.top10_days_value_share,
            v.top30_days_value_share,
            v.peak_month_std,
            v.peak_month_avg,
            v.xmas_qty_share,
            v.xmas_value_share,
            v.spring_qty_share,
            v.spring_value_share,
            v.cv_pos_max,
            v.cv_week_max,
            v.cv_month_max,
            v.cv_year_max,
            v.cv_weekday_max,
            v.top3_months_share_max,
            v.top6_months_share_max,
            v.top4_weeks_share_max,
            v.top8_weeks_share_max,
            v.top10_days_share_max,
            v.top30_days_share_max,
            v.spring_share_max,
            v.xmas_share_max,
            v.reliability_class_v4,
            v.predictability_class_v4,
            v.seasonality_strength_v4,
            v.day_peakiness_class_v4,
            v.week_peakiness_class_v4,
            v.peak_month_stability_class_v4,
            v.holiday_profile_v4,
            v.dominant_concentration_scale_v4,
            v.demand_class_v4,
            v.season_width_class_v4_1,
            v.day_peakiness_class_v4_1,
            v.week_peakiness_class_v4_1,
            v.continuity_class_v4_1,
            v.peak_month_stability_class_v4_1,
            v.holiday_profile_v4_1,
            v.dominant_concentration_scale_v4_1,
            v.instability_score_v4_1,
            v.reliability_class_v4_1,
            v.predictability_class_v4_1,
            v.demand_class_v4_1,
            v.months_to_80_qty,
            v.months_to_90_qty,
            v.months_to_80_value,
            v.months_to_90_value,
            v.peak_month_std_qty,
            v.peak_month_std_value,
            v.dominant_peak_month_share_qty,
            v.dominant_peak_month_share_value,
            v.avg_pos_run_len_qty,
            v.median_pos_run_len_qty,
            v.max_pos_run_len_qty,
            v.avg_zero_run_len_qty,
            v.median_zero_run_len_qty,
            v.max_zero_run_len_qty,
            v.avg_pos_run_len_value,
            v.median_pos_run_len_value,
            v.max_pos_run_len_value,
            v.avg_zero_run_len_value,
            v.median_zero_run_len_value,
            v.max_zero_run_len_value,
            v.avg_gap_days_qty,
            v.median_gap_days_qty,
            v.p90_gap_days_qty,
            v.max_gap_days_qty,
            v.avg_gap_days_value,
            v.median_gap_days_value,
            v.p90_gap_days_value,
            v.max_gap_days_value,
            v.top3_months_gap_qty_value,
            v.top4_weeks_gap_qty_value,
            v.top10_days_gap_qty_value,
            v.avg_unit_value,
            v.top3_months_share_max_v5,
            v.top4_weeks_share_max_v5,
            v.top10_days_share_max_v5,
            v.season_width_qty_class_v5,
            v.season_width_value_class_v5,
            v.season_repeatability_qty_class_v5,
            v.season_repeatability_value_class_v5,
            v.burstiness_qty_class_v5,
            v.burstiness_value_class_v5,
            v.qty_value_alignment_class_v5,
            v.logistics_profile_v5,
            v.economic_profile_v5,
            v.demand_class_v5,
            v.top3_months_share_max_v5_1,
            v.top4_weeks_share_max_v5_1,
            v.top10_days_share_max_v5_1,
            v.weeks_active_ratio_v5_1,
            v.months_active_ratio_v5_1,
            v.months_to_80_min_v5_1,
            v.months_to_80_max_v5_1,
            v.avg_pos_run_len_min_v5_1,
            v.avg_pos_run_len_max_v5_1,
            v.avg_zero_run_len_max_v5_1,
            v.season_width_class_v5_1,
            v.continuity_class_v5_1,
            v.burstiness_class_v5_1,
            v.repeatability_class_v5_1,
            v.demand_class_v5_1,
            v.top3_months_share_max_v6,
            v.top4_weeks_share_max_v6,
            v.top10_days_share_max_v6,
            v.avg_pos_run_len_max_v6,
            v.avg_pos_run_len_min_v6,
            v.months_to_80_min_v6,
            v.months_to_80_max_v6,
            v.demand_class_v6,
            v.horizon_days,
            v.avg_qty_per_sale,
            v.adi_v7,
            v.max_week_share,
            v.max_month_share,
            v.demand_class_v7,
            v.demand_class_v7_1,
            v.seasonal_strength_v7_2,
            v.burst_strength_v7_2,
            v.demand_class_v7_2,
            (COALESCE(v.top3_months_share_max_v6, (0)::numeric) - (COALESCE(v.months_active_ratio, (0)::numeric) * 0.35)) AS seasonal_strength_v7_2_quater,
            (((((COALESCE(v.top10_days_share_max_v6, (0)::numeric) * 0.45) + (COALESCE(v.top4_weeks_share_max_v6, (0)::numeric) * 0.35)) + (COALESCE(v.max_week_share, (0)::numeric) * 0.20)) - (COALESCE(v.weeks_active_ratio, (0)::numeric) * 0.25)) - (LEAST(COALESCE(v.avg_pos_run_len_max_v6, (0)::numeric), 3.0) * 0.05)) AS burst_strength_v7_2_quater
           FROM ml_diag.v_family_diagnostics_v7_2 v
        ), reclassified AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
            b.season_width_qty_class_v5,
            b.season_width_value_class_v5,
            b.season_repeatability_qty_class_v5,
            b.season_repeatability_value_class_v5,
            b.burstiness_qty_class_v5,
            b.burstiness_value_class_v5,
            b.qty_value_alignment_class_v5,
            b.logistics_profile_v5,
            b.economic_profile_v5,
            b.demand_class_v5,
            b.top3_months_share_max_v5_1,
            b.top4_weeks_share_max_v5_1,
            b.top10_days_share_max_v5_1,
            b.weeks_active_ratio_v5_1,
            b.months_active_ratio_v5_1,
            b.months_to_80_min_v5_1,
            b.months_to_80_max_v5_1,
            b.avg_pos_run_len_min_v5_1,
            b.avg_pos_run_len_max_v5_1,
            b.avg_zero_run_len_max_v5_1,
            b.season_width_class_v5_1,
            b.continuity_class_v5_1,
            b.burstiness_class_v5_1,
            b.repeatability_class_v5_1,
            b.demand_class_v5_1,
            b.top3_months_share_max_v6,
            b.top4_weeks_share_max_v6,
            b.top10_days_share_max_v6,
            b.avg_pos_run_len_max_v6,
            b.avg_pos_run_len_min_v6,
            b.months_to_80_min_v6,
            b.months_to_80_max_v6,
            b.demand_class_v6,
            b.horizon_days,
            b.avg_qty_per_sale,
            b.adi_v7,
            b.max_week_share,
            b.max_month_share,
            b.demand_class_v7,
            b.demand_class_v7_1,
            b.seasonal_strength_v7_2,
            b.burst_strength_v7_2,
            b.demand_class_v7_2,
            b.seasonal_strength_v7_2_quater,
            b.burst_strength_v7_2_quater,
                CASE
                    WHEN (b.demand_class_v7_2 = 'insufficient'::text) THEN 'insufficient'::text
                    WHEN (b.demand_class_v7_2 = 'dense'::text) THEN 'dense'::text
                    WHEN (b.demand_class_v7_2 = 'burst_lumpy'::text) THEN 'burst_lumpy'::text
                    WHEN (b.demand_class_v7_2 = 'seasonal_intermittent'::text) THEN 'seasonal_intermittent'::text
                    WHEN ((b.demand_class_v7_2 = 'seasonal_lumpy'::text) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.14) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.24) AND (COALESCE(b.avg_pos_run_len_max_v6, (99)::numeric) <= 1.6) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) < 0.78)) THEN 'intermittent'::text
                    WHEN ((b.demand_class_v7_2 = 'seasonal_lumpy'::text) AND ((COALESCE(b.top3_months_share_max_v6, (0)::numeric) < 0.76) OR (COALESCE(b.months_to_80_min_v6, (99)::bigint) > 4) OR ((COALESCE(b.months_active_ratio, (1)::numeric) > 0.62) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) > 0.48) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) < 0.86)))) THEN 'lumpy'::text
                    ELSE b.demand_class_v7_2
                END AS demand_class_v7_2_quater
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
    demand_class_v5,
    top3_months_share_max_v5_1,
    top4_weeks_share_max_v5_1,
    top10_days_share_max_v5_1,
    weeks_active_ratio_v5_1,
    months_active_ratio_v5_1,
    months_to_80_min_v5_1,
    months_to_80_max_v5_1,
    avg_pos_run_len_min_v5_1,
    avg_pos_run_len_max_v5_1,
    avg_zero_run_len_max_v5_1,
    season_width_class_v5_1,
    continuity_class_v5_1,
    burstiness_class_v5_1,
    repeatability_class_v5_1,
    demand_class_v5_1,
    top3_months_share_max_v6,
    top4_weeks_share_max_v6,
    top10_days_share_max_v6,
    avg_pos_run_len_max_v6,
    avg_pos_run_len_min_v6,
    months_to_80_min_v6,
    months_to_80_max_v6,
    demand_class_v6,
    horizon_days,
    avg_qty_per_sale,
    adi_v7,
    max_week_share,
    max_month_share,
    demand_class_v7,
    demand_class_v7_1,
    seasonal_strength_v7_2,
    burst_strength_v7_2,
    demand_class_v7_2,
    seasonal_strength_v7_2_quater,
    burst_strength_v7_2_quater,
    demand_class_v7_2_quater
   FROM reclassified;


--
-- Name: v_family_diagnostics_v7_2_ter; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_diagnostics_v7_2_ter AS
 WITH base AS (
         SELECT v.family_name,
            v.days_total,
            v.pos_days,
            v.zero_days,
            v.zero_rate,
            v.pos_rate,
            v.qty_total,
            v.qty_avg_all_days,
            v.qty_avg_pos_days,
            v.qty_std_pos_days,
            v.value_total,
            v.value_avg_all_days,
            v.value_avg_pos_days,
            v.value_std_pos_days,
            v.years_count,
            v.active_months,
            v.active_value_months,
            v.adi,
            v.cv2_pos,
            v.years_with_sales,
            v.season_start_p25,
            v.season_start_p50,
            v.season_start_p75,
            v.peak_doy,
            v.qty_pct_total,
            v.qty_cum_pct,
            v.qty_tier,
            v.value_pct_total,
            v.value_cum_pct,
            v.value_tier,
            v.business_tier,
            v.season_start_iqr,
            v.intermittency_class,
            v.seasonality_class,
            v.demand_class_v2,
            v.data_quality_class_v2,
            v.combined_segment_v2,
            v.cv_pos_qty,
            v.cv_pos_value,
            v.cv_week_qty,
            v.cv_week_value,
            v.cv_month_qty,
            v.cv_month_value,
            v.cv_year_qty,
            v.cv_year_value,
            v.cv_weekday_qty,
            v.cv_weekday_value,
            v.avg_gap_days,
            v.median_gap_days,
            v.p90_gap_days,
            v.max_gap_days,
            v.weeks_active_ratio,
            v.months_active_ratio,
            v.years_active_ratio,
            v.top3_months_qty_share,
            v.top6_months_qty_share,
            v.top3_months_value_share,
            v.top6_months_value_share,
            v.top4_weeks_qty_share,
            v.top8_weeks_qty_share,
            v.top4_weeks_value_share,
            v.top8_weeks_value_share,
            v.top10_days_qty_share,
            v.top30_days_qty_share,
            v.top10_days_value_share,
            v.top30_days_value_share,
            v.peak_month_std,
            v.peak_month_avg,
            v.xmas_qty_share,
            v.xmas_value_share,
            v.spring_qty_share,
            v.spring_value_share,
            v.cv_pos_max,
            v.cv_week_max,
            v.cv_month_max,
            v.cv_year_max,
            v.cv_weekday_max,
            v.top3_months_share_max,
            v.top6_months_share_max,
            v.top4_weeks_share_max,
            v.top8_weeks_share_max,
            v.top10_days_share_max,
            v.top30_days_share_max,
            v.spring_share_max,
            v.xmas_share_max,
            v.reliability_class_v4,
            v.predictability_class_v4,
            v.seasonality_strength_v4,
            v.day_peakiness_class_v4,
            v.week_peakiness_class_v4,
            v.peak_month_stability_class_v4,
            v.holiday_profile_v4,
            v.dominant_concentration_scale_v4,
            v.demand_class_v4,
            v.season_width_class_v4_1,
            v.day_peakiness_class_v4_1,
            v.week_peakiness_class_v4_1,
            v.continuity_class_v4_1,
            v.peak_month_stability_class_v4_1,
            v.holiday_profile_v4_1,
            v.dominant_concentration_scale_v4_1,
            v.instability_score_v4_1,
            v.reliability_class_v4_1,
            v.predictability_class_v4_1,
            v.demand_class_v4_1,
            v.months_to_80_qty,
            v.months_to_90_qty,
            v.months_to_80_value,
            v.months_to_90_value,
            v.peak_month_std_qty,
            v.peak_month_std_value,
            v.dominant_peak_month_share_qty,
            v.dominant_peak_month_share_value,
            v.avg_pos_run_len_qty,
            v.median_pos_run_len_qty,
            v.max_pos_run_len_qty,
            v.avg_zero_run_len_qty,
            v.median_zero_run_len_qty,
            v.max_zero_run_len_qty,
            v.avg_pos_run_len_value,
            v.median_pos_run_len_value,
            v.max_pos_run_len_value,
            v.avg_zero_run_len_value,
            v.median_zero_run_len_value,
            v.max_zero_run_len_value,
            v.avg_gap_days_qty,
            v.median_gap_days_qty,
            v.p90_gap_days_qty,
            v.max_gap_days_qty,
            v.avg_gap_days_value,
            v.median_gap_days_value,
            v.p90_gap_days_value,
            v.max_gap_days_value,
            v.top3_months_gap_qty_value,
            v.top4_weeks_gap_qty_value,
            v.top10_days_gap_qty_value,
            v.avg_unit_value,
            v.top3_months_share_max_v5,
            v.top4_weeks_share_max_v5,
            v.top10_days_share_max_v5,
            v.season_width_qty_class_v5,
            v.season_width_value_class_v5,
            v.season_repeatability_qty_class_v5,
            v.season_repeatability_value_class_v5,
            v.burstiness_qty_class_v5,
            v.burstiness_value_class_v5,
            v.qty_value_alignment_class_v5,
            v.logistics_profile_v5,
            v.economic_profile_v5,
            v.demand_class_v5,
            v.top3_months_share_max_v5_1,
            v.top4_weeks_share_max_v5_1,
            v.top10_days_share_max_v5_1,
            v.weeks_active_ratio_v5_1,
            v.months_active_ratio_v5_1,
            v.months_to_80_min_v5_1,
            v.months_to_80_max_v5_1,
            v.avg_pos_run_len_min_v5_1,
            v.avg_pos_run_len_max_v5_1,
            v.avg_zero_run_len_max_v5_1,
            v.season_width_class_v5_1,
            v.continuity_class_v5_1,
            v.burstiness_class_v5_1,
            v.repeatability_class_v5_1,
            v.demand_class_v5_1,
            v.top3_months_share_max_v6,
            v.top4_weeks_share_max_v6,
            v.top10_days_share_max_v6,
            v.avg_pos_run_len_max_v6,
            v.avg_pos_run_len_min_v6,
            v.months_to_80_min_v6,
            v.months_to_80_max_v6,
            v.demand_class_v6,
            v.horizon_days,
            v.avg_qty_per_sale,
            v.adi_v7,
            v.max_week_share,
            v.max_month_share,
            v.demand_class_v7,
            v.demand_class_v7_1,
            v.seasonal_strength_v7_2,
            v.burst_strength_v7_2,
            v.demand_class_v7_2,
            (COALESCE(v.top3_months_share_max_v6, (0)::numeric) - (COALESCE(v.months_active_ratio, (0)::numeric) * 0.35)) AS seasonal_strength_v7_2_ter,
            (((((COALESCE(v.top10_days_share_max_v6, (0)::numeric) * 0.45) + (COALESCE(v.top4_weeks_share_max_v6, (0)::numeric) * 0.35)) + (COALESCE(v.max_week_share, (0)::numeric) * 0.20)) - (COALESCE(v.weeks_active_ratio, (0)::numeric) * 0.25)) - (LEAST(COALESCE(v.avg_pos_run_len_max_v6, (0)::numeric), 3.0) * 0.05)) AS burst_strength_v7_2_ter
           FROM ml_diag.v_family_diagnostics_v7_2 v
        ), reclassified AS (
         SELECT b.family_name,
            b.days_total,
            b.pos_days,
            b.zero_days,
            b.zero_rate,
            b.pos_rate,
            b.qty_total,
            b.qty_avg_all_days,
            b.qty_avg_pos_days,
            b.qty_std_pos_days,
            b.value_total,
            b.value_avg_all_days,
            b.value_avg_pos_days,
            b.value_std_pos_days,
            b.years_count,
            b.active_months,
            b.active_value_months,
            b.adi,
            b.cv2_pos,
            b.years_with_sales,
            b.season_start_p25,
            b.season_start_p50,
            b.season_start_p75,
            b.peak_doy,
            b.qty_pct_total,
            b.qty_cum_pct,
            b.qty_tier,
            b.value_pct_total,
            b.value_cum_pct,
            b.value_tier,
            b.business_tier,
            b.season_start_iqr,
            b.intermittency_class,
            b.seasonality_class,
            b.demand_class_v2,
            b.data_quality_class_v2,
            b.combined_segment_v2,
            b.cv_pos_qty,
            b.cv_pos_value,
            b.cv_week_qty,
            b.cv_week_value,
            b.cv_month_qty,
            b.cv_month_value,
            b.cv_year_qty,
            b.cv_year_value,
            b.cv_weekday_qty,
            b.cv_weekday_value,
            b.avg_gap_days,
            b.median_gap_days,
            b.p90_gap_days,
            b.max_gap_days,
            b.weeks_active_ratio,
            b.months_active_ratio,
            b.years_active_ratio,
            b.top3_months_qty_share,
            b.top6_months_qty_share,
            b.top3_months_value_share,
            b.top6_months_value_share,
            b.top4_weeks_qty_share,
            b.top8_weeks_qty_share,
            b.top4_weeks_value_share,
            b.top8_weeks_value_share,
            b.top10_days_qty_share,
            b.top30_days_qty_share,
            b.top10_days_value_share,
            b.top30_days_value_share,
            b.peak_month_std,
            b.peak_month_avg,
            b.xmas_qty_share,
            b.xmas_value_share,
            b.spring_qty_share,
            b.spring_value_share,
            b.cv_pos_max,
            b.cv_week_max,
            b.cv_month_max,
            b.cv_year_max,
            b.cv_weekday_max,
            b.top3_months_share_max,
            b.top6_months_share_max,
            b.top4_weeks_share_max,
            b.top8_weeks_share_max,
            b.top10_days_share_max,
            b.top30_days_share_max,
            b.spring_share_max,
            b.xmas_share_max,
            b.reliability_class_v4,
            b.predictability_class_v4,
            b.seasonality_strength_v4,
            b.day_peakiness_class_v4,
            b.week_peakiness_class_v4,
            b.peak_month_stability_class_v4,
            b.holiday_profile_v4,
            b.dominant_concentration_scale_v4,
            b.demand_class_v4,
            b.season_width_class_v4_1,
            b.day_peakiness_class_v4_1,
            b.week_peakiness_class_v4_1,
            b.continuity_class_v4_1,
            b.peak_month_stability_class_v4_1,
            b.holiday_profile_v4_1,
            b.dominant_concentration_scale_v4_1,
            b.instability_score_v4_1,
            b.reliability_class_v4_1,
            b.predictability_class_v4_1,
            b.demand_class_v4_1,
            b.months_to_80_qty,
            b.months_to_90_qty,
            b.months_to_80_value,
            b.months_to_90_value,
            b.peak_month_std_qty,
            b.peak_month_std_value,
            b.dominant_peak_month_share_qty,
            b.dominant_peak_month_share_value,
            b.avg_pos_run_len_qty,
            b.median_pos_run_len_qty,
            b.max_pos_run_len_qty,
            b.avg_zero_run_len_qty,
            b.median_zero_run_len_qty,
            b.max_zero_run_len_qty,
            b.avg_pos_run_len_value,
            b.median_pos_run_len_value,
            b.max_pos_run_len_value,
            b.avg_zero_run_len_value,
            b.median_zero_run_len_value,
            b.max_zero_run_len_value,
            b.avg_gap_days_qty,
            b.median_gap_days_qty,
            b.p90_gap_days_qty,
            b.max_gap_days_qty,
            b.avg_gap_days_value,
            b.median_gap_days_value,
            b.p90_gap_days_value,
            b.max_gap_days_value,
            b.top3_months_gap_qty_value,
            b.top4_weeks_gap_qty_value,
            b.top10_days_gap_qty_value,
            b.avg_unit_value,
            b.top3_months_share_max_v5,
            b.top4_weeks_share_max_v5,
            b.top10_days_share_max_v5,
            b.season_width_qty_class_v5,
            b.season_width_value_class_v5,
            b.season_repeatability_qty_class_v5,
            b.season_repeatability_value_class_v5,
            b.burstiness_qty_class_v5,
            b.burstiness_value_class_v5,
            b.qty_value_alignment_class_v5,
            b.logistics_profile_v5,
            b.economic_profile_v5,
            b.demand_class_v5,
            b.top3_months_share_max_v5_1,
            b.top4_weeks_share_max_v5_1,
            b.top10_days_share_max_v5_1,
            b.weeks_active_ratio_v5_1,
            b.months_active_ratio_v5_1,
            b.months_to_80_min_v5_1,
            b.months_to_80_max_v5_1,
            b.avg_pos_run_len_min_v5_1,
            b.avg_pos_run_len_max_v5_1,
            b.avg_zero_run_len_max_v5_1,
            b.season_width_class_v5_1,
            b.continuity_class_v5_1,
            b.burstiness_class_v5_1,
            b.repeatability_class_v5_1,
            b.demand_class_v5_1,
            b.top3_months_share_max_v6,
            b.top4_weeks_share_max_v6,
            b.top10_days_share_max_v6,
            b.avg_pos_run_len_max_v6,
            b.avg_pos_run_len_min_v6,
            b.months_to_80_min_v6,
            b.months_to_80_max_v6,
            b.demand_class_v6,
            b.horizon_days,
            b.avg_qty_per_sale,
            b.adi_v7,
            b.max_week_share,
            b.max_month_share,
            b.demand_class_v7,
            b.demand_class_v7_1,
            b.seasonal_strength_v7_2,
            b.burst_strength_v7_2,
            b.demand_class_v7_2,
            b.seasonal_strength_v7_2_ter,
            b.burst_strength_v7_2_ter,
                CASE
                    WHEN (b.demand_class_v7_2 = 'insufficient'::text) THEN 'insufficient'::text
                    WHEN (b.demand_class_v7_2 = 'dense'::text) THEN 'dense'::text
                    WHEN (b.demand_class_v7_2 = 'burst_lumpy'::text) THEN 'burst_lumpy'::text
                    WHEN (b.demand_class_v7_2 = 'seasonal_intermittent'::text) THEN 'seasonal_intermittent'::text
                    WHEN ((b.demand_class_v7_2 = 'seasonal_lumpy'::text) AND ((COALESCE(b.top3_months_share_max_v6, (0)::numeric) < 0.76) OR (COALESCE(b.months_to_80_min_v6, (99)::bigint) > 4) OR (COALESCE(b.months_active_ratio, (1)::numeric) > 0.55) OR (COALESCE(b.weeks_active_ratio, (1)::numeric) > 0.40))) THEN 'lumpy'::text
                    WHEN ((b.demand_class_v7_2 = 'seasonal_lumpy'::text) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.14) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.24) AND (COALESCE(b.avg_pos_run_len_max_v6, (99)::numeric) <= 1.6) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) < 0.78)) THEN 'intermittent'::text
                    WHEN ((b.demand_class_v7_2 = 'lumpy'::text) AND (COALESCE(b.top3_months_share_max_v6, (0)::numeric) >= 0.80) AND (COALESCE(b.months_to_80_min_v6, (99)::bigint) <= 3) AND (COALESCE(b.months_active_ratio, (1)::numeric) <= 0.42) AND (COALESCE(b.weeks_active_ratio, (1)::numeric) <= 0.28)) THEN 'seasonal_lumpy'::text
                    ELSE b.demand_class_v7_2
                END AS demand_class_v7_2_ter
           FROM base b
        )
 SELECT family_name,
    days_total,
    pos_days,
    zero_days,
    zero_rate,
    pos_rate,
    qty_total,
    qty_avg_all_days,
    qty_avg_pos_days,
    qty_std_pos_days,
    value_total,
    value_avg_all_days,
    value_avg_pos_days,
    value_std_pos_days,
    years_count,
    active_months,
    active_value_months,
    adi,
    cv2_pos,
    years_with_sales,
    season_start_p25,
    season_start_p50,
    season_start_p75,
    peak_doy,
    qty_pct_total,
    qty_cum_pct,
    qty_tier,
    value_pct_total,
    value_cum_pct,
    value_tier,
    business_tier,
    season_start_iqr,
    intermittency_class,
    seasonality_class,
    demand_class_v2,
    data_quality_class_v2,
    combined_segment_v2,
    cv_pos_qty,
    cv_pos_value,
    cv_week_qty,
    cv_week_value,
    cv_month_qty,
    cv_month_value,
    cv_year_qty,
    cv_year_value,
    cv_weekday_qty,
    cv_weekday_value,
    avg_gap_days,
    median_gap_days,
    p90_gap_days,
    max_gap_days,
    weeks_active_ratio,
    months_active_ratio,
    years_active_ratio,
    top3_months_qty_share,
    top6_months_qty_share,
    top3_months_value_share,
    top6_months_value_share,
    top4_weeks_qty_share,
    top8_weeks_qty_share,
    top4_weeks_value_share,
    top8_weeks_value_share,
    top10_days_qty_share,
    top30_days_qty_share,
    top10_days_value_share,
    top30_days_value_share,
    peak_month_std,
    peak_month_avg,
    xmas_qty_share,
    xmas_value_share,
    spring_qty_share,
    spring_value_share,
    cv_pos_max,
    cv_week_max,
    cv_month_max,
    cv_year_max,
    cv_weekday_max,
    top3_months_share_max,
    top6_months_share_max,
    top4_weeks_share_max,
    top8_weeks_share_max,
    top10_days_share_max,
    top30_days_share_max,
    spring_share_max,
    xmas_share_max,
    reliability_class_v4,
    predictability_class_v4,
    seasonality_strength_v4,
    day_peakiness_class_v4,
    week_peakiness_class_v4,
    peak_month_stability_class_v4,
    holiday_profile_v4,
    dominant_concentration_scale_v4,
    demand_class_v4,
    season_width_class_v4_1,
    day_peakiness_class_v4_1,
    week_peakiness_class_v4_1,
    continuity_class_v4_1,
    peak_month_stability_class_v4_1,
    holiday_profile_v4_1,
    dominant_concentration_scale_v4_1,
    instability_score_v4_1,
    reliability_class_v4_1,
    predictability_class_v4_1,
    demand_class_v4_1,
    months_to_80_qty,
    months_to_90_qty,
    months_to_80_value,
    months_to_90_value,
    peak_month_std_qty,
    peak_month_std_value,
    dominant_peak_month_share_qty,
    dominant_peak_month_share_value,
    avg_pos_run_len_qty,
    median_pos_run_len_qty,
    max_pos_run_len_qty,
    avg_zero_run_len_qty,
    median_zero_run_len_qty,
    max_zero_run_len_qty,
    avg_pos_run_len_value,
    median_pos_run_len_value,
    max_pos_run_len_value,
    avg_zero_run_len_value,
    median_zero_run_len_value,
    max_zero_run_len_value,
    avg_gap_days_qty,
    median_gap_days_qty,
    p90_gap_days_qty,
    max_gap_days_qty,
    avg_gap_days_value,
    median_gap_days_value,
    p90_gap_days_value,
    max_gap_days_value,
    top3_months_gap_qty_value,
    top4_weeks_gap_qty_value,
    top10_days_gap_qty_value,
    avg_unit_value,
    top3_months_share_max_v5,
    top4_weeks_share_max_v5,
    top10_days_share_max_v5,
    season_width_qty_class_v5,
    season_width_value_class_v5,
    season_repeatability_qty_class_v5,
    season_repeatability_value_class_v5,
    burstiness_qty_class_v5,
    burstiness_value_class_v5,
    qty_value_alignment_class_v5,
    logistics_profile_v5,
    economic_profile_v5,
    demand_class_v5,
    top3_months_share_max_v5_1,
    top4_weeks_share_max_v5_1,
    top10_days_share_max_v5_1,
    weeks_active_ratio_v5_1,
    months_active_ratio_v5_1,
    months_to_80_min_v5_1,
    months_to_80_max_v5_1,
    avg_pos_run_len_min_v5_1,
    avg_pos_run_len_max_v5_1,
    avg_zero_run_len_max_v5_1,
    season_width_class_v5_1,
    continuity_class_v5_1,
    burstiness_class_v5_1,
    repeatability_class_v5_1,
    demand_class_v5_1,
    top3_months_share_max_v6,
    top4_weeks_share_max_v6,
    top10_days_share_max_v6,
    avg_pos_run_len_max_v6,
    avg_pos_run_len_min_v6,
    months_to_80_min_v6,
    months_to_80_max_v6,
    demand_class_v6,
    horizon_days,
    avg_qty_per_sale,
    adi_v7,
    max_week_share,
    max_month_share,
    demand_class_v7,
    demand_class_v7_1,
    seasonal_strength_v7_2,
    burst_strength_v7_2,
    demand_class_v7_2,
    seasonal_strength_v7_2_ter,
    burst_strength_v7_2_ter,
    demand_class_v7_2_ter
   FROM reclassified;


--
-- Name: v_family_season_start; Type: VIEW; Schema: ml_diag; Owner: -
--

CREATE VIEW ml_diag.v_family_season_start AS
 WITH base AS (
         SELECT lower(TRIM(BOTH FROM greenhouse_forecast_features_dense.famiglia)) AS family_name,
            greenhouse_forecast_features_dense.data,
            sum(COALESCE(greenhouse_forecast_features_dense.qty_venduta, (0)::numeric)) AS qty
           FROM public.greenhouse_forecast_features_dense
          WHERE ((greenhouse_forecast_features_dense.famiglia IS NOT NULL) AND (TRIM(BOTH FROM greenhouse_forecast_features_dense.famiglia) <> ''::text) AND (greenhouse_forecast_features_dense.data >= '2009-01-01'::date))
          GROUP BY (lower(TRIM(BOTH FROM greenhouse_forecast_features_dense.famiglia))), greenhouse_forecast_features_dense.data
        ), pos AS (
         SELECT base.family_name,
            (EXTRACT(year FROM base.data))::integer AS yy,
            (EXTRACT(doy FROM base.data))::integer AS doy
           FROM base
          WHERE (base.qty > (0)::numeric)
        ), first_sale AS (
         SELECT pos.family_name,
            pos.yy,
            min(pos.doy) AS first_doy
           FROM pos
          GROUP BY pos.family_name, pos.yy
        )
 SELECT family_name,
    count(*) AS years_with_sales,
    round((percentile_cont((0.25)::double precision) WITHIN GROUP (ORDER BY ((first_doy)::double precision)))::numeric, 1) AS season_start_p25,
    round((percentile_cont((0.50)::double precision) WITHIN GROUP (ORDER BY ((first_doy)::double precision)))::numeric, 1) AS season_start_p50,
    round((percentile_cont((0.75)::double precision) WITHIN GROUP (ORDER BY ((first_doy)::double precision)))::numeric, 1) AS season_start_p75
   FROM first_sale
  GROUP BY family_name;


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
-- Name: family_benchmark_run_v1_run_id_seq; Type: SEQUENCE; Schema: ml_forecast; Owner: -
--

CREATE SEQUENCE ml_forecast.family_benchmark_run_v1_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: family_benchmark_run_v1_run_id_seq; Type: SEQUENCE OWNED BY; Schema: ml_forecast; Owner: -
--

ALTER SEQUENCE ml_forecast.family_benchmark_run_v1_run_id_seq OWNED BY ml_forecast.family_benchmark_run_v1.run_id;


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
-- Name: family_model_benchmark_v1_benchmark_id_seq; Type: SEQUENCE; Schema: ml_forecast; Owner: -
--

CREATE SEQUENCE ml_forecast.family_model_benchmark_v1_benchmark_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: family_model_benchmark_v1_benchmark_id_seq; Type: SEQUENCE OWNED BY; Schema: ml_forecast; Owner: -
--

ALTER SEQUENCE ml_forecast.family_model_benchmark_v1_benchmark_id_seq OWNED BY ml_forecast.family_model_benchmark_v1.benchmark_id;


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
-- Name: model_artifact_registry_v1_artifact_id_seq; Type: SEQUENCE; Schema: ml_forecast; Owner: -
--

CREATE SEQUENCE ml_forecast.model_artifact_registry_v1_artifact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: model_artifact_registry_v1_artifact_id_seq; Type: SEQUENCE OWNED BY; Schema: ml_forecast; Owner: -
--

ALTER SEQUENCE ml_forecast.model_artifact_registry_v1_artifact_id_seq OWNED BY ml_forecast.model_artifact_registry_v1.artifact_id;


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
-- Name: VIEW v_family_model_registry_v1; Type: COMMENT; Schema: ml_forecast; Owner: -
--

COMMENT ON VIEW ml_forecast.v_family_model_registry_v1 IS '[DEPRECATED — Blocco G] Usa family_model_registry_v1 (old table v1, 845 righe).
 Vista attiva è v_family_model_registry_v2 (basata su family_model_registry_v2 + ml_diag).
 Tenuta per compatibilità. Da eliminare dopo verifica nessun consumer esterno.';


--
-- Name: v_family_model_registry_v2; Type: VIEW; Schema: ml_forecast; Owner: -
--

CREATE VIEW ml_forecast.v_family_model_registry_v2 AS
 SELECT d.family_name,
    d.business_tier,
    d.value_total,
    d.qty_total,
    d.demand_class_v7_2_quater AS demand_class_final,
    m.model_code,
    c.model_name,
    d.seasonal_strength_v7_2_quater AS seasonal_strength,
    d.burst_strength_v7_2_quater AS burst_strength,
    d.weeks_active_ratio,
    d.months_active_ratio,
    d.avg_pos_run_len_max_v6,
    d.top3_months_share_max_v6,
    d.top10_days_share_max_v6,
    d.top4_weeks_share_max_v6,
    d.max_week_share,
    d.max_month_share,
    d.months_to_80_min_v6,
    d.adi_v7,
    'ml_diag.v_family_diagnostics_v7_2_quater'::text AS source_view_name,
    'v7_2_quater'::text AS classification_version,
    now() AS registry_generated_at
   FROM ((ml_diag.v_family_diagnostics_v7_2_quater d
     JOIN ml_forecast.class_model_map_v1 m ON ((m.demand_class_final = d.demand_class_v7_2_quater)))
     JOIN ml_forecast.model_catalog_v1 c ON ((c.model_code = m.model_code)));


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
-- Name: classification_change_log_v1_change_id_seq; Type: SEQUENCE; Schema: ml_ops; Owner: -
--

CREATE SEQUENCE ml_ops.classification_change_log_v1_change_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: classification_change_log_v1_change_id_seq; Type: SEQUENCE OWNED BY; Schema: ml_ops; Owner: -
--

ALTER SEQUENCE ml_ops.classification_change_log_v1_change_id_seq OWNED BY ml_ops.classification_change_log_v1.change_id;


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
-- Name: family_run_log_v1_family_run_id_seq; Type: SEQUENCE; Schema: ml_ops; Owner: -
--

CREATE SEQUENCE ml_ops.family_run_log_v1_family_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: family_run_log_v1_family_run_id_seq; Type: SEQUENCE OWNED BY; Schema: ml_ops; Owner: -
--

ALTER SEQUENCE ml_ops.family_run_log_v1_family_run_id_seq OWNED BY ml_ops.family_run_log_v1.family_run_id;


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
-- Name: pipeline_run_log_v1_run_id_seq; Type: SEQUENCE; Schema: ml_ops; Owner: -
--

CREATE SEQUENCE ml_ops.pipeline_run_log_v1_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pipeline_run_log_v1_run_id_seq; Type: SEQUENCE OWNED BY; Schema: ml_ops; Owner: -
--

ALTER SEQUENCE ml_ops.pipeline_run_log_v1_run_id_seq OWNED BY ml_ops.pipeline_run_log_v1.run_id;


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
-- Name: VIEW v_benchmark_suggestions_status_v1; Type: COMMENT; Schema: ml_ops; Owner: -
--

COMMENT ON VIEW ml_ops.v_benchmark_suggestions_status_v1 IS '[Blocco D.1] Suggestion layer con semantica raw/effective/decision.
 suggestion_strength_raw       = forza originale calcolata dall''improvement_pct
 suggestion_strength_effective = forza utilizzabile (NULL se suppressed)
 decision_status               = clean | downgraded | suppressed';


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
-- Name: VIEW v_benchmark_admin_v1; Type: COMMENT; Schema: ml_ops; Owner: -
--

COMMENT ON VIEW ml_ops.v_benchmark_admin_v1 IS '[Blocco D.1] Vista admin con semantica suggestion aggiornata.
 suggestion_status: clean | suppressed | downgraded | already_optimal | suppressed_or_no_change | no_benchmark
 Aggiunto suggestion_strength_raw, suggestion_strength_effective, decision_status.';


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
-- Name: VIEW v_daily_pipeline_summary_v1; Type: COMMENT; Schema: ml_ops; Owner: -
--

COMMENT ON VIEW ml_ops.v_daily_pipeline_summary_v1 IS 'Blocco D: sostituisce ml_monitor.v_daily_runs. Aggregazione giornaliera dei run di pipeline per job_type.';


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
-- Name: VIEW v_family_ops_status_v1; Type: COMMENT; Schema: ml_ops; Owner: -
--

COMMENT ON VIEW ml_ops.v_family_ops_status_v1 IS 'Blocco D: sostituisce ml_monitor.v_model_status. Stato operativo per famiglia: train/predict recency, bundle freshness, model_state. Usa ml_forecast.family_model_state_v1 come fonte autorevole di train/predict timestamps.';


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
-- Name: VIEW v_model_stale_v1; Type: COMMENT; Schema: ml_ops; Owner: -
--

COMMENT ON VIEW ml_ops.v_model_stale_v1 IS 'Blocco D: sostituisce ml_monitor.v_model_stale. Famiglie con modelli scaduti, mai trainati o con train fallito.';


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
-- Name: VIEW v_pipeline_runs_recent_v1; Type: COMMENT; Schema: ml_ops; Owner: -
--

COMMENT ON VIEW ml_ops.v_pipeline_runs_recent_v1 IS 'Blocco D: sostituisce ml_monitor.v_run_recent. Mostra i run di pipeline recenti da ml_ops.pipeline_run_log_v1.';


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
-- Name: t_dashboard_sales_daily; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_dashboard_sales_daily (
    data date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli_tot integer DEFAULT 0 NOT NULL
);


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
-- Name: t_dashboard_sales_monthly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_dashboard_sales_monthly (
    period_start date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL
);


--
-- Name: dashboard__sales_monthly; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard__sales_monthly AS
 SELECT period_start AS data,
    qty_tot,
    imp_tot
   FROM public.t_dashboard_sales_monthly;


--
-- Name: t_dashboard_sales_weekly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_dashboard_sales_weekly (
    period_start date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL
);


--
-- Name: dashboard__sales_weekly; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard__sales_weekly AS
 SELECT period_start AS data,
    qty_tot,
    imp_tot
   FROM public.t_dashboard_sales_weekly;


--
-- Name: t_dashboard_sales_yearly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.t_dashboard_sales_yearly (
    period_start date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL
);


--
-- Name: dashboard__sales_yearly; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard__sales_yearly AS
 SELECT period_start AS data,
    qty_tot,
    imp_tot
   FROM public.t_dashboard_sales_yearly;


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
-- Name: greenhouse_alerts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.greenhouse_alerts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: greenhouse_alerts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.greenhouse_alerts_id_seq OWNED BY public.greenhouse_alerts.id;


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
-- Name: mv_core_analytics__breakdown_daily_fascia_fp; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_core_analytics__breakdown_daily_fascia_fp AS
 SELECT f.data,
    lower(f.fascia_corretta) AS entity_key_lc,
    f.fascia_prezzo_iva_inc,
    (sum(f.qty_venduta))::numeric(12,3) AS qty_venduta,
    (sum(f.imponibile_netto_tot))::numeric(12,2) AS imponibile_netto_tot,
    (sum(f.num_articoli))::integer AS num_articoli,
    bool_or(COALESCE(f.is_holiday, false)) AS is_holiday,
    max(f.holiday_name) AS holiday_name,
    max(f.dow) AS dow,
    (sum(fc.qty_forecast))::numeric(12,3) AS qty_forecast
   FROM (public.greenhouse_forecast_features_dense f
     LEFT JOIN public.greenhouse_forecast_results_v2 fc ON (((fc.data = f.data) AND (lower(fc.famiglia) = lower(f.famiglia)) AND (fc.fascia_prezzo_iva_inc = f.fascia_prezzo_iva_inc))))
  WHERE ((f.fascia_corretta IS NOT NULL) AND (btrim(f.fascia_corretta) <> ''::text))
  GROUP BY f.data, (lower(f.fascia_corretta)), f.fascia_prezzo_iva_inc
  WITH NO DATA;


--
-- Name: mv_core_analytics__catalog_entities; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_core_analytics__catalog_entities AS
 SELECT 'fascia'::text AS entity_type,
    lower(TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta)) AS entity_key,
    TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta) AS label,
    TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta) AS fascia,
    NULL::text AS categoria,
    NULL::text AS famiglia,
    NULL::text AS fascia_prezzo
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.fascia_corretta IS NOT NULL)
  GROUP BY greenhouse_products_normalized.fascia_corretta
UNION ALL
 SELECT 'categoria'::text AS entity_type,
    lower(TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta)) AS entity_key,
    TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta) AS label,
    max(TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta)) AS fascia,
    TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta) AS categoria,
    NULL::text AS famiglia,
    NULL::text AS fascia_prezzo
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.categoria_corretta IS NOT NULL)
  GROUP BY greenhouse_products_normalized.categoria_corretta
UNION ALL
 SELECT 'famiglia'::text AS entity_type,
    lower(TRIM(BOTH FROM greenhouse_products_normalized.famiglia)) AS entity_key,
    TRIM(BOTH FROM greenhouse_products_normalized.famiglia) AS label,
    max(TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta)) AS fascia,
    max(TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta)) AS categoria,
    TRIM(BOTH FROM greenhouse_products_normalized.famiglia) AS famiglia,
    NULL::text AS fascia_prezzo
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.famiglia IS NOT NULL)
  GROUP BY greenhouse_products_normalized.famiglia
UNION ALL
 SELECT 'fascia_prezzo'::text AS entity_type,
    lower(TRIM(BOTH FROM greenhouse_products_normalized.fascia_prezzo_iva_inc)) AS entity_key,
    TRIM(BOTH FROM greenhouse_products_normalized.fascia_prezzo_iva_inc) AS label,
    max(TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta)) AS fascia,
    max(TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta)) AS categoria,
    max(TRIM(BOTH FROM greenhouse_products_normalized.famiglia)) AS famiglia,
    TRIM(BOTH FROM greenhouse_products_normalized.fascia_prezzo_iva_inc) AS fascia_prezzo
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.fascia_prezzo_iva_inc IS NOT NULL)
  GROUP BY greenhouse_products_normalized.fascia_prezzo_iva_inc
  WITH NO DATA;


--
-- Name: mv_core_analytics__series_daily_categoria; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_core_analytics__series_daily_categoria AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.core_analytics__series_daily_categoria_v
  WITH NO DATA;


--
-- Name: mv_core_analytics__series_daily_famiglia; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_core_analytics__series_daily_famiglia AS
 SELECT data,
    famiglia AS entity_key,
    sum(qty_venduta) AS qty_venduta_tot,
    sum(imponibile_netto_tot) AS imponibile_netto_tot,
    (0)::numeric AS qty_forecast_tot,
    bool_or(is_holiday) AS is_holiday,
    max(holiday_name) AS holiday_name,
    max(dow) AS dow
   FROM public.greenhouse_forecast_features_dense
  GROUP BY data, famiglia
  WITH NO DATA;


--
-- Name: mv_core_analytics__series_daily_fascia; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_core_analytics__series_daily_fascia AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.core_analytics__series_daily_fascia_v
  WITH NO DATA;


--
-- Name: mv_core_analytics__series_daily_fascia_prezzo; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_core_analytics__series_daily_fascia_prezzo AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.core_analytics__series_daily_fascia_prezzo_v
  WITH NO DATA;


--
-- Name: mv_famiglie_catalog; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_famiglie_catalog AS
 SELECT DISTINCT lower(TRIM(BOTH FROM famiglia)) AS famiglia,
    public.slugify_family(famiglia) AS famiglia_slug
   FROM public.greenhouse_forecast_features_dense
  WITH NO DATA;


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
-- Name: ops_parquet_export_runs_run_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ops_parquet_export_runs_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ops_parquet_export_runs_run_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ops_parquet_export_runs_run_id_seq OWNED BY public.ops_parquet_export_runs.run_id;


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


--
-- Name: t_ops_pipeline_monitor_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.t_ops_pipeline_monitor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: t_ops_pipeline_monitor_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.t_ops_pipeline_monitor_id_seq OWNED BY public.t_ops_pipeline_monitor.id;


--
-- Name: v_famiglie_catalog; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_famiglie_catalog AS
 SELECT famiglia,
    public.slugify_family(famiglia) AS famiglia_slug
   FROM public.mv_famiglie_catalog;


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


--
-- Name: VIEW v_order_suggestions_api; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_order_suggestions_api IS 'touch';


--
-- Name: messages; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
)
PARTITION BY RANGE (inserted_at);


--
-- Name: schema_migrations; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: subscription; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.subscription (
    id bigint NOT NULL,
    subscription_id uuid NOT NULL,
    entity regclass NOT NULL,
    filters realtime.user_defined_filter[] DEFAULT '{}'::realtime.user_defined_filter[] NOT NULL,
    claims jsonb NOT NULL,
    claims_role regrole GENERATED ALWAYS AS (realtime.to_regrole((claims ->> 'role'::text))) STORED NOT NULL,
    created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    action_filter text DEFAULT '*'::text,
    CONSTRAINT subscription_action_filter_check CHECK ((action_filter = ANY (ARRAY['*'::text, 'INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


--
-- Name: subscription_id_seq; Type: SEQUENCE; Schema: realtime; Owner: -
--

ALTER TABLE realtime.subscription ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME realtime.subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text,
    type storage.buckettype DEFAULT 'STANDARD'::storage.buckettype NOT NULL
);


--
-- Name: COLUMN buckets.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.buckets.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: buckets_analytics; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets_analytics (
    name text NOT NULL,
    type storage.buckettype DEFAULT 'ANALYTICS'::storage.buckettype NOT NULL,
    format text DEFAULT 'ICEBERG'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deleted_at timestamp with time zone
);


--
-- Name: buckets_vectors; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets_vectors (
    id text NOT NULL,
    type storage.buckettype DEFAULT 'VECTOR'::storage.buckettype NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: migrations; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: objects; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    version text,
    owner_id text,
    user_metadata jsonb
);


--
-- Name: COLUMN objects.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.objects.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: s3_multipart_uploads; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads (
    id text NOT NULL,
    in_progress_size bigint DEFAULT 0 NOT NULL,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    version text NOT NULL,
    owner_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_metadata jsonb
);


--
-- Name: s3_multipart_uploads_parts; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    upload_id text NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    part_number integer NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    etag text NOT NULL,
    owner_id text,
    version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: vector_indexes; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.vector_indexes (
    id text DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL COLLATE pg_catalog."C",
    bucket_id text NOT NULL,
    data_type text NOT NULL,
    dimension integer NOT NULL,
    distance_metric text NOT NULL,
    metadata_configuration jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: refresh_tokens id; Type: DEFAULT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('auth.refresh_tokens_id_seq'::regclass);


--
-- Name: t_etl_steps step_id; Type: DEFAULT; Schema: etl; Owner: -
--

ALTER TABLE ONLY etl.t_etl_steps ALTER COLUMN step_id SET DEFAULT nextval('etl.t_etl_steps_step_id_seq'::regclass);


--
-- Name: family_benchmark_run_v1 run_id; Type: DEFAULT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_benchmark_run_v1 ALTER COLUMN run_id SET DEFAULT nextval('ml_forecast.family_benchmark_run_v1_run_id_seq'::regclass);


--
-- Name: family_model_benchmark_v1 benchmark_id; Type: DEFAULT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_benchmark_v1 ALTER COLUMN benchmark_id SET DEFAULT nextval('ml_forecast.family_model_benchmark_v1_benchmark_id_seq'::regclass);


--
-- Name: model_artifact_registry_v1 artifact_id; Type: DEFAULT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.model_artifact_registry_v1 ALTER COLUMN artifact_id SET DEFAULT nextval('ml_forecast.model_artifact_registry_v1_artifact_id_seq'::regclass);


--
-- Name: classification_change_log_v1 change_id; Type: DEFAULT; Schema: ml_ops; Owner: -
--

ALTER TABLE ONLY ml_ops.classification_change_log_v1 ALTER COLUMN change_id SET DEFAULT nextval('ml_ops.classification_change_log_v1_change_id_seq'::regclass);


--
-- Name: family_run_log_v1 family_run_id; Type: DEFAULT; Schema: ml_ops; Owner: -
--

ALTER TABLE ONLY ml_ops.family_run_log_v1 ALTER COLUMN family_run_id SET DEFAULT nextval('ml_ops.family_run_log_v1_family_run_id_seq'::regclass);


--
-- Name: pipeline_run_log_v1 run_id; Type: DEFAULT; Schema: ml_ops; Owner: -
--

ALTER TABLE ONLY ml_ops.pipeline_run_log_v1 ALTER COLUMN run_id SET DEFAULT nextval('ml_ops.pipeline_run_log_v1_run_id_seq'::regclass);


--
-- Name: greenhouse_alerts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_alerts ALTER COLUMN id SET DEFAULT nextval('public.greenhouse_alerts_id_seq'::regclass);


--
-- Name: ops_parquet_export_runs run_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ops_parquet_export_runs ALTER COLUMN run_id SET DEFAULT nextval('public.ops_parquet_export_runs_run_id_seq'::regclass);


--
-- Name: t_ops_pipeline_monitor id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_ops_pipeline_monitor ALTER COLUMN id SET DEFAULT nextval('public.t_ops_pipeline_monitor_id_seq'::regclass);


--
-- Name: mfa_amr_claims amr_id_pk; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT amr_id_pk PRIMARY KEY (id);


--
-- Name: audit_log_entries audit_log_entries_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.audit_log_entries
    ADD CONSTRAINT audit_log_entries_pkey PRIMARY KEY (id);


--
-- Name: custom_oauth_providers custom_oauth_providers_identifier_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.custom_oauth_providers
    ADD CONSTRAINT custom_oauth_providers_identifier_key UNIQUE (identifier);


--
-- Name: custom_oauth_providers custom_oauth_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.custom_oauth_providers
    ADD CONSTRAINT custom_oauth_providers_pkey PRIMARY KEY (id);


--
-- Name: flow_state flow_state_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.flow_state
    ADD CONSTRAINT flow_state_pkey PRIMARY KEY (id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: identities identities_provider_id_provider_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_provider_id_provider_unique UNIQUE (provider_id, provider);


--
-- Name: instances instances_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.instances
    ADD CONSTRAINT instances_pkey PRIMARY KEY (id);


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_authentication_method_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_authentication_method_pkey UNIQUE (session_id, authentication_method);


--
-- Name: mfa_challenges mfa_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_pkey PRIMARY KEY (id);


--
-- Name: mfa_factors mfa_factors_last_challenged_at_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_last_challenged_at_key UNIQUE (last_challenged_at);


--
-- Name: mfa_factors mfa_factors_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_pkey PRIMARY KEY (id);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_code_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_code_key UNIQUE (authorization_code);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_id_key UNIQUE (authorization_id);


--
-- Name: oauth_authorizations oauth_authorizations_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_pkey PRIMARY KEY (id);


--
-- Name: oauth_client_states oauth_client_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_client_states
    ADD CONSTRAINT oauth_client_states_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients oauth_clients_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_clients
    ADD CONSTRAINT oauth_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_user_client_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_client_unique UNIQUE (user_id, client_id);


--
-- Name: one_time_tokens one_time_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_token_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_unique UNIQUE (token);


--
-- Name: saml_providers saml_providers_entity_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_entity_id_key UNIQUE (entity_id);


--
-- Name: saml_providers saml_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_pkey PRIMARY KEY (id);


--
-- Name: saml_relay_states saml_relay_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sso_domains sso_domains_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_pkey PRIMARY KEY (id);


--
-- Name: sso_providers sso_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_providers
    ADD CONSTRAINT sso_providers_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: t_etl_runs t_etl_runs_pkey; Type: CONSTRAINT; Schema: etl; Owner: -
--

ALTER TABLE ONLY etl.t_etl_runs
    ADD CONSTRAINT t_etl_runs_pkey PRIMARY KEY (run_id);


--
-- Name: t_etl_steps t_etl_steps_pkey; Type: CONSTRAINT; Schema: etl; Owner: -
--

ALTER TABLE ONLY etl.t_etl_steps
    ADD CONSTRAINT t_etl_steps_pkey PRIMARY KEY (step_id);


--
-- Name: class_model_map_v1 class_model_map_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.class_model_map_v1
    ADD CONSTRAINT class_model_map_v1_pkey PRIMARY KEY (demand_class_final);


--
-- Name: execution_engine_catalog_v1 execution_engine_catalog_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.execution_engine_catalog_v1
    ADD CONSTRAINT execution_engine_catalog_v1_pkey PRIMARY KEY (execution_engine);


--
-- Name: family_benchmark_run_v1 family_benchmark_run_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_benchmark_run_v1
    ADD CONSTRAINT family_benchmark_run_v1_pkey PRIMARY KEY (run_id);


--
-- Name: family_model_assignment_log_v1 family_model_assignment_log_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_assignment_log_v1
    ADD CONSTRAINT family_model_assignment_log_v1_pkey PRIMARY KEY (log_id);


--
-- Name: family_model_benchmark_v1 family_model_benchmark_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_benchmark_v1
    ADD CONSTRAINT family_model_benchmark_v1_pkey PRIMARY KEY (benchmark_id);


--
-- Name: family_model_benchmark_v1 family_model_benchmark_v1_run_id_family_name_model_code_key; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_benchmark_v1
    ADD CONSTRAINT family_model_benchmark_v1_run_id_family_name_model_code_key UNIQUE (run_id, family_name, model_code);


--
-- Name: family_model_registry_v1 family_model_registry_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_registry_v1
    ADD CONSTRAINT family_model_registry_v1_pkey PRIMARY KEY (family_name);


--
-- Name: family_model_registry_v2 family_model_registry_v2_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_registry_v2
    ADD CONSTRAINT family_model_registry_v2_pkey PRIMARY KEY (family_name);


--
-- Name: family_model_state_v1 family_model_state_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_state_v1
    ADD CONSTRAINT family_model_state_v1_pkey PRIMARY KEY (family_name);


--
-- Name: family_model_suggestion_benchmark_v1 family_model_suggestion_benchmark_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_suggestion_benchmark_v1
    ADD CONSTRAINT family_model_suggestion_benchmark_v1_pkey PRIMARY KEY (suggestion_id);


--
-- Name: model_artifact_registry_v1 model_artifact_registry_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.model_artifact_registry_v1
    ADD CONSTRAINT model_artifact_registry_v1_pkey PRIMARY KEY (artifact_id);


--
-- Name: model_catalog_v1 model_catalog_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.model_catalog_v1
    ADD CONSTRAINT model_catalog_v1_pkey PRIMARY KEY (model_code);


--
-- Name: model_engine_map_v1 model_engine_map_v1_pkey; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.model_engine_map_v1
    ADD CONSTRAINT model_engine_map_v1_pkey PRIMARY KEY (model_code);


--
-- Name: family_model_assignment_v1 pk_family_model_assignment_v1; Type: CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_assignment_v1
    ADD CONSTRAINT pk_family_model_assignment_v1 PRIMARY KEY (family_name);


--
-- Name: classification_change_log_v1 classification_change_log_v1_pkey; Type: CONSTRAINT; Schema: ml_ops; Owner: -
--

ALTER TABLE ONLY ml_ops.classification_change_log_v1
    ADD CONSTRAINT classification_change_log_v1_pkey PRIMARY KEY (change_id);


--
-- Name: family_run_log_v1 family_run_log_v1_pkey; Type: CONSTRAINT; Schema: ml_ops; Owner: -
--

ALTER TABLE ONLY ml_ops.family_run_log_v1
    ADD CONSTRAINT family_run_log_v1_pkey PRIMARY KEY (family_run_id);


--
-- Name: job_schedule_config_v1 job_schedule_config_v1_pkey; Type: CONSTRAINT; Schema: ml_ops; Owner: -
--

ALTER TABLE ONLY ml_ops.job_schedule_config_v1
    ADD CONSTRAINT job_schedule_config_v1_pkey PRIMARY KEY (job_type);


--
-- Name: pipeline_run_log_v1 pipeline_run_log_v1_pkey; Type: CONSTRAINT; Schema: ml_ops; Owner: -
--

ALTER TABLE ONLY ml_ops.pipeline_run_log_v1
    ADD CONSTRAINT pipeline_run_log_v1_pkey PRIMARY KEY (run_id);


--
-- Name: dim_iso_day dim_iso_day_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_iso_day
    ADD CONSTRAINT dim_iso_day_pkey PRIMARY KEY (day);


--
-- Name: famiglie_catalog_static famiglie_catalog_static_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.famiglie_catalog_static
    ADD CONSTRAINT famiglie_catalog_static_pk PRIMARY KEY (famiglia);


--
-- Name: greenhouse_alerts greenhouse_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_alerts
    ADD CONSTRAINT greenhouse_alerts_pkey PRIMARY KEY (id);


--
-- Name: greenhouse_forecast_features_dense greenhouse_forecast_features_dense_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_forecast_features_dense
    ADD CONSTRAINT greenhouse_forecast_features_dense_pkey PRIMARY KEY (data, famiglia, fascia_prezzo_iva_inc);


--
-- Name: greenhouse_forecast_results_v2 greenhouse_forecast_results_v2_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_forecast_results_v2
    ADD CONSTRAINT greenhouse_forecast_results_v2_pkey PRIMARY KEY (data, famiglia, fascia_prezzo_iva_inc);


--
-- Name: greenhouse_forecast_results_v2 greenhouse_forecast_results_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_forecast_results_v2
    ADD CONSTRAINT greenhouse_forecast_results_v2_uk UNIQUE (data, famiglia, fascia_prezzo_iva_inc);


--
-- Name: greenhouse_forecast_results_v2 greenhouse_forecast_results_v2_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_forecast_results_v2
    ADD CONSTRAINT greenhouse_forecast_results_v2_uniq UNIQUE (data, famiglia, fascia_prezzo_iva_inc);


--
-- Name: greenhouse_holidays greenhouse_holidays_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_holidays
    ADD CONSTRAINT greenhouse_holidays_pkey PRIMARY KEY (data);


--
-- Name: greenhouse_products_normalized greenhouse_products_normalized_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_products_normalized
    ADD CONSTRAINT greenhouse_products_normalized_pkey PRIMARY KEY (codart);


--
-- Name: greenhouse_sales_family_daily_dense greenhouse_sales_family_daily_dense_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_sales_family_daily_dense
    ADD CONSTRAINT greenhouse_sales_family_daily_dense_pkey PRIMARY KEY (data, famiglia, fascia_prezzo_iva_inc);


--
-- Name: greenhouse_sales_family_daily_fact greenhouse_sales_family_daily_fact_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_sales_family_daily_fact
    ADD CONSTRAINT greenhouse_sales_family_daily_fact_pkey PRIMARY KEY (data, famiglia, fascia_prezzo_iva_inc);


--
-- Name: greenhouse_sales_raw greenhouse_sales_raw_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_sales_raw
    ADD CONSTRAINT greenhouse_sales_raw_pkey PRIMARY KEY (progressivo);


--
-- Name: greenhouse_series_list_fact greenhouse_series_list_fact_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_series_list_fact
    ADD CONSTRAINT greenhouse_series_list_fact_pkey PRIMARY KEY (famiglia, fascia_prezzo_iva_inc);


--
-- Name: greenhouse_stock_raw_upload greenhouse_stock_raw_upload_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_stock_raw_upload
    ADD CONSTRAINT greenhouse_stock_raw_upload_pkey PRIMARY KEY (data_rilevazione, codart);


--
-- Name: greenhouse_weather_daily greenhouse_weather_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_weather_daily
    ADD CONSTRAINT greenhouse_weather_daily_pkey PRIMARY KEY (data);


--
-- Name: greenhouse_weekday_strength_family greenhouse_weekday_strength_family_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_weekday_strength_family
    ADD CONSTRAINT greenhouse_weekday_strength_family_pkey PRIMARY KEY (famiglia, week_of_year, dow);


--
-- Name: greenhouse_weekday_strength greenhouse_weekday_strength_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.greenhouse_weekday_strength
    ADD CONSTRAINT greenhouse_weekday_strength_pkey PRIMARY KEY (famiglia, fascia_prezzo_iva_inc, week_of_year, dow);


--
-- Name: ops_parquet_export_runs ops_parquet_export_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ops_parquet_export_runs
    ADD CONSTRAINT ops_parquet_export_runs_pkey PRIMARY KEY (run_id);


--
-- Name: ops_parquet_export_state ops_parquet_export_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ops_parquet_export_state
    ADD CONSTRAINT ops_parquet_export_state_pkey PRIMARY KEY (id);


--
-- Name: t_analytics_backfill_state t_analytics_backfill_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_analytics_backfill_state
    ADD CONSTRAINT t_analytics_backfill_state_pkey PRIMARY KEY (job_name);


--
-- Name: t_core_analytics__breakdown_monthly_categoria_fp t_bdcat_mon_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_monthly_categoria_fp
    ADD CONSTRAINT t_bdcat_mon_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_monthly_categoria_fp_v2 t_bdcat_mon_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_monthly_categoria_fp_v2
    ADD CONSTRAINT t_bdcat_mon_v2_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_daily_categoria_fp t_bdcat_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_daily_categoria_fp
    ADD CONSTRAINT t_bdcat_uk UNIQUE (data, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_daily_categoria_fp_v2 t_bdcat_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_daily_categoria_fp_v2
    ADD CONSTRAINT t_bdcat_v2_uk UNIQUE (data, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_weekly_categoria_fp t_bdcat_week_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_weekly_categoria_fp
    ADD CONSTRAINT t_bdcat_week_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_weekly_categoria_fp_v2 t_bdcat_week_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_weekly_categoria_fp_v2
    ADD CONSTRAINT t_bdcat_week_v2_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_yearly_categoria_fp_v2 t_bdcat_year_v2_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_yearly_categoria_fp_v2
    ADD CONSTRAINT t_bdcat_year_v2_pk PRIMARY KEY (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_monthly_famiglia_fp t_bdfam_mon_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_monthly_famiglia_fp
    ADD CONSTRAINT t_bdfam_mon_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_monthly_famiglia_fp_v2 t_bdfam_mon_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_monthly_famiglia_fp_v2
    ADD CONSTRAINT t_bdfam_mon_v2_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_daily_famiglia_fp t_bdfam_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_daily_famiglia_fp
    ADD CONSTRAINT t_bdfam_uk UNIQUE (data, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_daily_famiglia_fp_v2 t_bdfam_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_daily_famiglia_fp_v2
    ADD CONSTRAINT t_bdfam_v2_uk UNIQUE (data, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_weekly_famiglia_fp t_bdfam_week_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_weekly_famiglia_fp
    ADD CONSTRAINT t_bdfam_week_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_weekly_famiglia_fp_v2 t_bdfam_week_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_weekly_famiglia_fp_v2
    ADD CONSTRAINT t_bdfam_week_v2_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_yearly_famiglia_fp_v2 t_bdfam_year_v2_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_yearly_famiglia_fp_v2
    ADD CONSTRAINT t_bdfam_year_v2_pk PRIMARY KEY (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_monthly_fascia_fp t_bdfas_mon_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_monthly_fascia_fp
    ADD CONSTRAINT t_bdfas_mon_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_monthly_fascia_fp_v2 t_bdfas_mon_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_monthly_fascia_fp_v2
    ADD CONSTRAINT t_bdfas_mon_v2_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_daily_fascia_fp_v2 t_bdfas_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_daily_fascia_fp_v2
    ADD CONSTRAINT t_bdfas_v2_uk UNIQUE (data, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_weekly_fascia_fp t_bdfas_week_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_weekly_fascia_fp
    ADD CONSTRAINT t_bdfas_week_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_weekly_fascia_fp_v2 t_bdfas_week_v2_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_weekly_fascia_fp_v2
    ADD CONSTRAINT t_bdfas_week_v2_uk UNIQUE (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_yearly_fascia_fp_v2 t_bdfas_year_v2_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_yearly_fascia_fp_v2
    ADD CONSTRAINT t_bdfas_year_v2_pk PRIMARY KEY (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_yearly_categoria_fp t_bdy_cat_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_yearly_categoria_fp
    ADD CONSTRAINT t_bdy_cat_pk PRIMARY KEY (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_yearly_famiglia_fp t_bdy_fam_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_yearly_famiglia_fp
    ADD CONSTRAINT t_bdy_fam_pk PRIMARY KEY (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__breakdown_yearly_fascia_fp t_bdy_fas_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__breakdown_yearly_fascia_fp
    ADD CONSTRAINT t_bdy_fas_pk PRIMARY KEY (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: t_core_analytics__series_daily_categoria t_cat_day_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_daily_categoria
    ADD CONSTRAINT t_cat_day_uk UNIQUE (data, entity_key);


--
-- Name: t_core_analytics__series_monthly_categoria t_cat_mon_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_monthly_categoria
    ADD CONSTRAINT t_cat_mon_uk UNIQUE (period_start, entity_key);


--
-- Name: t_core_analytics__series_weekly_categoria t_cat_week_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_weekly_categoria
    ADD CONSTRAINT t_cat_week_uk UNIQUE (period_start, entity_key);


--
-- Name: t_core_analytics__seasonality_month t_core_analytics__seasonality_month_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__seasonality_month
    ADD CONSTRAINT t_core_analytics__seasonality_month_pkey PRIMARY KEY (entity_type, entity_key_lc, month_num);


--
-- Name: t_core_analytics__series_yearly_categoria t_core_analytics__series_yearly_categoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_yearly_categoria
    ADD CONSTRAINT t_core_analytics__series_yearly_categoria_pkey PRIMARY KEY (period_start, entity_key_lc);


--
-- Name: t_core_analytics__series_yearly_famiglia t_core_analytics__series_yearly_famiglia_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_yearly_famiglia
    ADD CONSTRAINT t_core_analytics__series_yearly_famiglia_pkey PRIMARY KEY (period_start, entity_key_lc);


--
-- Name: t_core_analytics__series_yearly_fascia t_core_analytics__series_yearly_fascia_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_yearly_fascia
    ADD CONSTRAINT t_core_analytics__series_yearly_fascia_pkey PRIMARY KEY (period_start, entity_key_lc);


--
-- Name: t_core_analytics__series_yearly_fascia_prezzo t_core_analytics__series_yearly_fascia_prezzo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_yearly_fascia_prezzo
    ADD CONSTRAINT t_core_analytics__series_yearly_fascia_prezzo_pkey PRIMARY KEY (period_start, entity_key_lc);


--
-- Name: t_core_planner__assortment_calendar t_core_planner__assortment_calendar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_planner__assortment_calendar
    ADD CONSTRAINT t_core_planner__assortment_calendar_pkey PRIMARY KEY (mode, level, node_id, week_52);


--
-- Name: t_core_planner__density t_core_planner__density_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_planner__density
    ADD CONSTRAINT t_core_planner__density_pkey PRIMARY KEY (pot_size_group);


--
-- Name: t_core_planner__fact_weekly t_core_planner__fact_weekly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_planner__fact_weekly
    ADD CONSTRAINT t_core_planner__fact_weekly_pkey PRIMARY KEY (iso_year, week_52, week_start, fascia, categoria, famiglia, fascia_prezzo);


--
-- Name: t_core_planner__heat_cells t_core_planner__heat_cells_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_planner__heat_cells
    ADD CONSTRAINT t_core_planner__heat_cells_pkey PRIMARY KEY (mode, node_id, week_52);


--
-- Name: t_core_planner__orchestrator_state t_core_planner__orchestrator_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_planner__orchestrator_state
    ADD CONSTRAINT t_core_planner__orchestrator_state_pkey PRIMARY KEY (pipeline);


--
-- Name: t_core_planner__params_level t_core_planner__params_level_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_planner__params_level
    ADD CONSTRAINT t_core_planner__params_level_pkey PRIMARY KEY (level);


--
-- Name: t_core_planner__potsize_profile t_core_planner__potsize_profile_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_planner__potsize_profile
    ADD CONSTRAINT t_core_planner__potsize_profile_pkey PRIMARY KEY (level, famiglia, fascia_prezzo);


--
-- Name: t_core_planner__refresh_state t_core_planner__refresh_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_planner__refresh_state
    ADD CONSTRAINT t_core_planner__refresh_state_pkey PRIMARY KEY (pipeline);


--
-- Name: t_core_planner__space_budget t_core_planner__space_budget_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_planner__space_budget
    ADD CONSTRAINT t_core_planner__space_budget_pkey PRIMARY KEY (mode, level, node_id, week_52);


--
-- Name: t_dashboard_sales_daily t_dashboard_sales_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_dashboard_sales_daily
    ADD CONSTRAINT t_dashboard_sales_daily_pkey PRIMARY KEY (data);


--
-- Name: t_dashboard_sales_monthly t_dashboard_sales_monthly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_dashboard_sales_monthly
    ADD CONSTRAINT t_dashboard_sales_monthly_pkey PRIMARY KEY (period_start);


--
-- Name: t_dashboard_sales_weekly t_dashboard_sales_weekly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_dashboard_sales_weekly
    ADD CONSTRAINT t_dashboard_sales_weekly_pkey PRIMARY KEY (period_start);


--
-- Name: t_dashboard_sales_yearly t_dashboard_sales_yearly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_dashboard_sales_yearly
    ADD CONSTRAINT t_dashboard_sales_yearly_pkey PRIMARY KEY (period_start);


--
-- Name: t_core_analytics__series_monthly_famiglia t_fam_mon_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_monthly_famiglia
    ADD CONSTRAINT t_fam_mon_uk UNIQUE (period_start, entity_key);


--
-- Name: t_core_analytics__series_weekly_famiglia t_fam_week_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_weekly_famiglia
    ADD CONSTRAINT t_fam_week_uk UNIQUE (period_start, entity_key);


--
-- Name: t_core_analytics__series_daily_famiglia t_famiglia_day_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_daily_famiglia
    ADD CONSTRAINT t_famiglia_day_uk UNIQUE (data, entity_key);


--
-- Name: t_core_analytics__series_daily_fascia t_fas_day_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_daily_fascia
    ADD CONSTRAINT t_fas_day_uk UNIQUE (data, entity_key);


--
-- Name: t_core_analytics__series_monthly_fascia t_fas_mon_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_monthly_fascia
    ADD CONSTRAINT t_fas_mon_uk UNIQUE (period_start, entity_key);


--
-- Name: t_core_analytics__series_weekly_fascia t_fas_week_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_weekly_fascia
    ADD CONSTRAINT t_fas_week_uk UNIQUE (period_start, entity_key);


--
-- Name: t_core_analytics__series_daily_fascia_prezzo t_fp_day_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_daily_fascia_prezzo
    ADD CONSTRAINT t_fp_day_uk UNIQUE (data, entity_key);


--
-- Name: t_core_analytics__series_monthly_fascia_prezzo t_fp_mon_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_monthly_fascia_prezzo
    ADD CONSTRAINT t_fp_mon_uk UNIQUE (period_start, entity_key);


--
-- Name: t_core_analytics__series_weekly_fascia_prezzo t_fp_week_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_core_analytics__series_weekly_fascia_prezzo
    ADD CONSTRAINT t_fp_week_uk UNIQUE (period_start, entity_key);


--
-- Name: t_ops_pipeline_monitor t_ops_pipeline_monitor_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.t_ops_pipeline_monitor
    ADD CONSTRAINT t_ops_pipeline_monitor_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: subscription pk_subscription; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.subscription
    ADD CONSTRAINT pk_subscription PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: buckets_analytics buckets_analytics_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets_analytics
    ADD CONSTRAINT buckets_analytics_pkey PRIMARY KEY (id);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: buckets_vectors buckets_vectors_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets_vectors
    ADD CONSTRAINT buckets_vectors_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_name_key; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_pkey PRIMARY KEY (id);


--
-- Name: vector_indexes vector_indexes_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_pkey PRIMARY KEY (id);


--
-- Name: audit_logs_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX audit_logs_instance_id_idx ON auth.audit_log_entries USING btree (instance_id);


--
-- Name: confirmation_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX confirmation_token_idx ON auth.users USING btree (confirmation_token) WHERE ((confirmation_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: custom_oauth_providers_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_created_at_idx ON auth.custom_oauth_providers USING btree (created_at);


--
-- Name: custom_oauth_providers_enabled_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_enabled_idx ON auth.custom_oauth_providers USING btree (enabled);


--
-- Name: custom_oauth_providers_identifier_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_identifier_idx ON auth.custom_oauth_providers USING btree (identifier);


--
-- Name: custom_oauth_providers_provider_type_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_provider_type_idx ON auth.custom_oauth_providers USING btree (provider_type);


--
-- Name: email_change_token_current_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX email_change_token_current_idx ON auth.users USING btree (email_change_token_current) WHERE ((email_change_token_current)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_new_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX email_change_token_new_idx ON auth.users USING btree (email_change_token_new) WHERE ((email_change_token_new)::text !~ '^[0-9 ]*$'::text);


--
-- Name: factor_id_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX factor_id_created_at_idx ON auth.mfa_factors USING btree (user_id, created_at);


--
-- Name: flow_state_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX flow_state_created_at_idx ON auth.flow_state USING btree (created_at DESC);


--
-- Name: identities_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX identities_email_idx ON auth.identities USING btree (email text_pattern_ops);


--
-- Name: INDEX identities_email_idx; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON INDEX auth.identities_email_idx IS 'Auth: Ensures indexed queries on the email column';


--
-- Name: identities_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX identities_user_id_idx ON auth.identities USING btree (user_id);


--
-- Name: idx_auth_code; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_auth_code ON auth.flow_state USING btree (auth_code);


--
-- Name: idx_oauth_client_states_created_at; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_oauth_client_states_created_at ON auth.oauth_client_states USING btree (created_at);


--
-- Name: idx_user_id_auth_method; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_user_id_auth_method ON auth.flow_state USING btree (user_id, authentication_method);


--
-- Name: mfa_challenge_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_challenge_created_at_idx ON auth.mfa_challenges USING btree (created_at DESC);


--
-- Name: mfa_factors_user_friendly_name_unique; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX mfa_factors_user_friendly_name_unique ON auth.mfa_factors USING btree (friendly_name, user_id) WHERE (TRIM(BOTH FROM friendly_name) <> ''::text);


--
-- Name: mfa_factors_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_factors_user_id_idx ON auth.mfa_factors USING btree (user_id);


--
-- Name: oauth_auth_pending_exp_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_auth_pending_exp_idx ON auth.oauth_authorizations USING btree (expires_at) WHERE (status = 'pending'::auth.oauth_authorization_status);


--
-- Name: oauth_clients_deleted_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_clients_deleted_at_idx ON auth.oauth_clients USING btree (deleted_at);


--
-- Name: oauth_consents_active_client_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_active_client_idx ON auth.oauth_consents USING btree (client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_active_user_client_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_active_user_client_idx ON auth.oauth_consents USING btree (user_id, client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_user_order_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_user_order_idx ON auth.oauth_consents USING btree (user_id, granted_at DESC);


--
-- Name: one_time_tokens_relates_to_hash_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX one_time_tokens_relates_to_hash_idx ON auth.one_time_tokens USING hash (relates_to);


--
-- Name: one_time_tokens_token_hash_hash_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX one_time_tokens_token_hash_hash_idx ON auth.one_time_tokens USING hash (token_hash);


--
-- Name: one_time_tokens_user_id_token_type_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX one_time_tokens_user_id_token_type_key ON auth.one_time_tokens USING btree (user_id, token_type);


--
-- Name: reauthentication_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX reauthentication_token_idx ON auth.users USING btree (reauthentication_token) WHERE ((reauthentication_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: recovery_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX recovery_token_idx ON auth.users USING btree (recovery_token) WHERE ((recovery_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: refresh_tokens_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_instance_id_idx ON auth.refresh_tokens USING btree (instance_id);


--
-- Name: refresh_tokens_instance_id_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_instance_id_user_id_idx ON auth.refresh_tokens USING btree (instance_id, user_id);


--
-- Name: refresh_tokens_parent_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_parent_idx ON auth.refresh_tokens USING btree (parent);


--
-- Name: refresh_tokens_session_id_revoked_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_session_id_revoked_idx ON auth.refresh_tokens USING btree (session_id, revoked);


--
-- Name: refresh_tokens_updated_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_updated_at_idx ON auth.refresh_tokens USING btree (updated_at DESC);


--
-- Name: saml_providers_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_providers_sso_provider_id_idx ON auth.saml_providers USING btree (sso_provider_id);


--
-- Name: saml_relay_states_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_created_at_idx ON auth.saml_relay_states USING btree (created_at DESC);


--
-- Name: saml_relay_states_for_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_for_email_idx ON auth.saml_relay_states USING btree (for_email);


--
-- Name: saml_relay_states_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_sso_provider_id_idx ON auth.saml_relay_states USING btree (sso_provider_id);


--
-- Name: sessions_not_after_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_not_after_idx ON auth.sessions USING btree (not_after DESC);


--
-- Name: sessions_oauth_client_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_oauth_client_id_idx ON auth.sessions USING btree (oauth_client_id);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_user_id_idx ON auth.sessions USING btree (user_id);


--
-- Name: sso_domains_domain_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX sso_domains_domain_idx ON auth.sso_domains USING btree (lower(domain));


--
-- Name: sso_domains_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sso_domains_sso_provider_id_idx ON auth.sso_domains USING btree (sso_provider_id);


--
-- Name: sso_providers_resource_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX sso_providers_resource_id_idx ON auth.sso_providers USING btree (lower(resource_id));


--
-- Name: sso_providers_resource_id_pattern_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sso_providers_resource_id_pattern_idx ON auth.sso_providers USING btree (resource_id text_pattern_ops);


--
-- Name: unique_phone_factor_per_user; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX unique_phone_factor_per_user ON auth.mfa_factors USING btree (user_id, phone);


--
-- Name: user_id_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX user_id_created_at_idx ON auth.sessions USING btree (user_id, created_at);


--
-- Name: users_email_partial_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX users_email_partial_key ON auth.users USING btree (email) WHERE (is_sso_user = false);


--
-- Name: INDEX users_email_partial_key; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON INDEX auth.users_email_partial_key IS 'Auth: A partial unique index that applies only when is_sso_user is false';


--
-- Name: users_instance_id_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_instance_id_email_idx ON auth.users USING btree (instance_id, lower((email)::text));


--
-- Name: users_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_instance_id_idx ON auth.users USING btree (instance_id);


--
-- Name: users_is_anonymous_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_is_anonymous_idx ON auth.users USING btree (is_anonymous);


--
-- Name: ix_etl_runs_pipe; Type: INDEX; Schema: etl; Owner: -
--

CREATE INDEX ix_etl_runs_pipe ON etl.t_etl_runs USING btree (pipeline, started_at DESC);


--
-- Name: ix_etl_steps_run; Type: INDEX; Schema: etl; Owner: -
--

CREATE INDEX ix_etl_steps_run ON etl.t_etl_steps USING btree (run_id);


--
-- Name: idx_mv_family_day_base_data; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX idx_mv_family_day_base_data ON ml_diag.mv_family_day_base USING btree (data);


--
-- Name: idx_mv_family_day_base_family_data; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX idx_mv_family_day_base_family_data ON ml_diag.mv_family_day_base USING btree (family_name, data);


--
-- Name: idx_mv_family_importance_family; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX idx_mv_family_importance_family ON ml_diag.mv_family_importance USING btree (family_name);


--
-- Name: idx_mv_family_intermittency_family; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX idx_mv_family_intermittency_family ON ml_diag.mv_family_intermittency USING btree (family_name);


--
-- Name: idx_mv_family_metrics_v3_family; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX idx_mv_family_metrics_v3_family ON ml_diag.mv_family_metrics_v3 USING btree (family_name);


--
-- Name: idx_mv_family_metrics_v3b_family; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX idx_mv_family_metrics_v3b_family ON ml_diag.mv_family_metrics_v3b USING btree (family_name);


--
-- Name: idx_mv_family_metrics_v4_family_name; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX idx_mv_family_metrics_v4_family_name ON ml_diag.mv_family_metrics_v4 USING btree (family_name);


--
-- Name: idx_mv_family_seasonality_family; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX idx_mv_family_seasonality_family ON ml_diag.mv_family_seasonality USING btree (family_name);


--
-- Name: idx_mv_family_stats_family; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX idx_mv_family_stats_family ON ml_diag.mv_family_stats USING btree (family_name);


--
-- Name: ix_mv_family_metrics_v5_family_name; Type: INDEX; Schema: ml_diag; Owner: -
--

CREATE INDEX ix_mv_family_metrics_v5_family_name ON ml_diag.mv_family_metrics_v5 USING btree (family_name);


--
-- Name: idx_bm_v1_family_name; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX idx_bm_v1_family_name ON ml_forecast.family_model_benchmark_v1 USING btree (family_name);


--
-- Name: idx_bm_v1_is_best; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX idx_bm_v1_is_best ON ml_forecast.family_model_benchmark_v1 USING btree (family_name, is_best) WHERE (is_best = true);


--
-- Name: idx_bm_v1_run_id; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX idx_bm_v1_run_id ON ml_forecast.family_model_benchmark_v1 USING btree (run_id);


--
-- Name: idx_family_model_registry_v1_class; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX idx_family_model_registry_v1_class ON ml_forecast.family_model_registry_v1 USING btree (demand_class_final);


--
-- Name: idx_family_model_registry_v1_model; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX idx_family_model_registry_v1_model ON ml_forecast.family_model_registry_v1 USING btree (model_code);


--
-- Name: idx_family_model_registry_v1_tier; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX idx_family_model_registry_v1_tier ON ml_forecast.family_model_registry_v1 USING btree (business_tier);


--
-- Name: idx_family_model_registry_v1_value; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX idx_family_model_registry_v1_value ON ml_forecast.family_model_registry_v1 USING btree (value_total DESC);


--
-- Name: ix_assignment_log_family_at; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_assignment_log_family_at ON ml_forecast.family_model_assignment_log_v1 USING btree (family_name, changed_at DESC);


--
-- Name: ix_family_model_assignment_locked; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_family_model_assignment_locked ON ml_forecast.family_model_assignment_v1 USING btree (is_locked) WHERE (is_locked = true);


--
-- Name: ix_family_model_registry_v2_class; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_family_model_registry_v2_class ON ml_forecast.family_model_registry_v2 USING btree (demand_class_final);


--
-- Name: ix_family_model_registry_v2_model; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_family_model_registry_v2_model ON ml_forecast.family_model_registry_v2 USING btree (model_code);


--
-- Name: ix_family_model_registry_v2_tier; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_family_model_registry_v2_tier ON ml_forecast.family_model_registry_v2 USING btree (business_tier);


--
-- Name: ix_family_model_state_flags; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_family_model_state_flags ON ml_forecast.family_model_state_v1 USING btree (needs_reclass, needs_retrain, needs_predict);


--
-- Name: ix_family_model_state_v1_class; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_family_model_state_v1_class ON ml_forecast.family_model_state_v1 USING btree (demand_class_final);


--
-- Name: ix_family_model_state_v1_model; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_family_model_state_v1_model ON ml_forecast.family_model_state_v1 USING btree (model_code);


--
-- Name: ix_family_model_state_v1_needs_train; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_family_model_state_v1_needs_train ON ml_forecast.family_model_state_v1 USING btree (needs_initial_train, is_active);


--
-- Name: ix_model_artifact_registry_family; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_model_artifact_registry_family ON ml_forecast.model_artifact_registry_v1 USING btree (family_name, is_active, updated_at DESC);


--
-- Name: ix_model_artifact_registry_model; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_model_artifact_registry_model ON ml_forecast.model_artifact_registry_v1 USING btree (model_code, is_active, updated_at DESC);


--
-- Name: ix_suggestion_benchmark_family_at; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE INDEX ix_suggestion_benchmark_family_at ON ml_forecast.family_model_suggestion_benchmark_v1 USING btree (family_name, suggested_at DESC);


--
-- Name: ux_suggestion_one_open_per_family; Type: INDEX; Schema: ml_forecast; Owner: -
--

CREATE UNIQUE INDEX ux_suggestion_one_open_per_family ON ml_forecast.family_model_suggestion_benchmark_v1 USING btree (family_name) WHERE (is_applied = false);


--
-- Name: ix_classification_change_log_family; Type: INDEX; Schema: ml_ops; Owner: -
--

CREATE INDEX ix_classification_change_log_family ON ml_ops.classification_change_log_v1 USING btree (family_name, detected_at DESC);


--
-- Name: ix_family_run_log_v1_family_started; Type: INDEX; Schema: ml_ops; Owner: -
--

CREATE INDEX ix_family_run_log_v1_family_started ON ml_ops.family_run_log_v1 USING btree (family_name, started_at DESC);


--
-- Name: ix_family_run_log_v1_job_status; Type: INDEX; Schema: ml_ops; Owner: -
--

CREATE INDEX ix_family_run_log_v1_job_status ON ml_ops.family_run_log_v1 USING btree (job_type, status, started_at DESC);


--
-- Name: ix_pipeline_run_log_v1_job_type_started; Type: INDEX; Schema: ml_ops; Owner: -
--

CREATE INDEX ix_pipeline_run_log_v1_job_type_started ON ml_ops.pipeline_run_log_v1 USING btree (job_type, started_at DESC);


--
-- Name: greenhouse_forecast_results_v2_fam_data_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX greenhouse_forecast_results_v2_fam_data_idx ON public.greenhouse_forecast_results_v2 USING btree (famiglia, data);


--
-- Name: idx_assort_cal_mode_level_node_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assort_cal_mode_level_node_week ON public.t_core_planner__assortment_calendar USING btree (mode, level, node_id, week_52);


--
-- Name: idx_assortment_mode_level_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assortment_mode_level_week ON public.t_core_planner__assortment_calendar USING btree (mode, level, week_52);


--
-- Name: idx_assortment_node; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assortment_node ON public.t_core_planner__assortment_calendar USING btree (node_id);


--
-- Name: idx_bdcat_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_data ON public.t_core_analytics__breakdown_daily_categoria_fp USING btree (data);


--
-- Name: idx_bdcat_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_key_data ON public.t_core_analytics__breakdown_daily_categoria_fp USING btree (entity_key_lc, data);


--
-- Name: idx_bdcat_mon_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_mon_key_start ON public.t_core_analytics__breakdown_monthly_categoria_fp USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdcat_mon_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_mon_start ON public.t_core_analytics__breakdown_monthly_categoria_fp USING btree (period_start);


--
-- Name: idx_bdcat_mon_v2_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_mon_v2_key_start ON public.t_core_analytics__breakdown_monthly_categoria_fp_v2 USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdcat_mon_v2_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_mon_v2_start ON public.t_core_analytics__breakdown_monthly_categoria_fp_v2 USING btree (period_start);


--
-- Name: idx_bdcat_v2_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_v2_data ON public.t_core_analytics__breakdown_daily_categoria_fp_v2 USING btree (data);


--
-- Name: idx_bdcat_v2_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_v2_key_data ON public.t_core_analytics__breakdown_daily_categoria_fp_v2 USING btree (entity_key_lc, data);


--
-- Name: idx_bdcat_week_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_week_key_start ON public.t_core_analytics__breakdown_weekly_categoria_fp USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdcat_week_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_week_start ON public.t_core_analytics__breakdown_weekly_categoria_fp USING btree (period_start);


--
-- Name: idx_bdcat_week_v2_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_week_v2_key_start ON public.t_core_analytics__breakdown_weekly_categoria_fp_v2 USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdcat_week_v2_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_week_v2_start ON public.t_core_analytics__breakdown_weekly_categoria_fp_v2 USING btree (period_start);


--
-- Name: idx_bdcat_year_v2_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_year_v2_key_start ON public.t_core_analytics__breakdown_yearly_categoria_fp_v2 USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdcat_year_v2_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdcat_year_v2_start ON public.t_core_analytics__breakdown_yearly_categoria_fp_v2 USING btree (period_start);


--
-- Name: idx_bdfam_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_data ON public.t_core_analytics__breakdown_daily_famiglia_fp USING btree (data);


--
-- Name: idx_bdfam_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_key_data ON public.t_core_analytics__breakdown_daily_famiglia_fp USING btree (entity_key_lc, data);


--
-- Name: idx_bdfam_mon_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_mon_key_start ON public.t_core_analytics__breakdown_monthly_famiglia_fp USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfam_mon_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_mon_start ON public.t_core_analytics__breakdown_monthly_famiglia_fp USING btree (period_start);


--
-- Name: idx_bdfam_mon_v2_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_mon_v2_key_start ON public.t_core_analytics__breakdown_monthly_famiglia_fp_v2 USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfam_mon_v2_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_mon_v2_start ON public.t_core_analytics__breakdown_monthly_famiglia_fp_v2 USING btree (period_start);


--
-- Name: idx_bdfam_v2_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_v2_data ON public.t_core_analytics__breakdown_daily_famiglia_fp_v2 USING btree (data);


--
-- Name: idx_bdfam_v2_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_v2_key_data ON public.t_core_analytics__breakdown_daily_famiglia_fp_v2 USING btree (entity_key_lc, data);


--
-- Name: idx_bdfam_week_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_week_key_start ON public.t_core_analytics__breakdown_weekly_famiglia_fp USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfam_week_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_week_start ON public.t_core_analytics__breakdown_weekly_famiglia_fp USING btree (period_start);


--
-- Name: idx_bdfam_week_v2_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_week_v2_key_start ON public.t_core_analytics__breakdown_weekly_famiglia_fp_v2 USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfam_week_v2_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_week_v2_start ON public.t_core_analytics__breakdown_weekly_famiglia_fp_v2 USING btree (period_start);


--
-- Name: idx_bdfam_year_v2_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_year_v2_key_start ON public.t_core_analytics__breakdown_yearly_famiglia_fp_v2 USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfam_year_v2_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfam_year_v2_start ON public.t_core_analytics__breakdown_yearly_famiglia_fp_v2 USING btree (period_start);


--
-- Name: idx_bdfas_mon_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_mon_key_start ON public.t_core_analytics__breakdown_monthly_fascia_fp USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfas_mon_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_mon_start ON public.t_core_analytics__breakdown_monthly_fascia_fp USING btree (period_start);


--
-- Name: idx_bdfas_mon_v2_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_mon_v2_key_start ON public.t_core_analytics__breakdown_monthly_fascia_fp_v2 USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfas_mon_v2_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_mon_v2_start ON public.t_core_analytics__breakdown_monthly_fascia_fp_v2 USING btree (period_start);


--
-- Name: idx_bdfas_v2_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_v2_data ON public.t_core_analytics__breakdown_daily_fascia_fp_v2 USING btree (data);


--
-- Name: idx_bdfas_v2_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_v2_key_data ON public.t_core_analytics__breakdown_daily_fascia_fp_v2 USING btree (entity_key_lc, data);


--
-- Name: idx_bdfas_week_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_week_key_start ON public.t_core_analytics__breakdown_weekly_fascia_fp USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfas_week_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_week_start ON public.t_core_analytics__breakdown_weekly_fascia_fp USING btree (period_start);


--
-- Name: idx_bdfas_week_v2_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_week_v2_key_start ON public.t_core_analytics__breakdown_weekly_fascia_fp_v2 USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfas_week_v2_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_week_v2_start ON public.t_core_analytics__breakdown_weekly_fascia_fp_v2 USING btree (period_start);


--
-- Name: idx_bdfas_year_v2_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_year_v2_key_start ON public.t_core_analytics__breakdown_yearly_fascia_fp_v2 USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdfas_year_v2_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdfas_year_v2_start ON public.t_core_analytics__breakdown_yearly_fascia_fp_v2 USING btree (period_start);


--
-- Name: idx_bdy_cat_key_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdy_cat_key_date ON public.t_core_analytics__breakdown_yearly_categoria_fp USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdy_cat_period_key_fp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdy_cat_period_key_fp ON public.t_core_analytics__breakdown_yearly_categoria_fp USING btree (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: idx_bdy_fam_key_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdy_fam_key_date ON public.t_core_analytics__breakdown_yearly_famiglia_fp USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdy_fam_period_key_fp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdy_fam_period_key_fp ON public.t_core_analytics__breakdown_yearly_famiglia_fp USING btree (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: idx_bdy_fas_key_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdy_fas_key_date ON public.t_core_analytics__breakdown_yearly_fascia_fp USING btree (entity_key_lc, period_start);


--
-- Name: idx_bdy_fas_period_key_fp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bdy_fas_period_key_fp ON public.t_core_analytics__breakdown_yearly_fascia_fp USING btree (period_start, entity_key_lc, fascia_prezzo_iva_inc);


--
-- Name: idx_cat_mon_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cat_mon_key_start ON public.t_core_analytics__series_monthly_categoria USING btree (entity_key, period_start);


--
-- Name: idx_cat_mon_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cat_mon_start ON public.t_core_analytics__series_monthly_categoria USING btree (period_start);


--
-- Name: idx_cat_week_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cat_week_key_start ON public.t_core_analytics__series_weekly_categoria USING btree (entity_key, period_start);


--
-- Name: idx_cat_week_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cat_week_start ON public.t_core_analytics__series_weekly_categoria USING btree (period_start);


--
-- Name: idx_catalog_entities_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_catalog_entities_key ON public.mv_core_analytics__catalog_entities USING btree (entity_type, entity_key);


--
-- Name: idx_catalog_entities_label_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_catalog_entities_label_trgm ON public.mv_core_analytics__catalog_entities USING gin (lower(label) public.gin_trgm_ops);


--
-- Name: idx_daily_cat_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_cat_data ON public.t_core_analytics__series_daily_categoria USING btree (data);


--
-- Name: idx_daily_fam_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_fam_data ON public.t_core_analytics__series_daily_famiglia USING btree (data);


--
-- Name: idx_daily_fas_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_fas_data ON public.t_core_analytics__series_daily_fascia USING btree (data);


--
-- Name: idx_daily_fp_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_fp_data ON public.t_core_analytics__series_daily_fascia_prezzo USING btree (data);


--
-- Name: idx_dense_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dense_data ON public.greenhouse_sales_family_daily_dense USING btree (data);


--
-- Name: idx_dense_series; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dense_series ON public.greenhouse_sales_family_daily_dense USING btree (famiglia, fascia_prezzo_iva_inc);


--
-- Name: idx_dim_iso_day_iso_year_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dim_iso_day_iso_year_week ON public.dim_iso_day USING btree (iso_year, week_52);


--
-- Name: idx_dim_iso_day_week_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dim_iso_day_week_start ON public.dim_iso_day USING btree (week_start);


--
-- Name: idx_fact_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fact_data ON public.greenhouse_sales_family_daily_fact USING btree (data);


--
-- Name: idx_fact_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fact_key ON public.greenhouse_sales_family_daily_fact USING btree (data, famiglia, fascia_prezzo_iva_inc);


--
-- Name: idx_fact_series; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fact_series ON public.greenhouse_sales_family_daily_fact USING btree (famiglia, fascia_prezzo_iva_inc);


--
-- Name: idx_fam_mon_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fam_mon_key_start ON public.t_core_analytics__series_monthly_famiglia USING btree (entity_key, period_start);


--
-- Name: idx_fam_mon_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fam_mon_start ON public.t_core_analytics__series_monthly_famiglia USING btree (period_start);


--
-- Name: idx_fam_week_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fam_week_key_start ON public.t_core_analytics__series_weekly_famiglia USING btree (entity_key, period_start);


--
-- Name: idx_fam_week_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fam_week_start ON public.t_core_analytics__series_weekly_famiglia USING btree (period_start);


--
-- Name: idx_famiglie_catalog_static_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_famiglie_catalog_static_slug ON public.famiglie_catalog_static USING btree (famiglia_slug);


--
-- Name: idx_fas_mon_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fas_mon_key_start ON public.t_core_analytics__series_monthly_fascia USING btree (entity_key, period_start);


--
-- Name: idx_fas_mon_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fas_mon_start ON public.t_core_analytics__series_monthly_fascia USING btree (period_start);


--
-- Name: idx_fas_week_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fas_week_key_start ON public.t_core_analytics__series_weekly_fascia USING btree (entity_key, period_start);


--
-- Name: idx_fas_week_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fas_week_start ON public.t_core_analytics__series_weekly_fascia USING btree (period_start);


--
-- Name: idx_fc_v2_date_famfp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fc_v2_date_famfp ON public.greenhouse_forecast_results_v2 USING btree (data, lower(famiglia), fascia_prezzo_iva_inc);


--
-- Name: idx_fc_v2_fam_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fc_v2_fam_date ON public.greenhouse_forecast_results_v2 USING btree (lower(famiglia), data);


--
-- Name: idx_fc_v2_fam_fp_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fc_v2_fam_fp_date ON public.greenhouse_forecast_results_v2 USING btree (lower(famiglia), fascia_prezzo_iva_inc, data);


--
-- Name: idx_forecast_results_v2_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_forecast_results_v2_data ON public.greenhouse_forecast_results_v2 USING btree (data);


--
-- Name: idx_forecast_results_v2_series; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_forecast_results_v2_series ON public.greenhouse_forecast_results_v2 USING btree (famiglia, fascia_prezzo_iva_inc);


--
-- Name: idx_forecast_v2_fam; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_forecast_v2_fam ON public.greenhouse_forecast_results_v2 USING btree (famiglia);


--
-- Name: idx_fp_mon_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fp_mon_key_start ON public.t_core_analytics__series_monthly_fascia_prezzo USING btree (entity_key, period_start);


--
-- Name: idx_fp_mon_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fp_mon_start ON public.t_core_analytics__series_monthly_fascia_prezzo USING btree (period_start);


--
-- Name: idx_fp_week_key_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fp_week_key_start ON public.t_core_analytics__series_weekly_fascia_prezzo USING btree (entity_key, period_start);


--
-- Name: idx_fp_week_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fp_week_start ON public.t_core_analytics__series_weekly_fascia_prezzo USING btree (period_start);


--
-- Name: idx_gffd_cat_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_cat_date ON public.greenhouse_forecast_features_dense USING btree (lower(categoria_corretta), data);


--
-- Name: idx_gffd_categoria_lc_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_categoria_lc_date ON public.greenhouse_forecast_features_dense USING btree (lower(categoria_corretta), data);


--
-- Name: idx_gffd_categoria_lc_date_fam_fp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_categoria_lc_date_fam_fp ON public.greenhouse_forecast_features_dense USING btree (lower(categoria_corretta), data, lower(famiglia), fascia_prezzo_iva_inc);


--
-- Name: idx_gffd_categoria_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_categoria_trgm ON public.greenhouse_forecast_features_dense USING gin (lower(categoria_corretta) public.gin_trgm_ops);


--
-- Name: idx_gffd_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_data ON public.greenhouse_forecast_features_dense USING btree (data);


--
-- Name: idx_gffd_fam_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_fam_date ON public.greenhouse_forecast_features_dense USING btree (lower(famiglia), data);


--
-- Name: idx_gffd_fam_fascia_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_fam_fascia_date ON public.greenhouse_forecast_features_dense USING btree (lower(famiglia), fascia_prezzo_iva_inc, data);


--
-- Name: idx_gffd_fam_fp_lc_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_fam_fp_lc_date ON public.greenhouse_forecast_features_dense USING btree (lower(famiglia), lower(fascia_prezzo_iva_inc), data);


--
-- Name: idx_gffd_famiglia_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_famiglia_data ON public.greenhouse_forecast_features_dense USING btree (famiglia, data);


--
-- Name: idx_gffd_famiglia_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_famiglia_trgm ON public.greenhouse_forecast_features_dense USING gin (lower(famiglia) public.gin_trgm_ops);


--
-- Name: idx_gffd_fascia_lc_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_fascia_lc_date ON public.greenhouse_forecast_features_dense USING btree (lower(fascia_corretta), data) WHERE ((fascia_corretta IS NOT NULL) AND (btrim(fascia_corretta) <> ''::text));


--
-- Name: idx_gffd_fascia_lc_date_fam_fp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_fascia_lc_date_fam_fp ON public.greenhouse_forecast_features_dense USING btree (lower(fascia_corretta), data, lower(famiglia), fascia_prezzo_iva_inc);


--
-- Name: idx_gffd_fascia_prezzo_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_fascia_prezzo_trgm ON public.greenhouse_forecast_features_dense USING gin (lower(fascia_prezzo_iva_inc) public.gin_trgm_ops);


--
-- Name: idx_gffd_fascia_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_fascia_trgm ON public.greenhouse_forecast_features_dense USING gin (lower(fascia_corretta) public.gin_trgm_ops);


--
-- Name: idx_gffd_fasciacorr_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_fasciacorr_date ON public.greenhouse_forecast_features_dense USING btree (lower(fascia_corretta), data);


--
-- Name: idx_gffd_fp_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_fp_data ON public.greenhouse_forecast_features_dense USING btree (fascia_prezzo_iva_inc, data);


--
-- Name: idx_gffd_series; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gffd_series ON public.greenhouse_forecast_features_dense USING btree (famiglia, fascia_prezzo_iva_inc);


--
-- Name: idx_greenhouse_alerts_unsent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_greenhouse_alerts_unsent ON public.greenhouse_alerts USING btree (is_sent, created_at DESC);


--
-- Name: idx_gws_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gws_lookup ON public.greenhouse_weekday_strength USING btree (famiglia, fascia_prezzo_iva_inc, week_of_year, dow);


--
-- Name: idx_gwsf_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gwsf_lookup ON public.greenhouse_weekday_strength_family USING btree (famiglia, week_of_year, dow);


--
-- Name: idx_heat_cells_keys; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_heat_cells_keys ON public.t_core_planner__heat_cells USING btree (mode, fascia, categoria, famiglia, fascia_prezzo);


--
-- Name: idx_heat_cells_mode_level_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_heat_cells_mode_level_week ON public.t_core_planner__heat_cells USING btree (mode, level, week_52);


--
-- Name: idx_heat_cells_mode_node_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_heat_cells_mode_node_week ON public.t_core_planner__heat_cells USING btree (mode, node_id, week_52);


--
-- Name: idx_heat_cells_mode_week52; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_heat_cells_mode_week52 ON public.t_core_planner__heat_cells USING btree (mode, week_52);


--
-- Name: idx_heat_cells_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_heat_cells_parent ON public.t_core_planner__heat_cells USING btree (mode, parent_id);


--
-- Name: idx_mv_breakdown_fascia_fp_key_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mv_breakdown_fascia_fp_key_date ON public.mv_core_analytics__breakdown_daily_fascia_fp USING btree (entity_key_lc, data);


--
-- Name: idx_mv_breakdown_fascia_fp_key_date_fp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mv_breakdown_fascia_fp_key_date_fp ON public.mv_core_analytics__breakdown_daily_fascia_fp USING btree (entity_key_lc, data, fascia_prezzo_iva_inc);


--
-- Name: idx_mv_cat_lc_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mv_cat_lc_data ON public.mv_core_analytics__series_daily_categoria USING btree (lower(entity_key), data);


--
-- Name: idx_mv_fas_lc_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mv_fas_lc_data ON public.mv_core_analytics__series_daily_fascia USING btree (lower(entity_key), data);


--
-- Name: idx_mv_fp_lc_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mv_fp_lc_data ON public.mv_core_analytics__series_daily_fascia_prezzo USING btree (lower(entity_key), data);


--
-- Name: idx_ops_pipeline_monitor_snap_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ops_pipeline_monitor_snap_ts ON public.t_ops_pipeline_monitor USING btree (snap_ts DESC);


--
-- Name: idx_planner_weekly_fam_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_planner_weekly_fam_week ON public.t_core_planner__fact_weekly USING btree (famiglia, week_52);


--
-- Name: idx_planner_weekly_keys_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_planner_weekly_keys_week ON public.t_core_planner__fact_weekly USING btree (fascia, categoria, famiglia, fascia_prezzo, week_52);


--
-- Name: idx_planner_weekly_week_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_planner_weekly_week_start ON public.t_core_planner__fact_weekly USING btree (week_start);


--
-- Name: idx_planner_weekly_year_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_planner_weekly_year_week ON public.t_core_planner__fact_weekly USING btree (iso_year, week_52);


--
-- Name: idx_potsize_profile_fam; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_potsize_profile_fam ON public.t_core_planner__potsize_profile USING btree (famiglia);


--
-- Name: idx_potsize_profile_fam_fp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_potsize_profile_fam_fp ON public.t_core_planner__potsize_profile USING btree (famiglia, fascia_prezzo);


--
-- Name: idx_sales_fam_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sales_fam_data ON public.greenhouse_sales_family_daily_dense USING btree (famiglia, data);


--
-- Name: idx_sales_raw_codart; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sales_raw_codart ON public.greenhouse_sales_raw USING btree (codart);


--
-- Name: idx_sales_raw_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sales_raw_data ON public.greenhouse_sales_raw USING btree (data_movimento);


--
-- Name: idx_sales_raw_data_codart_1prefix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sales_raw_data_codart_1prefix ON public.greenhouse_sales_raw USING btree (data_movimento) WHERE ((codart)::text ~~ '1%'::text);


--
-- Name: idx_series_list_fact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_series_list_fact ON public.greenhouse_series_list_fact USING btree (famiglia, fascia_prezzo_iva_inc);


--
-- Name: idx_space_budget_mode_level_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_space_budget_mode_level_week ON public.t_core_planner__space_budget USING btree (mode, level, week_52);


--
-- Name: idx_space_budget_node; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_space_budget_node ON public.t_core_planner__space_budget USING btree (node_id);


--
-- Name: idx_t_bdfam_fp_key_clean_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_bdfam_fp_key_clean_data ON public.t_core_analytics__breakdown_daily_famiglia_fp USING btree (btrim(translate(entity_key_lc, chr(160), ' '::text)), data);


--
-- Name: idx_t_cat_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_cat_data ON public.t_core_analytics__series_daily_categoria USING btree (data);


--
-- Name: idx_t_cat_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_cat_key_data ON public.t_core_analytics__series_daily_categoria USING btree (entity_key, data);


--
-- Name: idx_t_cat_lc_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_cat_lc_key_data ON public.t_core_analytics__series_daily_categoria USING btree (lower(entity_key), data);


--
-- Name: idx_t_dashboard_sales_daily_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_dashboard_sales_daily_data ON public.t_dashboard_sales_daily USING btree (data);


--
-- Name: idx_t_dashboard_sales_monthly_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_dashboard_sales_monthly_start ON public.t_dashboard_sales_monthly USING btree (period_start);


--
-- Name: idx_t_dashboard_sales_weekly_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_dashboard_sales_weekly_start ON public.t_dashboard_sales_weekly USING btree (period_start);


--
-- Name: idx_t_dashboard_sales_yearly_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_dashboard_sales_yearly_start ON public.t_dashboard_sales_yearly USING btree (period_start);


--
-- Name: idx_t_fam_lc_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_fam_lc_data ON public.t_core_analytics__series_daily_famiglia USING btree (lower(entity_key), data);


--
-- Name: idx_t_fas_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_fas_data ON public.t_core_analytics__series_daily_fascia USING btree (data);


--
-- Name: idx_t_fas_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_fas_key_data ON public.t_core_analytics__series_daily_fascia USING btree (entity_key, data);


--
-- Name: idx_t_fas_lc_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_fas_lc_key_data ON public.t_core_analytics__series_daily_fascia USING btree (lower(entity_key), data);


--
-- Name: idx_t_fp_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_fp_data ON public.t_core_analytics__series_daily_fascia_prezzo USING btree (data);


--
-- Name: idx_t_fp_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_fp_key_data ON public.t_core_analytics__series_daily_fascia_prezzo USING btree (entity_key, data);


--
-- Name: idx_t_fp_lc_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_t_fp_lc_key_data ON public.t_core_analytics__series_daily_fascia_prezzo USING btree (lower(entity_key), data);


--
-- Name: idx_y_cat_key_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_y_cat_key_date ON public.t_core_analytics__series_yearly_categoria USING btree (entity_key_lc, period_start);


--
-- Name: idx_y_fam_key_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_y_fam_key_date ON public.t_core_analytics__series_yearly_famiglia USING btree (entity_key_lc, period_start);


--
-- Name: idx_y_fas_key_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_y_fas_key_date ON public.t_core_analytics__series_yearly_fascia USING btree (entity_key_lc, period_start);


--
-- Name: idx_y_fp_key_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_y_fp_key_date ON public.t_core_analytics__series_yearly_fascia_prezzo USING btree (entity_key_lc, period_start);


--
-- Name: ix_fact_weekly_iso_year_week52_keys; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_fact_weekly_iso_year_week52_keys ON public.t_core_planner__fact_weekly USING btree (iso_year, week_52, fascia, categoria, famiglia, fascia_prezzo);


--
-- Name: ix_fact_weekly_week52_keys; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_fact_weekly_week52_keys ON public.t_core_planner__fact_weekly USING btree (week_52, fascia, categoria, famiglia, fascia_prezzo);


--
-- Name: ix_fact_weekly_weekstart; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_fact_weekly_weekstart ON public.t_core_planner__fact_weekly USING btree (week_start);


--
-- Name: ix_heat_cells_mode_level_week52; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_heat_cells_mode_level_week52 ON public.t_core_planner__heat_cells USING btree (mode, level, week_52);


--
-- Name: ix_heat_cells_mode_node_week52; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_heat_cells_mode_node_week52 ON public.t_core_planner__heat_cells USING btree (mode, node_id, week_52);


--
-- Name: ix_ops_monitor_snap_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ops_monitor_snap_ts ON public.t_ops_pipeline_monitor USING btree (snap_ts DESC);


--
-- Name: mv_cat_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mv_cat_data ON public.mv_core_analytics__series_daily_categoria USING btree (data);


--
-- Name: mv_cat_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mv_cat_key_data ON public.mv_core_analytics__series_daily_categoria USING btree (entity_key, data);


--
-- Name: mv_fas_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mv_fas_data ON public.mv_core_analytics__series_daily_fascia USING btree (data);


--
-- Name: mv_fas_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mv_fas_key_data ON public.mv_core_analytics__series_daily_fascia USING btree (entity_key, data);


--
-- Name: mv_fp_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mv_fp_data ON public.mv_core_analytics__series_daily_fascia_prezzo USING btree (data);


--
-- Name: mv_fp_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mv_fp_key_data ON public.mv_core_analytics__series_daily_fascia_prezzo USING btree (entity_key, data);


--
-- Name: t_fam_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX t_fam_data ON public.t_core_analytics__series_daily_famiglia USING btree (data);


--
-- Name: t_fam_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX t_fam_key_data ON public.t_core_analytics__series_daily_famiglia USING btree (entity_key, data);


--
-- Name: t_forecast_fam_key_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX t_forecast_fam_key_data ON public.t_forecast_fam_daily USING btree (entity_key, data);


--
-- Name: uq_alert_once_per_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_alert_once_per_day ON public.greenhouse_alerts USING btree (alert_day, code);


--
-- Name: ix_realtime_subscription_entity; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX ix_realtime_subscription_entity ON realtime.subscription USING btree (entity);


--
-- Name: messages_inserted_at_topic_index; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_inserted_at_topic_index ON ONLY realtime.messages USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: subscription_subscription_id_entity_filters_action_filter_key; Type: INDEX; Schema: realtime; Owner: -
--

CREATE UNIQUE INDEX subscription_subscription_id_entity_filters_action_filter_key ON realtime.subscription USING btree (subscription_id, entity, filters, action_filter);


--
-- Name: bname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);


--
-- Name: bucketid_objname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bucketid_objname ON storage.objects USING btree (bucket_id, name);


--
-- Name: buckets_analytics_unique_name_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX buckets_analytics_unique_name_idx ON storage.buckets_analytics USING btree (name) WHERE (deleted_at IS NULL);


--
-- Name: idx_multipart_uploads_list; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_multipart_uploads_list ON storage.s3_multipart_uploads USING btree (bucket_id, key, created_at);


--
-- Name: idx_objects_bucket_id_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_bucket_id_name ON storage.objects USING btree (bucket_id, name COLLATE "C");


--
-- Name: idx_objects_bucket_id_name_lower; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_bucket_id_name_lower ON storage.objects USING btree (bucket_id, lower(name) COLLATE "C");


--
-- Name: name_prefix_search; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);


--
-- Name: vector_indexes_name_bucket_id_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX vector_indexes_name_bucket_id_idx ON storage.vector_indexes USING btree (name, bucket_id);


--
-- Name: greenhouse_sales_family_daily_fact trg_clean_famiglia_fact; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_clean_famiglia_fact BEFORE INSERT OR UPDATE OF famiglia ON public.greenhouse_sales_family_daily_fact FOR EACH ROW EXECUTE FUNCTION public.trg_clean_famiglia_fact();


--
-- Name: greenhouse_series_list_fact trg_clean_famiglia_series_list; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_clean_famiglia_series_list BEFORE INSERT OR UPDATE OF famiglia ON public.greenhouse_series_list_fact FOR EACH ROW EXECUTE FUNCTION public.trg_clean_famiglia_series_list();


--
-- Name: ops_parquet_export_state trg_ops_parquet_export_state_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ops_parquet_export_state_touch BEFORE UPDATE ON public.ops_parquet_export_state FOR EACH ROW EXECUTE FUNCTION public._touch_updated_at();


--
-- Name: subscription tr_check_filters; Type: TRIGGER; Schema: realtime; Owner: -
--

CREATE TRIGGER tr_check_filters BEFORE INSERT OR UPDATE ON realtime.subscription FOR EACH ROW EXECUTE FUNCTION realtime.subscription_check_filters();


--
-- Name: buckets enforce_bucket_name_length_trigger; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();


--
-- Name: buckets protect_buckets_delete; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_buckets_delete BEFORE DELETE ON storage.buckets FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects protect_objects_delete; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_objects_delete BEFORE DELETE ON storage.objects FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects update_objects_updated_at; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();


--
-- Name: identities identities_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: mfa_challenges mfa_challenges_auth_factor_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_auth_factor_id_fkey FOREIGN KEY (factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE;


--
-- Name: mfa_factors mfa_factors_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: one_time_tokens one_time_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: saml_providers saml_providers_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_flow_state_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_flow_state_id_fkey FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_oauth_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_oauth_client_id_fkey FOREIGN KEY (oauth_client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sso_domains sso_domains_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: t_etl_steps t_etl_steps_run_id_fkey; Type: FK CONSTRAINT; Schema: etl; Owner: -
--

ALTER TABLE ONLY etl.t_etl_steps
    ADD CONSTRAINT t_etl_steps_run_id_fkey FOREIGN KEY (run_id) REFERENCES etl.t_etl_runs(run_id) ON DELETE CASCADE;


--
-- Name: class_model_map_v1 class_model_map_v1_model_code_fkey; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.class_model_map_v1
    ADD CONSTRAINT class_model_map_v1_model_code_fkey FOREIGN KEY (model_code) REFERENCES ml_forecast.model_catalog_v1(model_code);


--
-- Name: family_model_benchmark_v1 family_model_benchmark_v1_model_code_fkey; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_benchmark_v1
    ADD CONSTRAINT family_model_benchmark_v1_model_code_fkey FOREIGN KEY (model_code) REFERENCES ml_forecast.model_catalog_v1(model_code);


--
-- Name: family_model_benchmark_v1 family_model_benchmark_v1_run_id_fkey; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_benchmark_v1
    ADD CONSTRAINT family_model_benchmark_v1_run_id_fkey FOREIGN KEY (run_id) REFERENCES ml_forecast.family_benchmark_run_v1(run_id) ON DELETE CASCADE;


--
-- Name: family_model_state_v1 family_model_state_v1_last_predict_run_id_fkey; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_state_v1
    ADD CONSTRAINT family_model_state_v1_last_predict_run_id_fkey FOREIGN KEY (last_predict_run_id) REFERENCES ml_ops.pipeline_run_log_v1(run_id) ON DELETE SET NULL;


--
-- Name: family_model_state_v1 family_model_state_v1_last_train_run_id_fkey; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_state_v1
    ADD CONSTRAINT family_model_state_v1_last_train_run_id_fkey FOREIGN KEY (last_train_run_id) REFERENCES ml_ops.pipeline_run_log_v1(run_id) ON DELETE SET NULL;


--
-- Name: family_model_state_v1 family_model_state_v1_model_code_fkey; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_state_v1
    ADD CONSTRAINT family_model_state_v1_model_code_fkey FOREIGN KEY (model_code) REFERENCES ml_forecast.model_catalog_v1(model_code);


--
-- Name: family_model_assignment_v1 fk_assignment_model_code; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_assignment_v1
    ADD CONSTRAINT fk_assignment_model_code FOREIGN KEY (model_code) REFERENCES ml_forecast.model_catalog_v1(model_code);


--
-- Name: family_model_suggestion_benchmark_v1 fk_suggestion_benchmark_model; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.family_model_suggestion_benchmark_v1
    ADD CONSTRAINT fk_suggestion_benchmark_model FOREIGN KEY (model_code) REFERENCES ml_forecast.model_catalog_v1(model_code);


--
-- Name: model_engine_map_v1 model_engine_map_v1_current_execution_engine_fkey; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.model_engine_map_v1
    ADD CONSTRAINT model_engine_map_v1_current_execution_engine_fkey FOREIGN KEY (current_execution_engine) REFERENCES ml_forecast.execution_engine_catalog_v1(execution_engine);


--
-- Name: model_engine_map_v1 model_engine_map_v1_target_execution_engine_fkey; Type: FK CONSTRAINT; Schema: ml_forecast; Owner: -
--

ALTER TABLE ONLY ml_forecast.model_engine_map_v1
    ADD CONSTRAINT model_engine_map_v1_target_execution_engine_fkey FOREIGN KEY (target_execution_engine) REFERENCES ml_forecast.execution_engine_catalog_v1(execution_engine);


--
-- Name: family_run_log_v1 family_run_log_v1_pipeline_run_id_fkey; Type: FK CONSTRAINT; Schema: ml_ops; Owner: -
--

ALTER TABLE ONLY ml_ops.family_run_log_v1
    ADD CONSTRAINT family_run_log_v1_pipeline_run_id_fkey FOREIGN KEY (pipeline_run_id) REFERENCES ml_ops.pipeline_run_log_v1(run_id) ON DELETE SET NULL;


--
-- Name: objects objects_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE;


--
-- Name: vector_indexes vector_indexes_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets_vectors(id);


--
-- Name: audit_log_entries; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.audit_log_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: flow_state; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.flow_state ENABLE ROW LEVEL SECURITY;

--
-- Name: identities; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.identities ENABLE ROW LEVEL SECURITY;

--
-- Name: instances; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.instances ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_amr_claims; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_amr_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_challenges; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_challenges ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_factors; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_factors ENABLE ROW LEVEL SECURITY;

--
-- Name: one_time_tokens; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.one_time_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_providers; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.saml_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_relay_states; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.saml_relay_states ENABLE ROW LEVEL SECURITY;

--
-- Name: schema_migrations; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.schema_migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_domains; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sso_domains ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_providers; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sso_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;

--
-- Name: greenhouse_products_normalized; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.greenhouse_products_normalized ENABLE ROW LEVEL SECURITY;

--
-- Name: greenhouse_sales_raw; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.greenhouse_sales_raw ENABLE ROW LEVEL SECURITY;

--
-- Name: messages; Type: ROW SECURITY; Schema: realtime; Owner: -
--

ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_analytics; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets_analytics ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_vectors; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets_vectors ENABLE ROW LEVEL SECURITY;

--
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: vector_indexes; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.vector_indexes ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION supabase_realtime WITH (publish = 'insert, update, delete, truncate');


--
-- Name: supabase_realtime greenhouse_sales_raw; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.greenhouse_sales_raw;


--
-- Name: issue_graphql_placeholder; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop
         WHEN TAG IN ('DROP EXTENSION')
   EXECUTE FUNCTION extensions.set_graphql_placeholder();


--
-- Name: issue_pg_cron_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();


--
-- Name: issue_pg_graphql_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end
         WHEN TAG IN ('CREATE FUNCTION')
   EXECUTE FUNCTION extensions.grant_pg_graphql_access();


--
-- Name: issue_pg_net_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_net_access();


--
-- Name: pgrst_ddl_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_ddl_watch ON ddl_command_end
   EXECUTE FUNCTION extensions.pgrst_ddl_watch();


--
-- Name: pgrst_drop_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_drop_watch ON sql_drop
   EXECUTE FUNCTION extensions.pgrst_drop_watch();


--
-- PostgreSQL database dump complete
--

\unrestrict ZuYoL18kYYYOlnoyZ34yiO5ALxPXDJRURYogWJ59vPtHrgXrOaN050s8Eg0qLLn

