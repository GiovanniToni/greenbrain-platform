# Frontend, Auth, and Domain Strategy
> Architecture recommendation for greenbrain.it, owner dev-cloud access,
> and customer-local frontend access.
> Updated: 2026-04-02.
> Evidence: `docs/architecture/greenbrain-canonical-architecture.md` ·
> `docs/architecture/dev-cloud-vs-client-local.md` ·
> `docs/migration/source-of-truth.md`
> **Execution priority:** GreenBrain Platform completion precedes this workstream. See `docs/architecture/final-platform-priority-and-access-decision.md`.

---

## 1. The Three Access Contexts

GreenBrain has exactly three distinct access contexts. Each requires a different
answer for routing, auth, and hosting. They must not be conflated.

| Context | Who | Where does the app run | Who manages it |
|---------|-----|----------------------|----------------|
| **Owner dev-cloud** | Product owner / developer | DigitalOcean droplet | Owner |
| **Customer local install** | Garden center staff, on-site | Customer's own server | Customer (guided install) |
| **Customer remote web access** | Garden center staff, off-site | Still customer's server (data never leaves) | Owner provides tunnel mechanism |

---

## 2. Answers to the Direct Questions

### Should greenbrain.it point to the dev-cloud environment directly?

**No.** `greenbrain.it` is the product domain. It should point to a static product
or landing page. The owner's dev-cloud application is a private internal tool, not
a public product page. Exposing the dev application directly at the root domain
conflates product marketing with operational infrastructure.

Use `app.greenbrain.it` for the owner's dev instance.

### Should customers share the same frontend/backend instance?

**No.** The product is explicitly designed as a single-tenant local install.
Each customer has their own isolated PostgreSQL, their own ML models, and their own
data. Multi-tenant cloud hosting would require:
- Complete auth redesign (tenant isolation in DB schema)
- Cloud ETL running against customer data
- Shared ML infrastructure per tenant
- Data residency and privacy guarantees

None of these exist in the current codebase and all contradict the client-local
product vision. Do not pursue multi-tenant until explicitly decided as a separate
product direction.

### When is reverse proxy / VPN / secure tunnel better than multi-tenant cloud?

A reverse proxy or tunnel to the customer's server is better than multi-tenant cloud
when:
- Data must remain on the customer's premises (garden center preference or legal)
- The customer's server already runs the full stack (this is the install target)
- Customer count is small enough to manage individual tunnels operationally
- You want zero cloud data liability for customer records

A multi-tenant cloud instance is better when:
- You want zero server management for customers
- Data residency is not a concern
- You have engineering resources to build proper tenant isolation

**For GreenBrain V1: use tunnel/reverse-proxy, not multi-tenant cloud.**
The infrastructure already exists (customer server running Docker stack). Exposing
it remotely via a tunnel is the lowest-cost path to remote access without
rebuilding the product.

### When should customer online access hit local infrastructure vs a cloud relay?

**All data access must always hit the customer's local server.** A cloud relay
(tunnel endpoint) is acceptable as a transport layer only — it forwards HTTP
requests to the customer's backend and returns responses. The relay must carry
no persistent state and must not cache responses.

The only thing that lives in the cloud for customer remote access is the DNS
entry and the tunnel endpoint. All computation, data, and ML artifacts remain
on the customer's server.

---

## 3. Recommended Architecture

### Domain layout

```
greenbrain.it                  →  Static product landing page
                                  (Netlify / GitHub Pages / nginx static)
                                  No backend. No auth. No application logic.

app.greenbrain.it              →  Owner dev-cloud application
                                  nginx on DigitalOcean → gb_v2_frontend + gb_v2_backend
                                  Auth: FastAPI JWT (post Phase 5 of dev-cloud plan)

<slug>.greenbrain.it           →  Customer remote access (Phase 2 only)
                                  Cloudflare Tunnel OR Wireguard + nginx relay
                                  → Customer's local gb_v2_backend + gb_v2_frontend
                                  Data never leaves customer server
```

### Visual overview

```
Internet
│
├── greenbrain.it
│     └── Static site (Netlify or DO nginx static)
│           No application, no auth
│
├── app.greenbrain.it
│     └── DigitalOcean nginx (TLS via Let's Encrypt)
│           └── Docker gb_v2_nginx → gb_v2_frontend → gb_v2_backend
│                 Auth: FastAPI JWT
│                 DB: gb_v2_postgres (local Docker)
│
└── customer1.greenbrain.it      ← Phase 2 only
      └── Cloudflare Tunnel / relay endpoint
            → Customer server (Linux, local LAN)
                  └── Docker gb_v2_nginx → gb_v2_frontend → gb_v2_backend
                        Auth: FastAPI JWT (customer-specific secrets)
                        DB: customer's gb_v2_postgres
```

### Phase 1 (implement now)

Only two things needed:

