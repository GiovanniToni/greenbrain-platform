# GreenBrain Customer Local — Status & Roadmap 0.1.39

## Release validata

Release corrente: `customer-local-0.1.39`

Bundle:
- `/opt/greenbrain-platform/releases/customer-local/0.1.39/customer-local-0.1.39.tar.gz`

Runtime demo:
- `/tmp/gb_customer_final_install/customer-local-template`

## Validazioni completate

- Update demo runtime OK
- VERSION/package_version = 0.1.39
- Auto SQL patches OK
- Provisioning validation OK
- Backend wait health durante install aggiunto
- Backend/frontend healthy
- Scheduler OK
- run-local-daily-once OK
- Pipeline raw -> fact -> dense -> features OK
- train_missing OK rc=0
- predict_all OK rc=0
- Heartbeat centrale healthy con local_agent_version 0.1.39
- Extended doctor OK
- Log ML host-owned gh:gh

## Miglioramenti inclusi

- Install più robusto: attende backend healthy prima del doctor
- Provisioning locale validato con placeholder guard
- Runtime heartbeat fresh-safe
- Scheduler usa wrapper operativo
- ML worker scrive log come utente host

## Prossima fase

1. Provisioning wizard reale
2. Installer plug-and-play
3. Setup cliente con file `.env` guidati
4. Source DB connector / import flow
5. Runbook operatore definitivo
