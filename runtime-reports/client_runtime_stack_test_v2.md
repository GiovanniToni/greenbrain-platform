# Client Runtime Stack Test V2

## Verificato
- docker compose config ok
- backend image build ok
- frontend image build ok
- postgres container ok
- backend container ok
- frontend container ok
- backend /health ok
- backend / ok
- backend /health/db ok
- frontend porta 8081 raggiungibile

## Note
- docker-compose.yml usa ancora il campo version, oggi obsoleto
- frontend nel compose gira in dev mode (npm run dev), non ancora in asset statici nginx production-mode
- presenti errori storici nei log postgres, non bloccanti per la validazione attuale

## Stato
La stack docker client-runtime è validata a livello base.
