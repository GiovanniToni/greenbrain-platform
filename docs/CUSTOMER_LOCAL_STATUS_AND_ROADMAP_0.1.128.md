# GreenBrain Customer Local — Status & Roadmap 0.1.128

Data: 2026-05-28  
Branch: feat/customer-ops-supabase-foundation  
Release: customer-local-0.1.128

## Obiettivo

La release 0.1.128 completa il flusso post-installazione:

- il cliente può accedere al portale/account dopo pagamento e download;
- le sezioni operative della piattaforma vengono abilitate solo dopo installazione locale completata;
- l’abilitazione avviene quando il runtime locale invia heartbeat healthy al cloud;
- dopo heartbeat healthy, il login centrale porta il cliente a `/dashboard`.

Regola funzionale confermata:

cliente pagante / bundle scaricato  
→ resta su `/account`

installazione completata + heartbeat healthy  
→ `platform_enabled=true`  
→ `home_path=/dashboard`  
→ sezioni operative visibili

## Problema risolto

Il runtime locale inviava heartbeat a:

`/api/v1/customer-runtime/heartbeat`

ma il cloud rispondeva 500 perché `greenbrain_runtime_connections` aveva una foreign key verso `greenbrain_tenants.tenant_code` e il tenant `z` non esisteva ancora in `greenbrain_tenants`.

Errore precedente:

`Key (tenant_code)=(z) is not present in table "greenbrain_tenants"`

## Modifiche principali

### 1. Heartbeat runtime esteso

Il modello `RuntimeHeartbeatPayload` ora accetta anche:

- `tenant_name`
- `local_backend_url`
- `public_backend_url`
- `tunnel_public_host`
- `data_mode`
- `sync_enabled`
- `sync_frequency_minutes`
- `runtime_health`

### 2. Tenant bootstrap su heartbeat

Quando arriva un heartbeat:

- se il tenant non esiste in `greenbrain_tenants`, viene creato/aggiornato;
- viene aggiornata/creata la riga in `greenbrain_runtime_connections`;
- viene aggiornata/creata la riga in `gb_customer_runtime_installations`;
- viene aggiornato `gb_customer_companies`.

### 3. Aggiornamento customer runtime fields

Dopo heartbeat healthy, `gb_customer_companies` viene aggiornato con:

- `installed_release_version`
- `runtime_connection_status`
- `latest_installation_id`
- `last_runtime_heartbeat_at`

### 4. Login centrale e redirect

`/api/v1/auth/me` ora mantiene il cliente su `/account` finché `platform_enabled=false`.

Quando invece il runtime è healthy e `platform_enabled=true`, per ruoli cliente:

- `customer_admin`
- `customer_user`
- `tenant_admin`

il backend restituisce:

`home_path=/dashboard`

Il frontend già supporta questo comportamento.

## Validazioni funzionali

### Login prima del fix

Per `z@gmail.com`:

- `platform_enabled=false`
- `home_path=/account`
- sezioni operative non visibili

### Heartbeat manuale

POST manuale a `/api/v1/customer-runtime/heartbeat` per tenant `z`:

- HTTP 200
- `status=heartbeat_received`
- tenant creato in `greenbrain_tenants`
- runtime connection creata in `greenbrain_runtime_connections`
- installation collegata in `gb_customer_runtime_installations`
- customer aggiornato in `gb_customer_companies`

### Heartbeat reale runtime

Il runtime reale ha poi aggiornato:

- `installed_release_version=0.1.122`
- `runtime_connection_status=healthy`
- `latest_installation_id=bf095292-f24a-42c4-97c1-d83e9a4a6084`
- `last_runtime_heartbeat_at` valorizzato

### Login dopo heartbeat

Per `z@gmail.com` con password corretta:

- `platform_enabled=true`
- `home_path=/dashboard`
- `runtime_health=healthy`
- `runtime_public_backend_url=https://z.greenbrain.it`
- `runtime_installation_id=bf095292-f24a-42c4-97c1-d83e9a4a6084`

### Test browser reale

Accesso da browser con:

- email: `z@gmail.com`
- password: `zzzz`

Risultato:

- login OK;
- cliente vede le 5 sezioni operative del programma.

### API operative

Con token cliente:

- `/api/v1/dashboard/kpis` → HTTP 200
- `/api/v1/planner/current-week` → HTTP 200

Endpoint non rilevanti:

- `/api/v1/dashboard/summary` → 404 perché endpoint non disponibile;
- `/api/v1/analytics/components` → 422 perché richiede parametri.

Questi non sono blocchi di entitlement.

## Build 0.1.128

Release files generati:

- `/opt/greenbrain-platform/releases/customer-local/0.1.128/customer-local-0.1.128.tar.gz`
- `/opt/greenbrain-platform/releases/customer-local/0.1.128/GreenBrain-Installer.zip`

BUILD-INFO:

- `release_version=0.1.128`
- `built_at=2026-05-28T12:01:31Z`
- `git_commit=375d81364eb99bd4812b54054a79f8b566f3cebd`

Verifiche:

- VERSION=0.1.128
- package_version=0.1.128
- tar pulito
- embedded tar pulito
- nessun `.bak`
- nessun `venv`
- nessun `overlay/logs`
- nessun pycache
- nessun `.pyc`
- nessun env reale

## GHCR

Immagini GHCR 0.1.128 pubblicate e pull-verified:

- `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.128`
- `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.128`

Digest:

- backend: `sha256:d295bb10d92815eb3f897f9bdb92ec4631d2a4fd704c34c88b1403bd39fe055e`
- ml-worker: `sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680`

## Test portale cliente reale

Login portale come:

`z@gmail.com`

Click su “Scarica GreenBrain”.

Generati su host:

- `runtime-reports/customer-bundles/customer-local-0.1.128-z-20260528120828.tar.gz`
- `runtime-reports/customer-bundles/customer-local-0.1.128-z-20260528120828.tar.gz.sha256`
- `runtime-reports/customer-bundles/GreenBrain-Installer-0.1.128-z-20260528120829.zip`
- `runtime-reports/customer-bundles/GreenBrain-Installer-0.1.128-z-20260528120829.zip.sha256`

Audit log:

`customer_bundle_download actor=customer_portal customer_id=28265444-dbda-4f94-93cf-75e6305466c6 email=z@gmail.com tenant_code=z release_version=0.1.128 source=personalized_universal_installer_latest_release filename=GreenBrain-Installer-0.1.128-z-20260528120829.zip size_bytes=1499563 sha256=ecd79d3525b9f6da0c835aaa672210bdca86cf15121011c58e3758fdd5741ea0`

### Verifica ZIP scaricato sul Mac

File scaricato:

`GreenBrain-Installer-0.1.128-z-20260528120829.zip`

Embedded tar ispezionato:

- VERSION=0.1.128
- package_version=0.1.128
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

0.1.128 chiude il flusso:

portale cliente → download/installazione → runtime heartbeat healthy → cloud abilita platform → login centrale → dashboard e sezioni operative visibili

## Prossimi hardening consigliati

1. Mostrare nel portale lo stato “Installazione completata / piattaforma attiva”.
2. Mostrare ultima versione installata e ultimo heartbeat.
3. Bottone “Apri piattaforma” visibile solo dopo heartbeat healthy.
4. Test automatico su `/auth/me` per cliente pre/post heartbeat.
5. Test reale installazione bundle 0.1.128 su Mac/Windows pulito.
