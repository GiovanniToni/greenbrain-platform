# Tenant Registry - Current State

## Obiettivo
Registry centrale tenant in auth DB per separare:
- tenant hosted
- tenant con runtime locale futuro

## Tabelle
- public.greenbrain_users
- public.greenbrain_tenants
- public.v_greenbrain_user_tenant_routing

## Tenant attuali
- greenbrain -> dev.greenbrain.it
- cliente1 -> cliente1.greenbrain.it

## Modalità attuali
- greenbrain: hosted / hosted-db
- cliente1: hosted / hosted-db

## Uso futuro
Per clienti reali:
- accesso centrale da www.greenbrain.it
- tenant registry decide target host / modalità accesso
- modalità futura preferita per clienti reali:
  local-runtime + local-db-via-tunnel
