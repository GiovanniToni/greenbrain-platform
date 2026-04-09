# GreenBrain Hosted + Hybrid Runtime Runbook

## Domini attivi
- https://www.greenbrain.it -> landing + login centrale
- https://dev.greenbrain.it -> ambiente dev cloud
- https://cliente1.greenbrain.it -> tenant hosted demo/cliente

## Login
- admin@greenbrain.it / admin123 -> dev.greenbrain.it/dashboard
- admin@cliente1.local / admin123 -> cliente1.greenbrain.it/dashboard

## Backend attivi
- auth backend: localhost:3001
- dev backend: localhost:8002
- cliente1 backend: localhost:8082

## Database attivi
- auth postgres: localhost:55442
- dev postgres: localhost:55443
- cliente1 postgres: localhost:55441

## HTTPS
- certbot nginx attivo
- test rinnovo: sudo certbot renew --dry-run

## Flusso attuale
1. utente entra da www.greenbrain.it
2. login centrale
3. auth backend decide tenant e home_host
4. redirect SSO verso host target
5. token locale scambiato su tenant target
6. accesso dashboard

## Target architetturale finale cliente reale
- cliente installa runtime locale con:
  - db locale
  - ml locale
  - codice locale
  - dati locali
- accesso sempre da greenbrain.it
- frontend online mostra dati cliente tramite:
  - sync sicuro locale -> cloud
  oppure
  - API sicura del runtime cliente

## Test rapidi
- curl -i -X POST https://www.greenbrain.it/api/v1/auth/sso/start ...
- curl -i -X POST https://dev.greenbrain.it/api/v1/auth/login ...
- curl -i -X POST https://cliente1.greenbrain.it/api/v1/auth/login ...
