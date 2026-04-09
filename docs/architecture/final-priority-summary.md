# GreenBrain — Final Priority Summary
> Concise operational reference for execution priority, confirmed decisions,
> and workstream sequencing.
> Updated: 2026-04-02.
> Canonical decision: `docs/architecture/final-platform-priority-and-access-decision.md`

---

## Execution Priority (in order)

| # | Workstream | Status |
|---|-----------|--------|
| 1 | **GreenBrain Platform completion** | Active — primary |
| 2 | **Brand and domain rollout** (`greenbrain.it`, `app.greenbrain.it`) | Confirmed — secondary |
| 3 | **Customer remote access** (`<slug>.greenbrain.it`) | Confirmed — tertiary; gated on #1 |

---

## Primary Workstream — Platform Completion

Required in this order:

1. Storage abstraction wiring in ML (`.bak_phase2b/2c`)
2. ML monorepo consolidation (shell scripts, `WorkingDirectory`, env)
3. Backend production Dockerfile (`apps/backend/Dockerfile`)
4. Frontend production Dockerfile (`apps/frontend/Dockerfile`)
5. FastAPI JWT auth replacing Supabase JS auth
6. Client-runtime Wave 7B.4 — ETL functions ported to local PostgreSQL
7. Client-local scheduler — pg_cron in Docker; ML cron/systemd
8. `install.sh` and `update.sh` for client-runtime

Plan: `docs/migration/dev-cloud-execution-plan.md` + `docs/client-runtime/client-local-product-plan.md`

---

## Secondary Workstream — Brand and Domain Rollout

**Allowed to plan now. Must not execute before platform is stable.**

- `greenbrain.it` → static public site
- `www.greenbrain.it` → 301 redirect to apex
- `app.greenbrain.it` → owner dev-cloud application (nginx + TLS + Certbot)

These steps do not block platform work and can be prepared in parallel,
but production rollout of `app.greenbrain.it` with FastAPI JWT requires auth
(step 5 above) to be complete.

Plan: `docs/deploy/phase-1-domain-rollout-plan.md`

---

## Tertiary Workstream — Customer Remote Access

**Must not start until all of the following are true:**

- [ ] GreenBrain Platform is complete
- [ ] Client-local V1 is installable (`install.sh` works cold)
- [ ] FastAPI JWT auth is live on customer installations
- [ ] ETL and ML run locally; analytics data is non-empty
- [ ] Frontend production build is complete (nginx, not Vite dev server)

Plan: `docs/deploy/phase-2-customer-remote-access-plan.md`

---

## Confirmed Domain Model (final, not subject to revision)

| Domain | Role |
|--------|------|
| `greenbrain.it` | Static public product / marketing site |
| `www.greenbrain.it` | Redirect to `greenbrain.it` |
| `app.greenbrain.it` | Owner dev-cloud application |
| `<slug>.greenbrain.it` | Per-customer remote access (Phase 2) |

- Authentication is **separate per installation** — no shared sessions, no SSO
- Customer data **remains on customer infrastructure** — no centralized DB
- GreenBrain V1 is **not shared multi-tenant SaaS**
- Tunnel/relay is **transport only** — no data stored at relay

Auth plan: `docs/architecture/per-install-auth-strategy.md`
Access plan: `docs/architecture/customer-remote-access-architecture.md`

---

## What Is Allowed Now

- Planning and documentation for domain/access strategy ✓ (done)
- DNS configuration for `greenbrain.it` and `app.greenbrain.it` ✓
- Static site content preparation ✓
- nginx config drafting ✓
- Slug naming convention and registry design ✓

## What Must Wait

- Production rollout of `app.greenbrain.it` with JWT auth → wait for step 5
- Any customer subdomain activation → wait for client-local V1 complete
- Cloudflare Tunnel onboarding for real customers → wait for client-local V1
- Customer remote auth rollout → wait for FastAPI JWT live on customer install
