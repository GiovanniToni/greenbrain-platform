# Client Local Runtime with Cloud Frontend

## Obiettivo
Il cliente installa tutto in locale:
- database
- ML
- codice
- dati
- programma

L'accesso utente avviene da greenbrain.it.

## Flusso desiderato
1. utente apre https://www.greenbrain.it
2. login centrale
3. il sistema riconosce il tenant
4. il frontend mostra i dati del cliente

## Modelli possibili

### Modello A - sync locale -> cloud
- runtime locale elabora dati
- sincronizza tabelle/aggregati verso cloud
- frontend cloud legge dati cloud
- più semplice per accesso web
- migliore per affidabilità UX

### Modello B - API runtime locale esposta
- frontend cloud chiama API del runtime cliente
- serve endpoint pubblico o tunnel sicuro
- più complesso
- più fragile lato rete/firewall

## Scelta consigliata
Modello A:
- login centrale cloud
- frontend cloud
- sync sicuro dal runtime locale al cloud
- dati raw sensibili restano locali dove possibile
- in cloud vanno dati aggregati/necessari

## Componenti da preparare
- installer cliente runtime
- env cliente locale
- job sync locale -> cloud
- mapping tenant_code <-> customer runtime
- controllo stato sync
