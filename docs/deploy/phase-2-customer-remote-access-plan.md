# Phase 2 — Customer Remote Access Plan
> Step-by-step plan for onboarding a customer installation to a branded subdomain
> (`<slug>.greenbrain.it`) with secure remote access.
> Based on: `docs/architecture/customer-remote-access-architecture.md` ·
> `docs/architecture/domain-and-access-operating-model.md`.
> Updated: 2026-04-02.
> **Execution priority:** GreenBrain Platform completion precedes this workstream. See `docs/architecture/final-platform-priority-and-access-decision.md`.

---

## Scope

Phase 2 adds remote access for a specific customer whose local installation is
already running and validated. It does not modify the product. It adds a routing
layer between the internet and the customer's server.

Phase 2 cannot start before:
- **GreenBrain Platform is complete** (storage, ML, auth, ETL, scheduler, install.sh)
- Client-local V1 is complete (`install.sh` works on clean Ubuntu 22.04)
- FastAPI JWT auth is live on the customer's installation
- The customer's local installation has been running stably for at least one week
  (ETL running, analytics data present, ops health ok)

---

## Current Reality

No customer remote access exists. Phase 2 is future work.
This plan defines the process for when it is needed.

---

## Recommended Mechanism: Cloudflare Tunnel

See `docs/architecture/customer-remote-access-architecture.md` §5 for the full
rationale. Summary: no static public IP required, no port forwarding, TLS handled
by Cloudflare, one daemon on the customer server.

The plan below uses Cloudflare Tunnel. The WireGuard alternative follows the same
logical sequence but with different technical steps at the tunnel setup stage.

---

## Slug Naming Convention

| Rule | Example |
|------|---------|
| Lowercase only | `rossi-garden` |
| Hyphens, no underscores | `verde-futuro` |
| Derived from customer name | `gardenroma` |
| Max 32 characters | ✓ |
| No spaces, no special chars | ✓ |
| Registered in owner's slug registry | `docs/deploy/slug-registry.md` |

The slug registry is a simple markdown table maintained by the owner:
```markdown
| Slug | Customer | Install date | Tunnel status | Notes |
|------|---------|-------------|--------------|-------|
| rossi-garden | Rossi Garden Srl | 2026-05-01 | active | ... |
```

---

## Prerequisites — Go / No-Go Before Starting

All must be YES before proceeding.

### Customer runtime readiness
- [ ] `install.sh` completed successfully on the customer's server
- [ ] `GET /api/v1/ops/health` → `ok` (confirmed via local access)
- [ ] `GET /health/db` → healthy
- [ ] ETL has run at least once; analytics tables non-empty
- [ ] ML predict cycle has run at least once; `greenhouse_forecast_results_v2` non-empty
- [ ] FastAPI JWT auth working: login produces a token; authenticated routes respond
- [ ] Customer has changed the default admin password from the install-generated one
- [ ] Production frontend image running (nginx, not Vite dev server)

### Auth readiness
- [ ] Customer's `JWT_SECRET` is in `infra/env/client.env` and not the default template value
- [ ] `POST /api/v1/auth/login` works locally: returns valid JWT
- [ ] `GET /api/v1/auth/me` works with the returned JWT

### Backend/frontend readiness
- [ ] CORS in backend `allow_origins` includes `https://<slug>.greenbrain.it`
  (must be added before tunnel is activated)
- [ ] `VITE_API_BASE_URL` is set correctly (relative paths preferred; no localhost hardcode)
- [ ] Frontend serves correctly at `http://localhost:80` or `http://<local-ip>:80`

### Infrastructure readiness
- [ ] Cloudflare account set up; DNS for `greenbrain.it` managed by Cloudflare
- [ ] Owner has a Cloudflare API token with `Zone:DNS:Edit` and `Tunnel:Edit` permissions
- [ ] Slug chosen and registered in `docs/deploy/slug-registry.md`
- [ ] Customer server has internet access (for outbound tunnel connection)
- [ ] Owner can SSH into customer server (for initial agent installation)

---

## Rollout Sequence

### Step 1 — Add CORS origin to customer backend

On the customer's server, update `apps/backend/app/main.py` (or config):
```python
allow_origins=["https://<slug>.greenbrain.it", "http://localhost"]
```
Restart backend:
```bash
docker-compose restart backend
```

This must happen before the tunnel is active to avoid CORS errors on first access.

---

### Step 2 — Install cloudflared on customer server

```bash
# On the customer server (can be added to install.sh for future customers)
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb   -o cloudflared.deb
sudo dpkg -i cloudflared.deb
cloudflared --version
```

---

### Step 3 — Create Cloudflare Tunnel (owner side)

In the Cloudflare dashboard (or via CLI):
```bash
cloudflared tunnel login    # authenticates with Cloudflare
cloudflared tunnel create <slug>-tunnel
# Outputs a tunnel ID and credentials file
```

