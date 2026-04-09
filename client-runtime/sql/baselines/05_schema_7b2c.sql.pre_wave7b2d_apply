-- GreenBrain Client Runtime — Wave 7B.2-C Dashboard Reorder Suggestions
--
-- STATUS: PLANNED — not yet applied to client-runtime postgres
--
-- Scope: exactly 1 endpoint:
--   /api/v1/dashboard/reorder-suggestions → dashboard__reorder_suggestions_top
--
-- Object count: 1
--   1 view  (dashboard__reorder_suggestions_top)
--
-- Prerequisites (must already exist before applying this file):
--   Wave 7B.2-B: greenhouse_order_suggestions_enriched_v2
--
-- No new tables. No functions. No extensions.
-- All dependencies already present in client-runtime after Wave 7B.2-B.
--
-- View definition extracted VERBATIM from sql/schema/current-schema.sql.
-- The only change from dev: COALESCE wrappers in the ORDER BY are preserved
-- exactly as written in the source.
--
-- Expected behaviour with empty backing tables:
--   greenhouse_order_suggestions_enriched_v2 returns 0 rows (empty)
--   → dashboard__reorder_suggestions_top returns 0 rows
--   → endpoint returns HTTP 200 {"count": 0, "items": []}
--

SET search_path = public;


-- ============================================================
-- SECTION 1: VIEW — dashboard__reorder_suggestions_top
-- Thin filter+projection over greenhouse_order_suggestions_enriched_v2.
-- Restricts to rows where qty_da_ordinare > 0 and caps at 200 rows.
-- Referenced directly by dashboard.py with a plain SELECT (no RPC).
-- Extracted VERBATIM from sql/schema/current-schema.sql.
-- ============================================================

CREATE OR REPLACE VIEW public.dashboard__reorder_suggestions_top AS
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
     WHERE coalesce(qty_da_ordinare, 0) > 0
     ORDER BY coalesce(rischio_stockout_prima_di_arrivo, false) DESC,
              coalesce(qty_da_ordinare, 0)   DESC,
              coalesce(qty_giacenza, 0)       ASC
     LIMIT 200;


-- ============================================================
-- END OF WAVE 7B.2-C SCHEMA
-- Object counts:
--   Views:  1  (dashboard__reorder_suggestions_top)
--   Total:  1
-- ============================================================
