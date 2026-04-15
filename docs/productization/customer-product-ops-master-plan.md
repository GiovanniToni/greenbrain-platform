# GreenBrain Customer Product & Ops Master Plan

## Obiettivo
Trasformare GreenBrain da installazione tecnica assistita a prodotto distribuibile e gestibile con flusso semplificato per il cliente.

## Principio chiave
Il cliente:
1. arriva dalla landing page
2. sceglie il piano
3. paga / sottoscrive
4. crea account GreenBrain
5. compila onboarding aziendale
6. riceve bundle e istruzioni
7. installa il runtime locale
8. completa con supporto GreenBrain il collegamento al DB sorgente
9. accede poi sempre con le stesse credenziali dal sito GreenBrain

## Architettura a 4 blocchi

### 1. Commerce / Signup
- landing page
- pricing
- checkout Stripe
- raccolta dati anagrafici
- creazione account cliente

### 2. Provisioning
- creazione tenant
- creazione utente admin
- registrazione runtime connection
- assegnazione release
- generazione delivery bundle
- invio mail iniziale

### 3. Customer Local Runtime
- installazione locale cliente
- overlay cliente compilato
- validazione
- avvio compose
- tunnel / accesso remoto
- integrazione DB sorgente cliente
- ETL / sync

### 4. Central Customer Ops
- dashboard interna clienti
- stato subscription
- stato onboarding
- versione installata
- versione disponibile
- stato tunnel
- stato sync
- stato DB integration
- invio aggiornamenti
- dettaglio cliente

## Cosa esiste già
- release customer-local
- build release versionata
- package clean
- validate instance
- onboarding tenant/runtime
- update da template
- bundle delivery helpers
- base/overlay model
- cloud sync primitives
- runbook iniziali

## Gap da chiudere
1. flusso commerciale centralizzato
2. onboarding utente/tenant automatico
3. dashboard clienti centrale
4. update management centralizzato
5. installazione cliente ancora più guidata
6. runbook DB source integration più operativo
7. area cliente riservata dal sito
8. area ops GreenBrain con vista completa clienti

## Regola architetturale
Identità utente unica centrale GreenBrain:
- stessa email/password per onboarding, login, area riservata e accesso successivo alla piattaforma

## Regola operativa
La release consegnata al cliente:
- non contiene segreti runtime reali
- non contiene overlay già compilati per clienti reali
- è installabile, validabile e aggiornabile
