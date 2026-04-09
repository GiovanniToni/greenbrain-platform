# Frontend Compose Mode

## Stato attuale
Nel client-runtime docker-compose il frontend gira in modalità dev:

- image: node:20-alpine
- mount volume su apps/frontend
- command: npm install -q && npm run dev

## Significato
Questo va bene per test locale rapido.
Non è ancora la forma finale production-style cliente.

## Target futuro
Frontend servito da immagine buildata con nginx,
senza dev server Vite nel runtime cliente finale.
