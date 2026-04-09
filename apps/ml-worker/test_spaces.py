import os
import boto3
from dotenv import load_dotenv

load_dotenv("/opt/greenhouse/.env")

region = os.getenv("DO_SPACES_REGION")
bucket = os.getenv("DO_SPACES_BUCKET")
key = os.getenv("DO_SPACES_KEY")
secret = os.getenv("DO_SPACES_SECRET")

endpoint = f"https://{region}.digitaloceanspaces.com"

s3 = boto3.client(
    "s3",
    region_name=region,
    endpoint_url=endpoint,
    aws_access_key_id=key,
    aws_secret_access_key=secret,
)

print("Endpoint:", endpoint)
print("Bucket:", bucket)

# list_buckets può essere negato se la key è scoped su 1 bucket: testiamo direttamente il bucket.
s3.head_bucket(Bucket=bucket)
print("OK: head_bucket")

resp = s3.list_objects_v2(Bucket=bucket, MaxKeys=5)
print("OK: list_objects_v2 KeyCount =", resp.get("KeyCount", 0))
for o in resp.get("Contents", []):
    print(" -", o["Key"])
