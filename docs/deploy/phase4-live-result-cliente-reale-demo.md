# Phase 4 Live Result - cliente-reale-demo

## Stato finale
- runtime locale attivo
- frontend locale attivo
- backend locale attivo
- db locale attivo
- login locale attivo
- tenant centrale registrato
- SSO centrale attivo
- reverse tunnel Cloudflare attivo
- reachability HTTPS pubblica verificata
- tenant remoto raggiungibile su cliente-reale-demo.greenbrain.it

## Modello confermato
- dev: cloud
- auth centrale: cloud
- cliente reale: locale
- accesso remoto: reverse tunnel outbound
- nessun sync raw standard verso cloud GreenBrain

## Nota tecnica residua
L'utente locale demo autenticato sul runtime locale risponde ancora con:
- tenant_code null
- home_host null
- user_role null

Questo non blocca il funzionamento remoto attuale, ma va corretto per allineare completamente runtime locale e central auth.

## Hardening operativo
- il file credentials reale Cloudflare tunnel resta solo sulla macchina/runtime
- il file json reale non va versionato in git
- il tenant remoto si considera live solo con:
  - tunnel connesso
  - DNS pubblico risolto
  - HTTPS raggiungibile
  - login remoto verificato
  - /api/v1/auth/me verificato
