from __future__ import annotations

import os
import time
from pathlib import Path

from storage.factory import get_storage
from jobs.common import load_env, get_worker_root, base_arg_parser

load_env()


def main() -> int:
    parser = base_arg_parser("Upload priors bundle to configured storage backend")
    args = parser.parse_args()
    if args.dry_run:
        print("DRY_RUN: upload_priors | no files uploaded")
        return 0

    local_path = Path(os.getenv("PRIORS_LOCAL_PATH", str(get_worker_root() / "priors_cache" / "priors_v1.parquet")))
    remote_path = os.getenv("PRIORS_REMOTE_PATH", "priors/priors_v1.parquet")

    if not local_path.exists():
        raise SystemExit(f"Missing priors file: {local_path}")

    storage = get_storage()
    content = local_path.read_bytes()

    max_attempts = int(os.getenv("PRIORS_UPLOAD_MAX_ATTEMPTS", "6"))
    sleep_seconds = int(os.getenv("PRIORS_UPLOAD_RETRY_SLEEP_SECONDS", "20"))

    last_error = None
    for attempt in range(1, max_attempts + 1):
        try:
            storage.upload_bytes(
                remote_path=remote_path,
                content=content,
                content_type="application/octet-stream",
            )
            print(
                f"OK upload_priors | local={local_path} remote={remote_path} "
                f"attempt={attempt}/{max_attempts}"
            )
            return 0
        except Exception as e:
            last_error = e
            print(
                f"WARN upload_priors failed | attempt={attempt}/{max_attempts} "
                f"remote={remote_path} err={type(e).__name__}: {e}",
                flush=True,
            )
            if attempt < max_attempts:
                time.sleep(sleep_seconds)

    raise SystemExit(
        f"FAILED upload_priors after {max_attempts} attempts | "
        f"remote={remote_path} err={type(last_error).__name__}: {last_error}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
