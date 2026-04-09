# Storage Migration Analysis
> Exact diff-level analysis for migrating 4 files to `storage.backend.get_storage_backend()`.
> No files modified. All line numbers verified against current source.

---

## Abstraction Review

The current `StorageBackend` Protocol exposes:

```python
upload_bytes(remote_path: str, content: bytes, content_type: str = ...) -> None
download_bytes(remote_path: str) -> bytes          # raises on not-found
exists(remote_path: str) -> bool
```

**Verdict: Sufficient for all 4 files.** All current storage operations map cleanly to these 3 methods.
One structural issue and one critical boot-time crash are documented in §4 (Risks).

---

## 1. Exact Imports to Replace

### `data_access_v1.py` — lines 10–13

```python
# REMOVE:
try:
    from supabase import create_client
except Exception:
    create_client = None
```

```python
# ADD (top of file, after stdlib imports):
from storage.backend import get_storage_backend
```

---

### `jobs/parquet_export/export_features_dense.py` — line 14

```python
# REMOVE:
from supabase import create_client
```

```python
# ADD (same position):
from storage.backend import get_storage_backend
```

Also remove 4 module-level constants that reference Supabase (see §3).

---

### `jobs/upload_priors_to_supabase.py` — line 31 (inside `main()`)

```python
# REMOVE (inline import inside main):
from supabase import create_client
```

```python
# ADD (top of file, after stdlib imports):
from storage.backend import get_storage_backend
```

---

### `jobs/download_priors_from_supabase.py` — line 16 (inside `main()`)

```python
# REMOVE (inline import inside main):
from supabase import create_client
```

```python
# ADD (top of file, after stdlib imports):
from storage.backend import get_storage_backend
```

---

## 2. Exact Storage Calls to Replace

### `data_access_v1.py`

**Delete entire `_supabase_client()` function — lines 53–61:**

```python
# DELETE:
def _supabase_client():
    if create_client is None:
        raise RuntimeError("supabase non disponibile. Installa oppure disabilita PARQUET (PARQUET_ENABLE=0).")
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_KEY")
    bucket = os.getenv("SUPABASE_BUCKET", "ml-snapshots")
    if not url or not key:
        raise RuntimeError("Mancano SUPABASE_URL e/o SUPABASE_SERVICE_ROLE_KEY nel .env del progetto forecast_model.")
    return create_client(url, key), bucket
```

**In `_download_one_parquet()` — lines 80, 95, 100:**

```python
# FROM (line 80):
sb, bucket = _supabase_client()

# TO:
storage = get_storage_backend()
```

```python
# FROM (line 95):
data = sb.storage.from_(bucket).download(rp)

# TO:
data = storage.download_bytes(rp)
```

```python
# FROM (line 100):
data = sb.storage.from_(bucket).download(alt_rp)

# TO:
data = storage.download_bytes(alt_rp)
```

The surrounding `try/except Exception` blocks and `if data is None: return None` logic are unchanged —
`download_bytes()` raises (same as Supabase SDK) so the exception-catching pattern is compatible.

---

### `jobs/parquet_export/export_features_dense.py`

**Delete `create_supabase_client()` function — lines 283–297:**

```python
# DELETE entirely:
def create_supabase_client():
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    try:
        storage_client = getattr(sb.storage, "_client", None)
        if storage_client is not None and hasattr(storage_client, "timeout"):
            storage_client.timeout = SUPABASE_HTTP_TIMEOUT_SEC
    except Exception:
        pass
    return sb
```

**Rename `upload_bytes_with_retry` first parameter — line 300:**

```python
# FROM:
def upload_bytes_with_retry(sb, path: str, b: bytes, run_id: int, famiglia_slug: str, year: int):

# TO:
def upload_bytes_with_retry(storage, path: str, b: bytes, run_id: int, famiglia_slug: str, year: int):
```

**Replace the upload call inside `upload_bytes_with_retry` — lines 307–311:**

```python
# FROM:
sb.storage.from_(BUCKET).upload(
    path=path,
    file=b,
    file_options={"content-type": "application/octet-stream", "upsert": "true"},
)

# TO:
storage.upload_bytes(path, b, content_type="application/octet-stream")
```

**Replace the client refresh inside the retry loop — lines 326–329:**

```python
# FROM:
try:
    sb = create_supabase_client()
except Exception:
    pass

# TO:
try:
    storage = get_storage_backend()
except Exception:
    pass
```

**In `main()` — line 344:**

```python
# FROM:
sb = create_supabase_client()

# TO:
storage = get_storage_backend()
```

**Call site inside the family loop — line 455:**

```python
# FROM:
upload_bytes_with_retry(sb, relpath, b, run_id, famiglia_slug, y)

# TO:
upload_bytes_with_retry(storage, relpath, b, run_id, famiglia_slug, y)
```

---

### `jobs/upload_priors_to_supabase.py`

**Delete the entire `_call` compatibility helper — lines 4–16:**

