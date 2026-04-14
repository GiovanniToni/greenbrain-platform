# Customer Local Install Runbook

## Scopo
Installare GreenBrain presso un nuovo cliente in locale.

## Input richiesti
- release ufficiale customer-local-X.Y.Z.tar.gz
- tenant_code
- tenant_name
- tenant_host
- credenziali locali runtime
- parametri tunnel
- accesso al DB sorgente cliente
- strategia ETL / sync

## Procedura

### 1. Estrarre la release
Usare install_customer_local.sh oppure estrazione manuale del tar.gz.

### 2. Configurare il runtime locale
Compilare:
- overlay/env/customer-local.env
- overlay/tunnel/cloudflared/config.yml
- overlay/tunnel/cloudflared/cloudflared.env

### 3. Validare
Eseguire validate_customer_local_instance.sh

### 4. Registrare tenant centrale
Usare:
- register_local_runtime_tenant.sh
- register_tenant_in_auth.sh

### 5. Avviare runtime locale
docker compose up -d --build

### 6. Verificare
- health backend
- frontend locale
- login remoto
- routing tenant
- tunnel
- sync agent

### 7. Collegare DB sorgente cliente
Attività manuale tecnica:
- capire DB sorgente cliente
- definire mapping raw -> GreenBrain
- configurare ETL locale
- verificare prime importazioni

## Nota importante
L'installazione del runtime è standardizzabile.
Il collegamento al DB grezzo del cliente resta una fase tecnica assistita da GreenBrain.
