# P1 Live Cleanup Level 2

## Stato
Eseguito cleanup live di secondo livello sui file runtime/ops ancora utili.

## Aree toccate
- validate_engines.py
- train_all_monitor.py
- shell scripts ML
- principali infra/scripts/bin

## Obiettivo
Ridurre riferimenti live a /opt/greenhouse e allineare i path runtime a:
- /opt/greenbrain-platform/apps/ml-worker
- /opt/greenbrain-platform/runtime-reports
- /opt/greenbrain/storage

## Regola
Nessuna schedulazione attiva.
Runtime resta in modalità manuale / demo validation.
