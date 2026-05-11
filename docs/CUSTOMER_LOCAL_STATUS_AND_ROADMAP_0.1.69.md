# GreenBrain Customer Local — Status & Roadmap 0.1.69

## Release validata

Release corrente: `customer-local-0.1.69`

## Validazioni completate

- Fresh install via `INSTALL_GREENBRAIN.sh` OK
- `install_exit=0`
- `post-install-check.sh` OK
- Daily sequence OK
- Source DB non configurato gestito come `SOURCE_DB_IMPORT_NOT_CONFIGURED`
- Heartbeat centrale healthy con `local_agent_version=0.1.69`
- Controllo `JWT_SECRET` nel doctor esteso OK
- Bundle portale scarica latest release disponibile
- Bundle personalizzato contiene `local-runtime.env`

## Nota bundle download

Il file scaricato ha nome diverso per cliente perché include:
- versione
- tenant_code
- timestamp

Esempio:
- `customer-local-0.1.69-cliente_reale-...tar.gz`
- `customer-local-0.1.69-z-...tar.gz`

Questo è corretto perché il bundle è personalizzato per cliente.

## Prossimi step

0.1.70:
- valutare filename pubblico più pulito per il download
- mostrare nel portale la versione bundle scaricata
- rendere launcher desktop ancora più robusto
- continuare a rimandare test SQL Server reale fino a fine ciclo wizard/installazione
