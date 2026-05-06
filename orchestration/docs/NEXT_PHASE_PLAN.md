# GreenBrain — Orchestration Migration Next Phase

## Current state

Canonical control plane exists under:

- orchestration/systemd
- orchestration/jobs
- orchestration/scripts
- orchestration/validators
- orchestration/docs

Compatibility mirrors still exist under:

- infra/systemd
- apps/ml-worker/jobs/*
- infra/scripts/bin/*

Current production runtime still uses compatibility locations.

---

## Goal

Move GreenBrain toward:

- orchestration as single source of truth
- infra/systemd as deployment mirror only
- apps/ml-worker/jobs wrappers minimized
- unified operational commands
- deterministic orchestration governance

---

## Safe migration strategy

### Phase 1 — COMPLETED
- Create orchestration control plane
- Add validators
- Add runtime doctor/status
- Add sync scripts
- Mark legacy wrappers deprecated

### Phase 2 — NEXT
- Make orchestration authoritative
- Sync outward to infra/apps
- Add deploy helper
- Add orchestration README
- Add health snapshot command

### Phase 3 — LATER
- Move remaining runtime wrappers to orchestration
- Reduce duplicated shell logic
- Introduce orchestration/lib
- Introduce orchestration/config

### Phase 4 — FINAL
- Optional removal of legacy wrappers
- Optional removal of duplicate mirrors
- Fully declarative orchestration model

---

## Important rule

No live runtime path changes without:
1. validation
2. syntax checks
3. drift checks
4. systemd verification
5. safe rollback path
