# Secrets Hardening Checklist

## Da cambiare prima di un cliente reale
- password admin demo
- password postgres demo
- JWT secret ambienti auth/dev/tenant
- eventuali credenziali versionate nei file env
- eventuali account test lasciati attivi

## Auth centrale
- deploy/env/auth.env
- utente admin@greenbrain.it
- eventuali utenti tenant di test

## Dev cloud
- deploy/env/dev-cloud.env
- db user/password
- jwt secret

## Tenant demo / cliente
- deploy/env/cliente1.env
- db user/password
- jwt secret
- admin tenant

## Certificati
- verificare scadenza e rinnovo automatico
- sudo certbot renew --dry-run

## Verifiche finali
- login dev ok
- login tenant ok
- sso start ok
- sso exchange ok
