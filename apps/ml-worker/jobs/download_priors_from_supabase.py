from __future__ import annotations

import os
from pathlib import Path

from storage.factory import get_storage
from jobs.common import load_env, get_worker_root, base_arg_parser

load_env()


def main() -> int:
    parser = base_arg_parser("Download priors bundle from configured storage backend")
    args = parser.parse_args()
    if args.dry_run:
        print("DRY_RUN: download_priors | no files written")
        return 0

    local_path = Path(os.getenv("PRIORS_LOCAL_PATH", str(get_worker_root() / "priors_cache" / "priors_v1.parquet")))
    remote_path = os.getenv("PRIORS_REMOTE_PATH", "priors/priors_v1.parquet")

    storage = get_storage()

    try:
        content = storage.download_bytes(remote_path)
    except Exception as e:
        raise SystemExit(f"Download priors failed: remote={remote_path} err={e}")

    local_path.parent.mkdir(parents=True, exist_ok=True)
    local_path.write_bytes(content)

    print(f"OK download_priors | remote={remote_path} local={local_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
