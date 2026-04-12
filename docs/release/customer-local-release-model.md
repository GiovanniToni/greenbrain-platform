# Customer Local Release Model

## Principio
- dev è la sorgente canonica
- il template cliente deriva da dev
- ogni cliente riceve una release versionata
- gli aggiornamenti cliente avvengono tramite update controllato

## Flusso
1. sviluppo e test su dev
2. build frontend
3. aggiornamento template cliente
4. build release versionata
5. update istanza cliente
6. restart controllato
7. test locale
8. test remoto

## Regola anti-drift
Le istanze cliente non vanno modificate manualmente salvo:
- env locale cliente
- credenziali tunnel
- hostname tenant
- note di installazione cliente

## File da non sovrascrivere senza attenzione
- env/customer-local.env
- tunnel/cloudflared/*.json
- eventuali credenziali locali
