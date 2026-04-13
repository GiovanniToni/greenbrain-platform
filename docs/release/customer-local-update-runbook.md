# Customer Local Update Runbook

## Flusso standard aggiornamento cliente

1. sviluppo e test su dev
2. build frontend
3. sync template cliente
4. backup istanza cliente
5. update istanza cliente dal template
6. restart runtime locale
7. test locale
8. test remoto
9. conferma finale

## Comandi

### Backup
bash deploy/customer-local-instances/<tenant>/scripts/pre-update-backup.sh

### Update
bash tools/release/update_customer_instance_from_template.sh <tenant>

### Restart
docker compose --env-file deploy/customer-local-instances/<tenant>/env/customer-local.env \
  -f deploy/customer-local-instances/<tenant>/docker-compose.local.yml up -d --build

### Check finale
bash deploy/customer-local-instances/<tenant>/scripts/post-update-check.sh

## Modello base / overlay

### Base
Aggiornata dal template/dev:
- base/backend-src
- base/frontend-dist
- base/scripts
- base/systemd
- base/desktop
- base/tunnel
- docker-compose.local.yml
- tunnel/docker-compose.tunnel.yml
- VERSION
- release-manifest.yml

### Overlay
Preservata per cliente:
- overlay/env/customer-local.env
- overlay/frontend-nginx/default.conf
- overlay/tunnel/cloudflared/config.yml
- overlay/tunnel/cloudflared/cloudflared.env
- overlay/tunnel/cloudflared/*.json
- overlay/meta/overlay-manifest.yml
