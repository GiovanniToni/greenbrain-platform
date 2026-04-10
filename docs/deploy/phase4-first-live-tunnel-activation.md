# Phase 4 First Live Tunnel Activation

## Scopo
Attivare il primo tunnel reale per un tenant local-runtime senza toccare dev o auth live.

## Ordine corretto
1. backend locale healthy
2. frontend locale healthy
3. file credentials tunnel valido presente
4. tunnel container avviato
5. verifica tunnel lato provider
6. aggiornamento metadata centrale:
   - tunnel_status = connected
   - remote_enabled = true
   - remote_route_enabled = true
   - remote_route_mode = live
7. solo dopo test login remoto completo

## Regola
Mai attivare remote_enabled o remote_route_enabled prima che il tunnel sia davvero collegato.
