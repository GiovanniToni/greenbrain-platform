# GreenBrain Customer Local — Status and Roadmap 0.1.131

## Release

- Versione: `0.1.131`
- Branch: `feat/customer-ops-supabase-foundation`
- Template bump commit: `a5990566 chore(customer-local): bump runtime template to 0.1.131`
- Patch funzionale: `84710bb5 fix(customer-local): seed local password sync metadata from cloud bundle`

## Obiettivo release

La release 0.1.131 corregge il seed iniziale dei metadati password nel runtime locale quando il cliente installa un bundle personalizzato scaricato dal portale cloud.

Prima della correzione, il bundle conteneva correttamente l'hash password cloud, quindi il login locale funzionava, ma il DB locale nasceva con metadati incoerenti:

- `password_version = 1`
- `password_change_source = initial`
- `password_last_sync_status = not_required`

Dalla 0.1.131 il bundle personalizzato porta anche i metadati cloud password e il provisioning locale li salva nel DB locale.

## Modifiche principali

### Cloud bundle generation

`apps/backend/app/services/customer_delivery_service.py`

Il backend cloud ora legge da `greenbrain_users`:

- `hashed_password`
- `password_version`
- `password_changed_at`
- `password_last_sync_status`

e scrive nel bundle personalizzato:

- `LOCAL_CUSTOMER_PASSWORD_HASH`
- `LOCAL_CUSTOMER_PASSWORD_MODE=cloud_password`
- `LOCAL_CUSTOMER_PASSWORD_VERSION`
- `LOCAL_CUSTOMER_PASSWORD_CHANGED_AT`
- `LOCAL_CUSTOMER_PASSWORD_SYNC_STATUS`
- `LOCAL_CUSTOMER_PASSWORD_SEED_SOURCE=cloud_seed`

### Local provisioning

`deploy/customer-local-template/base/scripts/provision-local-user.sh`

Lo script passa i nuovi campi al backend locale durante il provisioning utente.

### Local auth user service

`deploy/customer-local-template/base/backend-src/app/services/customer_auth_user_service.py`

`provision_customer_auth_user()` accetta ora campi opzionali:

- `password_version`
- `password_changed_at`
- `password_seed_source`
- `password_sync_status`

Quando riceve un hash cloud, inizializza il DB locale con:

- `password_version = <versione cloud>`
- `password_changed_at = <data cambio cloud>`
- `password_change_source = cloud_seed`
- `password_last_sync_status = synced`
- `password_last_synced_at = now`
- `password_last_sync_attempt_at = now`
- `password_last_sync_error = NULL`

## Release artifacts

Release files:

- `/opt/greenbrain-platform/releases/customer-local/0.1.131/customer-local-0.1.131.tar.gz`
- `/opt/greenbrain-platform/releases/customer-local/0.1.131/GreenBrain-Installer.zip`
- `/opt/greenbrain-platform/releases/customer-local/0.1.131/INSTALLA_GREENBRAIN.run`
- `/opt/greenbrain-platform/releases/customer-local/0.1.131/BUILD-INFO.txt`

`GreenBrain-Installer.zip` contiene:

- `GreenBrain-Install.desktop`
- `INSTALLA_GREENBRAIN_LINUX.run`
- `INSTALLA_GREENBRAIN_MAC.command`
- `INSTALLA_GREENBRAIN_WINDOWS.bat`
- `INSTALLA_GREENBRAIN_WINDOWS.ps1`
- `LEGGIMI_INSTALLAZIONE.txt`
- `customer-local-0.1.131.tar.gz`

## GHCR images

Backend:

- `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.131`
- Digest: `sha256:8f5214488b4815d4e58619dd57fe4e922f95fbccf11bc1f195b50e0322196855`

ML worker:

- `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.131`
- Digest: `sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680`

Nota: il backend 0.1.131 è stato rebuildato realmente dal package patchato. Non è un semplice retag della 0.1.130.

## Validazioni eseguite

### Package validation

Confermato:

- `VERSION=0.1.131`
- `package_version=0.1.131`
- marker password seed presenti nel package
- nessun secret file inatteso
- prebuilt compose senza `build:`
- nessun cron password sync automatico

### Bundle personalizzato z@gmail.com

Generati:

- `GreenBrain-Installer-0.1.131-z-20260603123703.zip`
- `customer-local-0.1.131-z-20260603123700.tar.gz`

SHA256 verificati correttamente.

Il bundle personalizzato contiene:

- `LOCAL_CUSTOMER_PASSWORD_VERSION=4`
- `LOCAL_CUSTOMER_PASSWORD_CHANGED_AT=2026-06-03T09:51:59.354966+00:00`
- `LOCAL_CUSTOMER_PASSWORD_SYNC_STATUS=synced`
- `LOCAL_CUSTOMER_PASSWORD_SEED_SOURCE=cloud_seed`

### Fresh install personalizzato

Fresh install test:

- path: `/tmp/gb_0131_fresh_personalized_v3_final_U3BnrV/package/customer-local-template`
- installazione completata con `INSTALL COMPLETED`
- backend image: `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.131`
- backend healthy
- frontend OK
- local DB credentials OK
- `LOCAL_USER_PROVISION_OK`

DB locale dopo install:

- `email = z@gmail.com`
- `tenant_code = z`
- `password_version = 4`
- `password_changed_at = 2026-06-03 09:51:59.354966+00`
- `password_change_source = cloud_seed`
- `password_last_sync_status = synced`
- `password_last_synced_at` valorizzato
- `password_last_sync_attempt_at` valorizzato
- `password_last_sync_error` vuoto

Login smoke:

- `GreenBrain2` -> HTTP 200
- `GreenBrain1` -> HTTP 401

Manual password sync after install:

- `PASSWORD_SYNC_PENDING_HTTP=200`
- `PASSWORD_SYNC_NO_PENDING`

Il run `NO_PENDING` non modifica il DB locale e non crea ACK inutili.

## Decisione architetturale

La 0.1.131 non abilita cron automatico per la password sync.

Il cron locale resta limitato a:

- heartbeat ogni 5 minuti
- daily sequence alle 21:05

La password sync resta manuale per questa release.

## Roadmap successiva

### 0.1.132 / prossima fase consigliata

1. Testare su Mac reale l'aggiornamento/installazione 0.1.131 dal portale.
2. Eseguire un nuovo ciclo password version 5:
   - cambio password cloud;
   - cloud pending;
   - locale ancora con vecchia password prima del sync;
   - sync manuale dentro scheduler;
   - locale aggiornato;
   - ACK cloud synced;
   - secondo run `NO_PENDING`;
   - zero failed.
3. Solo dopo valutare:
   - heartbeat actions come fallback sicuro;
   - event-driven push cloud -> runtime solo se `z.greenbrain.it` / tunnel è realmente raggiungibile;
   - evitare un cron password-sync ogni 5 minuti se possibile.

## Stato finale

La release 0.1.131 è validata end-to-end per:

- generazione bundle personalizzato;
- seed password metadata;
- fresh install con GHCR prebuilt;
- login locale con password cloud corrente;
- sync manuale `NO_PENDING`.

