# Client Remote Access via Secure Tunnel

## Obiettivo
Consentire al cliente di:
- usare GreenBrain in locale dal proprio PC
- accedere anche da remoto via greenbrain.it
- mantenere dati, db, backend e ML in locale

## Strategia
- il runtime locale apre una connessione outbound verso un relay/tunnel sicuro
- nessuna porta inbound da aprire sul router del cliente
- il sito greenbrain.it autentica l'utente
- il central auth instrada verso il tenant
- il traffico applicativo passa nel tunnel sicuro verso il backend locale cliente

## Requisiti
- tunnel outbound persistente
- autenticazione forte macchina/runtime
- TLS end-to-end o equivalente
- allowlist tenant
- healthcheck tunnel
- revoca accesso immediata

## Vantaggi
- niente raw data nel cloud GreenBrain
- niente apertura porte lato cliente
- migliore sicurezza rispetto ad API pubblica esposta direttamente
- modello commerciale premium per accesso remoto

## Nota
Il tunnel è la direzione target per clienti reali.
