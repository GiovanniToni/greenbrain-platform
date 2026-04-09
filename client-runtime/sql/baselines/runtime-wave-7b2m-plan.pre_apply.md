# Runtime Wave 7B.2-M — Series-Breakdown Business Validation

## Goal
Validate /api/v1/analytics/series-breakdown with real non-empty deterministic data,
without changing backend logic or expanding schema.

## Scope
- seed minimal deterministic data for famiglia / categoria / fascia
- validate day / week / month / year behavior
- verify whether returned rows are semantically acceptable
- classify endpoint as:
  - STUB
  - REAL / PARTIALLY-VALIDATED
  - REAL / BUSINESS-VALIDATED

## No-go
- no live stack changes
- no shadow stack changes
- no frontend work
- no backend rewrites
- no new SQL objects unless strictly necessary

## Exit criteria
- non-empty output observed for at least one entity
- granularity day/week/month/year tested
- endpoint matrix updated coherently
