# GreenBrain Customer Local — Prep 0.1.75

## Stato base

Base validata: `customer-local-0.1.74`

## Conferme richieste prima di 0.1.75

- Download portale serve latest bundle 0.1.74
- Filename pubblico: `GreenBrain-Customer-Local-Setup.tar.gz`
- Bundle personalizzato contiene `local-runtime.env`
- SSO account `2@gmail.com` OK
- Runtime demo locale healthy
- Daily sequence e heartbeat OK

## Target 0.1.75

UX hardening:
- migliorare istruzioni cliente post-download
- rendere launcher desktop più robusto
- rendere più chiaro il flusso: estrai bundle → clicca installer → wizard → verifica finale
- aggiungere eventuale check visibile versione nel portale
- mantenere SQL Server reale rimandato

## Verifica download portale

- Download portale testato dopo rebuild backend/frontend.
- Bundle personalizzato generato correttamente.
- Versione bundle attesa: `0.1.74`.
- File runtime personalizzato `overlay/provisioning/local-runtime.env` presente.
- Nome pubblico atteso: `GreenBrain-Customer-Local-Setup.tar.gz`.
