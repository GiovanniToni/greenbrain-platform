# Customer Remote Access Architecture
> How a customer-local GreenBrain installation can be accessed remotely
> without moving customer data to the cloud.
> Based on decision: `docs/architecture/brand-access-and-tenant-routing-decision.md`.
> Updated: 2026-04-02.
> **Execution priority:** GreenBrain Platform completion precedes this workstream. See `docs/architecture/final-platform-priority-and-access-decision.md`.

---

## Decision

Customer data must remain on customer infrastructure.
Remote access is provided by forwarding HTTP traffic to the customer's server
via a secure transport layer. The relay is stateless and carries no persistent
customer data.

This document defines the available transport patterns, their tradeoffs, the
recommended option, and the security requirements.

---

## 1. Current Reality

No remote customer access mechanism exists today. In V1, all customer access is
local (LAN or direct machine access). Remote access is a Phase 2 feature and
requires client-local V1 to be fully installable and stable first.

---

## 2. The Core Constraint

```
Internet user
     │
     ▼  HTTPS
<slug>.greenbrain.it
     │
     ▼  transport layer only (tunnel / relay / proxy)
     │  ← no data stored here
     │  ← no computation here
     │  ← no auth bypass here
     ▼
Customer server (local LAN or data center)
     └── Docker gb_v2_nginx → gb_v2_frontend → gb_v2_backend
                                                     │
                                                     ▼
                                            Customer PostgreSQL
                                            Customer ML artifacts
                                            Customer analytics data
```

The relay exists only to bridge the internet to the customer's server.
Every byte of business data originates from and stays on the customer's
infrastructure.

---

## 3. Transport Pattern Options

### Option A — Local only (no remote access)
The customer accesses the product from their LAN only. No subdomain.
No tunnel. No public exposure.

### Option B — Cloudflare Tunnel
The customer runs a lightweight `cloudflared` agent on their server.
This agent creates an outbound encrypted connection to Cloudflare's edge.
The owner configures a DNS entry pointing `<slug>.greenbrain.it` to the
Cloudflare Tunnel endpoint. No inbound port forwarding required on the customer side.

```
Browser → HTTPS → Cloudflare edge → Tunnel → cloudflared agent → local nginx
```

### Option C — WireGuard VPN
The owner runs a WireGuard relay server (can be the existing DigitalOcean droplet).
The customer server connects as a VPN peer. Owner's nginx proxies
`<slug>.greenbrain.it` requests over the WireGuard interface to the customer server.

```
Browser → HTTPS → Owner nginx (DO) → WireGuard VPN → Customer server nginx
```

### Option D — Public reverse proxy (customer has fixed IP)
The owner's cloud nginx proxies `<slug>.greenbrain.it` directly to the customer's
public IP:port. Requires the customer server to have a stable public IP and
port-forwarding (or a DMZ entry) for port 443 or 80.

```
Browser → HTTPS → Owner nginx (DO) → TCP proxy → Customer public IP:port
```

---

## 4. Comparison Table

| Criterion | A: Local only | B: Cloudflare Tunnel | C: WireGuard VPN | D: Public proxy |
|-----------|:---:|:---:|:---:|:---:|
| Customer remote access | ✗ | ✓ | ✓ | ✓ |
| Customer fixed public IP required | — | ✗ | ✗ | ✓ |
| Port forwarding required | — | ✗ | ✗ | ✓ |
| Third-party dependency | None | Cloudflare | None | None |
| Owner manages relay | — | Partial (DNS + tunnel config) | Full (VPN server) | Full (nginx config) |
| Customer manages agent | — | `cloudflared` daemon | `wg-quick` config | None |
| TLS management | — | Cloudflare handles | Let's Encrypt on DO | Let's Encrypt on DO |
| Setup time per customer | — | 15–30 min | 30–60 min | 15 min |
| Network complexity | Low | Low | Medium | Low |
| Data passes through owner infra | — | No (Cloudflare edge, not DO) | No (VPN tunnel direct) | No (TCP pass-through) |
| Cloudflare sees traffic metadata | — | Yes (IPs, headers) | No | No |
| Suitable for V1.5 / Phase 2 | ✓ (baseline) | ✓ (**recommended**) | ✓ (alternative) | ✗ (requires fixed IP) |

---

## 5. Recommended Option for Phase 2: Cloudflare Tunnel

### Why Cloudflare Tunnel

- No requirement for the customer to have a static public IP or configure
  port forwarding — the most common operational obstacle with garden-center
  server setups
- Customer runs a single daemon (`cloudflared`) — one binary, one systemd
  unit, one config file; can be added to `install.sh`
- Owner controls routing entirely via Cloudflare dashboard + DNS; customer
  changes nothing when the slug is configured or updated
- TLS is handled end-to-end by Cloudflare; no certificate management on
  the relay side
- Free tier sufficient for single-customer subdomains at this scale
- Optional: Cloudflare Access can add IP allowlist or email OTP layer per
  subdomain with zero code changes

### Limitations to accept

- Cloudflare is a third-party that sees HTTP request metadata (source IPs,
  URL paths, response codes). It does not see decrypted request/response bodies
  if origin TLS is enabled (Cloudflare Tunnel with HTTPS origin).
- Cloudflare's availability is outside the owner's control. Downtime at
  Cloudflare edge affects remote access for all tunneled customers simultaneously.
- Requires the owner to manage DNS through Cloudflare (move nameservers, or
  use Cloudflare as a secondary DNS with CNAME delegation).

### When to choose WireGuard instead

Use WireGuard VPN when:
- The customer explicitly requires no third-party intermediary
- The customer has an IT department capable of managing VPN peer config
- Compliance requirements prohibit traffic metadata visibility by third parties

