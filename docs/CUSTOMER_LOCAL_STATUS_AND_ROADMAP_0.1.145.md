# GreenBrain Customer Local 0.1.145 — Stato release e roadmap

Data chiusura: 2026-06-12  
Branch: `feat/customer-ops-supabase-foundation`  
Tag: `customer-local-0.1.145`  
Commit release/tag: `6e0aac94483b4d40bedccb62af8342b890b13aca`

## Stato finale

La release `0.1.145` è chiusa, validata, pushata e taggata.

Il tag `customer-local-0.1.145` punta al commit finale corretto:

```text
6e0aac94483b4d40bedccb62af8342b890b13aca
```

Il commit finale include la correzione:

```text
fix(customer-local): persist runtime image tag in env
```

Questa patch è stata necessaria perché, durante la validazione del bundle personalizzato, Docker Compose risolveva le immagini su `latest` invece che su `0.1.145`. La causa era che `install.sh` calcolava correttamente `GREENBRAIN_IMAGE_TAG=0.1.145`, ma non lo persisteva in `overlay/env/customer-local.env`, cioè il file usato da `docker compose --env-file`.

## Correzione principale 0.1.145

La release introduce la persistenza esplicita del tag runtime:

```env
GREENBRAIN_IMAGE_TAG=0.1.145
```

Il valore viene scritto/aggiornato in:

```text
overlay/env/customer-local.env
```

durante l'installazione, tramite funzione dedicata in:

```text
deploy/customer-local-template/install.sh
```

È stato inoltre aggiunto il valore di default nel template:

```text
deploy/customer-local-template/env/customer-local.env.example
```

## Source DB technical flow

La release `0.1.145` include il flusso tecnico Source DB customer-local:

- servizio dedicato `source-db-importer`;
- script locale `base/scripts/test-source-db-technical.sh`;
- uploader `base/scripts/upload-source-db-technical-report.sh`;
- checker `base/apps/source-db-importer/technical_check_source_db.py`;
- import script `base/apps/source-db-importer/import_sales_raw.py`;
- upload report verso endpoint cloud `/api/v1/customer-runtime/source-db/technical-check`;
- upload non bloccante rispetto al risultato tecnico locale;
- supporto a stato `technical_test_ok` / `technical_test_failed`.

Nel test senza configurazione Source DB reale, il checker restituisce correttamente `technical_test_failed` per assenza di `overlay/env/source-db.env`, ma l'upload del report al cloud funziona con HTTP 200. Questo è il comportamento atteso nello smoke test.

## Validazioni completate

### Static release validation

Passata:

```text
CUSTOMER_LOCAL_RELEASE_STATIC_VALIDATION_OK version=0.1.145
```

Verificati:

- `BUILD-INFO.txt`;
- `customer-local-0.1.145.tar.gz`;
- `INSTALLA_GREENBRAIN.run`;
- `GreenBrain-Installer.zip`;
- payload TAR;
- payload ZIP embedded;
- versione `0.1.145`;
- proxy nginx locale `backend:8000`;
- password sync run-local;
- Source DB technical flow;
- assenza vecchio proxy `host.docker.internal:8008`;
- compose prebuilt senza build sections.

### Image validation

Passata:

```text
CUSTOMER_LOCAL_IMAGES_VALIDATION_OK version=0.1.145
```

Immagini validate:

```text
ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.145
ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.145
ghcr.io/giovannitoni/greenbrain-customer-source-db-importer:0.1.145
```

Digest validati:

```text
backend:            sha256:bec942304ed9ded6a8573ab1e762a61ae8abb665c63d00f2930249c70af26976
ml-worker:          sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680
source-db-importer: sha256:48b64c7f51c0923851d07b38e9b274b44b6039d1658c9f9e38df56e51342f672
```

### Fresh reset personalizzato tenant z

Passato con bundle personalizzato `z`.

Marker principali:

```text
LOGIN_OK
DOWNLOAD_OK
PERSONALIZED_REBUILT_PAYLOAD_PATCH_OK
FRESH_RESET_INSTALL_OK
ENV_IMAGE_TAG_0_1_145_OK
RESOLVED_BACKEND_IMAGE_0_1_145_OK
RESOLVED_ML_WORKER_IMAGE_0_1_145_OK
RESOLVED_SOURCE_DB_IMPORTER_IMAGE_0_1_145_OK
BACKEND_HEALTH_CONFIRMED_OK
FRONTEND_HTTP_CONFIRMED_OK
SOURCE_DB_TECHNICAL_CHECKER_SMOKE_OK
CUSTOMER_LOCAL_0_1_145_Z_REBUILT_FRESH_RESET_IMAGE_TAG_57K_OK
```

Installazione validata:

