# GreenBrain — Domain and Access Operating Model
> Canonical operating model for public domain layout, owner dev-cloud access,
> and customer remote access. Based on decision recorded in
> `docs/architecture/brand-access-and-tenant-routing-decision.md`.
> Updated: 2026-04-02.
> **Execution priority:** GreenBrain Platform completion precedes this workstream. See `docs/architecture/final-platform-priority-and-access-decision.md`.

---

## Decision

GreenBrain V1 is:

> **brand-unified, access-unified, installation-isolated**

- One shared codebase
- One public brand under `greenbrain.it`
- Two execution modes: dev-cloud (owner) and client-local (customer)
- Each installation is fully isolated: separate database, separate auth, separate ML runtime
- Customer data never leaves customer infrastructure
- This is **not** shared multi-tenant SaaS

---

## 1. Official Domain Layout

| Domain | Purpose | Points to | Phase | Visibility |
|--------|---------|-----------|-------|------------|
| `greenbrain.it` | Public product / marketing site | Static host (Netlify or DO nginx static) | 1 | Public |
| `www.greenbrain.it` | Redirect to apex | Same as above (301 redirect) | 1 | Public |
| `app.greenbrain.it` | Owner dev-cloud application | DigitalOcean nginx → Docker stack | 1 | Private (owner) |
| `docs.greenbrain.it` | Technical documentation (optional) | Static host | 1 optional | Public or private |
| `<slug>.greenbrain.it` | Per-customer remote access | Tunnel/relay → customer local server | 2 | Private (customer) |

### Slug examples
- `rossi-garden.greenbrain.it`
- `verdefuturo.greenbrain.it`
- `gardenroma.greenbrain.it`

Slugs are assigned by the owner at customer onboarding. They are short, lowercase,
hyphen-separated identifiers derived from the customer name. No spaces, no special
characters, max 32 characters.

---

## 2. What Each Domain Does and Does Not Do

### `greenbrain.it`

**Is:** A static presentation site. No backend. No auth. No application logic.
Describes the product, its value proposition, and how to contact the owner.

**Is not:** The product application. Customers do not log in here. Owner does not
log in here for work purposes.

**Current reality:** Does not exist yet. Phase 1 task.

**Target:** Static HTML/CSS deployed on Netlify or a static nginx directory.
Can be updated without touching any application infrastructure.

---

### `app.greenbrain.it`

**Is:** The owner's private dev-cloud application instance. Used for development,
analytics validation, ML validation, schema evolution, product management, and
internal operations. Protected by FastAPI JWT auth (post Phase 5 of dev-cloud plan;
Supabase JS auth is the current temporary state).

**Is not:** A customer-facing endpoint. Customers do not receive credentials for
`app.greenbrain.it`.

**Current reality:** Owner accesses the running stack directly via port or through
the existing `gb_v2_nginx`. Public HTTPS subdomain not yet configured.

**Target:** nginx on DigitalOcean droplet, TLS via Let's Encrypt, proxies to
`gb_v2_frontend :8082` and `gb_v2_backend :8002`. Rate-limited auth endpoint.

---

### `<slug>.greenbrain.it`

**Is:** A customer's remote access point to their own local installation.
The subdomain is branded under `greenbrain.it` but all requests are forwarded
to the customer's server via a secure transport layer (tunnel or relay).
The customer's backend and database remain on their hardware. No customer data
passes through the owner's infrastructure persistently.

**Is not:** A shared cloud environment. Each slug routes to exactly one isolated
customer server. No two slugs share a backend.

**Current reality:** Does not exist yet. Phase 2 task. Requires customer runtime
to be fully installable first (client-local V1 complete).

**Target:** DNS A/CNAME entry pointing to Cloudflare Tunnel endpoint or relay
nginx, which forwards traffic to the customer's local server. See
`docs/architecture/customer-remote-access-architecture.md`.

---

## 3. Routing Principles

1. **`greenbrain.it` routes carry no application state.** The public site is
   stateless. It never proxies to a backend.

2. **`app.greenbrain.it` routes only to the owner's stack.** No customer data
   passes through this endpoint.

3. **`<slug>.greenbrain.it` routes only to the named customer's server.**
   Routing is 1:1. There is no load balancing across customers. A request
   to `slug-A.greenbrain.it` can never reach `slug-B`'s server.

