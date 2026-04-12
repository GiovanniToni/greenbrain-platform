# Customer Local Update Runbook

## Flusso standard aggiornamento cliente

1. sviluppo e test su dev
2. build frontend
3. sync template cliente
4. backup istanza cliente
5. update istanza cliente dal template
6. restart runtime locale
7. test locale
8. test remoto
9. conferma finale

## Comandi

### Backup
bash deploy/customer-local-instances/<tenant>/scripts/pre-update-backup.sh

### Update
bash tools/release/update_customer_instance_from_template.sh <tenant>

### Restart
docker compose --env-file deploy/customer-local-instances/<tenant>/env/customer-local.env \
  -f deploy/customer-local-instances/<tenant>/docker-compose.local.yml up -d --build

### Check finale
bash deploy/customer-local-instances/<tenant>/scripts/post-update-check.sh
