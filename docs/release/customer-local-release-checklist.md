# Customer Local Release Checklist

## Prima della release
- modifiche validate su dev
- frontend buildato
- backend coerente
- template aggiornato
- script di backup presenti
- script di post-check presenti

## Durante la release
- build release versionata
- sync template -> instance
- backup instance
- restart runtime locale
- test locale backend
- test locale frontend
- test login remoto
- test /api/v1/auth/me remoto

## Dopo la release
- commit eseguito
- runtime reports salvati
- versione aggiornata
- eventuali note specifiche cliente documentate
