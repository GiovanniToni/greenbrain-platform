"""
Namespace bridge: extends __path__ so that
`python -m apps.ml_worker.jobs.<job>` resolves to
`apps/ml-worker/jobs/<job>.py`.
"""
from pathlib import Path

_real_jobs_dir = str(Path(__file__).resolve().parent.parent.parent / "ml-worker" / "jobs")
if _real_jobs_dir not in __path__:
    __path__.append(_real_jobs_dir)
