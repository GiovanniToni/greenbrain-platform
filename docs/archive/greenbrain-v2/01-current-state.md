# GreenBrain v2 — Current State

## Goal
Build a new GreenBrain v2 architecture in parallel, without modifying the current production structure.

## Current structure

### Forecasting
- Path: /opt/greenhouse/repo
- Role: ML pipeline (train, predict, ETL)

### Frontend
- Path: /opt/greenbrain/frontend
- Role: React + Supabase frontend

## Rule
This structure must remain untouched.
All new work happens in /opt/greenbrain-v2.