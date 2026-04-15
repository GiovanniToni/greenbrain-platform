# Customer Portal and Ops Console

## Obiettivo
Definire due superfici applicative centrali:

1. Area cliente accessibile dal sito GreenBrain
2. Dashboard interna GreenBrain per gestione clienti, versioni e aggiornamenti

## Area cliente
Accessibile dalla landing / sito GreenBrain.

### Funzioni
- signup / login
- gestione abbonamento
- dati aziendali
- stato onboarding
- download bundle
- istruzioni installazione
- stato installazione
- stato collegamento DB
- supporto / contatti
- accesso alla piattaforma GreenBrain

### Credenziali
Le credenziali create in signup restano le credenziali ufficiali del cliente.

## Dashboard ops GreenBrain

### Vista lista clienti
- customer name
- tenant_code
- subscription status
- onboarding status
- installed version
- target version
- runtime health
- tunnel status
- sync status
- db integration status

### Scheda cliente
- anagrafica
- contatti
- tenant/runtime
- utenti
- release assegnata
- storico aggiornamenti
- stato accesso remoto
- stato integrazione DB
- note operative

### Azioni operative
- registrare / modificare tenant
- vedere versione installata
- vedere clienti da aggiornare
- inviare comunicazione update
- aprire dettaglio cliente
- marcare stati onboarding / integrazione

## Dipendenze applicative future
- backend endpoints per customer ops
- frontend schermate per area cliente
- frontend schermate per dashboard ops
- integrazione Stripe
- invio email transazionali
