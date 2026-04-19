# Customer Billing Implementation Checklist

## Fase 1 — allineamento modello
- [x] definire nuovi piani 99 / 149 / 199
- [x] definire onboarding tecnico come fase obbligatoria
- [ ] decidere se Stripe deve:
  - salvare payment method soltanto
  - oppure creare subscription con trial fino ad attivazione
- [ ] separare "payment collected" da "service active"

## Fase 2 — backend
- [ ] aggiornare schema subscription/customer
- [ ] aggiungere plan_code reale
- [ ] aggiungere activation/billing states
- [ ] modificare webhook handling
- [ ] evitare che checkout completed => active
- [ ] introdurre endpoint admin/manuale per "activation completed"
- [ ] introdurre eventuale endpoint admin/manuale per "start billing"

## Fase 3 — frontend
- [ ] pricing a 3 piani
- [ ] signup con piano selezionato
- [ ] account con stati corretti
- [ ] messaggi post-checkout coerenti
- [ ] bloccare download/operatività fino a onboarding tecnico completato

## Fase 4 — test
- [ ] signup
- [ ] login
- [ ] checkout
- [ ] ritorno billing success/cancel
- [ ] stato account aggiornato
- [ ] simulazione attivazione manuale
