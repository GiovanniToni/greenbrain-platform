# GreenBrain Customer Local — Status & Roadmap 0.1.124

Data: 2026-05-28  
Branch: feat/customer-ops-supabase-foundation  
Release: customer-local-0.1.124

## Stato precedente

La release 0.1.123 aveva consolidato:

- wizard port fallback: se 8099 è occupata, il launcher seleziona una porta libera tra 8099, 8100, 8101, 8110;
- package staging pulito: esclusione di file .bak, venv, overlay/logs, pycache ed env reali.

La release 0.1.122 era già stata validata end-to-end su Mac con bundle personalizzato scaricato dal portale come z@gmail.com.

## Obiettivo 0.1.124

Gestire correttamente il caso in cui esista una vecchia installazione GreenBrain locale con volume Postgres già inizializzato con credenziali diverse dal nuovo bundle.

Problema precedente:

- l’installer poteva entrare in modalità update;
- il backend risultava healthy;
- il provisioning utente falliva con traceback tecnico password authentication failed;
- il messaggio non spiegava chiaramente che il volume Postgres era incompatibile.

## Modifiche 0.1.124

### 1. Alias fresh install

Aggiunto supporto a:

GREENBRAIN_FORCE_FRESH_INSTALL=1

come alias operativo di:

GREENBRAIN_INSTALL_MODE=fresh-reset

### 2. Verifica credenziali DB dal backend

Aggiunto controllo prima di provision-local-user.sh:

== VERIFY LOCAL DB CREDENTIALS ==

La verifica viene eseguita dal container backend verso postgres:5432 usando psycopg, quindi replica il percorso reale del provisioning.

In caso di password o volume incompatibile, l’installer esce con:

LOCAL_DB_CREDENTIALS_FAILED
ERROR: il database locale esiste ma le credenziali non sono compatibili con questo bundle.

e suggerisce:

GREENBRAIN_FORCE_FRESH_INSTALL=1 GREENBRAIN_CONFIGURE_SOURCE_DB=no bash install.sh

oppure:

GREENBRAIN_INSTALL_MODE=fresh-reset GREENBRAIN_CONFIGURE_SOURCE_DB=no bash install.sh

### 3. Docker exec corretto

La verifica usa docker exec -i per passare correttamente lo script Python al container backend.

### 4. Fresh reset idempotente

Corretto il cleanup dei volumi in fresh_reset_existing_stack(), rendendolo sicuro con set -euo pipefail.

Il cleanup non interrompe più lo script se non trova volumi da rimuovere.

## Validazioni 0.1.124

### Caso negativo: volume Postgres incompatibile

Test:

- volume inizializzato con POSTGRES_PASSWORD=test_password_0124;
- env modificato con POSTGRES_PASSWORD=wrong_password_0124;
- installazione rilanciata in update mode.

Risultato ottenuto:

- exit code 31;
- LOCAL_DB_CREDENTIALS_FAILED;
- messaggio user-friendly;
- nessun LOCAL_USER_PROVISION_OK;
- nessun INSTALL COMPLETED;
- nessun traceback tecnico finale del provisioning.

### Caso positivo: fresh-reset

Test:

- env buono ripristinato;
- GREENBRAIN_FORCE_FRESH_INSTALL=1;
- installazione pulita.

Risultato ottenuto:

- PREFLIGHT_LOCAL_INSTALL_OK;
- LOCAL_DB_CREDENTIALS_OK user=greenbrain_z db=greenbrain_z;
- LOCAL_USER_PROVISION_OK;
- backend healthy;
- frontend HTTP 200;
- DB greenbrain_z;
- utente locale z@gmail.com presente come customer_admin;
- INSTALL COMPLETED.

### Package validation

- customer-local-0.1.124.tar.gz buildato correttamente.
- GreenBrain-Installer.zip buildato correttamente.
- Embedded tar contiene VERSION=0.1.124 e package_version=0.1.124.
- Embedded tar contiene GREENBRAIN_FORCE_FRESH_INSTALL, VERIFY LOCAL DB CREDENTIALS, LOCAL_DB_CREDENTIALS_FAILED, docker exec -i e done || true.
- Embedded tar pulito: nessun .bak, venv, overlay/logs, pycache, .pyc o env reale.

## File release

- /opt/greenbrain-platform/releases/customer-local/0.1.124/customer-local-0.1.124.tar.gz
- /opt/greenbrain-platform/releases/customer-local/0.1.124/GreenBrain-Installer.zip

## Prossimi hardening

1. Download bundle:
   - header anti-cache;
   - logging esplicito;
   - directory output bundle visibile host/container.

2. Wizard UX:
   - bottone “Reinstalla da zero” che imposta GREENBRAIN_FORCE_FRESH_INSTALL=1;
   - messaggio chiaro quando vecchi volumi sono incompatibili.

3. Test automatici:
   - bundle personalizzato da portale;
   - 8099 occupata;
   - vecchio volume incompatibile;
   - fresh-reset positivo.