---

## 6. Security Requirements (all options)

The following are mandatory regardless of transport pattern:

| Requirement | Applies to | Implementation |
|-------------|-----------|---------------|
| HTTPS on all remote endpoints | All options | TLS cert on `<slug>.greenbrain.it` (Cloudflare or Let's Encrypt) |
| HTTPS on customer origin server | Cloudflare Tunnel | Self-signed or Let's Encrypt cert on customer nginx |
| JWT auth on all API endpoints | All options | FastAPI JWT middleware — already planned |
| Auth rate-limiting on login endpoint | All options | nginx `limit_req_zone` on customer nginx |
| pgAdmin and internal ports NOT exposed | All options | Bind pgAdmin to `127.0.0.1` only; not in docker-compose ports |
| Unique JWT secret per installation | All options | Generated at install time; stored in `client.env` only |
| No customer DB credentials in tunnel config | All options | Tunnel config contains only network routing, not credentials |
| Tunnel terminates at nginx, not at DB | All options | Customer nginx is the only entry point; DB port never forwarded |

---

## 7. Per-Customer Isolation Guarantees

Each customer installation provides the following guarantees independent of the
transport layer:

1. **Separate database** — each customer's PostgreSQL instance contains only that
   customer's data. There is no shared schema or shared connection pool.

2. **Separate JWT secret** — a session at `customer-A.greenbrain.it` cannot be
   replayed at `customer-B.greenbrain.it`. Tokens are cryptographically tied to
   the installation's `JWT_SECRET`.

3. **Separate analytics and ML** — customer analytics views, ETL jobs, and ML
   forecast models run against only that customer's data. No cross-customer
   aggregation.

4. **Separate DNS routing** — each slug routes to exactly one tunnel or proxy
   target. Misconfiguration of one slug cannot expose another customer's server.

5. **Planner data isolation** — the planner depends on local forecast data and
   local analytics. It never queries across installations.

---

## 8. What the Owner Manages vs What the Customer Server Handles

| Responsibility | Owner | Customer Server |
|---------------|-------|----------------|
| DNS entry for `<slug>.greenbrain.it` | ✓ | — |
| Cloudflare Tunnel configuration | ✓ (in dashboard) | — |
| `cloudflared` daemon on customer server | — | ✓ (installed by `install.sh`) |
| TLS certificate for `<slug>.greenbrain.it` | ✓ (Cloudflare manages) | — |
| TLS certificate for customer origin (optional) | — | ✓ (self-signed or Let's Encrypt) |
| nginx on customer server | — | ✓ (Docker container) |
| PostgreSQL data | — | ✓ |
| ML artifacts and models | — | ✓ |
| JWT secrets | — | ✓ (generated at install) |
| ETL schedule (pg_cron) | — | ✓ |
| Backup of customer data | — | ✓ (guided by runbook) |

The owner's only ongoing operational responsibility per customer is maintaining
the DNS entry and tunnel configuration. This is a one-time setup per customer.

---

## 9. Failure Modes and Operational Risks

| Failure mode | Impact | Mitigation |
|---|---|---|
| Cloudflare edge outage | Remote access unavailable; local access still works | Document local-access fallback for customers |
| `cloudflared` agent crash on customer server | Remote access unavailable; local access still works | Add `Restart=on-failure` to systemd unit; `install.sh` sets this |
| Customer server offline (power, network) | Both local and remote access unavailable | Customer responsibility; document restart procedure |
| DNS misconfiguration (wrong slug) | Wrong customer's server exposed | Pre-flight checklist before activating subdomain (see phase-2 plan) |
| JWT secret leaked | Session hijacking risk | Unique secret per install; rotate via `update.sh` |
| Owner accesses customer server directly | Privacy / trust concern | Owner must not retain or store any customer credentials; documented in install runbook |
| Cloudflare policy change affecting tunnels | Loss of free tier or API changes | WireGuard is a documented fallback; can migrate per customer |

---

## 10. Analytics, ML, and Planner — Remote Access Invariants

These invariants must hold for any remote access configuration:

- **Analytics data is served by the customer's backend.** The analytics API
  (`/api/v1/analytics/*`) reads from the customer's local PostgreSQL. No
  request to an analytics endpoint is forwarded to the owner's cloud.

- **ML forecast is computed locally.** The customer's ML worker runs against
  local storage and writes to local PostgreSQL. No ML computation occurs at the
  tunnel relay.

- **Planner uses local forecast and local analytics.** Planner RPCs query the
  customer's `greenhouse_forecast_results_v2` and analytics views. They must
  never be re-routed to a cloud instance.

- **ETL runs in the customer's pg_cron.** Remote access does not affect the
  ETL schedule. If the customer's server is online, ETL runs at the configured
  time regardless of whether the tunnel is active.

---

## 11. Next Actions for Phase 2

| Action | Who | Dependency |
|--------|-----|------------|
| Confirm Cloudflare Tunnel as the selected mechanism | Owner decision | — |
| Add `cloudflared` agent install to `client-runtime/install.sh` | Dev | client-local V1 complete |
| Write `client-runtime/setup-tunnel.sh` (per-customer tunnel config) | Dev | Cloudflare account + API token |
| Define slug registry (simple JSON or markdown list) | Owner | First customer identified |
| Test end-to-end: slug → tunnel → local backend → analytics response | Dev + Owner | First customer install ready |
| Document local-access fallback for customers | Dev | Phase 2 plan written |

*See `docs/deploy/phase-2-customer-remote-access-plan.md` for the full rollout
checklist.*
