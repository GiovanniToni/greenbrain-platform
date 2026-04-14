# Customer Local Install / Update Target

## Obiettivo
Rendere GreenBrain distribuibile ai clienti in modo semplice, mantenendo:
- runtime locale cliente
- accesso remoto per tenant
- overlay cliente preservato
- possibilità di aggiornamento semplice tra versioni

## Flusso target

### Nuovo cliente
1. build release ufficiale
2. consegna pacchetto customer-local-X.Y.Z.tar.gz
3. installazione locale semplice
4. compilazione config locale cliente
5. registrazione tenant centrale
6. attivazione tunnel
7. collegamento DB sorgente cliente
8. attivazione sync / ETL

### Cliente esistente
1. nuova release
2. consegna update package
3. backup
4. update base
5. preservazione overlay
6. restart
7. validate
8. smoke test locale e remoto

## Componenti già esistenti
- build release
- update instance from template
- validate instance
- register tenant in auth
- register local runtime tenant
- cloud sync agent
- base/overlay model

## Componenti da costruire adesso
- install_customer_local.sh
- update_customer_local.sh
- install runbook cliente reale
- handoff checklist post-install
- DB source connection runbook