1. **`app.greenbrain.it`** — configure nginx on the existing DigitalOcean droplet
   to serve `gb_v2_frontend` and proxy `/api/` to `gb_v2_backend` over HTTPS.
   Requires TLS cert (Let's Encrypt / Certbot — 10 minutes).

2. **`greenbrain.it`** — deploy a static landing page. Can be a single `index.html`
   on Netlify or the same DigitalOcean nginx serving a static directory.
   No backend dependency.

This is the complete Phase 1. Nothing else is required.

### Phase 2 (customer remote access — when first customer requests it)

Add a `<slug>.greenbrain.it` subdomain that tunnels to the customer's server.
Do not build this speculatively. Build it when the first customer needs it.

Two viable mechanisms:

| Mechanism | Complexity | Requires | Best for |
|-----------|-----------|---------|---------|
| **Cloudflare Tunnel** | Low | Customer runs `cloudflared` agent; owner controls DNS | Easiest; customer server behind NAT; no port forwarding |
| **Wireguard VPN** | Medium | Customer and owner manage VPN config; nginx relay on cloud | Stricter security; no third-party tunnel dependency |
| Traditional nginx proxy | Low-Medium | Customer server has public IP or port-forwarded 443 | Customer has fixed IP; no agent needed |

**Recommendation for Phase 2:** Cloudflare Tunnel. The customer runs a single
`cloudflared` agent on their server. The owner creates a `<slug>.greenbrain.it`
DNS entry pointing to the Cloudflare Tunnel endpoint. No port forwarding, no
public IP required on the customer side. TLS is handled by Cloudflare.

Cloudflare sees encrypted HTTP traffic but not the application data inside it
if you use end-to-end TLS (HTTPS from tunnel origin to Cloudflare). This is
acceptable for garden-center business data.

---

## 4. Auth Model Recommendation

### Single-tenant, per-install JWT

Each installation — owner's dev-cloud and each customer — has its own independent
auth system. There is no shared user database between instances.

**Implementation (already planned in dev-cloud execution plan):**
- `POST /api/v1/auth/login` — accepts `{email, password}`, returns JWT
- `GET /api/v1/auth/me` — validates JWT, returns user
- JWT secret: unique per install, stored in `infra/env/client.env` as `JWT_SECRET`
- User table: local PostgreSQL; no Supabase auth dependency
- Password storage: `passlib[bcrypt]` — no plaintext

**What this means for the domain strategy:**
- `app.greenbrain.it` uses the owner's JWT secret
- `customer1.greenbrain.it` (tunneled to customer server) uses the customer's JWT secret
- A login at `app.greenbrain.it` is NOT valid at any customer instance
- No SSO, no shared session — each instance is fully isolated

### First-install admin setup

`install.sh` must create an initial admin user during installation:
```bash
# After init waves applied:
curl -X POST http://localhost:8002/api/v1/auth/setup   -d '{"email": "admin@greenbrain.it", "password": "<generated>"}'
```
`POST /api/v1/auth/setup` — creates the first admin user only if no users exist.
Disabled after first use. Owner communicates the credential to the customer out-of-band.

### What NOT to build for V1 auth

- No OAuth / OIDC (unnecessary complexity for V1)
- No password reset via email (no SMTP dependency)
- No multi-factor authentication (can add in V1.1)
- No role-based access control beyond a single admin role
- No shared session between owner and customer instances

---

## 5. Subdomain Strategy

| Subdomain | Purpose | Points to | TLS | Phase |
|-----------|---------|-----------|-----|-------|
| `greenbrain.it` | Product landing page | Static hosting | Let's Encrypt | Phase 1 |
| `www.greenbrain.it` | Redirect to apex | Same static host | Let's Encrypt | Phase 1 |
| `app.greenbrain.it` | Owner dev-cloud application | DigitalOcean nginx | Let's Encrypt / Certbot | Phase 1 |
| `docs.greenbrain.it` | Technical documentation | Static hosting (optional) | Let's Encrypt | Phase 1 (optional) |
| `<slug>.greenbrain.it` | Per-customer remote access | Cloudflare Tunnel → customer server | Cloudflare | Phase 2 |

DNS managed via the domain registrar or Cloudflare. If using Cloudflare Tunnel for
customer subdomains, move DNS management to Cloudflare — it is required for tunnel
routing.

---

## 6. Security Constraints

### Mandatory for `app.greenbrain.it`

- **HTTPS only** — no HTTP; nginx redirects port 80 to 443
- **JWT secret** — minimum 32 bytes, randomly generated at deploy time; never
  committed to source control; stored only in `infra/env/dev.env`
- **CORS** — backend allows only `https://app.greenbrain.it`; no wildcard origin
- **Rate limiting** on `/api/v1/auth/login` — nginx `limit_req_zone`; max 10
  requests/minute per IP to prevent brute force
- **No `gb_v2_pgadmin` exposed** — pgAdmin must not be reachable from `app.greenbrain.it`;
  bind to `127.0.0.1` only or use a separate internal port

### Per-customer remote access (Phase 2)

- **TLS end-to-end** — customer's nginx must serve HTTPS even inside the tunnel
  (Cloudflare Tunnel supports origin certificates)
- **JWT secrets per install** — customer's `JWT_SECRET` is generated by `install.sh`
  and never leaves the customer server
- **Tunnel agent on customer server only** — the `cloudflared` agent connects outbound;
  no inbound ports opened on customer firewall
- **Optional: IP allowlist** — restrict `<slug>.greenbrain.it` to the customer's
  known office IP range via Cloudflare Access (zero-config; free tier available)

### What does the owner see from customer traffic?

If using Cloudflare Tunnel: Cloudflare sees request metadata (IPs, headers, URLs).
The owner sees nothing — tunnels are handled entirely by Cloudflare.
If using Wireguard: the owner's relay server sees encrypted WireGuard packets only;
no HTTP content is visible.

---

## 7. Operational Complexity Tradeoffs

| Approach | Customer setup | Owner ops | Scalability | Data sovereignty | Complexity |
|----------|---------------|-----------|-------------|-----------------|------------|
| Local-only (no remote) | None | None | N/A | Full | Minimal |
| Cloudflare Tunnel | Install `cloudflared` agent | Add DNS entry + tunnel config | 1 subdomain per customer | Full (data on customer server) | Low |
| Wireguard VPN | Configure VPN client | Manage VPN server + peers + nginx | 1 peer config per customer | Full | Medium |
| Multi-tenant cloud | None | Full infra management | High (but requires redesign) | Shared cloud | Very high |

**For V1:** Local-only. Zero operational cost.
**For Phase 2 (first customer requesting remote access):** Cloudflare Tunnel.
**Never for this product:** Multi-tenant shared cloud (contradicts product design).

---

## 8. Nginx Configuration for app.greenbrain.it (Phase 1)

The owner's droplet already runs `gb_v2_nginx` on port 8082. The public-facing
nginx configuration for `app.greenbrain.it` is a thin wrapper:

```nginx
# /etc/nginx/sites-available/app.greenbrain.it

server {
    listen 80;
    server_name app.greenbrain.it;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.greenbrain.it;

    ssl_certificate     /etc/letsencrypt/live/app.greenbrain.it/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.greenbrain.it/privkey.pem;

    # Serve React app (via gb_v2_nginx or directly to frontend container)
    location / {
        proxy_pass http://127.0.0.1:8082;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # FastAPI backend
    location /api/ {
        proxy_pass http://127.0.0.1:8002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Auth endpoint (rate-limited)
    location /api/v1/auth/login {
        limit_req zone=auth_limit burst=5 nodelay;
        proxy_pass http://127.0.0.1:8002;
    }
}
```

Add rate limit zone to `nginx.conf`:
```nginx
http {
    limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=10r/m;
}
```

TLS certificate via Certbot:
```bash
certbot --nginx -d app.greenbrain.it -d greenbrain.it -d www.greenbrain.it
```

---

## 9. Recommended Phase 1 Implementation

Exact steps, in order. No speculative work beyond Phase 1.

| Step | Action | Time | Dependency |
|------|--------|------|------------|
| 1 | Point `app.greenbrain.it` DNS A record → droplet IP | 5 min | DNS access |
| 2 | Point `greenbrain.it` + `www.` → same IP (or static host) | 5 min | DNS access |
| 3 | Install Certbot on droplet; obtain certs for all 3 names | 15 min | DNS propagated |
| 4 | Write nginx config (Step 8 template above); `nginx -t && systemctl reload nginx` | 15 min | Cert obtained |
| 5 | Verify HTTPS access to `app.greenbrain.it` → frontend loads | 5 min | Step 4 |
| 6 | Deploy static landing page at `greenbrain.it` | 30 min | DNS propagated |
| 7 | Implement FastAPI JWT auth (see dev-cloud plan §8) | 3–4 days | Backend must be stable |
| 8 | Replace frontend Supabase auth with JWT hooks | 2–3 days | Step 7 |
| 9 | Remove `@supabase/supabase-js`; rebuild image; redeploy | 1 hr | Step 8 |

Steps 1–6 can be done today with the existing running stack (Supabase auth still in
place). Steps 7–9 are the auth replacement already planned in the dev-cloud execution
plan. They do not add work — they are the same steps.

Phase 1 is complete after Step 6. Auth replacement (Steps 7–9) runs on the dev-cloud
execution plan timeline.

---

## 10. What This Document Does Not Decide

These are explicitly out of scope for this document and must be separate decisions:

- **Email auth / password reset** — requires SMTP or transactional email service
- **Multi-factor authentication** — not required for V1
- **Role-based access control** (admin vs read-only staff) — not required for V1
- **Cloudflare Access** policies per customer — Phase 2 detail
- **Customer onboarding flow** (how owner provisions a new customer subdomain) — Phase 2 runbook
- **Whether `greenbrain.it` eventually becomes a SaaS multi-tenant portal** — separate product decision; not implied by anything in this document

---

*For the FastAPI JWT implementation steps, see
`docs/migration/dev-cloud-execution-plan.md` §8.*
*For the client-local install architecture, see
`docs/client-runtime/client-local-product-plan.md`.*
*For the full execution roadmap, see
`docs/architecture/master-roadmap-to-product.md`.*
