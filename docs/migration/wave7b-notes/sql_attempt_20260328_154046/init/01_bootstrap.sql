-- GreenBrain Client Runtime — Postgres Init Script
-- Wave 7A: infrastructure marker only.
--
-- This script runs once on first postgres container startup (empty data volume).
-- It does NOT create any business schema — that is Wave 7B.
--
-- Business endpoints will return HTTP 500 until full schema is applied in Wave 7B.
-- /health and /health/db will return OK regardless of schema state.
--
-- To verify this ran:
--   docker exec -it <postgres_container> psql -U greenbrain -d greenbrain \
--     -c "SELECT * FROM _runtime_bootstrap;"

CREATE TABLE IF NOT EXISTS _runtime_bootstrap (
    id          SERIAL PRIMARY KEY,
    wave        TEXT        NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    note        TEXT
);

INSERT INTO _runtime_bootstrap (wave, note)
VALUES (
    'wave-7a',
    'infrastructure bootstrap: DB connection verified, schema DDL deferred to Wave 7B'
);
