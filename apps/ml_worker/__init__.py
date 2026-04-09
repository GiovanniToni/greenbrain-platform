"""
apps/ml_worker — Python package bridge for apps/ml-worker/.

Allows running jobs as:
    python -m apps.ml_worker.jobs.<job_name>

from the greenbrain-platform repo root, even though the actual source lives
in apps/ml-worker/ (hyphenated directory, not directly importable).
"""
import sys
from pathlib import Path

_ml_worker_root = Path(__file__).resolve().parent.parent / "ml-worker"
if str(_ml_worker_root) not in sys.path:
    sys.path.insert(0, str(_ml_worker_root))
