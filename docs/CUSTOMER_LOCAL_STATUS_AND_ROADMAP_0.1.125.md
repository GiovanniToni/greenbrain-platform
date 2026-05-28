# GreenBrain Customer Local — Status & Roadmap 0.1.125

Data: 2026-05-28  
Branch: feat/customer-ops-supabase-foundation  
Release: customer-local-0.1.125

## Obiettivo

La release 0.1.125 introduce una UX guidata nel wizard per gestire il caso di vecchia installazione locale non compatibile.

Con 0.1.124 l’installer rilevava correttamente un vecchio volume Postgres incompatibile e si fermava con messaggio chiaro. Con 0.1.125 il wizard espone anche un percorso semplice per l’utente finale: "Reinstalla da zero".

## Modifiche principali

### Wizard backend

`base/apps/local-installer-wizard/wizard.py` ora supporta il parametro:

force_fresh_install=true

Quando presente nella chiamata POST `/api/install`, il wizard imposta:

GREENBRAIN_FORCE_FRESH_INSTALL=1

e scrive nel log:

Fresh reset requested from installer wizard

### Wizard frontend

`base/frontend-dist/wizard_index.html` ora:

- riconosce `LOCAL_DB_CREDENTIALS_FAILED` oppure `INSTALL_EXIT_CODE=31`;
- mostra un messaggio specifico: "Vecchia installazione locale non compatibile";
- mostra il bottone "Reinstalla da zero";
- chiede conferma all’utente prima di procedere;
- rilancia `/api/install` con `force_fresh_install=true`.

### GHCR

Pubblicate e verificate immagini GHCR 0.1.125:

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.125
- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.125

Digest verificati:

- backend: sha256:d295bb10d92815eb3f897f9bdb92ec4631d2a4fd704c34c88b1403bd39fe055e
- ml-worker: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

## Validazioni

### API wizard fresh-reset

Testato POST `/api/install` con:

force_fresh_install=true

Risultato:

- `GREENBRAIN_FORCE_FRESH_INSTALL=1` presente nei log;
- `Fresh reset requested from installer wizard`;
- `Install mode: fresh-reset`;
- installazione completata.

### Package validation

- `customer-local-0.1.125.tar.gz` buildato correttamente.
- `GreenBrain-Installer.zip` buildato correttamente.
- Embedded tar contiene:
  - `VERSION=0.1.125`;
  - `package_version=0.1.125`;
  - `force_fresh_install`;
  - `GREENBRAIN_FORCE_FRESH_INSTALL`;
  - `freshResetBtn`;
  - `LOCAL_DB_CREDENTIALS_FAILED`.
- Tar ed embedded tar puliti: nessun `.bak`, `venv`, `overlay/logs`, pycache, `.pyc`, env reali.

### Fresh install prebuilt

Test fresh install da tar 0.1.125 con:

GREENBRAIN_IMAGE_TAG=0.1.125
GREENBRAIN_USE_PREBUILT_IMAGES=1
GREENBRAIN_FORCE_FRESH_INSTALL=1

Risultato:

- `Docker image tag: 0.1.125`;
- `Using prebuilt Docker images`;
- nessun fallback a build locale;
- backend su immagine `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.125`;
- `LOCAL_DB_CREDENTIALS_OK`;
- `LOCAL_USER_PROVISION_OK`;
- backend healthy;
- frontend HTTP 200;
- `INSTALL COMPLETED`.

## File release

- `/opt/greenbrain-platform/releases/customer-local/0.1.125/customer-local-0.1.125.tar.gz`
- `/opt/greenbrain-platform/releases/customer-local/0.1.125/GreenBrain-Installer.zip`

## Prossimo hardening

La prossima release consigliata è 0.1.126:

- download bundle anti-cache;
- logging esplicito download bundle;
- directory bundle personalizzati visibile host/container;
- test portale cliente per verificare che il bundle scaricato sia sempre l’ultimo bundle personalizzato.
