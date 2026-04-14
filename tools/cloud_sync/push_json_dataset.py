import json
import sys
import urllib.request

if len(sys.argv) != 4:
    print("Uso: python3 push_json_dataset.py <base_url> <api_key> <json_file>")
    sys.exit(1)

base_url = sys.argv[1].rstrip("/")
api_key = sys.argv[2]
json_file = sys.argv[3]

with open(json_file, "r", encoding="utf-8") as f:
    payload = json.load(f)

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
