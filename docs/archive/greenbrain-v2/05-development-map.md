# GreenBrain Development Map

## Database
Location:
- /opt/greenbrain-v2/database/schema
- /opt/greenbrain-v2/database/migrations
- /opt/greenbrain-v2/database/seeds

Responsibility:
- schema baseline
- migration files
- seed files for local/client environments

## Backend
Location:
- /opt/greenbrain-v2/backend/app

Responsibility:
- REST API
- database access
- business logic
- future auth/session logic
- orchestration between frontend and DB

## Frontend
Location:
- /opt/greenbrain-v2/frontend/src

Responsibility:
- UI
- API calls to backend
- dashboards
- planner screens
- analytics screens

## ML
Location:
- /opt/greenbrain-v2/ml

Responsibility:
- forecast pipeline
- training jobs
- inference jobs
- future batch tasks

## Deploy
Location:
- /opt/greenbrain-v2/deploy

Responsibility:
- docker compose files
- env templates
- startup scripts
- install/update procedures

## Docs
Location:
- /opt/greenbrain-v2/docs

Responsibility:
- architecture
- checkpoints
- migration strategy
- operational documentation
