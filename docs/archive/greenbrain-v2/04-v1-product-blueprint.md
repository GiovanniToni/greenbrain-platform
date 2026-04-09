# GreenBrain V1 Product Blueprint

## Goal
Create a reinstallable product package for each client garden center.

## Runtime model

### Development environment
Runs in cloud / controlled environment by GreenBrain team:
- source code
- schema and migrations
- frontend code
- backend code
- ML code
- release packaging

### Client environment
Runs locally on client machine:
- PostgreSQL
- FastAPI backend
- React frontend
- ML worker
- Nginx
- optional pgAdmin

## Core containers
- postgres
- backend
- frontend
- ml
- nginx

## Optional containers
- pgadmin

## Persistent data
- postgres data volume
- local backup folder
- future local model/artifact folders

## Principles
- one isolated stack per client
- no shared client database
- backend talks to postgres
- frontend talks to backend
- ML talks to postgres/backend
- deploy through docker compose
- versioned schema and migrations
- versioned release package

## Near-term target
Convert current prototype into:
- stable backend API layer
- stable frontend connected only to backend
- versioned database migration flow
- reproducible client install procedure
