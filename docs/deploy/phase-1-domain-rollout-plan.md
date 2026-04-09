# Phase 1 — Domain Rollout Plan
> Concrete implementation steps to bring `greenbrain.it` and `app.greenbrain.it`
> live as the first operational phase of the domain strategy.
> Based on: `docs/architecture/domain-and-access-operating-model.md`.
> Updated: 2026-04-02.
> **Execution priority:** GreenBrain Platform completion precedes this workstream. See `docs/architecture/final-platform-priority-and-access-decision.md`.

---

## Scope

Phase 1 covers exactly:
1. `greenbrain.it` — static public presentation site
2. `www.greenbrain.it` — redirect to apex
3. `app.greenbrain.it` — owner dev-cloud application over HTTPS

Phase 1 does **not** include customer subdomains (`<slug>.greenbrain.it`).
That is Phase 2.

Phase 1 does **not** require FastAPI JWT to be complete. Steps 1–9 can be
executed now with Supabase auth still in place. The nginx + TLS configuration
is independent of the auth implementation.

---

## Current Reality

- `greenbrain.it` — not deployed; DNS not yet configured for product
- `app.greenbrain.it` — not configured; owner accesses stack via direct port or
  unbranded URL on the DigitalOcean droplet
- DigitalOcean droplet is running `gb_v2_nginx :8082` which already reverse-proxies
  to `gb_v2_frontend` and `gb_v2_backend`

---

## Prerequisites

Before starting:
- [ ] Access to domain registrar for `greenbrain.it` (DNS management)
- [ ] SSH access to the DigitalOcean droplet
- [ ] `nginx` installed on the droplet host (not just in Docker — the host nginx
  serves as the TLS terminator)
