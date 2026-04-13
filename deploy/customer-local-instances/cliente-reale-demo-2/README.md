# GreenBrain Customer Local Template

## Obiettivo
Installazione cliente locale con:
- database locale
- backend locale
- frontend locale
- ML locale
- launcher desktop

## Accesso locale
- frontend locale: http://127.0.0.1:8088
- backend locale: http://127.0.0.1:8008

## Accesso remoto futuro
- login centrale su www.greenbrain.it
- instradamento tenant
- reverse tunnel verso backend locale cliente

## File principali
- env/customer-local.env.example
- docker-compose.local.yml
- scripts/start-local.sh
- scripts/stop-local.sh
- desktop/greenbrain-local.desktop
- tunnel/tunnel.env.example
