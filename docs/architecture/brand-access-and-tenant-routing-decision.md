# GreenBrain — Brand, Access, and Tenant Routing Decision
> Canonical architectural decision for public domain strategy, owner dev-cloud access,
> and customer remote access with local isolated installations.
> Updated: 2026-04-02.

---

## 1. Decision Summary

GreenBrain will follow this model:

- **unified brand and unified web access**
- **separate customer instances**
- **separate authentication per installation**
- **routing via subdomain and secure tunnel / reverse proxy**
- **single codebase**
- **two execution modes**
  - **dev-cloud**
  - **client-local**

This means:

- the public brand is centralized under `greenbrain.it`
- the owner has a dedicated cloud instance
- each customer has a dedicated isolated installation
- each customer may access their own local installation remotely through a branded subdomain
- customer data remains on the customer infrastructure
- GreenBrain is **not** a shared multi-tenant SaaS in V1

---

## 2. Core Principle

GreenBrain V1 is:

> **single-tenant per installation, brand-unified at domain level**

This means:

- one customer = one isolated stack
- one customer = one isolated database
- one customer = one isolated auth system
- one customer = one isolated ML / analytics runtime
- the user experience remains unified under the GreenBrain brand

So the architecture is:

- **multi-tenant in access / branding**
- **single-tenant in execution / infrastructure / data**

---

## 3. Official Domain Strategy

### Phase 1
- `greenbrain.it` → public marketing / presentation website
- `www.greenbrain.it` → redirect to `greenbrain.it`
- `app.greenbrain.it` → owner dev-cloud application

### Phase 2
- `<customer-slug>.greenbrain.it` → remote access to that customer's local installation
- routing through:
  - secure tunnel
  - or controlled reverse proxy
  - or equivalent secure relay
- data always stays on customer infrastructure

Examples:
- `rossi-garden.greenbrain.it`
- `verdefuturo.greenbrain.it`
- `gardenroma.greenbrain.it`

---

## 4. Execution Model

### 4.1 Owner dev-cloud
Runs in cloud and is used for:
- development
- improvements
- testing
- analytics validation
- ML validation
- schema evolution
- product management

Main endpoint:
- `app.greenbrain.it`

Infrastructure:
- cloud backend
- cloud frontend
- cloud PostgreSQL / dev environment
- cloud ML runtime where needed

### 4.2 Customer local
Runs on the customer server and is used for:
- local database
- local backend
- local frontend
- local ML inference / forecast runtime
- local analytics
- local planner
- local reorder workflow

Optional remote access:
- `<customer-slug>.greenbrain.it`

Infrastructure:
- customer-local PostgreSQL
- customer-local backend
- customer-local frontend
- customer-local ML runtime
- customer-local data and files

---

## 5. Authentication Model

Authentication is **separate for each installation**.

That means:

- owner dev-cloud auth is independent
- each customer installation has its own users
- JWT secret or equivalent auth secret is unique per installation
- sessions are not shared across installations
- no cross-customer identity exists in V1
- no centralized auth SaaS is required for client-local

### Consequences
- login on `app.greenbrain.it` is valid only for the owner/dev-cloud environment
- login on `clienteX.greenbrain.it` is valid only for that customer installation
- customers do not share accounts or sessions
- customer identity data remains local to the customer stack

---

## 6. Routing Model

### 6.1 Phase 1 routing
- `greenbrain.it` → static/public website
- `app.greenbrain.it` → cloud app

### 6.2 Phase 2 routing
- `<customer-slug>.greenbrain.it` routes to the specific customer installation
- routing is transport-only
- no shared central customer database
- no central analytics execution for customer data
- no central ML execution for customer data unless explicitly redesigned in the future

### Rule
Remote branded access must never change data ownership.

So:
- customer traffic may pass through a tunnel or relay
- but request handling and data access must occur on the customer installation

---

## 7. Security Principle

For customer remote access:

- the tunnel / reverse proxy is only a secure transport layer
- persistent customer data remains on customer infrastructure
- JWT secrets are unique per installation
- HTTPS is mandatory
- public exposure of DB admin tools is forbidden
- the owner must not need direct database access to customer runtime for normal operation

---

## 8. What GreenBrain V1 Is NOT

GreenBrain V1 is **not**:

- a shared multi-tenant SaaS
- a single cloud backend serving all customers from one database
- a centralized auth provider for all customers
- a shared ML runtime serving all customers
- a shared analytics database for all customers

These options may be evaluated later as a different product evolution, but they are
**not** part of the current V1 direction.

---

## 9. Why This Decision Is Correct

This model is the best fit because it gives:

- unified GreenBrain brand
- professional remote access UX
- isolated customer data
- lower privacy risk
- coherence with the current codebase direction
- coherence with client-runtime design
- easier migration from current hybrid architecture
- no forced redesign into true SaaS multi-tenancy

It also preserves the original product vision:

- one shared codebase
- one dev-cloud mode
- one client-local mode
- clean migration path from current state to installable product

---

## 10. Operational Consequences

### Immediate implications
We must design and standardize:

1. public website under `greenbrain.it`
2. owner app under `app.greenbrain.it`
3. customer slug strategy for future subdomains
4. per-install auth strategy
5. customer remote-access strategy
6. tunnel / reverse-proxy approach for Phase 2

### Consequence for implementation
The product roadmap must treat these as separate workstreams:

- **Brand / public web**
- **Dev-cloud app**
- **Client-local installable runtime**
- **Per-customer remote access layer**

---

## 11. Canonical Product Statement

The official GreenBrain product statement is:

> GreenBrain is a single product with a unified brand and a unified codebase.
> It runs in two modes:
> - owner dev-cloud
> - customer client-local
>
> Customer installations remain isolated and local, but can optionally be exposed
> remotely through branded subdomains under `greenbrain.it`.
>
> GreenBrain V1 is therefore:
> **brand-unified, access-unified, installation-isolated.**

---

## 12. Next Required Deliverables

Following this decision, the next architectural deliverables are:

1. canonical document for domain layout and public access
2. canonical document for frontend/auth/domain strategy
3. canonical document for customer remote access model
4. implementation plan for:
   - `greenbrain.it`
   - `app.greenbrain.it`
   - `<customer-slug>.greenbrain.it`
5. FastAPI JWT auth plan aligned with per-install auth
6. deployment plan for Phase 1 and Phase 2

---

## 13. Decision Status

**Status:** ACCEPTED  
**Scope:** architecture / product / deployment  
**Applies to:** dev-cloud, client-local, frontend, auth, deploy, domain strategy