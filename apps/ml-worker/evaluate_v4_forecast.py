import os
import pandas as pd
import numpy as np
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv(".env")

FEATURE_TABLE = "public.greenhouse_forecast_features_dense"
FORECAST_TABLE = "public.greenhouse_forecast_results_v2"

START_D = "2026-01-15"
END_D   = "2026-01-24"
HIST_DAYS = 90

eng = create_engine(
    f"postgresql+psycopg2://{os.getenv('PG_USER')}:{os.getenv('PG_PASSWORD')}@"
    f"{os.getenv('PG_HOST')}:{os.getenv('PG_PORT','5432')}/{os.getenv('PG_DB')}?sslmode=require",
    pool_pre_ping=True,
)

# 1) forecast per famiglia
q_fc = text(f"""
select
  lower(famiglia) fam,
  sum(qty_forecast) as sum_fc,
  avg(qty_forecast) as avg_fc,
  percentile_cont(0.95) within group (order by qty_forecast) as p95_fc,
  max(qty_forecast) as max_fc
from {FORECAST_TABLE}
where data between date :sd and date :ed
group by 1
order by sum_fc desc;
""")
df_fc = pd.read_sql(q_fc, eng, params={"sd": START_D, "ed": END_D})

# 2) storico 90gg per famiglia
q_hist = text(f"""
select
  lower(famiglia) fam,
  sum(qty_venduta) as sum_90,
  avg(qty_venduta) as avg_90,
  max(qty_venduta) as max_90,
  sum((qty_venduta>0)::int) as pos_days_90,
  percentile_cont(0.99) within group (order by qty_venduta) as p99_90
from {FEATURE_TABLE}
where data >= date :sd - interval '{HIST_DAYS} days'
group by 1;
""")
df_hist = pd.read_sql(q_hist, eng, params={"sd": START_D})

df = df_fc.merge(df_hist, on="fam", how="left")

df["sum_ratio"] = df["sum_fc"] / df["sum_90"].replace(0, np.nan)
df["max_ratio"] = df["max_fc"] / df["max_90"].replace(0, np.nan)
df["max_over_p99"] = df["max_fc"] / df["p99_90"].replace(0, np.nan)

print("\n==============================")
print(f"V4 Forecast Evaluation {START_D} → {END_D}")
print("==============================\n")

print(df[[
  "fam","sum_fc","sum_90","sum_ratio",
  "max_fc","max_90","max_ratio",
  "p99_90","max_over_p99",
  "pos_days_90"
]].sort_values("sum_ratio", ascending=False).to_string(index=False))

# flags
print("\n==============================")
print("⚠️ FLAGS")
print("==============================")

flags = df[
  ((df["sum_ratio"] > 2.5) | (df["sum_ratio"] < 0.4)) |
  ((df["sum_90"].fillna(0) == 0) & (df["sum_fc"] > 0)) |
  (df["max_over_p99"] > 1.5)
].copy()

if flags.empty:
    print("✅ Nessuna anomalia evidente")
else:
    print(flags[[
      "fam","sum_fc","sum_90","sum_ratio",
      "max_fc","p99_90","max_over_p99",
      "pos_days_90"
    ]].sort_values(["sum_ratio"], ascending=False).to_string(index=False))

eng.dispose()