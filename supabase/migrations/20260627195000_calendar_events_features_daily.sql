-- GreenBrain calendar/event feature store for ML parquet v2.
--
-- Goals:
-- - keep public.greenhouse_holidays as legacy/source seed
-- - add normalized event store public.greenhouse_calendar_events
-- - add daily feature store public.greenhouse_calendar_features_daily
-- - preserve old compatibility columns used by v1 parquet/model:
--   is_holiday, holiday_name, dow, week_num, month_num, year_num
-- - add richer local/commercial/garden calendar signals for Feature Builder V2
--
-- This migration intentionally does NOT modify greenhouse_forecast_features_dense.

CREATE TABLE IF NOT EXISTS public.greenhouse_calendar_events (
  event_id bigserial PRIMARY KEY,
  event_name text NOT NULL,
  event_slug text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  event_type text NOT NULL,
  event_scope text NOT NULL,
  location_name text NULL,
  location_scope text NULL,
  is_public_holiday boolean NOT NULL DEFAULT false,
  is_school_related boolean NOT NULL DEFAULT false,
  is_local_event boolean NOT NULL DEFAULT false,
  is_commercial_event boolean NOT NULL DEFAULT false,
  is_garden_relevant boolean NOT NULL DEFAULT false,
  expected_impact text NULL,
  impact_score numeric NOT NULL DEFAULT 0,
  pre_window_days integer NOT NULL DEFAULT 0,
  post_window_days integer NOT NULL DEFAULT 0,
  source_table text NULL,
  source_key text NULL,
  source_note text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT greenhouse_calendar_events_date_check CHECK (end_date >= start_date),
  CONSTRAINT greenhouse_calendar_events_impact_score_check CHECK (impact_score >= 0 AND impact_score <= 100),
  CONSTRAINT greenhouse_calendar_events_window_check CHECK (pre_window_days >= 0 AND post_window_days >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_greenhouse_calendar_events_source
  ON public.greenhouse_calendar_events(source_table, source_key)
  WHERE source_table IS NOT NULL AND source_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_greenhouse_calendar_events_dates
  ON public.greenhouse_calendar_events(start_date, end_date);

CREATE INDEX IF NOT EXISTS idx_greenhouse_calendar_events_type_scope
  ON public.greenhouse_calendar_events(event_type, event_scope);

CREATE INDEX IF NOT EXISTS idx_greenhouse_calendar_events_flags
  ON public.greenhouse_calendar_events(is_public_holiday, is_local_event, is_garden_relevant);

CREATE TABLE IF NOT EXISTS public.greenhouse_calendar_features_daily (
  data date PRIMARY KEY,

  dow integer NOT NULL,
  week_num integer NOT NULL,
  month_num integer NOT NULL,
  year_num integer NOT NULL,
  day_of_year integer NOT NULL,

  doy_sin numeric NOT NULL,
  doy_cos numeric NOT NULL,
  dow_sin numeric NOT NULL,
  dow_cos numeric NOT NULL,

  is_weekend boolean NOT NULL,
  is_month_start boolean NOT NULL,
  is_month_end boolean NOT NULL,

  is_holiday boolean NOT NULL DEFAULT false,
  holiday_name text NULL,

  is_national_holiday boolean NOT NULL DEFAULT false,
  is_local_holiday boolean NOT NULL DEFAULT false,
  is_local_event boolean NOT NULL DEFAULT false,
  is_commercial_event boolean NOT NULL DEFAULT false,
  is_garden_relevant_event boolean NOT NULL DEFAULT false,

  event_count_total integer NOT NULL DEFAULT 0,
  event_names text NULL,
  event_types text NULL,

  event_impact_score numeric NOT NULL DEFAULT 0,
  max_event_impact_score numeric NOT NULL DEFAULT 0,

  is_pre_holiday boolean NOT NULL DEFAULT false,
  is_post_holiday boolean NOT NULL DEFAULT false,
  is_pre_local_event boolean NOT NULL DEFAULT false,
  is_post_local_event boolean NOT NULL DEFAULT false,

  days_to_next_holiday integer NULL,
  days_since_prev_holiday integer NULL,
  days_to_next_local_event integer NULL,
  days_since_prev_local_event integer NULL,

  retail_season_code text NULL,
  garden_season_code text NULL,

  is_spring_peak boolean NOT NULL DEFAULT false,
  is_summer_peak boolean NOT NULL DEFAULT false,
  is_autumn_peak boolean NOT NULL DEFAULT false,
  is_christmas_season boolean NOT NULL DEFAULT false,
  is_easter_window boolean NOT NULL DEFAULT false,
  is_mother_day_window boolean NOT NULL DEFAULT false,
  is_valentine_window boolean NOT NULL DEFAULT false,
  is_women_day_window boolean NOT NULL DEFAULT false,
  is_saints_window boolean NOT NULL DEFAULT false,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_greenhouse_calendar_features_year_month
  ON public.greenhouse_calendar_features_daily(year_num, month_num);

CREATE INDEX IF NOT EXISTS idx_greenhouse_calendar_features_holidays
  ON public.greenhouse_calendar_features_daily(is_holiday, is_local_event, is_garden_relevant_event);

CREATE INDEX IF NOT EXISTS idx_greenhouse_calendar_features_season
  ON public.greenhouse_calendar_features_daily(garden_season_code, retail_season_code);

CREATE OR REPLACE FUNCTION public.refresh_greenhouse_calendar_features_daily(
  p_from date,
  p_to date
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_rows integer := 0;
BEGIN
  IF p_from IS NULL OR p_to IS NULL THEN
    RAISE EXCEPTION 'refresh_greenhouse_calendar_features_daily requires non-null p_from and p_to';
  END IF;

  IF p_to < p_from THEN
    RAISE EXCEPTION 'refresh_greenhouse_calendar_features_daily invalid range: % > %', p_from, p_to;
  END IF;

  INSERT INTO public.greenhouse_calendar_features_daily (
    data,
    dow,
    week_num,
    month_num,
    year_num,
    day_of_year,
    doy_sin,
    doy_cos,
    dow_sin,
    dow_cos,
    is_weekend,
    is_month_start,
    is_month_end,
    is_holiday,
    holiday_name,
    is_national_holiday,
    is_local_holiday,
    is_local_event,
    is_commercial_event,
    is_garden_relevant_event,
    event_count_total,
    event_names,
    event_types,
    event_impact_score,
    max_event_impact_score,
    is_pre_holiday,
    is_post_holiday,
    is_pre_local_event,
    is_post_local_event,
    days_to_next_holiday,
    days_since_prev_holiday,
    days_to_next_local_event,
    days_since_prev_local_event,
    retail_season_code,
    garden_season_code,
    is_spring_peak,
    is_summer_peak,
    is_autumn_peak,
    is_christmas_season,
    is_easter_window,
    is_mother_day_window,
    is_valentine_window,
    is_women_day_window,
    is_saints_window,
    updated_at
  )
  WITH days AS (
    SELECT gs::date AS data
    FROM generate_series(p_from, p_to, interval '1 day') AS gs
  ),
  exact_events AS (
    SELECT
      d.data,
      COUNT(e.*)::int AS event_count_total,
      string_agg(e.event_name, ' | ' ORDER BY e.event_name) AS event_names,
      string_agg(DISTINCT e.event_type, ' | ' ORDER BY e.event_type) AS event_types,
      COALESCE(SUM(e.impact_score), 0)::numeric AS event_impact_score,
      COALESCE(MAX(e.impact_score), 0)::numeric AS max_event_impact_score,
      BOOL_OR(e.is_public_holiday) AS is_holiday,
      string_agg(e.event_name, ' | ' ORDER BY e.event_name) FILTER (WHERE e.is_public_holiday) AS holiday_name,
      BOOL_OR(e.event_scope = 'national' AND e.is_public_holiday) AS is_national_holiday,
      BOOL_OR(e.event_type = 'local_holiday') AS is_local_holiday,
      BOOL_OR(e.is_local_event) AS is_local_event,
      BOOL_OR(e.is_commercial_event) AS is_commercial_event,
      BOOL_OR(e.is_garden_relevant) AS is_garden_relevant_event
    FROM days d
    LEFT JOIN public.greenhouse_calendar_events e
      ON d.data BETWEEN e.start_date AND e.end_date
    GROUP BY d.data
  ),
  window_flags AS (
    SELECT
      d.data,
      EXISTS (
        SELECT 1
        FROM public.greenhouse_calendar_events e
        WHERE e.is_public_holiday
          AND d.data < e.start_date
          AND d.data >= e.start_date - e.pre_window_days
      ) AS is_pre_holiday,
      EXISTS (
        SELECT 1
        FROM public.greenhouse_calendar_events e
        WHERE e.is_public_holiday
          AND d.data > e.end_date
          AND d.data <= e.end_date + e.post_window_days
      ) AS is_post_holiday,
      EXISTS (
        SELECT 1
        FROM public.greenhouse_calendar_events e
        WHERE e.is_local_event
          AND d.data < e.start_date
          AND d.data >= e.start_date - e.pre_window_days
      ) AS is_pre_local_event,
      EXISTS (
        SELECT 1
        FROM public.greenhouse_calendar_events e
        WHERE e.is_local_event
          AND d.data > e.end_date
          AND d.data <= e.end_date + e.post_window_days
      ) AS is_post_local_event,
      (
        SELECT MIN(e.start_date - d.data)::int
        FROM public.greenhouse_calendar_events e
        WHERE e.is_public_holiday
          AND e.start_date >= d.data
      ) AS days_to_next_holiday,
      (
        SELECT MIN(d.data - e.end_date)::int
        FROM public.greenhouse_calendar_events e
        WHERE e.is_public_holiday
          AND e.end_date <= d.data
      ) AS days_since_prev_holiday,
      (
        SELECT MIN(e.start_date - d.data)::int
        FROM public.greenhouse_calendar_events e
        WHERE e.is_local_event
          AND e.start_date >= d.data
      ) AS days_to_next_local_event,
      (
        SELECT MIN(d.data - e.end_date)::int
        FROM public.greenhouse_calendar_events e
        WHERE e.is_local_event
          AND e.end_date <= d.data
      ) AS days_since_prev_local_event,
      EXISTS (
        SELECT 1
        FROM public.greenhouse_calendar_events e
        WHERE lower(e.event_name) LIKE '%pasqua%'
          AND d.data BETWEEN e.start_date - 14 AND e.end_date + 7
      ) AS is_easter_window
    FROM days d
  ),
  base AS (
    SELECT
      d.data,
      EXTRACT(DOW FROM d.data)::int AS dow,
      EXTRACT(WEEK FROM d.data)::int AS week_num,
      EXTRACT(MONTH FROM d.data)::int AS month_num,
      EXTRACT(YEAR FROM d.data)::int AS year_num,
      EXTRACT(DOY FROM d.data)::int AS day_of_year
    FROM days d
  )
  SELECT
    b.data,
    b.dow,
    b.week_num,
    b.month_num,
    b.year_num,
    b.day_of_year,
    sin(2 * pi() * b.day_of_year / 365.0)::numeric AS doy_sin,
    cos(2 * pi() * b.day_of_year / 365.0)::numeric AS doy_cos,
    sin(2 * pi() * b.dow / 7.0)::numeric AS dow_sin,
    cos(2 * pi() * b.dow / 7.0)::numeric AS dow_cos,
    (b.dow IN (0, 6)) AS is_weekend,
    (EXTRACT(DAY FROM b.data)::int <= 3) AS is_month_start,
    (EXTRACT(DAY FROM b.data)::int >= 28) AS is_month_end,

    COALESCE(x.is_holiday, false) AS is_holiday,
    x.holiday_name,

    COALESCE(x.is_national_holiday, false) AS is_national_holiday,
    COALESCE(x.is_local_holiday, false) AS is_local_holiday,
    COALESCE(x.is_local_event, false) AS is_local_event,
    COALESCE(x.is_commercial_event, false) AS is_commercial_event,
    COALESCE(x.is_garden_relevant_event, false) AS is_garden_relevant_event,

    COALESCE(x.event_count_total, 0) AS event_count_total,
    x.event_names,
    x.event_types,

    COALESCE(x.event_impact_score, 0) AS event_impact_score,
    COALESCE(x.max_event_impact_score, 0) AS max_event_impact_score,

    COALESCE(w.is_pre_holiday, false) AS is_pre_holiday,
    COALESCE(w.is_post_holiday, false) AS is_post_holiday,
    COALESCE(w.is_pre_local_event, false) AS is_pre_local_event,
    COALESCE(w.is_post_local_event, false) AS is_post_local_event,

    w.days_to_next_holiday,
    w.days_since_prev_holiday,
    w.days_to_next_local_event,
    w.days_since_prev_local_event,

    CASE
      WHEN b.month_num IN (11, 12, 1) THEN 'winter'
      WHEN b.month_num IN (2, 3, 4, 5) THEN 'spring'
      WHEN b.month_num IN (6, 7, 8) THEN 'summer'
      WHEN b.month_num IN (9, 10) THEN 'autumn'
      ELSE 'unknown'
    END AS retail_season_code,

    CASE
      WHEN b.month_num IN (3, 4, 5) THEN 'spring_garden_peak'
      WHEN b.month_num IN (6, 7) THEN 'summer_garden'
      WHEN b.month_num IN (9, 10) THEN 'autumn_garden'
      WHEN b.month_num IN (11, 12) THEN 'christmas_garden'
      ELSE 'off_peak'
    END AS garden_season_code,

    (b.month_num IN (3, 4, 5)) AS is_spring_peak,
    (b.month_num IN (6, 7, 8)) AS is_summer_peak,
    (b.month_num IN (9, 10)) AS is_autumn_peak,
    (
      (b.month_num = 12)
      OR (b.month_num = 1 AND EXTRACT(DAY FROM b.data)::int <= 6)
    ) AS is_christmas_season,
    COALESCE(w.is_easter_window, false) AS is_easter_window,
    (
      b.month_num = 5
      AND EXTRACT(DAY FROM b.data)::int BETWEEN 1 AND 14
    ) AS is_mother_day_window,
    (
      b.month_num = 2
      AND EXTRACT(DAY FROM b.data)::int BETWEEN 7 AND 14
    ) AS is_valentine_window,
    (
      b.month_num = 3
      AND EXTRACT(DAY FROM b.data)::int BETWEEN 1 AND 8
    ) AS is_women_day_window,
    (
      (b.month_num = 10 AND EXTRACT(DAY FROM b.data)::int >= 25)
      OR (b.month_num = 11 AND EXTRACT(DAY FROM b.data)::int <= 2)
    ) AS is_saints_window,

    now() AS updated_at
  FROM base b
  LEFT JOIN exact_events x ON x.data = b.data
  LEFT JOIN window_flags w ON w.data = b.data
  ON CONFLICT (data) DO UPDATE SET
    dow = EXCLUDED.dow,
    week_num = EXCLUDED.week_num,
    month_num = EXCLUDED.month_num,
    year_num = EXCLUDED.year_num,
    day_of_year = EXCLUDED.day_of_year,
    doy_sin = EXCLUDED.doy_sin,
    doy_cos = EXCLUDED.doy_cos,
    dow_sin = EXCLUDED.dow_sin,
    dow_cos = EXCLUDED.dow_cos,
    is_weekend = EXCLUDED.is_weekend,
    is_month_start = EXCLUDED.is_month_start,
    is_month_end = EXCLUDED.is_month_end,
    is_holiday = EXCLUDED.is_holiday,
    holiday_name = EXCLUDED.holiday_name,
    is_national_holiday = EXCLUDED.is_national_holiday,
    is_local_holiday = EXCLUDED.is_local_holiday,
    is_local_event = EXCLUDED.is_local_event,
    is_commercial_event = EXCLUDED.is_commercial_event,
    is_garden_relevant_event = EXCLUDED.is_garden_relevant_event,
    event_count_total = EXCLUDED.event_count_total,
    event_names = EXCLUDED.event_names,
    event_types = EXCLUDED.event_types,
    event_impact_score = EXCLUDED.event_impact_score,
    max_event_impact_score = EXCLUDED.max_event_impact_score,
    is_pre_holiday = EXCLUDED.is_pre_holiday,
    is_post_holiday = EXCLUDED.is_post_holiday,
    is_pre_local_event = EXCLUDED.is_pre_local_event,
    is_post_local_event = EXCLUDED.is_post_local_event,
    days_to_next_holiday = EXCLUDED.days_to_next_holiday,
    days_since_prev_holiday = EXCLUDED.days_since_prev_holiday,
    days_to_next_local_event = EXCLUDED.days_to_next_local_event,
    days_since_prev_local_event = EXCLUDED.days_since_prev_local_event,
    retail_season_code = EXCLUDED.retail_season_code,
    garden_season_code = EXCLUDED.garden_season_code,
    is_spring_peak = EXCLUDED.is_spring_peak,
    is_summer_peak = EXCLUDED.is_summer_peak,
    is_autumn_peak = EXCLUDED.is_autumn_peak,
    is_christmas_season = EXCLUDED.is_christmas_season,
    is_easter_window = EXCLUDED.is_easter_window,
    is_mother_day_window = EXCLUDED.is_mother_day_window,
    is_valentine_window = EXCLUDED.is_valentine_window,
    is_women_day_window = EXCLUDED.is_women_day_window,
    is_saints_window = EXCLUDED.is_saints_window,
    updated_at = now();

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

INSERT INTO public.greenhouse_calendar_events (
  event_name,
  event_slug,
  start_date,
  end_date,
  event_type,
  event_scope,
  location_name,
  location_scope,
  is_public_holiday,
  is_school_related,
  is_local_event,
  is_commercial_event,
  is_garden_relevant,
  expected_impact,
  impact_score,
  pre_window_days,
  post_window_days,
  source_table,
  source_key,
  source_note
)
SELECT
  h.holiday_name AS event_name,
  lower(
    regexp_replace(
      regexp_replace(
        translate(
          h.holiday_name,
          'àáâãäåèéêëìíîïòóôõöùúûüçñÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÇÑ’''–—',
          'aaaaaaeeeeiiiiooooouuuucnAAAAAAEEEEIIIIOOOOOUUUUCN----'
        ),
        '[^a-zA-Z0-9]+',
        '-',
        'g'
      ),
      '(^-|-$)',
      '',
      'g'
    )
  ) || '-' || to_char(h.data, 'YYYYMMDD') AS event_slug,
  h.data AS start_date,
  h.data AS end_date,

  CASE
    WHEN lower(h.holiday_name) LIKE '%firenze%' THEN 'local_holiday'
    WHEN lower(h.holiday_name) LIKE '%pistoia%' OR lower(h.holiday_name) LIKE '%jacopo%' THEN 'local_holiday'
    WHEN lower(h.holiday_name) LIKE '%pasqua%'
      OR lower(h.holiday_name) LIKE '%angelo%'
      OR lower(h.holiday_name) LIKE '%pentecoste%'
      OR lower(h.holiday_name) LIKE '%natale%'
      OR lower(h.holiday_name) LIKE '%stefano%'
      OR lower(h.holiday_name) LIKE '%immacolata%'
      OR lower(h.holiday_name) LIKE '%epifania%'
    THEN 'religious_holiday'
    ELSE 'national_holiday'
  END AS event_type,

  CASE
    WHEN lower(h.holiday_name) LIKE '%firenze%' THEN 'municipal'
    WHEN lower(h.holiday_name) LIKE '%pistoia%' OR lower(h.holiday_name) LIKE '%jacopo%' THEN 'municipal'
    ELSE 'national'
  END AS event_scope,

  CASE
    WHEN lower(h.holiday_name) LIKE '%firenze%' THEN 'Firenze'
    WHEN lower(h.holiday_name) LIKE '%pistoia%' OR lower(h.holiday_name) LIKE '%jacopo%' THEN 'Pistoia'
    ELSE NULL
  END AS location_name,

  CASE
    WHEN lower(h.holiday_name) LIKE '%firenze%' THEN 'municipality'
    WHEN lower(h.holiday_name) LIKE '%pistoia%' OR lower(h.holiday_name) LIKE '%jacopo%' THEN 'municipality'
    ELSE NULL
  END AS location_scope,

  h.is_holiday AS is_public_holiday,
  false AS is_school_related,

  CASE
    WHEN lower(h.holiday_name) LIKE '%firenze%' THEN true
    WHEN lower(h.holiday_name) LIKE '%pistoia%' OR lower(h.holiday_name) LIKE '%jacopo%' THEN true
    ELSE false
  END AS is_local_event,

  false AS is_commercial_event,

  CASE
    WHEN lower(h.holiday_name) LIKE '%firenze%' THEN true
    WHEN lower(h.holiday_name) LIKE '%pistoia%' OR lower(h.holiday_name) LIKE '%jacopo%' THEN true
    WHEN lower(h.holiday_name) LIKE '%pasqua%' THEN true
    WHEN lower(h.holiday_name) LIKE '%angelo%' THEN true
    WHEN lower(h.holiday_name) LIKE '%pentecoste%' THEN true
    WHEN lower(h.holiday_name) LIKE '%natale%' THEN true
    WHEN lower(h.holiday_name) LIKE '%stefano%' THEN true
    WHEN lower(h.holiday_name) LIKE '%immacolata%' THEN true
    WHEN lower(h.holiday_name) LIKE '%epifania%' THEN true
    ELSE false
  END AS is_garden_relevant,

  CASE
    WHEN lower(h.holiday_name) LIKE '%natale%'
      OR lower(h.holiday_name) LIKE '%stefano%'
      OR lower(h.holiday_name) LIKE '%immacolata%'
      OR lower(h.holiday_name) LIKE '%epifania%'
    THEN 'christmas_season_effect'
    WHEN lower(h.holiday_name) LIKE '%pasqua%'
      OR lower(h.holiday_name) LIKE '%angelo%'
      OR lower(h.holiday_name) LIKE '%pentecoste%'
    THEN 'garden_peak_or_family_traffic'
    WHEN lower(h.holiday_name) LIKE '%firenze%'
      OR lower(h.holiday_name) LIKE '%pistoia%'
      OR lower(h.holiday_name) LIKE '%jacopo%'
    THEN 'local_calendar_effect'
    ELSE 'closed_or_low_sales'
  END AS expected_impact,

  CASE
    WHEN lower(h.holiday_name) LIKE '%natale%'
      OR lower(h.holiday_name) LIKE '%stefano%'
      OR lower(h.holiday_name) LIKE '%immacolata%'
      OR lower(h.holiday_name) LIKE '%epifania%'
    THEN 80
    WHEN lower(h.holiday_name) LIKE '%pasqua%'
      OR lower(h.holiday_name) LIKE '%angelo%'
      OR lower(h.holiday_name) LIKE '%pentecoste%'
    THEN 70
    WHEN lower(h.holiday_name) LIKE '%pistoia%' OR lower(h.holiday_name) LIKE '%jacopo%' THEN 45
    WHEN lower(h.holiday_name) LIKE '%firenze%' THEN 35
    WHEN lower(h.holiday_name) LIKE '%capodanno%' THEN 65
    ELSE 55
  END AS impact_score,

  CASE
    WHEN lower(h.holiday_name) LIKE '%natale%'
      OR lower(h.holiday_name) LIKE '%stefano%'
      OR lower(h.holiday_name) LIKE '%immacolata%'
      OR lower(h.holiday_name) LIKE '%epifania%'
    THEN 14
    WHEN lower(h.holiday_name) LIKE '%pasqua%'
      OR lower(h.holiday_name) LIKE '%angelo%'
      OR lower(h.holiday_name) LIKE '%pentecoste%'
    THEN 7
    WHEN lower(h.holiday_name) LIKE '%capodanno%' THEN 2
    ELSE 1
  END AS pre_window_days,

  CASE
    WHEN lower(h.holiday_name) LIKE '%natale%'
      OR lower(h.holiday_name) LIKE '%stefano%'
      OR lower(h.holiday_name) LIKE '%immacolata%'
      OR lower(h.holiday_name) LIKE '%epifania%'
    THEN 3
    WHEN lower(h.holiday_name) LIKE '%pasqua%'
      OR lower(h.holiday_name) LIKE '%angelo%'
      OR lower(h.holiday_name) LIKE '%pentecoste%'
    THEN 2
    WHEN lower(h.holiday_name) LIKE '%capodanno%' THEN 2
    ELSE 1
  END AS post_window_days,

  'public.greenhouse_holidays' AS source_table,
  h.data::text || '|' || COALESCE(h.holiday_name, '') AS source_key,
  'seeded from legacy greenhouse_holidays' AS source_note
FROM public.greenhouse_holidays h
ON CONFLICT DO NOTHING;


-- B3.1D generated recurring holiday rows for 2028-2035.
-- Rationale:
-- greenhouse_holidays currently seeds holidays only through 2027, while the
-- calendar feature store is generated through 2035. These rows keep future
-- ML calendar features complete without mutating the legacy source table.
WITH years AS (
  SELECT generate_series(2028, 2035)::int AS y
),
easter_a AS (
  SELECT
    y,
    (y % 19) AS a,
    (y / 100) AS b,
    (y % 100) AS c
  FROM years
),
easter_b AS (
  SELECT
    *,
    (b / 4) AS d,
    (b % 4) AS e,
    ((b + 8) / 25) AS f
  FROM easter_a
),
easter_c AS (
  SELECT
    *,
    ((b - f + 1) / 3) AS g
  FROM easter_b
),
easter_d AS (
  SELECT
    *,
    ((19 * a + b - d - g + 15) % 30) AS h,
    (c / 4) AS i,
    (c % 4) AS k
  FROM easter_c
),
easter_e AS (
  SELECT
    *,
    ((32 + 2 * e + 2 * i - h - k) % 7) AS l
  FROM easter_d
),
easter_f AS (
  SELECT
    *,
    ((a + 11 * h + 22 * l) / 451) AS m
  FROM easter_e
),
easter_dates AS (
  SELECT
    y,
    make_date(
      y,
      ((h + l - 7 * m + 114) / 31)::int,
      (((h + l - 7 * m + 114) % 31) + 1)::int
    ) AS easter_date
  FROM easter_f
),
fixed_events AS (
  SELECT y, make_date(y, 1, 1) AS event_date, 'Capodanno'::text AS event_name,
         'national_holiday'::text AS event_type, 'national'::text AS event_scope,
         NULL::text AS location_name, NULL::text AS location_scope,
         true AS is_public_holiday, false AS is_school_related, false AS is_local_event,
         false AS is_commercial_event, false AS is_garden_relevant,
         'closed_or_low_sales'::text AS expected_impact, 65::numeric AS impact_score,
         2 AS pre_window_days, 2 AS post_window_days
  FROM years

  UNION ALL SELECT y, make_date(y, 1, 6), 'Epifania',
         'religious_holiday', 'national', NULL, NULL,
         true, false, false, false, true,
         'christmas_season_effect', 80, 14, 3
  FROM years

  UNION ALL SELECT y, make_date(y, 4, 25), 'Festa della Liberazione',
         'national_holiday', 'national', NULL, NULL,
         true, false, false, false, false,
         'closed_or_low_sales', 55, 1, 1
  FROM years

  UNION ALL SELECT y, make_date(y, 5, 1), 'Festa del Lavoro',
         'national_holiday', 'national', NULL, NULL,
         true, false, false, false, false,
         'closed_or_low_sales', 55, 1, 1
  FROM years

  UNION ALL SELECT y, make_date(y, 6, 2), 'Festa della Repubblica',
         'national_holiday', 'national', NULL, NULL,
         true, false, false, false, false,
         'closed_or_low_sales', 55, 1, 1
  FROM years

  UNION ALL SELECT y, make_date(y, 6, 24), 'Firenze – San Giovanni (locale)',
         'local_holiday', 'municipal', 'Firenze', 'municipality',
         true, false, true, false, true,
         'local_calendar_effect', 35, 1, 1
  FROM years

  UNION ALL SELECT y, make_date(y, 7, 25), 'Pistoia – San Jacopo (locale)',
         'local_holiday', 'municipal', 'Pistoia', 'municipality',
         true, false, true, false, true,
         'local_calendar_effect', 45, 1, 1
  FROM years

  UNION ALL SELECT y, make_date(y, 8, 15), 'Ferragosto o Assunzione',
         'national_holiday', 'national', NULL, NULL,
         true, false, false, false, false,
         'closed_or_low_sales', 55, 1, 1
  FROM years

  UNION ALL SELECT y, make_date(y, 10, 4), 'San Francesco d''Assisi',
         'national_holiday', 'national', NULL, NULL,
         true, false, false, false, false,
         'closed_or_low_sales', 55, 1, 1
  FROM years

  UNION ALL SELECT y, make_date(y, 11, 1), 'Tutti i santi',
         'national_holiday', 'national', NULL, NULL,
         true, false, false, false, false,
         'closed_or_low_sales', 55, 1, 1
  FROM years

  UNION ALL SELECT y, make_date(y, 12, 8), 'Immacolata Concezione',
         'religious_holiday', 'national', NULL, NULL,
         true, false, false, false, true,
         'christmas_season_effect', 80, 14, 3
  FROM years

  UNION ALL SELECT y, make_date(y, 12, 25), 'Natale',
         'religious_holiday', 'national', NULL, NULL,
         true, false, false, false, true,
         'christmas_season_effect', 80, 14, 3
  FROM years

  UNION ALL SELECT y, make_date(y, 12, 26), 'Santo Stefano',
         'religious_holiday', 'national', NULL, NULL,
         true, false, false, false, true,
         'christmas_season_effect', 80, 14, 3
  FROM years
),
easter_events AS (
  SELECT y, easter_date AS event_date, 'Pasqua'::text AS event_name,
         'religious_holiday'::text AS event_type, 'national'::text AS event_scope,
         NULL::text AS location_name, NULL::text AS location_scope,
         true AS is_public_holiday, false AS is_school_related, false AS is_local_event,
         false AS is_commercial_event, true AS is_garden_relevant,
         'garden_peak_or_family_traffic'::text AS expected_impact, 70::numeric AS impact_score,
         7 AS pre_window_days, 2 AS post_window_days
  FROM easter_dates

  UNION ALL SELECT y, easter_date + 1, 'Lunedì dell''Angelo',
         'religious_holiday', 'national', NULL, NULL,
         true, false, false, false, true,
         'garden_peak_or_family_traffic', 70, 7, 2
  FROM easter_dates

  UNION ALL SELECT y, easter_date + 50, 'Lunedì di Pentecoste',
         'religious_holiday', 'national', NULL, NULL,
         true, false, false, false, true,
         'garden_peak_or_family_traffic', 70, 7, 2
  FROM easter_dates
),
future_events AS (
  SELECT * FROM fixed_events
  UNION ALL
  SELECT * FROM easter_events
)
INSERT INTO public.greenhouse_calendar_events (
  event_name,
  event_slug,
  start_date,
  end_date,
  event_type,
  event_scope,
  location_name,
  location_scope,
  is_public_holiday,
  is_school_related,
  is_local_event,
  is_commercial_event,
  is_garden_relevant,
  expected_impact,
  impact_score,
  pre_window_days,
  post_window_days,
  source_table,
  source_key,
  source_note
)
SELECT
  f.event_name,
  'generated-recurring-' || to_char(f.event_date, 'YYYYMMDD') || '-' || md5(f.event_name) AS event_slug,
  f.event_date,
  f.event_date,
  f.event_type,
  f.event_scope,
  f.location_name,
  f.location_scope,
  f.is_public_holiday,
  f.is_school_related,
  f.is_local_event,
  f.is_commercial_event,
  f.is_garden_relevant,
  f.expected_impact,
  f.impact_score,
  f.pre_window_days,
  f.post_window_days,
  'generated.recurring_holidays_2028_2035' AS source_table,
  f.event_date::text || '|' || f.event_name AS source_key,
  'generated by migration to complete calendar features through 2035' AS source_note
FROM future_events f
WHERE NOT EXISTS (
  SELECT 1
  FROM public.greenhouse_calendar_events e
  WHERE e.start_date = f.event_date
    AND e.end_date = f.event_date
    AND e.event_name = f.event_name
)
ON CONFLICT DO NOTHING;


SELECT public.refresh_greenhouse_calendar_features_daily('2009-01-01'::date, '2035-12-31'::date);

COMMENT ON TABLE public.greenhouse_calendar_events IS
  'Normalized calendar/event source table for GreenBrain ML feature generation. Seeded from greenhouse_holidays and extensible for local/commercial/garden events.';

COMMENT ON TABLE public.greenhouse_calendar_features_daily IS
  'One-row-per-day calendar feature store for ML parquet v2 generation. Includes compatibility columns plus richer local/event/seasonal signals.';

COMMENT ON FUNCTION public.refresh_greenhouse_calendar_features_daily(date, date) IS
  'Refreshes daily calendar features from greenhouse_calendar_events for the requested date range.';
