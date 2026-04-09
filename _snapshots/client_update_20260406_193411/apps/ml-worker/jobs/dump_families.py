import os
import sqlalchemy as sa
from sqlalchemy.engine import URL
from dotenv import load_dotenv

load_dotenv("/opt/greenbrain-platform/client-runtime/etl/.env.ml.runtime")

table = os.getenv("FAMIGLIE_SOURCE_TABLE", "public.mv_famiglie_catalog")
col   = os.getenv("FAMIGLIE_COL", "famiglia")

url = URL.create(
    "postgresql+psycopg",
    username=os.getenv("PG_USER"),
    password=os.getenv("PG_PASSWORD"),
    host=os.getenv("PG_HOST"),
    port=int(os.getenv("PG_PORT", "5432")),
    database=os.getenv("PG_DB", "postgres"),
    query={"sslmode": os.getenv("PG_SSLMODE", "require")},
)
eng = sa.create_engine(url, pool_pre_ping=True)

q = sa.text(f"select {col} from {table} where {col} is not null order by 1;")
with eng.connect() as c:
    rows = c.execute(q).fetchall()

for (v,) in rows:
    s = str(v).strip()
    if s:
        print(s)
