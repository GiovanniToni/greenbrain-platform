# Customer DB Source Integration Runbook

## Scopo
Collegare il runtime locale GreenBrain al database sorgente del cliente contenente i dati grezzi.

## Attività
1. identificare tecnologia DB cliente
2. raccogliere host, porta, database, schema, credenziali
3. verificare connettività dal runtime GreenBrain
4. identificare tabelle raw rilevanti
5. definire mapping verso modello GreenBrain
6. configurare pipeline ETL locale
7. eseguire primo import di test
8. verificare dati su runtime locale
9. attivare sincronizzazione o schedulazione

## Nota
Questa fase non è standard completamente automatica.
Resta un'attività tecnica assistita da GreenBrain.
