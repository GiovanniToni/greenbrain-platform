# Customer Billing + Onboarding Target Model

## Obiettivo
Allineare GreenBrain a un modello in cui:
- il cliente crea account e sceglie il piano
- inserisce i dati di pagamento / metodo di pagamento
- GreenBrain esegue onboarding tecnico manuale
- il charge effettivo parte solo quando il collegamento è completato e il cliente è operativo

## Piani
### 1. Storico — 99€/mese
- accesso dati storici del cliente
- analisi e consultazione storico
- nessuna previsione
- nessuna logica completa fornitori

### 2. Forecast — 149€/mese
- include piano Storico
- previsioni
- riordino basato su storico + forecast

### 3. Complete — 199€/mese
- include piano Forecast
- sezione fornitori
- raccolta disponibilità fornitori
- confronto disponibilità/prezzi
- supporto decisionale su dove acquistare

## Nuova logica commerciale
1. signup account
2. scelta piano
3. raccolta metodo di pagamento
4. stato cliente = onboarding tecnico da completare
5. GreenBrain collega DB locale / tunnel / normalizzazione dati / verifica accesso
6. solo dopo attivazione tecnica il cliente passa a stato attivo
7. solo da quel momento parte la fatturazione effettiva

## Implicazioni di prodotto
- "checkout completed" NON deve significare "servizio attivo"
- serve distinzione tra:
  - payment method collected
  - onboarding technical pending
  - onboarding in progress
  - activation completed
  - billing started
- bundle/download non deve essere mostrato come pronto se onboarding tecnico non è concluso

## Stati suggeriti
### Subscription/Billing
- payment_pending
- payment_method_collected
- activation_pending
- activation_in_progress
- active
- paused
- canceled

### Onboarding
- signup_started
- payment_method_collected
- technical_review_pending
- technical_setup_in_progress
- normalization_in_progress
- customer_validation_pending
- active

## Regola fondamentale
Il charge reale / start billing avviene solo quando:
- DB cliente collegato
- tunnel configurato
- dati normalizzati
- accesso web funzionante
- provisioning validato

## UI target
### Landing
- funnel verso pricing e signup

### Pricing
- 3 piani chiari
- focus su attivazione guidata
- no promessa di operatività immediata

### Signup
- creazione account
- selezione piano
- aspettativa chiara: onboarding tecnico assistito

### Account
- mostrare:
  - piano scelto
  - stato pagamento
  - stato onboarding tecnico
  - stato attivazione
  - disponibilità accesso/dataset/bundle
- se pagamento raccolto ma onboarding non concluso:
  - NO "abbonamento attivo"
  - SI "attivazione tecnica in corso"
