# Customer Commercial and Runtime Data Model

## Obiettivo
Definire le entità centrali per gestire cliente, billing, runtime e onboarding.

## Entità principali

### Customer Company
Dati anagrafici del cliente:
- company_name
- vat_number
- address
- city
- country
- contact_name
- contact_email
- contact_phone

### Tenant
Dati logici runtime:
- tenant_code
- tenant_name
- app_host
- access_mode
- runtime_origin
- data_mode
- status

### Customer User
Utente/i del cliente:
- email
- password_hash
- role
- tenant_code
- status
- home_host

### Subscription
Billing / Stripe:
- stripe_customer_id
- stripe_subscription_id
- plan_code
- subscription_status
- billing_email
- current_period_end

### Runtime Connection
Stato tecnico del runtime:
- tenant_code
- connection_mode
- sync_enabled
- sync_frequency_minutes
- local_agent_version
- runtime_health
- last_sync_status
- notes

### Delivery / Install
Stato installativo:
- assigned_release_version
- bundle_generated_at
- bundle_sent_at
- install_status
- onboarding_status
- go_live_at

### DB Source Integration
Stato collegamento DB sorgente:
- db_type
- db_host
- db_port
- db_name
- db_schema
- connection_status
- mapping_status
- initial_etl_status
- notes

## Nota
Parte di queste informazioni esiste già o è implicitamente distribuita.
Va consolidata in modello coerente lato backend centrale.
