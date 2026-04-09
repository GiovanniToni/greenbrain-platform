# Next Step - Local Runtime Sync Plan

## Decisione
Per clienti reali scegliamo:
- runtime locale completo presso il cliente
- login centrale su greenbrain.it
- frontend cloud
- sync selettivo locale -> cloud
- niente esposizione diretta del DB cliente
- niente API pubblica dal punto vendita

## Perché
- più semplice
- più sicuro
- meno fragile su rete/firewall/NAT
- il cliente mantiene dati e infrastruttura locali
- in cloud arrivano solo aggregati e risultati necessari

## Stato attuale
- tenant registry centrale attivo
- user routing view attiva
- SSO centrale attivo
- tenant hosted attivi:
  - greenbrain
  - cliente1

## Step successivi
1. schema cloud per dati sincronizzati
2. sync agent locale
3. job di push schedulato
4. monitor stato sync
5. onboarding tenant reale
