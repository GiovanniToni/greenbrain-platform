# GreenBrain Customer Local — Status & Roadmap 0.1.47

## Release validata

Release corrente: `customer-local-0.1.47`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.47/customer-local-0.1.47.tar.gz`

Fresh test:
- `/tmp/gb_fresh_0147_full_20260510_235302/package/customer-local-template`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Fresh one-shot install OK
- `install_exit=0`
- Customer env wizard OK
- Runtime provisioning wizard OK
- Preflight install OK
- Backend health wait OK
- Smoke package OK
- Provisioning OK
- VERSION/package_version = 0.1.47
- Daily sequence OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con `local_agent_version=0.1.47`
- Extended doctor OK
- Scheduler cron OK
- Update demo runtime OK
- Auto SQL patches OK
- `overlay/logs` host-owned `gh:gh`
- `daily_sequence_latest.log` creato correttamente

## Nota preflight

Il preflight segnala correttamente porte già in uso:
- backend 8008
- frontend 8088
- postgres 55450

Nel test attuale sono warning accettabili perché la stack customer-local è già attiva. Prossimo step: distinguere conflitto reale da stack GreenBrain esistente.

## Prossima fase 0.1.48

- Rendere il preflight più intelligente
- Differenziare porte occupate da container GreenBrain attesi vs servizi esterni
- Preparare base per installer realmente robusto cliente
