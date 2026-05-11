# GreenBrain Customer Local — Portal Fix dopo 0.1.67

## Fix completati

- Download bundle portale ora preferisce sempre la latest release disponibile su host.
- Fallback su assigned release solo se non esiste una latest valida.
- Bundle personalizzato genera `local-runtime.env` da example o fallback.
- Download testato: generato bundle `customer-local-0.1.67-z-...tar.gz`.
- Bundle contiene:
  - `VERSION` = 0.1.67
  - `INSTALL_GREENBRAIN.sh`
  - `GreenBrain-Install.desktop`
  - `overlay/provisioning/local-runtime.env`
  - `overlay/provisioning/local-runtime.env.example`
  - `release-manifest.yml`

## Fix accesso utente installato

- User `2@gmail.com` non entrava per mismatch `JWT_SECRET` tra central backend e local backend.
- Risolto riavviando il backend locale con `overlay/env/customer-local.env`.
- Local backend ora usa lo stesso `JWT_SECRET` del central backend.
- Accesso user installato OK.

## Stato

Customer portal:
- User da installare `z@gmail.com`: login OK, download bundle OK, versione 0.1.67.
- User installato `2@gmail.com`: login SSO OK dopo restart backend locale.

## Prossimi step

- Rendere il fix latest-download definitivo e documentato.
- Valutare se sincronizzare automaticamente `assigned_release_version` alla latest quando viene pubblicata una nuova release.
- Migliorare UI portale mostrando versione bundle scaricata.
- Hardening SSO: controllo esplicito JWT_SECRET coerente tra runtime locale e centrale.
- Continuare con 0.1.68: README cliente, `COME_INSTALLARE_GREENBRAIN.txt`, launcher desktop robusto.
