"""Validation helpers for the build-global dry-run scaffold."""

from __future__ import annotations

from pathlib import Path


ALLOWED_SOURCES = {"cloud", "local"}
ALLOWED_MODES = {"full", "incremental"}


def validate_source(source: str) -> None:
    if source not in ALLOWED_SOURCES:
        raise ValueError(f"Invalid source={source!r}. Allowed: {sorted(ALLOWED_SOURCES)}")


def validate_mode(mode: str) -> None:
    if mode not in ALLOWED_MODES:
        raise ValueError(f"Invalid mode={mode!r}. Allowed: {sorted(ALLOWED_MODES)}")


def validate_output_root(output_root: Path) -> None:
    resolved = output_root.resolve()
    allowed_parent = Path("/opt/greenbrain-platform/runtime/ml-datasets/runs").resolve()
    if resolved != allowed_parent and allowed_parent not in resolved.parents:
        raise ValueError(
            f"Refusing output_root outside runtime ml-datasets runs: {resolved}"
        )


def validate_run_id(run_id: str) -> None:
    if not run_id:
        raise ValueError("run_id cannot be empty")
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    bad = sorted(set(run_id) - allowed)
    if bad:
        raise ValueError(f"run_id contains invalid characters: {bad}")
