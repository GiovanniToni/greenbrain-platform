-- GreenBrain Client Runtime — Wave 7B.2-J Planner Current Week
--
-- STATUS: PLANNED
--
-- Scope: exactly 1 endpoint:
--   /api/v1/planner/current-week
--
-- Backend RPC:
--   core_planner__get_current_week52()
--
-- Strategy:
--   SAFE LOCAL STUB (JSONB function)
--
-- Objects:
--   1 function
--
-- No tables
-- No views
--

SET search_path = public;

CREATE OR REPLACE FUNCTION public.core_planner__get_current_week52()
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
SELECT jsonb_build_object(
    'today', CURRENT_DATE,
    'week_52', EXTRACT(WEEK FROM CURRENT_DATE)::int,
    'iso_year', EXTRACT(ISOYEAR FROM CURRENT_DATE)::int,
    'week_start', date_trunc('week', CURRENT_DATE)::date
);
$$;

