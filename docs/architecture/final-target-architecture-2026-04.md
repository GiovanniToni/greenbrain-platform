# Final Target Architecture - April 2026

## Dev
- hosted in cloud
- frontend web
- backend cloud
- db/storage cloud
- current target: Supabase

## Central auth
- login centrale su www.greenbrain.it
- tenant registry centrale
- SSO / tenant routing centrale

## Cliente reale
- frontend locale
- backend locale
- db locale
- ML locale
- dati locali
- launcher desktop locale

## Accesso remoto cliente
- ingresso da www.greenbrain.it
- login centrale
- instradamento tenant
- tunnel sicuro outbound dal runtime cliente
- API del runtime cliente raggiungibile solo tramite tunnel/autenticazione
- nessun raw data sync standard verso cloud GreenBrain

## Principio dati
- i dati del cliente restano del cliente
- nessun cloud GreenBrain come archivio standard dei dati cliente
- eventuali cache/telemetria minime solo se esplicitamente abilitate

## Stato componenti
### Keep
- auth centrale
- nginx + https
- dev cloud
- tenant registry
- SSO

### Non modello finale cliente
- hosted tenant demo tipo cliente1
- cloud_sync come modello standard cliente
