# Customer Local Operations

## Comandi canonici

### Bootstrap nuova istanza
bash tools/ops/customer_local.sh bootstrap <tenant_code> <tenant_slug> <tenant_host>

### Validazione istanza
bash tools/ops/customer_local.sh validate <tenant_slug>

### Stato rapido
bash tools/ops/customer_local.sh status <tenant_slug>

### Diagnostica completa
bash tools/ops/customer_local.sh doctor <tenant_slug>

### Release completa
bash tools/ops/customer_local.sh release <version> <tenant_slug>

## Esempi

bash tools/ops/customer_local.sh validate cliente-reale-demo
bash tools/ops/customer_local.sh status cliente-reale-demo
bash tools/ops/customer_local.sh doctor cliente-reale-demo
bash tools/ops/customer_local.sh release 0.1.7 cliente-reale-demo
bash tools/ops/customer_local.sh bootstrap cliente-demo-6 cliente-demo-6 cliente-demo-6.greenbrain.it

## Note
- il flusso release promuove dev -> template -> package -> istanza cliente
- la base viene aggiornata automaticamente
- l'overlay cliente non deve essere sovrascritto
- i segreti reali restano fuori da git
