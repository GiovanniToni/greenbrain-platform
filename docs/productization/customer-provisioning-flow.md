# Customer Provisioning Flow

## Obiettivo
Passare da semplice customer record a provisioning operativo.

## Flusso
1. creare customer nel control plane
2. assegnare release ufficiale
3. generare delivery bundle
4. inviare istruzioni installazione
5. tracciare stato onboarding/installazione
6. completare tunnel e DB integration

## Stato attuale
Esiste:
- customer_ops control plane
- create/list customer
- bundle delivery helper

## Step successivo
Collegare:
- assign_release
- prepare bundle
- tracking delivery
- customer portal download