```python
# DELETE entirely — Supabase SDK version compat, not needed with abstraction:
def _call(obj, name, *args, **kwargs):
    fn = getattr(obj, name, None)
    if fn is None:
        raise AttributeError(name)
    try:
        return fn(*args, **kwargs)
    except TypeError:
        if "file_options" in kwargs:
            kw2 = dict(kwargs)
            kw2["options"] = kw2.pop("file_options")
            return fn(*args, **kw2)
        raise
```

**Replace the entire `main()` body from line 22 onwards:**

```python
# FROM (lines 22–62) — entire Supabase setup + update/remove/upload dance:
bucket = os.getenv("SUPABASE_BUCKET", "ml-snapshots")
remote_path = os.getenv("PRIORS_REMOTE_PATH", "priors/priors_v1.parquet")
url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
if not url or not key:
    raise SystemExit("Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in env")
from supabase import create_client
client = create_client(url, key)
storage = client.storage.from_(bucket)
file_opts = {"content-type": "application/octet-stream"}
try:
    _call(storage, "update", remote_path, str(local_path), file_options=file_opts)
    ...
except ...:
    ...

# TO (~5 lines):
remote_path = os.getenv("PRIORS_REMOTE_PATH", "priors/priors_v1.parquet")
storage = get_storage_backend()
content = local_path.read_bytes()
storage.upload_bytes(remote_path, content)
print(f"OK upload {remote_path} <- {local_path}")
```

Note: the `update → remove+upload` fallback dance existed only to work around Supabase SDK API
differences across versions. The abstraction's `upload_bytes()` is always idempotent (upsert for
Supabase backend, overwrite for local/S3). The compat dance is eliminated entirely.

---

### `jobs/download_priors_from_supabase.py`

**Replace the entire `main()` body from line 8 onwards:**

```python
# FROM (lines 8–26):
bucket = os.getenv("SUPABASE_BUCKET", "ml-snapshots")
remote_path = os.getenv("PRIORS_REMOTE_PATH", "priors/priors_v1.parquet")
url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
if not url or not key:
    raise SystemExit("Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in env")
from supabase import create_client
client = create_client(url, key)
storage = client.storage.from_(bucket)
obj = storage.download(remote_path)
data = obj if isinstance(obj, (bytes, bytearray)) else getattr(obj, "data", None)
if not data:
    raise SystemExit(f"Download failed for supabase://{bucket}/{remote_path}")
out.write_bytes(data)
print(f"OK download supabase://{bucket}/{remote_path} -> {out}")

# TO (~5 lines):
remote_path = os.getenv("PRIORS_REMOTE_PATH", "priors/priors_v1.parquet")
storage = get_storage_backend()
data = storage.download_bytes(remote_path)
out.write_bytes(data)
print(f"OK download {remote_path} -> {out}")
```

Note: `isinstance(obj, (bytes, bytearray)) ... getattr(obj, "data", None)` was Supabase SDK version
compat — different versions returned either raw bytes or a response object. `download_bytes()` always
returns `bytes` directly. Eliminated entirely.

---

## 3. Required Env Var Normalization

### `export_features_dense.py` only — DB connection vars (not covered by storage abstraction)

| Current (lines 99–103) | Replacement | Notes |
|------------------------|-------------|-------|
| `os.environ["SUPABASE_DB_HOST"]` | `os.environ["PG_HOST"]` | Required |
| `os.environ.get("SUPABASE_DB_PORT", "5432")` | `os.environ.get("PG_PORT", "5432")` | Required |
| `os.environ.get("SUPABASE_DB_NAME", "postgres")` | `os.environ.get("PG_DB", "postgres")` | Required |
| `os.environ.get("SUPABASE_DB_USER", "postgres")` | `os.environ.get("PG_USER", "postgres")` | Required |
| `os.environ["SUPABASE_DB_PASSWORD"]` | `os.environ["PG_PASSWORD"]` | Required |

**Also `pg_conn()` hardcoded `sslmode` — line 144:**

```python
# FROM:
sslmode="require",

# TO:
sslmode=os.getenv("PG_SSLMODE", "require"),
```

This is required for local deployment where `sslmode=disable`.

### Env vars removed from all 4 files (no longer read at call sites)

| Var | Was used in | Now lives in |
|-----|------------|-------------|
| `SUPABASE_URL` | All 4 files | `SupabaseStorageBackend.__init__()` only |
| `SUPABASE_SERVICE_ROLE_KEY` | All 4 files | `SupabaseStorageBackend.__init__()` only |
| `SUPABASE_KEY` (legacy alias) | `data_access_v1.py` line 57 | Remove from `data_access_v1.py` |
| `SUPABASE_BUCKET` | All 4 files | `SupabaseStorageBackend.__init__()` only |
| `SUPABASE_HTTP_TIMEOUT_SEC` | `export_features_dense.py` line 131 | Remove — no equivalent in abstraction |

### New env vars required at call sites (none — backend handles its own)

All backend-specific env vars (`SUPABASE_*`, `S3_*`, `LOCAL_STORAGE_ROOT`) are now read exclusively
inside the respective backend `__init__()`. The call sites only need `STORAGE_BACKEND`.

---

## 4. Migration Risks

