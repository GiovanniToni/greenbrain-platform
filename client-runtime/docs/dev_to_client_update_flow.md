# Dev -> Client Update Flow

## Obiettivo
Promuovere modifiche canoniche dal lato dev al client-runtime locale
senza toccare configurazioni cliente-specifiche.

## Regole
- il codice canonico viene da dev/master
- il client-runtime riceve solo i file inclusi in runtime_manifest.txt
- client-runtime/etl/.env NON va sovrascritto
- le migration SQL runtime vanno applicate a ogni update
- dopo l'update eseguire sempre validate_client_runtime.sh

## Procedura
1. aggiornare i file canonici in dev
2. creare package con package_client_runtime.sh
3. applicare update con client-runtime/update.sh <package_dir>
4. validare runtime
5. eseguire test manuali:
   - export
   - train
   - predict

## Cliente-specifico
Resta fuori dal package:
- sorgente SQL Server
- credenziali cliente
- env locali
- secret
