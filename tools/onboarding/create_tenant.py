from pathlib import Path
import re
import sys

if len(sys.argv) != 3:
    print("Uso: python3 tools/onboarding/create_tenant.py <tenant_code> <admin_email>")
    sys.exit(1)

tenant = sys.argv[1].strip().lower()
admin_email = sys.argv[2].strip().lower()

if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,30}", tenant):
    raise SystemExit("tenant_code non valido")

root = Path("/opt/greenbrain-platform")
stacks_dir = root / "deploy" / "stacks"
env_dir = root / "deploy" / "env"

compose_path = stacks_dir / f"{tenant}.docker-compose.yml"
env_path = env_dir / f"{tenant}.env"

if compose_path.exists() or env_path.exists():
    raise SystemExit("Tenant già esistente")

project_name = f"gb-{tenant}"
db_name = f"greenbrain_{tenant}"
db_user = f"greenbrain_{tenant}"
db_password = "CHANGE_ME_DB_PASSWORD"
backend_port = "CHANGE_ME_BACKEND_PORT"
postgres_port = "CHANGE_ME_POSTGRES_PORT"
host_name = f"{tenant}.greenbrain.it"

env_content = f"""APP_ENV=client
JWT_SECRET=CHANGE_ME_JWT_SECRET
JWT_EXPIRE_MINUTES=60

DATABASE_URL=postgresql://{db_user}:{db_password}@{tenant}_postgres:5432/{db_name}

POSTGRES_HOST={tenant}_postgres
POSTGRES_PORT=5432
POSTGRES_DB={db_name}
POSTGRES_USER={db_user}
POSTGRES_PASSWORD={db_password}
POSTGRES_SSLMODE=disable

TENANT_CODE={tenant}
TENANT_HOST={host_name}
TENANT_ADMIN_EMAIL={admin_email}
"""

compose_content = f"""name: {project_name}
version: "3.9"

services:
  {tenant}_postgres:
    image: postgres:16-alpine
    container_name: {tenant}_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: {db_name}
      POSTGRES_USER: {db_user}
      POSTGRES_PASSWORD: {db_password}
    ports:
      - "{postgres_port}:5432"
    volumes:
      - {tenant}_postgres_data:/var/lib/postgresql/data
      - ../../client-runtime/sql/init:/docker-entrypoint-initdb.d:ro

  {tenant}_backend:
    build:
      context: ../../apps/backend
      dockerfile: Dockerfile
    container_name: {tenant}_backend
    restart: unless-stopped
    env_file:
      - ../env/{tenant}.env
    ports:
      - "{backend_port}:8000"
    depends_on:
      - {tenant}_postgres

volumes:
  {tenant}_postgres_data:
"""

env_path.write_text(env_content)
compose_path.write_text(compose_content)

print("CREATED", env_path)
print("CREATED", compose_path)
print()
print("Prossimi passi manuali:")
print(f"1) imposta backend_port e postgres_port in {compose_path.name}")
print(f"2) imposta DB password e JWT secret in {env_path.name}")
print(f"3) aggiungi server_name {host_name} in nginx")
print(f"4) avvia: docker compose -f deploy/stacks/{compose_path.name} up -d --build")
