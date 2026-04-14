# Customer Local Update Target Runbook

## Scopo
Aggiornare un cliente da una versione precedente a una nuova release.

## Procedura target
1. ricevere nuova release ufficiale
2. backup istanza
3. aggiornare base
4. preservare overlay
5. restart runtime
6. validate
7. test health
8. test accesso remoto
9. test sync

## Stato attuale
Il repository ha già:
- pre-update backup
- update from template
- validate
- post-update checks

## Gap attuale
Serve completare il flusso update direttamente da pacchetto consegnato al cliente, non solo dal template presente nel repo operativo.
