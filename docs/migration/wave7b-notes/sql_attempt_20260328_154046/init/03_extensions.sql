-- GreenBrain Client Runtime — PostgreSQL extensions
-- Extracted from Supabase/local schema snapshot (sql/schema/current-schema.sql)
-- Wave 7B — DO NOT hand-edit; re-run extract-schema.py to regenerate
--
-- Apply order: 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
-- (tables before views, views before functions)
--
--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;

