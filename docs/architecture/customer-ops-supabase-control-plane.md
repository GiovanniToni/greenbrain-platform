# Customer Ops Supabase Control Plane

## Decisione
La parte centrale commerciale e operativa dei clienti usa Supabase come control plane, in continuità con l'ambiente dev attuale.

## Cosa va in Supabase
- anagrafica cliente
- subscription / billing references
- stato onboarding
- stato delivery bundle
- release assegnata / installata
- stato integrazione DB cliente
- metadati runtime cliente

## Cosa NON va in Supabase
- dati grezzi del cliente
- DB operativi cliente
- segreti runtime reali del cliente
- dump locali cliente

## Separazione dei ruoli
- Supabase centrale = controllo prodotto / customer ops
- runtime locale cliente = esecuzione locale GreenBrain
- DB sorgente cliente = fonte dati grezzi da integrare

## Vantaggi
- gestione centralizzata clienti
- dashboard ops unica
- stato installazioni e versioni
- base corretta per area cliente, Stripe e delivery