- [ ] Certbot (Let's Encrypt) available on the droplet host:
  ```bash
  sudo apt-get install certbot python3-certbot-nginx
  ```
- [ ] Ports 80 and 443 open in the droplet firewall (DigitalOcean Cloud Firewall
  or UFW)
  ```bash
  sudo ufw allow 80 && sudo ufw allow 443
  ```

---

## Rollout Steps

### Step 1 — Configure DNS A records

**Who:** Owner (domain registrar panel or Cloudflare DNS)
**Time:** 5 min + propagation delay (up to 1 hour)

```
greenbrain.it      A    <droplet-IPv4>
www.greenbrain.it  A    <droplet-IPv4>
app.greenbrain.it  A    <droplet-IPv4>
```

If already using Cloudflare for DNS, set proxy status to **DNS only** (grey cloud)
initially. Switch to proxied after TLS is confirmed working.

**Validation:**
```bash
dig +short greenbrain.it       # must return droplet IP
dig +short app.greenbrain.it   # must return droplet IP
```

---

### Step 2 — Deploy static presentation site

**Who:** Dev or Owner
**Time:** 30–60 min
**Options:**

**Option A (recommended for simplicity): Static directory on droplet**
```bash
sudo mkdir -p /var/www/greenbrain-site
# Place index.html + assets in /var/www/greenbrain-site/
```
nginx will serve this directly (configured in Step 3).

**Option B: Netlify**
- Push static site to a GitHub repo; deploy from Netlify
- Set custom domain `greenbrain.it` in Netlify settings
- Netlify handles TLS automatically — skip Step 4 for `greenbrain.it`
- `app.greenbrain.it` still needs the droplet nginx (Steps 3–4)

The static site requires no backend. A single `index.html` is sufficient
for Phase 1.

---

### Step 3 — Write nginx server blocks on the droplet host

**Who:** Dev
**Time:** 15 min

Create `/etc/nginx/sites-available/greenbrain`:

```nginx
# ── Rate limit zone (add to /etc/nginx/nginx.conf http block) ──────────────
# limit_req_zone $binary_remote_addr zone=auth_zone:10m rate=10r/m;

# ── greenbrain.it — static site ────────────────────────────────────────────
server {
    listen 80;
    server_name greenbrain.it www.greenbrain.it;
    # Certbot will convert this to HTTPS after Step 4
    root /var/www/greenbrain-site;
    index index.html;
    location / {
        try_files $uri $uri/ /index.html;
    }
}

# ── app.greenbrain.it — owner dev-cloud application ─────────────────────────
server {
    listen 80;
    server_name app.greenbrain.it;
    # Certbot will convert this to HTTPS after Step 4

    # React frontend (via gb_v2_nginx)
    location / {
        proxy_pass         http://127.0.0.1:8082;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    # FastAPI backend
    location /api/ {
        proxy_pass         http://127.0.0.1:8002;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

    # Health endpoint (no rate limit)
    location /health {
        proxy_pass http://127.0.0.1:8002;
    }
}
```

Enable and test:
```bash
sudo ln -s /etc/nginx/sites-available/greenbrain /etc/nginx/sites-enabled/
sudo nginx -t       # must print: syntax is ok / test is successful
sudo systemctl reload nginx
```

---

### Step 4 — Obtain TLS certificates with Certbot

**Who:** Dev
**Time:** 10 min

```bash
sudo certbot --nginx   -d greenbrain.it   -d www.greenbrain.it   -d app.greenbrain.it   --non-interactive   --agree-tos   --email <owner-email>
```

Certbot will:
1. Verify domain ownership via HTTP-01 challenge (requires DNS propagated from Step 1)
2. Update the nginx config blocks to add TLS directives and HTTP → HTTPS redirects
3. Set up a cron job for automatic renewal

After Certbot runs, verify the nginx config is still valid:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

### Step 5 — Add auth rate limiting

**Who:** Dev
**Time:** 5 min

Add to `/etc/nginx/nginx.conf` inside the `http {}` block:
```nginx
limit_req_zone $binary_remote_addr zone=auth_zone:10m rate=10r/m;
```

Add the following `location` block inside the `app.greenbrain.it` server block
(inside `/api/` or as a more specific override):
```nginx
location /api/v1/auth/login {
    limit_req zone=auth_zone burst=5 nodelay;
    proxy_pass http://127.0.0.1:8002;
    proxy_set_header Host $host;
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

### Step 6 — Verify pgAdmin is NOT publicly exposed

**Who:** Dev
**Time:** 5 min

pgAdmin runs on `gb_v2_pgadmin :5050`. It must not be reachable from the internet.

Check docker-compose ports for pgAdmin:
```bash
grep -A5 pgadmin /opt/greenbrain-v2/deploy/docker-compose.base.yml
```

Correct binding (bind to loopback only):
```yaml
ports:
  - "127.0.0.1:5050:80"
```

If it currently binds `0.0.0.0:5050`, change it and redeploy:
```bash
docker-compose up -d pgadmin
```

Verify from outside:
```bash
curl -I https://app.greenbrain.it:5050   # must be connection refused or 404 via nginx
```

---

### Step 7 — Verify CORS on the backend

**Who:** Dev
**Time:** 10 min

After `app.greenbrain.it` is live, the FastAPI backend must accept requests from
this origin. Check `apps/backend/app/main.py` or `app/core/config.py` for the
CORS `allow_origins` setting.

For Phase 1 (Supabase auth still in place), the origin `https://app.greenbrain.it`
must be in the allowed list. Do not use `allow_origins=["*"]` in production.

```python
# apps/backend/app/main.py
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.greenbrain.it"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

Restart backend container after this change:
```bash
docker-compose restart backend
```

---

### Step 8 — Update frontend VITE_API_BASE_URL

**Who:** Dev
**Time:** 5 min

The frontend's `VITE_API_BASE_URL` must point to `https://app.greenbrain.it/api`
(or remain as relative `/api/` if nginx proxies it correctly on the same origin —
preferred).

If using relative `/api/` paths in `apiClient.ts`, no env change is needed —
nginx handles the routing. Verify this is the case:
```bash
grep -r "VITE_API_BASE_URL\|apiClient" apps/frontend/src/ | head -10
```

---

### Step 9 — Smoke test

**Who:** Dev + Owner
**Time:** 10 min

```bash
# Public site
curl -sI https://greenbrain.it          | grep "HTTP/2 200"
curl -sI https://www.greenbrain.it      | grep "HTTP/2 301"

# Owner app
curl -sI https://app.greenbrain.it      | grep "HTTP/2 200"
curl -s  https://app.greenbrain.it/health | jq .status

# API reachable
curl -s  https://app.greenbrain.it/api/v1/analytics/series-breakdown   -H "Authorization: Bearer <token>" | jq ".data | length"

# Confirm pgAdmin not reachable
curl -sI https://app.greenbrain.it:5050  # expect connection refused
```

Analytics regression check — these must return non-empty:
```bash
for ep in analytics/series-breakdown analytics/future-windows-stats dashboard/reorder-suggestions; do
  count=$(curl -s "https://app.greenbrain.it/api/v1/$ep"     -H "Authorization: Bearer <token>" | jq ".data | length // .tree | length")
  echo "$ep → $count"
done
```

---

## Validation Checklist

- [ ] `https://greenbrain.it` loads static site (no backend error)
- [ ] `https://www.greenbrain.it` redirects 301 to `https://greenbrain.it`
- [ ] `https://app.greenbrain.it` loads the GreenBrain application
- [ ] `https://app.greenbrain.it/health` → `{"status": "ok"}` or equivalent
- [ ] `https://app.greenbrain.it/api/v1/analytics/series-breakdown` returns data
- [ ] `http://` variants all redirect to `https://`
- [ ] TLS cert valid: `openssl s_client -connect app.greenbrain.it:443` shows valid chain
- [ ] Certbot auto-renewal: `sudo certbot renew --dry-run` succeeds
- [ ] pgAdmin not accessible from the public internet
- [ ] No `@supabase/supabase-js` error in browser console (not required for Phase 1 — auth will still use Supabase until Phase 5 of dev-cloud plan)

---

## Rollback Checklist

If any step causes the running application to break:

| Problem | Rollback |
|---------|---------|
| nginx config breaks existing stack | `sudo nginx -t` first; if bad config: `sudo systemctl stop nginx`; access via direct port |
| Certbot fails | DNS not propagated yet; wait and retry; meanwhile port-based access still works |
| CORS error in browser | Revert `allow_origins` change; `docker-compose restart backend` |
| Frontend breaks after VITE var change | `docker-compose restart frontend`; revert `.env` |
| pgAdmin unreachable (intended) | Access via `ssh -L 5050:127.0.0.1:5050 user@droplet` tunnel |

The existing Docker stack (`gb_v2_*`) is not modified in Phase 1. All changes
are to host nginx configuration. Rolling back host nginx does not affect containers.
