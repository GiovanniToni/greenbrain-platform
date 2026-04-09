# ETL Source Status

## Stato attuale
Il client-runtime GreenBrain è collegato correttamente al DB Postgres locale target,
ma NON è ancora collegato a una sorgente SQL Server reale cliente.

## Evidenze
- client-runtime/etl/.env contiene placeholder demo:
  - SQLSERVER_SERVER=localhost
  - SQLSERVER_DB=CLIENT_DB
  - SQLSERVER_USER=readonly_user
  - SQLSERVER_PASSWORD=CHANGE_ME
- nessun SQL Server locale attivo
- nessun container MSSQL attivo
- nessun listener su porta 1433

## Conseguenza operativa
- non schedulare ETL giornaliero
- non schedulare daily ETL+predict
- mantenere solo train manuale/settimanale oppure nessun cron
- usare il runtime ML solo su dati demo/locali finché non viene definita la sorgente reale cliente

## Prossimo passo necessario
Ottenere i veri parametri della sorgente SQL Server cliente:
- host o host\instance
- database
- user read-only
- password
- eventuale porta
- nome reale della vista o query equivalente a GREENHOUSE_VIEW_STAT
