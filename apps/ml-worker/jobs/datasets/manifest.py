"""Manifest helpers for GreenBrain build-global dataset runs.

This module is intentionally small and side-effect-light. It only writes JSON
inside an explicitly provided run directory.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def ensure_run_layout(run_dir: Path) -> None:
    for rel in [
        "metadata",
        "analysis",
        "logs",
        "raw_extracts",
        "family_priceband_day",
        "weather_wide",
        "family_day",
        "family_day_enriched",
        "family_priceband_day_enriched",
        "rolling_sidecar",
    ]:
        (run_dir / rel).mkdir(parents=True, exist_ok=True)


@dataclass
class BuildGlobalStage:
    name: str
    status: str
    source_kind: str
    source_reference: str
    output_reference: str
    notes: str = ""


@dataclass
class BuildGlobalManifest:
    run_id: str
    command: str
    dry_run: bool
    source: str
    mode: str
    as_of_date: str
    output_root: str
    run_dir: str
    created_at_utc: str = field(default_factory=utc_now_iso)
    safety: dict[str, str] = field(default_factory=dict)
    stages: list[BuildGlobalStage] = field(default_factory=list)
    inputs: dict[str, Any] = field(default_factory=dict)
    decision: str = "BUILD_GLOBAL_DRY_RUN_PLAN_ONLY"

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["stages"] = [asdict(stage) for stage in self.stages]
        return data


def write_manifest(manifest: BuildGlobalManifest, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(manifest.to_dict(), indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def write_decision_csv(path: Path, manifest: BuildGlobalManifest) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "key,value\n"
        f"run_id,{manifest.run_id}\n"
        f"command,{manifest.command}\n"
        f"dry_run,{manifest.dry_run}\n"
        f"source,{manifest.source}\n"
        f"mode,{manifest.mode}\n"
        f"as_of_date,{manifest.as_of_date}\n"
        f"run_dir,{manifest.run_dir}\n"
        f"decision,{manifest.decision}\n",
        encoding="utf-8",
    )