4. **All transit is HTTPS.** TLS termination occurs at the entry point
   (Cloudflare, or nginx with Let's Encrypt cert). No plaintext HTTP for any
   authenticated endpoint.

5. **The tunnel/relay is transport-only.** It does not inspect, cache, store,
   or transform application payloads. It forwards bytes.

---

## 4. Customer Data Ownership Principle

> Customer data — sales records, analytics results, ML models, forecasts,
> planner events, stock data — must remain on the customer's server at all times.

This means:
- No centralized analytics aggregation across customers in V1
- No centralized ML training against customer data in V1
- No shared database, shared cache, or shared queue
- The relay/tunnel carries only HTTP traffic; the response payload originates
  from the customer's own PostgreSQL and is served by the customer's own backend
- Analytics, dashboard, planner, and ML forecast are all computed locally on
  the customer's installation

This principle is non-negotiable for V1 and must not be circumvented by any
caching or relay layer.

---

## 5. What Is Public, Private, Local, and Remotely Exposed

| Item | Classification | In V1 |
|------|---------------|-------|
| `greenbrain.it` content | Public | Phase 1 |
| `app.greenbrain.it` | Private — owner only | Phase 1 |
| Owner's PostgreSQL data | Private — never exposed | Always |
| Customer PostgreSQL data | Private — local to customer | Always |
| Customer local frontend (`:80` or `:8083`) | Local — customer LAN | V1 (local-only) |
| Customer backend API (`:8002`) | Local — customer LAN | V1 (local-only) |
| Customer frontend via `<slug>.greenbrain.it` | Remotely exposed — customer only | Phase 2 |
| Customer backend via `<slug>.greenbrain.it/api/` | Remotely exposed — customer only | Phase 2 |
| pgAdmin, internal ports | Never exposed | Always |
| ML training jobs | Local — cloud host or customer host | Never public |

---

## 6. What Is Explicitly Out of Scope in V1

| Item | Why out of scope |
|------|-----------------|
| Multi-tenant shared backend | Contradicts installation-isolated model; requires complete auth redesign |
| Centralized customer analytics | Contradicts data ownership principle |
| Centralized customer ML | Same as above |
| Shared SSO across installations | Auth is per-install; no central identity provider |
| Customer self-service subdomain provisioning | Requires owner involvement; not automated in V1 |
| Customer subdomain remote access | Phase 2 — requires client-local V1 installable first |
| CDN for customer app | Unnecessary complexity; Phase 2+ |
| Customer-facing status page | Not required for V1 |
| Email auth / password reset | SMTP dependency; V1.1 |
| Multi-factor authentication | V1.1 |

---

## 7. Interaction with Core Product Domains

Analytics, dashboard, planner, and ops are core product domains — not accessories.
The domain and access model must preserve their correct execution context:

| Domain | Execution context | Remote access impact |
|--------|------------------|---------------------|
| Analytics | Customer's local PostgreSQL + FastAPI | Served from customer server; no data leaves |
| Dashboard | Customer's local PostgreSQL + FastAPI | Same |
| Planner | Customer's local PostgreSQL + ML forecast | Same; requires local ML forecast populated |
| ML forecast | Customer's local ML worker + local storage | Never executed on relay; never proxied |
| Ops / health | Customer's local FastAPI + ml_ops schema | `/ops/health` reachable via tunnel → reflects customer state |

Remote access via `<slug>.greenbrain.it` does not change where these components run.
It only changes how a user's browser reaches them.

---

## 8. Next Required Actions

| Action | Phase | Owner |
|--------|-------|-------|
| Deploy `greenbrain.it` static site | 1 | Owner |
| Configure `app.greenbrain.it` nginx + TLS | 1 | Owner |
| Implement FastAPI JWT (replaces Supabase auth) | 1 | Dev |
| Design customer slug registry (simple list) | 1 | Owner |
| Complete client-local V1 (installable runtime) | 1 | Dev |
| Design Cloudflare Tunnel / relay approach | 2 | Dev + Owner |
| Onboard first customer to `<slug>.greenbrain.it` | 2 | Owner + Customer |

*See `docs/deploy/phase-1-domain-rollout-plan.md` and
`docs/deploy/phase-2-customer-remote-access-plan.md` for step-by-step plans.*
