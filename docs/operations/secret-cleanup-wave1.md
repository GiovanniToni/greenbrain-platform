# Secret cleanup — wave 1

Removed tracked or stray files containing live credentials:
- /opt/greenhouse/repo/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json
- /opt/greenbrain-platform/apps/ml-worker/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json
- /opt/greenbrain-platform/docs/operations/env-live.txt

Next mandatory action:
- rotate Supabase service role key
- rotate DO Spaces secret
- verify all env files
