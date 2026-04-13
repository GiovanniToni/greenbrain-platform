# Customer Local Base / Overlay Model

## Base
Parte aggiornata dal template/dev:
- backend-src
- frontend-dist
- scripts
- desktop
- systemd
- docker-compose.local.yml
- tunnel/docker-compose.tunnel.yml
- VERSION
- release-manifest.yml

## Overlay
Parte specifica cliente, da preservare:
- overlay/env/customer-local.env
- overlay/frontend-nginx/default.conf
- overlay/tunnel/cloudflared/config.yml
- overlay/tunnel/cloudflared/cloudflared.env
- overlay/tunnel/cloudflared/*.json
- overlay/meta/overlay-manifest.yml

## Regola
Gli update da dev sovrascrivono solo la base.
L'overlay non va toccato automaticamente.
