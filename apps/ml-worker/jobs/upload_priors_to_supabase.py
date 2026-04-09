from __future__ import annotations

import os
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
    storage.upload_bytes(
        remote_path=remote_path,
        content=local_path.read_bytes(),
        content_type="application/octet-stream",
    )

    print(f"OK upload_priors | local={local_path} remote={remote_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
