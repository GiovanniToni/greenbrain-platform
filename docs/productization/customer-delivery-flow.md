# Customer Delivery Flow

## Scopo
Preparare il bundle reale da consegnare al cliente partendo dal record customer e dalla release assegnata.

## Regola architetturale
La generazione bundle NON gira nel backend container.
Gira sul server host tramite script operativo dedicato.

## Flusso
1. backend legge customer e release assegnata dal control plane Supabase
2. endpoint /customer-delivery/prepare restituisce il piano
3. operatore lancia tools/customer_ops/prepare_assigned_bundle.sh <customer_id>
4. lo script genera il bundle sul filesystem host
5. lo script aggiorna gb_customer_delivery con:
   - assigned_release_version
   - bundle_generated_at
   - bundle_local_path

## Endpoint
- GET /api/v1/customer-delivery/health
- POST /api/v1/customer-delivery/prepare

## Script host
- tools/customer_ops/prepare_assigned_bundle.sh <customer_id>
