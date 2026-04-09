# Runtime Wave 7B.2-L — Compare-Series Semantic Classification

## Goal
Classify the observed runtime semantics of /api/v1/analytics/compare-series
without changing backend logic or schema.

## Scope
- validate observed behavior for famiglia across multi-fascia data
- decide whether per-date multi-row output is acceptable
- document accepted semantics or deferred correction

## No-go
- no backend rewrites
- no schema expansion
- no frontend work
- no live stack changes
- no shadow stack changes

## Decision question
When entity_type=famiglia, should compare-series:
1. return one row per date aggregated across fascia_prezzo
or
2. return multiple rows per date if multiple fascia_prezzo buckets exist?

## Exit criteria
- observed behavior frozen in baseline
- semantic status explicitly classified
- endpoint matrix updated coherently
