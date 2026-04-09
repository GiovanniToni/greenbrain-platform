# GreenBrain Client Runtime — Demo Data Runbook

## Scopo
Questo runbook serve per:
- preparare un ambiente client locale senza Supabase
- applicare lo schema minimo necessario per dense / features / parquet
- caricare dati demo sintetici
- generare i parquet locali per validazione funzionale
- validare backend auth locale e frontend client

## Stato dei dati
Importante:
- i dati usati in questo runbook sono demo sintetici locali
- non sono dati reali del cliente
- l'ambiente client-runtime è separato dall'ambiente dev/master collegato a Supabase

## Prerequisiti
- Docker attivo
- container postgres client esposto su porta host 55432
- backend client esposto su porta host 8001
- frontend client esposto su porta host 8081
- virtualenv Python disponibile in /opt/greenhouse/venv
- storage locale attivo su /opt/greenbrain/storage

## Procedura demo sintetica
1. avvio stack client
2. apply schema minimo
3. seed demo sintetico
4. refresh dense/features/catalog
5. export parquet locale
6. verifica backend
7. setup/login auth demo

## Note operative
- usare questa procedura solo per validazione tecnica
- non usare questi dati per analisi cliente reali
- per go-live usare sorgente SQL Server cliente + DB GreenBrain cliente standard
