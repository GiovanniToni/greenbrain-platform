# GreenBrain Customer Local — Status & Roadmap 0.1.127

Data: 2026-05-28  
Branch: feat/customer-ops-supabase-foundation  
Release: customer-local-0.1.127

## Obiettivo

La release 0.1.127 aggiunge verificabilità e gestione operativa ai bundle personalizzati scaricati dal portale cliente.

La 0.1.126 aveva già consolidato:

- download anti-cache;
- filename univoco;
- output bundle visibile host/container;
- audit log visibile;
- download reale da portale cliente dell’ultima versione.

La 0.1.127 aggiunge:

- checksum SHA256 per ogni ZIP/TAR personalizzato;
- file `.sha256` accanto ai bundle;
- header HTTP `X-GreenBrain-Bundle-SHA256`;
- audit log con `sha256=...`;
- retention cleanup sicuro dei vecchi bundle.

## Modifiche principali

### 1. SHA256 file helper

Aggiunti helper in:

`apps/backend/app/services/customer_delivery_service.py`

per calcolare SHA256 dei bundle generati.

Ogni bundle personalizzato ora genera anche:

- `customer-local-...tar.gz.sha256`
- `GreenBrain-Installer-...zip.sha256`

Il contenuto del file `.sha256` è compatibile con:

`sha256sum -c`

### 2. Header HTTP SHA256

Gli endpoint download ora includono:

`X-GreenBrain-Bundle-SHA256`

oltre agli header già presenti:

- `Cache-Control: no-store, no-cache, must-revalidate, max-age=0`
- `Pragma: no-cache`
- `Expires: 0`
- `X-GreenBrain-Bundle-Filename`
- `X-GreenBrain-Bundle-Version`

### 3. Audit log con checksum

Il log visibile in `docker logs dev_backend` ora include:

`sha256=<hash>`

Esempio:

`customer_bundle_download actor=customer_portal ... release_version=0.1.127 ... sha256=...`

### 4. Retention cleanup

Aggiunta funzione:

`cleanup_customer_bundle_output_dir()`

Configurabile con:

- `GREENBRAIN_CUSTOMER_BUNDLE_RETENTION_DAYS`
- `GREENBRAIN_CUSTOMER_BUNDLE_RETENTION_MIN_KEEP`

Default:

- retention days: 14
- min keep: 20

La retention elimina solo file matching:

- `GreenBrain-Installer-*.zip`
- `GreenBrain-Installer-*.zip.sha256`
- `customer-local-*.tar.gz`
- `customer-local-*.tar.gz.sha256`

e solo dentro:

`/opt/greenbrain-platform/runtime-reports/customer-bundles`

## Validazioni

### GHCR

Immagini GHCR 0.1.127 pubblicate e pull-verified:

- `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.127`
- `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.127`

Digest:

- backend: `sha256:d295bb10d92815eb3f897f9bdb92ec4631d2a4fd704c34c88b1403bd39fe055e`
- ml-worker: `sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680`

### SHA256 download ops

Download ops validato.

Header presente:

`X-GreenBrain-Bundle-SHA256`

Generati:

- `customer-local-0.1.126-z-20260528085920.tar.gz`
- `customer-local-0.1.126-z-20260528085920.tar.gz.sha256`
- `GreenBrain-Installer-0.1.126-z-20260528085921.zip`
- `GreenBrain-Installer-0.1.126-z-20260528085921.zip.sha256`

Verifica:

- `sha256sum -c` su ZIP: OK
- `sha256sum -c` su TAR: OK

Audit log include `sha256=...`.

### Retention cleanup

Creati 20 file fake vecchi 30 giorni, matching i pattern sicuri.

Eseguito cleanup con:

- `GREENBRAIN_CUSTOMER_BUNDLE_RETENTION_DAYS=1`
- `GREENBRAIN_CUSTOMER_BUNDLE_RETENTION_MIN_KEEP=0`

Risultato:

`customer_bundle_cleanup removed=20 kept=12`

Dopo cleanup, nessun file `fake-old` rimasto.

### Download dopo cleanup

Dopo il cleanup, il download ops continua a generare correttamente bundle e `.sha256`.

Header validato:

- HTTP 200
- `X-GreenBrain-Bundle-Version: 0.1.126`
- `X-GreenBrain-Bundle-SHA256: 9a90c91d4a9b9a3f58107bc4c8a2f07a5073fc31a69fc9f2eab39b41d6078bed`

### Build package 0.1.127

Release files generati:

- `/opt/greenbrain-platform/releases/customer-local/0.1.127/customer-local-0.1.127.tar.gz`
- `/opt/greenbrain-platform/releases/customer-local/0.1.127/GreenBrain-Installer.zip`

Verifiche:

- VERSION=0.1.127
- package_version=0.1.127
- tar pulito
- embedded tar pulito
- nessun `.bak`
- nessun `venv`
- nessun `overlay/logs`
- nessun pycache
- nessun `.pyc`
- nessun env reale

### Test portale cliente reale

Login portale come:

`z@gmail.com`

Click su “Scarica GreenBrain”.

Generati su host:

- `runtime-reports/customer-bundles/customer-local-0.1.127-z-20260528093158.tar.gz`
- `runtime-reports/customer-bundles/customer-local-0.1.127-z-20260528093158.tar.gz.sha256`
- `runtime-reports/customer-bundles/GreenBrain-Installer-0.1.127-z-20260528093158.zip`
- `runtime-reports/customer-bundles/GreenBrain-Installer-0.1.127-z-20260528093158.zip.sha256`

Audit log:

`customer_bundle_download actor=customer_portal customer_id=28265444-dbda-4f94-93cf-75e6305466c6 email=z@gmail.com tenant_code=z release_version=0.1.127 source=personalized_universal_installer_latest_release filename=GreenBrain-Installer-0.1.127-z-20260528093158.zip size_bytes=1499485 sha256=3dc293d8ec64b21819717ed934381d28dc5a9fefe578d62230557a0207df1cb7`

### Verifica ZIP scaricato sul Mac

File scaricato:

`GreenBrain-Installer-0.1.127-z-20260528093158.zip`

Embedded tar ispezionato:

- VERSION=0.1.127
- package_version=0.1.127
- APP_ENV=client-local
- TENANT_CODE=z
- POSTGRES_DB=greenbrain_z
- POSTGRES_USER=greenbrain_z
- LOCAL_CUSTOMER_EMAIL=z@gmail.com
- LOCAL_CUSTOMER_PASSWORD_MODE=cloud_password
- LOCAL_CUSTOMER_HOME_HOST=z.greenbrain.it
- LOCAL_CUSTOMER_USER_ROLE=customer_admin
- POSTGRES_PASSWORD presente e random
- JWT_SECRET presente
- LOCAL_CUSTOMER_PASSWORD_HASH presente

## Stato finale

0.1.127 chiude il flusso:

download bundle personalizzato → anti-cache → output host-visible → audit log → checksum SHA256 → file `.sha256` → retention cleanup → portale cliente ultima versione

## Prossimi hardening consigliati

1. Mostrare nel portale la versione bundle disponibile.
2. Mostrare o rendere scaricabile il checksum SHA256.
3. Test automatici backend per headers e checksum.
4. Validazione installazione reale del bundle 0.1.127 su Mac/Windows.
5. Eventuale pagina ops per storico bundle generati per tenant.
