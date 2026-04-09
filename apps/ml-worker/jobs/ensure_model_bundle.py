import os
import sys
import re
from pathlib import Path
from jobs.common import load_env, get_models_dir, setup_import_path

load_env()
setup_import_path()

MODELS_DIR = get_models_dir()
STORAGE_PREFIX = os.getenv("MODEL_STORAGE_PREFIX", "models_v4")

from storage.factory import get_storage


def _canon_slug(x: str) -> str:
    s = (x or "").strip().lower()
    s = s.replace("€", "eur")
    s = re.sub(r"\s+", "-", s)
    s = re.sub(r"[^a-z0-9._-]+", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s


def _legacy_slug_underscore(x: str) -> str:
    s = (x or "").strip().lower()
    s = s.replace("€", "eur").replace(" ", "_")
    s = re.sub(r"_+", "_", s).strip("_")
    return s


def fam_to_bundle_name(fam: str) -> str:
    slug = _canon_slug(fam)
    return f"bundle_{slug}_v4.pkl"


def fam_to_bundle_name_legacy(fam: str) -> str:
    slug = _legacy_slug_underscore(fam)
    return f"bundle_{slug}_v4.pkl"


def bundle_local_path_by_name(name: str) -> Path:
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    return MODELS_DIR / name


def bundle_storage_key_by_name(name: str) -> str:
    return f"{STORAGE_PREFIX}/{name}"


def ensure_bundle(fam: str):
    storage = get_storage()

    canon_name = fam_to_bundle_name(fam)
    canon_local = bundle_local_path_by_name(canon_name)
    if canon_local.exists():
        return True, f"LOCAL_OK {canon_local}"

    legacy_name = fam_to_bundle_name_legacy(fam)
    legacy_local = bundle_local_path_by_name(legacy_name)

    canon_key = bundle_storage_key_by_name(canon_name)
    if storage.exists(canon_key):
        canon_local.write_bytes(storage.read(canon_key))
        return True, f"DOWNLOADED {canon_key} -> {canon_local}"

    if legacy_local.exists():
        try:
            canon_local.write_bytes(legacy_local.read_bytes())
            return True, f"LOCAL_LEGACY_OK {legacy_local} -> COPIED_AS {canon_local}"
        except Exception:
            return True, f"LOCAL_LEGACY_OK {legacy_local}"

    legacy_key = bundle_storage_key_by_name(legacy_name)
    if storage.exists(legacy_key):
        legacy_local.write_bytes(storage.read(legacy_key))
        try:
            canon_local.write_bytes(legacy_local.read_bytes())
            return True, f"DOWNLOADED_LEGACY {legacy_key} -> {legacy_local} | COPIED_AS {canon_local}"
        except Exception:
            return True, f"DOWNLOADED_LEGACY {legacy_key} -> {legacy_local}"

    return False, f"STORAGE_MISSING {canon_key} (and legacy {legacy_key})"


def upload_bundle(fam: str):
    storage = get_storage()

    canon_name = fam_to_bundle_name(fam)
    canon_local = bundle_local_path_by_name(canon_name)

    if not canon_local.exists():
        legacy_name = fam_to_bundle_name_legacy(fam)
        legacy_local = bundle_local_path_by_name(legacy_name)
        if legacy_local.exists():
            try:
                canon_local.write_bytes(legacy_local.read_bytes())
            except Exception:
                pass

    if not canon_local.exists():
        return False, f"LOCAL_MISSING {canon_local}"

    canon_key = bundle_storage_key_by_name(canon_name)
    storage.write(canon_key, canon_local.read_bytes())
    return True, f"UPLOADED {canon_local} -> {canon_key}"


def ensure_bundle_any_engine(fam: str):
    ok, msg = ensure_bundle(fam)
    if ok:
        return ok, msg

    slug = _canon_slug(fam)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    matches = sorted(MODELS_DIR.glob(f"bundle_{slug}_*.pkl"))
    if matches:
        best = max(matches, key=lambda p: p.stat().st_mtime)
        return True, f"LOCAL_ENGINE_BUNDLE {best}"

    return False, msg + f" | NO_ENGINE_BUNDLE bundle_{slug}_*.pkl"


if __name__ == "__main__":
    fam = " ".join(sys.argv[1:]).strip()
    if not fam:
        print("Usage: python jobs/ensure_model_bundle.py <famiglia_or_slug>")
        raise SystemExit(2)

    ok, msg = ensure_bundle(fam)
    print(msg)
    raise SystemExit(0 if ok else 1)
