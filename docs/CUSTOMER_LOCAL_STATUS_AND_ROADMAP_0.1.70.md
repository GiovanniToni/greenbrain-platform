# GreenBrain Customer Local — Status & Roadmap 0.1.70

## Release validata

Release corrente candidata: `customer-local-0.1.70`

## Validazioni completate

- Fresh install via launcher OK
- `INSTALL_GREENBRAIN.sh` OK
- `GreenBrain-Install.desktop` OK
- `COME_INSTALLARE_GREENBRAIN.txt` incluso nel bundle
- `post-install-check.sh` OK
- `doctor-local-extended.sh` OK
- Daily sequence OK
- Heartbeat healthy OK
- Source DB opzionale gestito correttamente
- JWT consistency check aggiunto al doctor esteso
- Bundle download portale usa latest release disponibile
- Bundle personalizzato contiene `local-runtime.env`
- Frontend download filename handling corretto

## Fix download bundle

Problema:
- account installato usava frontend locale con bundle JS vecchio
- fallback filename risultava `greenbrain-bundle.tar.gz`

Fix:
- parsing `Content-Disposition` robusto
- fallback filename pulito:
  `GreenBrain-Customer-Local-Setup.tar.gz`
- frontend-dist aggiornato nel template customer-local
- frontend-dist aggiornato nel runtime locale

## Stato attuale

Customer experience attuale:

1. Login portale OK
2. Download bundle OK
3. Nome bundle pubblico pulito
4. Bundle contiene launcher e runtime env
5. Install guided wizard OK
6. Post-install checks OK
7. Heartbeat centrale healthy OK

## Prossimi step

0.1.71:
- hardening launcher desktop Linux
- mostrare versione bundle nel portale
- cleanup log storici
- preparare wizard finale quasi plug-and-play
- continuare a rimandare SQL Server reale fino a fine hardening install flow
