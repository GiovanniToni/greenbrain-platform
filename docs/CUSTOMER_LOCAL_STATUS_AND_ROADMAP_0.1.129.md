# GreenBrain Customer Local — Status & Roadmap 0.1.129

Data: 2026-05-30
Branch: feat/customer-ops-supabase-foundation
Ultimo commit validato: a3dd9caa fix(frontend): align customer detail release state

## Stato sintetico

La milestone 0.1.129 ha completato l'allineamento tra area cliente cloud, lista clienti ops e dettaglio cliente ops, in modo da rappresentare correttamente lo stato reale del runtime locale.

Caso validato principale: tenant z.

Stato reale validato per z:

- piattaforma attiva: sì
- runtime connection: healthy
- installation id: bf095292-f24a-42c4-97c1-d83e9a4a6084
- versione installata / local agent: 0.1.122
- ultima release disponibile: 0.1.128
- ultima release scaricata: 0.1.128
- stato aggiornamento: Scaricata, da installare

La distinzione ora è corretta: piattaforma attiva / runtime healthy non significa necessariamente runtime aggiornato all'ultima release disponibile.

## Fix principali completati

### 1. Runtime heartbeat e abilitazione piattaforma

Il backend runtime abilita la piattaforma dopo heartbeat healthy e aggiorna correttamente lo stato runtime cliente.

Commit principali:
- 23f6a242 fix(customer-ops): align runtime installation state with portal
- f39388c0 fix(customer-runtime): accept extended heartbeat payload

Effetto:
- /api/v1/auth/me restituisce platform_enabled=true
- home_path=/dashboard quando il runtime è healthy
- il cliente vede le sezioni operative solo dopo completamento installazione e heartbeat healthy

### 2. Area cliente /account

La pagina cliente cloud ora mostra piattaforma attiva, runtime healthy, versione installata, ultima disponibile, ultima scaricata e avviso se un aggiornamento è stato scaricato ma non installato.

Commit principali:
- 76d05795 chore(frontend): type runtime installation state fields
- 867dea6b fix(frontend): use unified runtime installation state
- 242a3985 fix(frontend): clarify customer account platform state
- dc695273 fix(frontend): show downloaded update pending install

### 3. Customer list /customers

La lista ops clienti ora è allineata con detail e account cliente.

Commit principali:
- 723b68de fix(customer-ops): enrich customer list release state
- 194408e0 fix(frontend): align customer list release state

Per z, /customers mostra installazione spuntata, piattaforma attiva, disponibile 0.1.128, scaricata 0.1.128, installata 0.1.122 e badge Scaricata, da installare.

### 4. Customer detail /customers/:customerId

Il dettaglio ops cliente ora è allineato con lista e account.

Commit principale:
- a3dd9caa fix(frontend): align customer detail release state

Per z, /customers/:id mostra piattaforma attiva, stato connessione healthy, installation id registrata, release installata 0.1.122, runtime pubblico https://z.greenbrain.it, agent locale 0.1.122, ultima release disponibile 0.1.128 e stato aggiornamento Scaricata, da installare.

### 5. Routing pubblico Nginx

Problema trovato: www.greenbrain.it instradava /api/v1/customer-ops/... verso la location generica /api/v1/customer su porta 3001.

Fix applicato: aggiunta location specifica /api/v1/customer-ops/ verso 127.0.0.1:8002, sia su HTTP sia HTTPS.

Validazione:
- backup Nginx spostato fuori da sites-enabled
- nginx -t OK
- systemctl reload nginx OK
- API pubblica customer-ops ora restituisce i campi aggiornati da 8002

### 6. Frontend pubblico

Problema trovato: www.greenbrain.it non usa dev_frontend, ma serve staticamente /opt/greenbrain-platform/apps/frontend/dist.

Fix:
- rebuild frontend host con npm run build
- dist pubblico aggiornato
- browser validato

## Validazione finale pubblica

Endpoint validato: https://www.greenbrain.it/api/v1/customer-ops/customers/28265444-dbda-4f94-93cf-75e6305466c6

Risultato finale per z:
- tenant_code=z
- latest_available_release_version=0.1.128
- last_downloaded_release_version=0.1.128
- installed_release_version=0.1.122
- platform_ready=True
- installation_status_label=Piattaforma attiva
- runtime_connection_status=healthy
- runtime_local_agent_version=0.1.122
- latest_installation_id=bf095292-f24a-42c4-97c1-d83e9a4a6084

## Stato Git

Branch pushata: feat/customer-ops-supabase-foundation
Remote aggiornata da 54756c2a a a3dd9caa.

Commit inclusi nel blocco 0.1.129:
- a3dd9caa fix(frontend): align customer detail release state
- 194408e0 fix(frontend): align customer list release state
- 723b68de fix(customer-ops): enrich customer list release state
- dc695273 fix(frontend): show downloaded update pending install
- 242a3985 fix(frontend): clarify customer account platform state
- 867dea6b fix(frontend): use unified runtime installation state
- 76d05795 chore(frontend): type runtime installation state fields
- 23f6a242 fix(customer-ops): align runtime installation state with portal

## Decisione

Si procede con opzione B: release runtime 0.1.129.

Motivazione:
- il frontend runtime/customer-local beneficia delle stesse correzioni di stato
- la logica cloud/ops è ora coerente con il bundle/customer flow
- la release 0.1.129 diventa un punto stabile per proseguire con update/install flow cliente

## Prossimi step 0.1.129 runtime

1. bump deploy/customer-local-template/VERSION
2. bump deploy/customer-local-template/release-manifest.yml
3. build bundle customer-local
4. build universal installer
5. validazione package
6. validazione download personalizzato
7. tag customer-local-0.1.129 solo dopo validazione
