# Secure Tunnel Template

## Obiettivo
Esporre in modo sicuro il backend locale cliente verso il dominio tenant,
senza aprire porte inbound sul router del cliente.

## Modello
- connessione outbound dal cliente
- autenticazione del tunnel
- host pubblico tenant dedicato
- accesso consentito solo dopo login centrale GreenBrain

## Da scegliere
- provider tunnel
- metodo di autenticazione macchina
- strategia di healthcheck
- rotazione token tunnel
