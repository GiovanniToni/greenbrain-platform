# GreenBrain Customer Local — Status & Roadmap 0.1.71

## Release validata

Release: `customer-local-0.1.71`

## Fix principali

- SSO runtime locale corretto: il ticket viene validato usando l'audience del ticket, non l'Host locale.
- Test manuale `/sso/start` + `/sso/exchange` OK per `2@gmail.com`.
- Bundle 0.1.71 contiene `auth.py` aggiornato.
- Download portale continua a servire latest release.
- Filename pubblico bundle: `GreenBrain-Customer-Local-Setup.tar.gz`.

## Nota validazione

Il fresh test precedente ha usato input wizard non validi, quindi il DB check ha fallito per ruolo PostgreSQL errato. Rifare fresh test con tenant code valido.

## Prossimi step

- Fresh test 0.1.71 con input corretti.
- Update demo runtime con script corretto.
- Verifica login reale `2@gmail.com`.
- Poi procedere con hardening installer/launcher.
