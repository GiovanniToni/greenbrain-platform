# GreenBrain Customer Local — Status and Roadmap 0.1.147

Data: 2026-06-18  
Release: `customer-local-0.1.147`  
Tag: `customer-local-0.1.147`  
Commit release/tag: `0f813a6b13ff6e495cb1ffb606ddf414bb3bcacd`  
Commit message: `chore(customer-local): bump runtime template to 0.1.147`

## Sintesi

La release `0.1.147` consolida il ponte operativo Source DB introdotto in `0.1.146`.

L’obiettivo principale è completare il passaggio:

1. configurazione Source DB nel portale cloud;
2. validazione formale della configurazione;
3. generazione bundle personalizzato con `overlay/env/source-db.env` già precompilato;
4. wizard locale compatibile con le chiavi lette da importer/checker;
5. validazione statica permanente su TAR e ZIP;
6. installazione fresca validata end-to-end.

La release non introduce ancora blocchi di slot, attivazione dati o subscription legati a Source DB. Questi rimangono step successivi.

## Scope funzionale 0.1.147

### 1. Prefill Source DB nei bundle personalizzati

Il backend cloud ora può generare `overlay/env/source-db.env` nel bundle cliente personalizzato quando esiste una configurazione Source DB con:

- `formal_validation_status = formal_validation_ok`;
- password cifrata presente;
- campi minimi DB disponibili;
- credenziali decrittabili correttamente.

Il file viene generato solo in modo condizionale e sicuro. Se la configurazione non è formalmente valida, incompleta o non decrittabile, il bundle viene generato senza `source-db.env` e il runtime locale continua a funzionare in modalità “Source DB not configured”.

### 2. Chiavi Source DB coerenti tra wizard, checker e importer

Il wizard locale ora scrive la chiave standard:

- `SOURCE_DB_NAME`

e mantiene anche alias di compatibilità:

- `SOURCE_DB_DATABASE`

Questo risolve il mismatch precedente: importer e technical checker leggono `SOURCE_DB_NAME`, mentre una parte del wizard scriveva solo `SOURCE_DB_DATABASE`.

Le chiavi validate sono:

- `SOURCE_DB_NAME`
- `SOURCE_DB_SCHEMA`
- `SOURCE_DB_VIEW`
- `SOURCE_DB_CLIENT_CODE`
- `SOURCE_DB_TRUST_CERT`

### 3. Validator release rafforzato

`tools/validation/validate_customer_local_release.sh` ora controlla la presenza delle chiavi Source DB nel wizard sia nel payload TAR sia nel payload ZIP embedded.

Marker aggiunti e validati:

- `SOURCE_DB_WIZARD_ENV_KEYS_OK`
- `SOURCE_DB_ZIP_WIZARD_ENV_KEYS_OK`

### 4. Source DB opzionale e non bloccante

Per tenant senza configurazione Source DB formalmente valida, l’installazione rimane valida e il daily locale continua a passare con:

- `SOURCE_DB_IMPORT_NOT_CONFIGURED`

Questo comportamento è corretto per clienti non ancora configurati.

## Commit inclusi dopo 0.1.146

- `dc5ead70 fix(customer-local): prefill source db env in personalized bundles`
- `4b221645 test(customer-local): validate source db wizard env keys`
- `0f813a6b chore(customer-local): bump runtime template to 0.1.147`

## Artefatti release

Directory release:

- `/opt/greenbrain-platform/releases/customer-local/0.1.147/`

File principali:

- `BUILD-INFO.txt`
- `customer-local-0.1.147.tar.gz`
- `INSTALLA_GREENBRAIN.run`
- `GreenBrain-Installer.zip`

SHA256:

- `030f97c9386d7172126fb7bd0117d034f3d95f1750695656a89e86b1008bb186` — `BUILD-INFO.txt`
- `13c277013b54f59c9a20163baafdf59433a645201bf7cfe218e778c431f66ea3` — `customer-local-0.1.147.tar.gz`
- `c55a9cd6cb86024f36d562850aa083ffdcef62cefa40e2bc07c48125f858ce37` — `INSTALLA_GREENBRAIN.run`
- `9a7461bc1b29552d4a55fc97f50492635e51c85345b36ac61770405300a14b7f` — `GreenBrain-Installer.zip`