- tenant: `z`;
- installazione runtime: generata correttamente;
- backend health OK;
- frontend HTTP OK;
- local DB credentials OK;
- local user `z@gmail.com` provisionato;
- password version cloud seed `33`;
- password sync status `synced`;
- Source DB checker smoke OK;
- upload report Source DB technical check OK.

## Artifact release

Directory:

```text
releases/customer-local/0.1.145/
```

Artifact:

```text
BUILD-INFO.txt
customer-local-0.1.145.tar.gz
INSTALLA_GREENBRAIN.run
GreenBrain-Installer.zip
universal-installer/
package/
```

Checksum SHA256:

```text
customer-local-0.1.145.tar.gz  cdeea4c19da33890b592a305e5858b9f7aff6c1edd0b40b1c476ba5a55fe2191
INSTALLA_GREENBRAIN.run        2c3161bbb4bd46d7b33c3e85829e39981c27feedf1ca0747658937a6f8022579
GreenBrain-Installer.zip       a7286cdc938dd832374af323e51f3e0efec7d0ac5d0a82fb9705898043e1aa11
BUILD-INFO.txt                 3f23773a30eb4ec72df2fe24dc403ff4cc3eab65e5bd754e248c5b70ef3d4e80
```

`BUILD-INFO.txt`:

```text
release_version=0.1.145
built_at=2026-06-12T17:47:13Z
git_commit=6e0aac94483b4d40bedccb62af8342b890b13aca
```

## Nota su Docker image aliases

Durante i test, `docker compose images` può mostrare tag storici locali, ad esempio `0.1.144`, `0.1.106` o `test-50D`, perché Docker associa più tag allo stesso image ID locale.

La validazione decisiva è il compose config risolto:

```text
image: ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.145
image: ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.145
image: ghcr.io/giovannitoni/greenbrain-customer-source-db-importer:0.1.145
```

e il marker:

```text
ENV_IMAGE_TAG_0_1_145_OK
```

## Stato Git finale

Branch remoto allineato:

```text
origin/feat/customer-ops-supabase-foundation -> 6e0aac94483b4d40bedccb62af8342b890b13aca
```

Tag remoto allineato:

```text
customer-local-0.1.145 -> 6e0aac94483b4d40bedccb62af8342b890b13aca
```

Untracked intenzionali lasciati fuori release:

```text
docs/analysis/bundle_plugnplay_plan_20260521.md
docs/analysis/exec_plan_0.1.122.md
docs/analysis/report_0.1.122_20260520.md
releases/customer-local-0.1.122.tar.gz
```

## Roadmap prossimi task

### Priorità 1 — Source DB reale cliente

Obiettivo: completare il collegamento reale al database sorgente SQL Server del cliente.

Passi consigliati:

1. creare/validare la vista standard `GREENBRAIN_VIEW_SALES_RAW` su SQL Server;
2. compilare `overlay/env/source-db.env`;
3. lanciare `bash base/scripts/test-source-db-technical.sh`;
4. verificare:
   - connessione ODBC;
   - presenza colonne obbligatorie;
   - presenza colonne raccomandate;
   - `COUNT_BIG(*)`;
   - `MAX(data_movimento)`;
   - upload report al cloud;
5. solo dopo, abilitare import effettivo vendite grezze.

### Priorità 2 — UX Source DB nel portale

Mostrare in modo chiaro al cliente/admin:

- stato formale;
- stato tecnico;
- ultimo test;
- errori tecnici leggibili;
- istruzioni operative per correggere configurazione SQL Server;
- differenza tra `configurazione mancante`, `connessione fallita`, `vista assente`, `colonne mancanti`.

### Priorità 3 — Import vendite raw

Dopo technical test OK:

- import incrementale da SQL Server;
- salvataggio in Postgres locale;
- gestione progressivo/data movimento;
- log e idempotenza;
- eventuale upload/sync cloud solo se necessario.

### Priorità 4 — Hardening release automation

Integrare nei validatori:

- controllo che `GREENBRAIN_IMAGE_TAG` venga scritto in `customer-local.env`;
- controllo compose config risolto a versione release;
- controllo bundle personalizzato anti-cache;
- controllo Source DB checker/uploader;
- controllo immagini GHCR per backend, ml-worker e source-db-importer.

### Priorità 5 — Pulizia token/installazioni test

Creare strumenti admin sicuri per:

- elencare installazioni vecchie;
- individuare token usati/scaduti;
- mantenere l’ultima installazione healthy;
- preparare cleanup plan;
- eseguire cleanup solo con conferma esplicita.

## Decisione operativa

La release `0.1.145` è chiusa.

Il prossimo ciclo dovrebbe partire da `0.1.146`, senza spostare il tag `customer-local-0.1.145`.

