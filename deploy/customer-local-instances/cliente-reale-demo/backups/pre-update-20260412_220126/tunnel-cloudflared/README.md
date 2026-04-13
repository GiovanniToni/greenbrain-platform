# Cloudflare Tunnel Template

## Obiettivo
Esporre il backend locale cliente tramite tunnel outbound sicuro.

## Target
- host pubblico tenant: cliente-reale.greenbrain.it
- backend locale: http://127.0.0.1:8008

## Note
- nessuna porta inbound sul router cliente
- tunnel avviato dal cliente verso il provider
- accesso remoto da attivare solo dopo collaudo completo