`BUILD-INFO.txt`:

- `release_version=0.1.147`
- `git_commit=0f813a6b13ff6e495cb1ffb606ddf414bb3bcacd`

## Immagini GHCR

Le immagini `0.1.147` sono state retaggate da `0.1.146`, pushate e pull-validate.

Digest:

- `greenbrain-customer-backend:0.1.147`
  - `sha256:bec942304ed9ded6a8573ab1e762a61ae8abb665c63d00f2930249c70af26976`
- `greenbrain-customer-ml-worker:0.1.147`
  - `sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680`
- `greenbrain-customer-source-db-importer:0.1.147`
  - `sha256:48b64c7f51c0923851d07b38e9b274b44b6039d1658c9f9e38df56e51342f672`

Validazioni immagini:

- backend image pull OK;
- ml-worker image pull OK;
- source-db-importer image pull OK;
- source-db-importer smoke OK con `ODBC Driver 18 for SQL Server`.

## Validazioni eseguite

### Static release validation

Passata con:

- `CUSTOMER_LOCAL_RELEASE_STATIC_VALIDATION_OK version=0.1.147`
- `SOURCE_DB_WIZARD_ENV_KEYS_OK`
- `SOURCE_DB_ZIP_WIZARD_ENV_KEYS_OK`

### Image validation

Passata con:

- `CUSTOMER_LOCAL_IMAGES_VALIDATION_OK version=0.1.147`
- `SOURCE_DB_IMPORTER_IMAGE_BASIC_SMOKE_OK`

### Fresh install validation

Passata per tenant `z`.

Risultato:

- `CUSTOMER_LOCAL_FRESH_INSTALL_VALIDATION_OK version=0.1.147 tenant=z`
- `CUSTOMER_LOCAL_0_1_147_FRESH_INSTALL_VALIDATION_73F_TER_OK`

Bundle personalizzato scaricato:

- `GreenBrain-Installer-0.1.147-z-20260618104730.zip`

SHA256 bundle personalizzato:

- `0367dc5ed2cb03c883e4e53354262434f31ef7673267a56a1cea61f8862d9af9`

Installazione locale validata:

- `installation_id=337d817a-02f2-417d-8b5d-fc0aae6094e8`
- `token_hint=0p25kY`

Runtime locale:

- backend healthy;
- frontend healthy;
- backend image `0.1.147`;
- ml-worker image `0.1.147`;
- source-db-importer image `0.1.147`;
- local login OK;
- password sync run-local OK con `no_pending`;
- extended doctor OK;
- run-local-daily-once OK;
- heartbeat cloud OK;
- `installed_release_version=0.1.147`;
- `local_agent_version=0.1.147`;
- `runtime_health=healthy`.

Per tenant `z`, Source DB non era configurato e il comportamento corretto è stato:

- `SOURCE_DB_IMPORT_NOT_CONFIGURED`

## Stato finale

Branch:

- `feat/customer-ops-supabase-foundation`

Tag:

- `customer-local-0.1.147`

Il tag punta al commit di bump release:

- `0f813a6b13ff6e495cb1ffb606ddf414bb3bcacd`

La branch è stata pushata fino al commit di release e il tag è stato pushato.

## Roadmap successiva

### 0.1.148 — possibili prossimi step

1. Test end-to-end Source DB con un cliente reale con configurazione `formal_validation_ok`.
2. Verifica bundle personalizzato con `source-db.env` effettivamente presente su cliente formalmente valido.
3. Test tecnico reale contro SQL Server gestionale.
4. Miglioramento UX portale customer/admin per evidenziare:
   - configurazione formalmente valida;
   - bundle Source DB precompilato;
   - ultimo technical check;
   - ultimi errori classificati.
5. Eventuale gating successivo su slot, onboarding e data activation, solo dopo test reale Source DB completato.
6. Hardening log installer: evitare stampa di payload utente troppo esteso durante provisioning locale.

## Note operative

File non tracciati intenzionali rimasti fuori release:

- `docs/analysis/bundle_plugnplay_plan_20260521.md`
- `docs/analysis/exec_plan_0.1.122.md`
- `docs/analysis/report_0.1.122_20260520.md`
- `releases/customer-local-0.1.122.tar.gz`
