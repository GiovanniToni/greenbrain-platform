# GreenBrain Customer Local — Status & Roadmap 0.1.126

Data: 2026-05-28  
Branch: feat/customer-ops-supabase-foundation  
Release: customer-local-0.1.126

## Obiettivo

La release 0.1.126 consolida il flusso di download bundle cliente dal portale.

Obiettivi principali:

- evitare download di bundle vecchi tramite cache browser/proxy;
- generare filename univoci per ogni download;
- rendere visibili sull’host i bundle personalizzati generati dal backend;
- loggare chiaramente ogni download bundle;
- verificare che il portale cliente scarichi sempre l’ultima release personalizzata.

## Modifiche principali

### 1. Output bundle host-visible

Il backend non genera più i bundle personalizzati in:

/tmp/greenbrain-customer-bundles

ma in:

/opt/greenbrain-platform/runtime-reports/customer-bundles

Questa directory è montata anche sull’host, quindi i file generati dal container `dev_backend` sono visibili da:

runtime-reports/customer-bundles

### 2. Directory configurabile

Aggiunta configurazione:

GREENBRAIN_CUSTOMER_BUNDLE_OUTPUT_DIR

Default:

/opt/greenbrain-platform/runtime-reports/customer-bundles

### 3. Header anti-cache

Gli endpoint download bundle ora restituiscono header anti-cache:

Cache-Control: no-store, no-cache, must-revalidate, max-age=0
Pragma: no-cache
Expires: 0
X-Accel-Buffering: no

e metadata utili:

X-GreenBrain-Bundle-Filename
X-GreenBrain-Bundle-Version

### 4. Audit log visibile

Aggiunto audit log visibile in `docker logs dev_backend`:

customer_bundle_download actor=... customer_id=... email=... tenant_code=... release_version=... source=... filename=... path=... size_bytes=...

Il log viene scritto anche tramite `uvicorn.error` per garantirne la visibilità nei log container.

### 5. Endpoint aggiornati

Aggiornati:

- `customer_portal.py`
- `customer_ops.py`
- `customer_delivery_service.py`

Gli endpoint interessati sono:

- `/api/v1/customer-portal/download-bundle`
- `/api/v1/customer-ops/customers/{customer_id}/download-bundle`

## Validazioni

### GHCR

Immagini GHCR 0.1.126 pubblicate e pull-verified:

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.126
- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.126

Digest:

- backend: sha256:d295bb10d92815eb3f897f9bdb92ec4631d2a4fd704c34c88b1403bd39fe055e
- ml-worker: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

### Build package

Release files generati:

- /opt/greenbrain-platform/releases/customer-local/0.1.126/customer-local-0.1.126.tar.gz
- /opt/greenbrain-platform/releases/customer-local/0.1.126/GreenBrain-Installer.zip

Verifiche:

- VERSION=0.1.126
- package_version=0.1.126
- tar pulito
- embedded tar pulito
- nessun `.bak`
- nessun `venv`
- nessun `overlay/logs`
- nessun pycache
- nessun `.pyc`
- nessun env reale

### Test endpoint ops

Download via endpoint ops:

- HTTP 200
- header anti-cache presenti
- filename univoco
- ZIP valido
- bundle personalizzato corretto
- output generato in `runtime-reports/customer-bundles`
- audit log visibile con `actor=customer_ops`

### Test portale cliente reale

Login portale come:

z@gmail.com

Click su “Scarica GreenBrain”.

Risultato:

- scaricato su Mac `GreenBrain-Installer-0.1.126-z-20260528083637.zip`;
- generati su host:
  - `runtime-reports/customer-bundles/customer-local-0.1.126-z-20260528083637.tar.gz`
  - `runtime-reports/customer-bundles/GreenBrain-Installer-0.1.126-z-20260528083637.zip`;
- audit log visibile:

customer_bundle_download actor=customer_portal customer_id=28265444-dbda-4f94-93cf-75e6305466c6 email=z@gmail.com tenant_code=z release_version=0.1.126 source=personalized_universal_installer_latest_release filename=GreenBrain-Installer-0.1.126-z-20260528083637.zip size_bytes=1499483

### Verifica ZIP scaricato sul Mac

Embedded tar ispezionato:

- VERSION=0.1.126
- package_version=0.1.126
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

0.1.126 valida il flusso:

cloud/backend → bundle personalizzato → portale cliente → download anti-cache → ZIP ultima versione → audit log → output visibile host/container

## Prossimi hardening consigliati

1. Pulizia/retention automatica di `runtime-reports/customer-bundles`.
2. UI portale: mostrare versione bundle disponibile/scaricata.
3. Test automatico backend per headers download.
4. Eventuale checksum SHA256 del bundle scaricato.
5. Validazione installazione reale del bundle 0.1.126 su Mac/Windows.
