CREATE TABLE IF NOT EXISTS public.garden_center_settings (
    id         integer PRIMARY KEY DEFAULT 1,
    city       text NOT NULL DEFAULT '',
    lat        double precision,
    lon        double precision,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT garden_center_settings_singleton CHECK (id = 1)
);

INSERT INTO public.garden_center_settings (id, city, lat, lon)
VALUES (1, '', NULL, NULL)
ON CONFLICT (id) DO NOTHING;
