# GreenBrain Customer Local — Status & Roadmap 0.1.72

## Release validata

Release: `customer-local-0.1.72`

## Fix principali

- Normalizzazione `tenant_code` nel wizard cliente.
- Input come `Cliente Reale !!!` viene convertito in `cliente_reale`.
- Evitati errori PostgreSQL da tenant code con spazi/maiuscole/caratteri speciali.
- Fresh install OK.
- post-install-check OK.
- extended doctor OK.
- daily sequence OK.
- heartbeat centrale healthy con `local_agent_version=0.1.72`.
- Source DB non configurato gestito correttamente come `SOURCE_DB_IMPORT_NOT_CONFIGURED`.

## Stato

0.1.72 è stabile come base installer/wizard più robusta.