### 🔴 CRITICAL — Module-level crash in `export_features_dense.py` at import time

**Lines 95–96, 99, 103** read `os.environ["..."]` unconditionally at module import:

```python
SUPABASE_URL = os.environ["SUPABASE_URL"]          # KeyError if not set
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]  # KeyError if not set
DB_HOST = os.environ["SUPABASE_DB_HOST"]           # KeyError if not set
DB_PASSWORD = os.environ["SUPABASE_DB_PASSWORD"]   # KeyError if not set
```

With `STORAGE_BACKEND=local`, `SUPABASE_URL` will not be set → **script crashes before `main()` runs**.

**Fix:** Move these 4 reads (plus `BUCKET`, `SUPABASE_HTTP_TIMEOUT_SEC`) inside `main()`, or guard them:

```python
# At module level — safe default:
STORAGE_BACKEND = os.getenv("STORAGE_BACKEND", "supabase")

# In main():
if STORAGE_BACKEND == "supabase":
    _check_supabase_env()   # validate SUPABASE_URL etc.
DB_HOST = os.environ["PG_HOST"]   # always required
```

Or simply move all the module-level `os.environ[...]` calls into `main()` as locals. This is the cleanest fix since they're all consumed only in `main()` anyway.

---

### 🟡 MEDIUM — `download_bytes()` raises, but `download_priors_from_supabase.py` currently checks `if not data`

Current code (line 22): `data = obj if isinstance(...) else getattr(obj, "data", None)` + `if not data: raise SystemExit(...)`.

After migration, `download_bytes()` **raises** `FileNotFoundError` (local) or `ClientError` (S3) when not found — it never returns `None`. The `if not data:` check is dead code. This is not a runtime failure (exception propagates correctly), but the error message would change from the controlled `SystemExit(f"Download failed...")` to an unhandled exception traceback.

**Fix:** Wrap in `try/except` in the migrated file:

```python
try:
    data = storage.download_bytes(remote_path)
except Exception as e:
    raise SystemExit(f"Download failed {remote_path}: {e}")
out.write_bytes(data)
```

---

### 🟡 MEDIUM — Import path for `export_features_dense.py`

The file is at `jobs/parquet_export/export_features_dense.py` (2 directories deep).
`from storage.backend import get_storage_backend` works only if the working directory is the
ml-worker root when the script is executed.

**Confirmed:** `storage/__init__.py` exists (0 bytes) ✅. The service file runs from
`WorkingDirectory=/opt/greenhouse/repo` (ml-worker root). But verify `run_daily_parquet_batches.sh`
doesn't `cd` into a subdirectory before running `python jobs/parquet_export/export_features_dense.py`.

If the working directory is not the ml-worker root, add at the top of `export_features_dense.py`:

```python
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))
```

---

### 🟡 MEDIUM — `upload_bytes_with_retry` refresh creates a new backend on every retry

Current: `sb = create_supabase_client()` creates a new HTTP client (useful to reset HTTP/2 streams).
After: `storage = get_storage_backend()` creates a new backend instance.

For `SupabaseStorageBackend`: re-runs `create_client(url, key)` — same intent, slightly more overhead.
For `S3StorageBackend`: re-runs boto3 client construction — acceptable.
For `LocalStorageBackend`: trivially cheap (no state).

No functional risk, but the retry is slightly more expensive than before. Acceptable.

---

### 🟢 LOW — `SUPABASE_KEY` legacy alias in `data_access_v1.py`

Line 57: `os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_KEY")`.

The `SUPABASE_KEY` alias is a legacy fallback. After migration, this whole line goes away (handled by
`SupabaseStorageBackend.__init__()`). No risk — just confirming the legacy alias is eliminated.

---

### 🟢 LOW — `_call` compat helper deletion in `upload_priors_to_supabase.py`

The `_call` helper (lines 4–16) handles `supabase-py` API differences (old `options=` vs new
`file_options=`). Deleting it only affects the Supabase upload path, which is now handled by
`SupabaseStorageBackend.upload_bytes()`. That backend uses `file_options=` (current API).

**Verify:** If the production server runs an older `supabase-py` that expects `options=`, the
`SupabaseStorageBackend` upload will fail. Check `pip show supabase` to confirm SDK version.
The `SupabaseStorageBackend` may need the same compat guard if the old SDK version is in use.

---

## Change Summary per File

| File | Import lines changed | Storage call lines changed | Env var lines changed | Lines deleted | Net change |
|------|---------------------|---------------------------|----------------------|--------------|------------|
| `data_access_v1.py` | 10–13 | 80, 95, 100 | 56–60 (inside deleted fn) | 9 (fn deleted) | −9, ~0 net |
| `export_features_dense.py` | 14 | 300, 307–311, 326–329, 344, 455 | 95–103, 131, 144 | 15 (fn deleted) | −15, ~+2 net |
| `upload_priors_to_supabase.py` | 31 | 32–62 (whole block) | 23–29 | 44 (fn + block) | −44, ~+5 net |
| `download_priors_from_supabase.py` | 16 | 17–26 (whole block) | 8–14 | 19 | −19, ~+5 net |
