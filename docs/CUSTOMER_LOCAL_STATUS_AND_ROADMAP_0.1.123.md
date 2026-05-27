# GreenBrain Customer Local — Status & Roadmap 0.1.123

Data: 2026-05-27  
Branch: feat/customer-ops-supabase-foundation  
Release: customer-local-0.1.123

## Stato validato precedente

La release 0.1.122 è stata validata end-to-end su Mac con bundle personalizzato scaricato dal portale come z@gmail.com:

- wizard precompilato con dati cliente;
- installazione Docker completata;
- backend `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.122` healthy;
- frontend OK su `http://localhost:8088`;
- DB locale `greenbrain_z`;
- utente locale `z@gmail.com` provisionato come `customer_admin`;
- login con le stesse credenziali del portale GreenBrain funzionante.

## Modifiche 0.1.123

### 1. Porta wizard libera

Corretto `INSTALL_GREENBRAIN.sh`:

- sceglie automaticamente una porta libera tra `8099`, `8100`, `8101`, `8110`;
- esporta `GREENBRAIN_INSTALLER_WIZARD_PORT`;
- stampa e apre la porta effettiva scelta;
- evita il caso in cui `8099` occupata da Windsurf faccia aprire una pagina bloccata/non GreenBrain.

### 2. Package staging pulito

Corretto `tools/release/build_customer_local_release.sh`:

- rimuove `.bak`, `.bak_*`, `*~`;
- rimuove `__pycache__` e `.pyc`;
- rimuove `venv`;
- rimuove `overlay/logs`;
- rimuove env runtime reali (`overlay/env/customer-local.env`, `overlay/provisioning/local-runtime.env`);
- mantiene solo file `.example` sicuri.

## Validazione 0.1.123

- Build tar `customer-local-0.1.123.tar.gz` OK.
- Build universal installer `GreenBrain-Installer.zip` OK.
- ZIP contiene launcher Mac/Linux/Windows.
- Embedded tar contiene `VERSION=0.1.123` e `package_version=0.1.123`.
- Embedded tar contiene `pick_wizard_port` e `WIZARD_URL`.
- Embedded tar pulito: nessun `.bak`, `venv`, log, pycache o env reale.
- Smoke test con porta `8099` occupata: launcher propone `http://localhost:8100`.

## File release

- `/opt/greenbrain-platform/releases/customer-local/0.1.123/customer-local-0.1.123.tar.gz`
- `/opt/greenbrain-platform/releases/customer-local/0.1.123/GreenBrain-Installer.zip`

## Prossimi hardening

1. Fresh install vs update:
   - rilevare vecchi volumi Postgres incompatibili;
   - aggiungere `GREENBRAIN_INSTALL_MODE=fresh-reset`;
   - mostrare messaggio user-friendly invece di traceback DB.

2. Download bundle:
   - header anti-cache;
   - logging esplicito;
   - directory output bundle visibile host/container.

3. Test automatici:
   - porta wizard occupata;
   - porte runtime occupate;
   - vecchio volume incompatibile;
   - bundle personalizzato e installazione pulita.
