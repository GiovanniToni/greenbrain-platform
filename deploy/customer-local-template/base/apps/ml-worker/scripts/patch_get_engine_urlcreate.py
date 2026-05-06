from pathlib import Path
import re
from datetime import datetime

p = Path("/opt/greenhouse/repo/predict_v4_single_family_tweedie.py")
txt = p.read_text()

bak = p.with_suffix(f".py.bak_getengine_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
bak.write_text(txt)

# 1) assicurati che ci siano gli import URL
if "from sqlalchemy.engine import URL" not in txt:
    txt = re.sub(r"(import sqlalchemy as sa\s*\n)", r"\1from sqlalchemy.engine import URL\n", txt, count=1)

# 2) sostituisci la funzione get_engine con una versione robusta
pattern = re.compile(r"def\s+get_engine\s*\(\s*\)\s*:\s*\n(?:[ \t].*\n)+?\n", re.MULTILINE)

replacement = """def get_engine():
    \"""
    Crea engine Postgres usando PG_* dal .env (robusto anche con password con caratteri speciali).
    \"""
    from dotenv import load_dotenv
    load_dotenv("/opt/greenhouse/.env")

    import os
    host = os.getenv("PG_HOST")
    port = int(os.getenv("PG_PORT", "5432"))
    db = os.getenv("PG_DB", "postgres")
    user = os.getenv("PG_USER")
    pw = os.getenv("PG_PASSWORD")
    ssl = os.getenv("PG_SSLMODE", "require")

    if not all([host, user, pw, db]):
        raise RuntimeError("Variabili PG_* mancanti nel .env")

    url = URL.create(
        drivername="postgresql+psycopg",
        username=user,
        password=pw,
        host=host,
        port=port,
        database=db,
        query={"sslmode": ssl},
    )

    return sa.create_engine(url, pool_pre_ping=True)
"""

m = pattern.search(txt)
if not m:
    raise SystemExit("❌ Non trovo def get_engine() nel file.")
txt2 = pattern.sub(replacement + "\n", txt, count=1)

p.write_text(txt2)
print("✅ Patch get_engine applicata.")
print("Backup:", bak)
