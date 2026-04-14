# Customer Local Release Contract

## Cosa contiene una release ufficiale
- template customer-local pulito
- base/backend-src
- base/frontend-dist
- scripts base
- tunnel template
- env example
- manifest versione

## Cosa non deve contenere
- env runtime reali
- credenziali cloudflared runtime
- file .env sensibili
- backup locali
- file .bak
- overlay runtime già compilati per clienti reali

## Regola
Una release ufficiale deve essere installabile, validabile e distribuibile a un nuovo cliente senza esposizione di segreti runtime.
