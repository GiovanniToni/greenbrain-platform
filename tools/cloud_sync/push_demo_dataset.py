import json
import os
import sys
import urllib.request

if len(sys.argv) != 4:
    print("Uso: python3 tools/cloud_sync/push_demo_dataset.py <base_url> <tenant_code> <api_key>")
    sys.exit(1)

base_url = sys.argv[1].rstrip("/")
tenant_code = sys.argv[2]
api_key = sys.argv[3]

payload = {
    "tenant_code": tenant_code,
    "dataset": "dashboard_kpis",
    "replace_mode": False,
    "records": [
        {
            "sales_7d": 9999.99,
            "sales_ytd": 123456.78,
            "sales_trend_pct": 5.25,
            "sales_ytd_trend_pct": 8.10,
            "products_monitored": 777,
            "reorders_week": 12,
            "reorder_risk_lines": 20,
            "reorder_qty_total": 88.0,
        }
    ],
}

req = urllib.request.Request(
    url=f"{base_url}/api/v1/cloud-sync/push",
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Content-Type": "application/json",
        "X-API-Key": api_key,
    },
    method="POST",
)

with urllib.request.urlopen(req) as resp:
    print(resp.read().decode("utf-8"))
