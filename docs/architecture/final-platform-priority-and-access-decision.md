# GreenBrain — Final Priority and Access Decision
> Canonical decision on execution priority, platform completion, and branded access model.
> Updated: 2026-04-02.

---

## 1. Final Priority Rule

GreenBrain must be completed in this order:

1. finish **GreenBrain Platform**
2. stabilize **dev-cloud**
3. complete **client-local V1**
4. only then operationalize full branded remote customer access

Brand/domain strategy is confirmed, but it does not take execution priority over
platform completion.

---

## 2. What "finish GreenBrain Platform" means

GreenBrain Platform is considered the primary workstream and must be completed first.

The required completion order is:

1. storage abstraction wiring in ML
2. ML monorepo consolidation
3. backend production dockerization
4. frontend production dockerization
5. FastAPI JWT auth replacing Supabase auth
6. client-runtime Wave 7B.4 ETL port
7. client-local scheduler
8. install.sh and update.sh for client-runtime

Until these are complete, domain strategy remains architectural guidance only.

---

## 3. Confirmed Brand and Access Model

The following decisions are accepted and final:

- `greenbrain.it` = static public product site
- `www.greenbrain.it` = redirect to apex
- `app.greenbrain.it` = owner dev-cloud application
- `<slug>.greenbrain.it` = per-customer remote access endpoint
- each installation remains single-tenant
- authentication is separate per installation
- customer data remains on customer infrastructure
- tunnel or reverse proxy is transport only
- GreenBrain V1 is not shared multi-tenant SaaS

---

## 4. Execution Priority Between Workstreams

### Primary workstream
- GreenBrain Platform completion

### Secondary workstream
- dev-cloud branding and domain rollout (`greenbrain.it`, `app.greenbrain.it`)

### Tertiary workstream
- remote customer access under `<slug>.greenbrain.it`

This means:
- domain rollout must not delay platform completion
- customer remote access must not start before client-local V1 is real

---

## 5. Domain Work That Is Allowed Before Full Platform Completion

The following are allowed early because they do not block platform work:

- decision documents
- nginx planning
- DNS planning
- static landing page planning
- subdomain naming convention
- slug registry design

The following must wait:

- production rollout of customer subdomains
- Cloudflare Tunnel onboarding for real customers
- customer remote auth rollout
- customer remote access operations

These must wait until:
- FastAPI JWT is live
- client-local V1 is installable
- ETL and ML work locally
- frontend production build is complete

---

## 6. Canonical Phase Model

### Phase A — Platform completion
- storage
- ML
- backend
- frontend
- auth
- ETL
- scheduler
- install/update

### Phase B — Brand rollout
- `greenbrain.it`
- `app.greenbrain.it`
- TLS
- nginx
- basic public site

### Phase C — Customer remote access
- `<slug>.greenbrain.it`
- tunnel / relay
- per-customer onboarding
- support runbook

---

## 7. Final Operational Rule

No architectural, branding, or domain work may cause distraction from or delay to
the completion of GreenBrain Platform.

Every new domain/access task must be evaluated against one question:

> Does this directly help complete GreenBrain Platform now?

If no, it is secondary.

---

## 8. Final Statement

GreenBrain is:
- one codebase
- one product
- two execution modes
- brand-unified
- installation-isolated

But the immediate execution priority is not branding.

The immediate execution priority is:

> finish GreenBrain Platform first.