# Phase 4 Demo Next Step

## Obiettivo immediato
Preparare il tenant local-runtime demo per il reverse tunnel senza attivarlo live.

## Stato
- runtime locale attivo
- auth centrale attiva
- tenant registry pronto
- metadata tunnel pronti
- scaffold cloudflared pronto
- tunnel non ancora avviato
- DNS / routing remoto non ancora attivati

## Prossimo step tecnico
1. ottenere credenziali reali del tunnel
2. inserire file credentials json
3. fare dry-run del container tunnel
4. verificare reachability verso backend locale
5. solo dopo attivare il routing remoto del tenant
