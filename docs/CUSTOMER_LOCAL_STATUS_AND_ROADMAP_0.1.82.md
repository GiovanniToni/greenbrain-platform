# GreenBrain Customer Local — Status & Roadmap 0.1.82

## Release validata

Release: `customer-local-0.1.82`

## Risultato

Prima release validata con installer one-click:

- file scaricabile/eseguibile: `INSTALLA_GREENBRAIN.run`
- estrazione automatica in cartella locale
- apertura wizard browser locale
- installazione tramite wizard
- env cliente generato correttamente
- runtime env con `INSTALLATION_ID`
- Docker stack locale avviato
- backend/frontend healthy
- doctor extended OK
- daily sequence OK
- heartbeat centrale ricevuto
- `runtime_health=healthy`

## Validazione

- `INSTALL_EXIT_CODE=0`
- `VERSION=0.1.82`
- `POST_INSTALL_CHECK_OK`
- `heartbeat_received`
- Source DB non configurato gestito come `SOURCE_DB_IMPORT_NOT_CONFIGURED`

## Stato architetturale

I dati cliente restano locali.
GreenBrain centrale gestisce login, tenant routing, heartbeat e visualizzazione autorizzata via runtime locale/tunnel.

## Prossimi step

1. Migliorare UX wizard:
   - schermata requisiti
   - stato Docker più chiaro
   - messaggi errore user-friendly
   - pulsante finale “Apri GreenBrain”
2. Migliorare flow Source DB:
   - wizard guidato connessione SQL Server
   - test connessione
   - import raw manuale iniziale
3. Validare visualizzazione dati cliente da account GreenBrain centrale senza spostare dati cliente fuori dal runtime locale.
