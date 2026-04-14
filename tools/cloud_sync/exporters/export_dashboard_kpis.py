import json
import os
import subprocess
import sys

if len(sys.argv) != 3:
    print("Uso: python3 export_dashboard_kpis.py <tenant_code> <db_url>")
    sys.exit(1)

tenant_code = sys.argv[1]
db_url = sys.argv[2]

sql = """
select json_agg(row_to_json(x))
from (
  select
    coalesce(sum(revenue_inc_vat), 0)::numeric(14,2) as sales_7d,
    coalesce(sum(revenue_inc_vat), 0)::numeric(14,2) as sales_ytd,
    0::numeric(8,2) as sales_trend_pct,
    0::numeric(8,2) as sales_ytd_trend_pct,
    0::integer as products_monitored,
    0::integer as reorders_week,
    0::integer as reorder_risk_lines,
    0::numeric(14,2) as reorder_qty_total,
    now() as source_runtime_ts
  from greenhouse_sales_raw
  where data_vendita >= current_date - interval '7 day'
) x;
"""

cmd = [
    "psql",
    db_url,
    "-t",
    "-A",
    "-c",
    sql,
]

result = subprocess.run(cmd, capture_output=True, text=True, check=True)
raw = result.stdout.strip()

records = json.loads(raw) if raw and raw != "null" else []

print(json.dumps({
    "tenant_code": tenant_code,
    "dataset": "dashboard_kpis",
    "replace_mode": False,
    "records": records
}))
