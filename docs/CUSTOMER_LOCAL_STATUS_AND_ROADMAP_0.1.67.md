# GreenBrain Customer Local — Status & Roadmap 0.1.67

## Release validata

Release corrente: `customer-local-0.1.67`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.67/customer-local-0.1.67.tar.gz`

## Validazioni completate

- Launcher `INSTALL_GREENBRAIN.sh` incluso nel bundle
- Desktop launcher `GreenBrain-Install.desktop` incluso nel bundle
- Icona GreenBrain impostata da `base/frontend-dist/favicon.ico`
- Fresh install via launcher CLI OK
- `install_exit=0`
- Source DB non configurato gestito come `SOURCE_DB_IMPORT_NOT_CONFIGURED`
- Post install check OK
- Daily sequence OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK
- predict_all OK
- Heartbeat centrale healthy con local_agent_version 0.1.67
- Nessun pycache nel bundle

## Stato

Il bundle ora si avvicina al flusso desiderato:
cliente scarica il pacchetto, apre la cartella, clicca/avvia il launcher GreenBrain, segue il wizard e ottiene un runtime locale funzionante.

## Prossimo step

0.1.68:
- migliorare README cliente finale
- aggiungere file `COME_INSTALLARE_GREENBRAIN.txt`
- rendere il launcher desktop più robusto su Linux desktop
- valutare asset logo dedicato invece del favicon
- rimandare test SQL Server reale a fine ciclo wizard/installazione