The credentials file is a JSON file. **It must be transferred to the customer
server securely (not via email).** Use `scp` or a temporary secrets share.

On the customer server, place credentials in the expected location:
```bash
mkdir -p ~/.cloudflared
scp owner@<relay>:~/<slug>-tunnel.json ~/.cloudflared/<tunnel-id>.json
```

---

### Step 4 — Write tunnel config on customer server

Create `~/.cloudflared/config.yml`:
```yaml
tunnel: <tunnel-id>
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: <slug>.greenbrain.it
    service: http://localhost:80    # customer nginx frontend
  - hostname: <slug>.greenbrain.it
    path: /api/
    service: http://localhost:8002  # customer FastAPI backend
  - service: http_status:404
```

Or use a single entry pointing to nginx which handles both:
```yaml
ingress:
  - hostname: <slug>.greenbrain.it
    service: http://localhost:80    # nginx handles / and /api/ routing
  - service: http_status:404
```

---

### Step 5 — Add DNS CNAME in Cloudflare

```bash
cloudflared tunnel route dns <slug>-tunnel <slug>.greenbrain.it
```

This creates `<slug>.greenbrain.it CNAME <tunnel-id>.cfargotunnel.com` in
Cloudflare DNS automatically.

Verify in Cloudflare dashboard: DNS → `<slug>.greenbrain.it` → CNAME record visible.

---

### Step 6 — Install cloudflared as a systemd service on customer server

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
sudo systemctl status cloudflared
```

The service must have `Restart=on-failure` in the unit file (cloudflared installs
this by default). Verify:
```bash
grep Restart /etc/systemd/system/cloudflared.service
```

---

### Step 7 — Smoke test remote access

From a machine outside the customer's LAN:
```bash
# Frontend loads
curl -sI https://<slug>.greenbrain.it | grep "HTTP/2 200"

# Health check
curl -s https://<slug>.greenbrain.it/api/v1/ops/health | jq .status
curl -s https://<slug>.greenbrain.it/health/db | jq .status

# Auth works
curl -s -X POST https://<slug>.greenbrain.it/api/v1/auth/login   -H "Content-Type: application/json"   -d '{"email":"admin@...", "password":"..."}' | jq .access_token

# Analytics data is present (customer's real data)
TOKEN="<token-from-above>"
curl -s "https://<slug>.greenbrain.it/api/v1/analytics/series?granularity=day&entity_type=famiglia"   -H "Authorization: Bearer $TOKEN" | jq ".data | length"
```

Expected: analytics returns non-empty data (customer's ETL has run at least once).

---

### Step 8 — Communicate access details to customer

Provide the customer:
- URL: `https://<slug>.greenbrain.it`
- Default credentials (if not already changed in Step 0)
- Browser bookmark instructions
- Note that data never leaves their server

Do **not** provide the Cloudflare tunnel credentials file or the `JWT_SECRET`
to the customer — these are infrastructure secrets.

---

## Go / No-Go Checklist (final, before announcing access to customer)

- [ ] `https://<slug>.greenbrain.it` loads the GreenBrain frontend
- [ ] Login with customer credentials succeeds
- [ ] After login, analytics charts render with non-empty data
- [ ] `/api/v1/ops/health` → `ok` via the tunnel URL
- [ ] `cloudflared` systemd service is enabled and running (`systemctl status`)
- [ ] pgAdmin not accessible via `https://<slug>.greenbrain.it:5050` (verify explicitly)
- [ ] CORS no error in browser developer tools
- [ ] Session persists after page refresh (JWT stored in browser, not Supabase)
- [ ] One analytics endpoint confirmed returning customer-specific data (not dev-cloud data)

---

## Rollback / Emergency Disable Checklist

If remote access must be disabled immediately (security incident, customer request,
misconfiguration):

| Action | Time | Effect |
|--------|------|--------|
| `sudo systemctl stop cloudflared` on customer server | 30 sec | Tunnel immediately closes; subdomain returns 502 |
| Delete CNAME record in Cloudflare DNS | 1 min | DNS stops resolving the subdomain |
| Delete tunnel in Cloudflare dashboard | 2 min | Tunnel ID invalidated; agent cannot reconnect |
| Local customer access is unaffected | — | Customer can still use the product locally |

The customer's data, database, and application are not touched by any of these
rollback steps. They only affect remote routing.

---

## Optional Hardening (post Phase 2 stabilization)

These are not required for Phase 2 but should be evaluated after the first
customer is live:

- **Cloudflare Access**: add an email OTP or IP allowlist policy to
  `<slug>.greenbrain.it` — zero code changes; configured in Cloudflare dashboard
- **Origin TLS**: install a self-signed cert on customer nginx and configure
  `originServerName` in tunnel config for end-to-end TLS
- **Automated tunnel provisioning**: script the full Steps 2–6 into
  `client-runtime/setup-tunnel.sh` for zero-manual-step customer onboarding
- **Slug registry automation**: track active tunnels and their health in a
  simple registry file committed to the monorepo
