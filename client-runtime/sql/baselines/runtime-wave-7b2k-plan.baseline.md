# Runtime Wave 7B.2-K — Business Validation Pass 1

## Goal
Increase confidence in real runtime behavior without expanding schema or changing backend logic.

## Scope
- validate /api/v1/dashboard/reorder-suggestions with edge cases
- clarify /api/v1/analytics/compare-series observed semantics
- keep entity-summary as tree-only
- keep planner/ops/dashboard-kpis stubs as accepted support endpoints

## No-go
- no live stack changes
- no shadow stack changes
- no frontend work
- no bulk schema extraction
- no business logic rewrite
- no new SQL objects unless strictly necessary

## Validation focus

### 1. reorder-suggestions
Scenarios:
- high stock => no reorder
- zero stock => reorder
- low forecast => no reorder
- high forecast => reorder
- multi-family
- multi-fascia

### 2. compare-series
Questions:
- should famiglia aggregate all fascia_prezzo rows by date?
- or is per-fascia row behavior acceptable for current API contract?

### 3. entity-summary
Accepted current role:
- hierarchical navigation tree only
- quantities deferred

## Exit criteria
- reorder-suggestions tested on deterministic edge cases
- compare-series explicitly classified as acceptable or needing later correction
- updated endpoint matrix and validation plan
