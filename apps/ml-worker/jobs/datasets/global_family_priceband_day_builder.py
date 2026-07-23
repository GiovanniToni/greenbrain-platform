#!/usr/bin/env python3
"""Phase 2M-H2 family-priceband-day source scaffold.

This audited scaffold implements contract loading, input resolution,
partition inventory, supervisor candidate ownership and CLI wiring.

Full Parquet materialization is deliberately blocked until the
streaming join implementation passes its dedicated micro-fixture and
failure-injection phases.
"""

from __future__ import annotations

import hashlib as _h2p_trust_hashlib
import os as _h2p_trust_os
import threading as _h2p_trust_threading

import hashlib as _h2p_hashlib
import json as _h2p_json
import os as _h2p_os
import re as _h2p_re
import shutil as _h2p_shutil
from pathlib import Path as _H2PPath

import pyarrow as _h2p_pa
import pyarrow.parquet as _h2p_pq

import argparse
import csv
import gc
import hashlib
import json
import os
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence

import pyarrow as pa
import pyarrow.parquet as pq


FULL_MATERIALIZATION_IMPLEMENTED = True
OWNER_ENVIRONMENT_VARIABLE = (
    "GREENBRAIN_H2_CANDIDATE_OWNER_TOKEN"
)
OWNERSHIP_MARKER_RELATIVE_PATH = Path(
    "metadata/"
    "global_family_priceband_day_"
    "candidate_ownership.json"
)
CONTRACT_FILENAME = (
    "phase2m_h2_family_priceband_day_contract_v1.json"
)
EXIT_DRAFT_RUNTIME_BLOCKED = 78


class DraftRuntimeBlocked(RuntimeError):
    """Raised when an unapproved materialization path is requested."""


class SupervisorSignalReceived(RuntimeError):
    """Raised by a temporary supervisor signal handler."""

    def __init__(self, signum: int) -> None:
        self.signum = signum
        super().__init__(
            f"SUPERVISOR_SIGNAL_RECEIVED:{signum}"
        )


@dataclass(frozen=True)
class ResolvedInput:
    role: str
    run_id: str
    run_root: Path
    dataset_root: Path
    key_columns: tuple[str, ...]


@dataclass(frozen=True)
class CandidateReservation:
    candidate: Path
    final: Path
    run_id: str
    token: str
    token_sha256: str
    st_dev: int
    st_ino: int
    marker: Path


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_contract(path: Path) -> dict[str, Any]:
    payload = json.loads(
        path.read_text(
            encoding="utf-8",
            errors="strict",
        )
    )

    embedded = payload.get(
        "contract_fingerprint"
    )

    if not isinstance(embedded, str):
        raise ValueError(
            "CONTRACT_FINGERPRINT_MISSING"
        )

    preimage = dict(payload)
    preimage.pop(
        "contract_fingerprint"
    )

    actual = sha256_bytes(
        canonical_json_bytes(
            preimage
        )
    )

    if actual != embedded:
        raise ValueError(
            "CONTRACT_FINGERPRINT_MISMATCH:"
            f"expected={embedded}:actual={actual}"
        )

    return payload


def write_json_atomic(
    path: Path,
    payload: Any,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    temporary = path.with_name(
        f".{path.name}.{os.getpid()}.tmp"
    )

    try:
        with temporary.open(
            "w",
            encoding="utf-8",
        ) as handle:
            json.dump(
                payload,
                handle,
                indent=2,
                ensure_ascii=True,
                allow_nan=False,
                sort_keys=True,
            )
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(
            temporary,
            path,
        )

    finally:
        if temporary.exists():
            temporary.unlink()


def write_tsv_atomic(
    path: Path,
    fieldnames: Sequence[str],
    rows: Iterable[dict[str, Any]],
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    temporary = path.with_name(
        f".{path.name}.{os.getpid()}.tmp"
    )

    try:
        with temporary.open(
            "w",
            encoding="utf-8",
            newline="",
        ) as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=list(fieldnames),
                delimiter="\t",
                extrasaction="ignore",
            )
            writer.writeheader()
            writer.writerows(rows)
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(
            temporary,
            path,
        )

    finally:
        if temporary.exists():
            temporary.unlink()


def parse_args(
    argv: Sequence[str] | None = None,
) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build or validate the Phase 2M-H2 "
            "family-priceband-day feature lake."
        )
    )

    parser.add_argument(
        "--mode",
        required=True,
        choices=(
            "dry-run",
            "execute",
            "validate-only",
            "_worker-execute",
        ),
    )
    parser.add_argument(
        "--contract",
        default=str(
            Path(__file__).resolve().parent
            / "contracts"
            / CONTRACT_FILENAME
        ),
    )
    parser.add_argument(
        "--runs-root",
        required=True,
    )
    parser.add_argument(
        "--b2-run",
        required=True,
    )
    parser.add_argument(
        "--f2-run",
        required=True,
    )
    parser.add_argument(
        "--c2-run",
        required=True,
    )
    parser.add_argument(
        "--g2-run",
        required=True,
    )
    parser.add_argument(
        "--output-root",
    )
    parser.add_argument(
        "--run-id",
    )
    parser.add_argument(
        "--batch-rows",
        type=int,
        default=512,
    )
    parser.add_argument(
        "--validator",
        default=str(
            Path(__file__).resolve().parent
            / "global_family_priceband_day_validation.py"
        ),
    )
    parser.add_argument(
        "--existing-run",
    )
    parser.add_argument(
        "--termination-grace-seconds",
        type=int,
        default=30,
    )
    parser.add_argument(
        "--failure-injection",
        default="none",
        choices=(
            "none",
            "after-first-partition",
            "before-validator",
            "after-validator-before-marker",
            "after-marker-before-promotion",
        ),
    )

    return parser.parse_args(argv)


def _direct_child(
    root: Path,
    name: str,
) -> Path:
    if not name:
        raise ValueError(
            "EMPTY_DIRECT_CHILD_NAME"
        )

    if Path(name).name != name:
        raise ValueError(
            f"NON_DIRECT_CHILD_NAME:{name}"
        )

    root_resolved = root.resolve(
        strict=True
    )

    child = root_resolved / name

    if child.parent != root_resolved:
        raise ValueError(
            f"PATH_ESCAPE:{child}"
        )

    return child


def resolve_inputs(
    args: argparse.Namespace,
    contract: dict[str, Any],
) -> dict[str, ResolvedInput]:
    runs_root = Path(
        args.runs_root
    ).resolve(strict=True)

    if not runs_root.is_dir():
        raise NotADirectoryError(
            f"RUNS_ROOT_NOT_DIRECTORY:{runs_root}"
        )

    argument_map = {
        "B2_GRID": args.b2_run,
        "F2_PAIR_SALES": args.f2_run,
        "C2_PAIR_PRODUCT": args.c2_run,
        "G2_FAMILY_DAY": args.g2_run,
    }

    resolved: dict[str, ResolvedInput] = {}

    for role, payload in contract[
        "required_inputs"
    ].items():
        run_id = argument_map[role]

        run_root = _direct_child(
            runs_root,
            run_id,
        ).resolve(strict=True)

        dataset_root = (
            run_root
            / payload["dataset_root"]
        ).resolve(strict=True)

        if not dataset_root.is_dir():
            raise NotADirectoryError(
                "INPUT_DATASET_NOT_DIRECTORY:"
                f"role={role}:path={dataset_root}"
            )

        if not dataset_root.is_relative_to(
            run_root
        ):
            raise ValueError(
                "INPUT_DATASET_ESCAPES_RUN_ROOT:"
                f"role={role}"
            )

        resolved[role] = ResolvedInput(
            role=role,
            run_id=run_id,
            run_root=run_root,
            dataset_root=dataset_root,
            key_columns=tuple(
                payload["key_columns"]
            ),
        )

    return resolved


def _partition_key(
    path: Path,
    dataset_root: Path,
) -> tuple[int, int]:
    relative = path.relative_to(
        dataset_root
    )

    year: int | None = None
    month: int | None = None

    for part in relative.parts:
        if part.startswith("year="):
            year = int(
                part.split("=", 1)[1]
            )

        elif part.startswith("month="):
            month = int(
                part.split("=", 1)[1]
            )

    if year is None or month is None:
        raise ValueError(
            "PARQUET_PARTITION_KEYS_MISSING:"
            f"{path}"
        )

    if not 1 <= month <= 12:
        raise ValueError(
            f"INVALID_PARTITION_MONTH:{path}"
        )

    return year, month


def inventory_partitions(
    dataset_root: Path,
) -> list[dict[str, Any]]:
    parquet_files = sorted(
        dataset_root.rglob("*.parquet")
    )

    if not parquet_files:
        raise FileNotFoundError(
            "NO_PARQUET_FILES:"
            f"{dataset_root}"
        )

    rows: list[dict[str, Any]] = []

    for path in parquet_files:
        year, month = _partition_key(
            path,
            dataset_root,
        )

        metadata = pq.read_metadata(
            path
        )

        rows.append(
            {
                "year": year,
                "month": month,
                "path": str(path),
                "relative_path": str(
                    path.relative_to(
                        dataset_root
                    )
                ),
                "rows": metadata.num_rows,
                "row_groups": (
                    metadata.num_row_groups
                ),
                "columns": (
                    metadata.num_columns
                ),
                "size_bytes": (
                    path.stat().st_size
                ),
            }
        )

    return rows


def validate_partition_alignment(
    inventories: dict[
        str,
        list[dict[str, Any]],
    ],
) -> None:
    aligned_roles = (
        "B2_GRID",
        "F2_PAIR_SALES",
        "G2_FAMILY_DAY",
    )

    partition_sets = {
        role: {
            (
                int(row["year"]),
                int(row["month"]),
            )
            for row in inventories[role]
        }
        for role in aligned_roles
    }

    reference = partition_sets[
        "B2_GRID"
    ]

    for role in aligned_roles[1:]:
        if partition_sets[role] != reference:
            raise ValueError(
                "PARTITION_ALIGNMENT_MISMATCH:"
                f"role={role}"
            )

    b2_rows = {
        (
            int(row["year"]),
            int(row["month"]),
        ): int(row["rows"])
        for row in inventories[
            "B2_GRID"
        ]
    }

    f2_rows = {
        (
            int(row["year"]),
            int(row["month"]),
        ): int(row["rows"])
        for row in inventories[
            "F2_PAIR_SALES"
        ]
    }

    if b2_rows != f2_rows:
        raise ValueError(
            "B2_F2_PARTITION_ROW_MISMATCH"
        )


def safe_candidate_path(
    output_root: Path,
    run_id: str,
) -> tuple[Path, Path]:
    root = output_root.resolve(
        strict=True
    )

    final = _direct_child(
        root,
        run_id,
    )

    candidate = _direct_child(
        root,
        f".{run_id}.candidate",
    )

    if final.exists():
        raise FileExistsError(
            f"FINAL_ALREADY_EXISTS:{final}"
        )

    if candidate.exists() or (
        candidate.is_symlink()
    ):
        raise FileExistsError(
            "CANDIDATE_ALREADY_EXISTS:"
            f"{candidate}"
        )

    return candidate, final


def write_candidate_ownership_marker(
    reservation: CandidateReservation,
    run_id: str,
) -> None:
    if run_id != reservation.run_id:
        raise ValueError(
            "RESERVATION_RUN_ID_MISMATCH"
        )

    marker = reservation.marker
    marker.parent.mkdir(
        parents=True,
        exist_ok=False,
        mode=0o700,
    )

    payload = {
        "format_version": 1,
        "run_id": run_id,
        "candidate_name": (
            reservation.candidate.name
        ),
        "final_name": (
            reservation.final.name
        ),
        "owner_token_sha256": (
            reservation.token_sha256
        ),
        "reserved_st_dev": (
            reservation.st_dev
        ),
        "reserved_st_ino": (
            reservation.st_ino
        ),
        "supervisor_pid": os.getpid(),
        "created_at_utc": (
            datetime_now_utc()
        ),
    }

    flags = (
        os.O_WRONLY
        | os.O_CREAT
        | os.O_EXCL
    )

    descriptor = os.open(
        marker,
        flags,
        0o600,
    )

    try:
        encoded = (
            json.dumps(
                payload,
                indent=2,
                ensure_ascii=True,
                allow_nan=False,
                sort_keys=True,
            )
            + "\n"
        ).encode("utf-8")

        os.write(
            descriptor,
            encoded,
        )
        os.fsync(descriptor)

    finally:
        os.close(descriptor)


def datetime_now_utc() -> str:
    from datetime import (
        datetime,
        timezone,
    )

    return datetime.now(
        timezone.utc
    ).isoformat()


def reserve_candidate_atomically(
    output_root: Path,
    run_id: str,
) -> CandidateReservation:
    candidate, final = (
        safe_candidate_path(
            output_root,
            run_id,
        )
    )

    candidate.mkdir(
        parents=False,
        exist_ok=False,
        mode=0o700,
    )

    stat_result = candidate.stat(
        follow_symlinks=False
    )

    token = secrets.token_hex(32)
    token_sha256 = sha256_bytes(
        token.encode("ascii")
    )

    reservation = CandidateReservation(
        candidate=candidate,
        final=final,
        run_id=run_id,
        token=token,
        token_sha256=token_sha256,
        st_dev=stat_result.st_dev,
        st_ino=stat_result.st_ino,
        marker=(
            candidate
            / OWNERSHIP_MARKER_RELATIVE_PATH
        ),
    )

    try:
        write_candidate_ownership_marker(
            reservation,
            run_id,
        )
    except Exception:
        shutil.rmtree(
            candidate
        )
        raise

    return reservation


def verify_candidate_ownership(
    reservation: CandidateReservation,
    token: str,
) -> dict[str, Any]:
    candidate = reservation.candidate

    if candidate.is_symlink():
        raise ValueError(
            "CANDIDATE_SYMLINK_FORBIDDEN"
        )

    stat_result = candidate.stat(
        follow_symlinks=False
    )

    if (
        stat_result.st_dev
        != reservation.st_dev
        or stat_result.st_ino
        != reservation.st_ino
    ):
        raise ValueError(
            "CANDIDATE_FILESYSTEM_IDENTITY_MISMATCH"
        )

    marker = json.loads(
        reservation.marker.read_text(
            encoding="utf-8",
            errors="strict",
        )
    )

    token_sha256 = sha256_bytes(
        token.encode("ascii")
    )

    expected = {
        "run_id": reservation.run_id,
        "candidate_name": (
            candidate.name
        ),
        "final_name": (
            reservation.final.name
        ),
        "owner_token_sha256": (
            token_sha256
        ),
        "reserved_st_dev": (
            reservation.st_dev
        ),
        "reserved_st_ino": (
            reservation.st_ino
        ),
    }

    for key, value in expected.items():
        if marker.get(key) != value:
            raise ValueError(
                "CANDIDATE_OWNERSHIP_MISMATCH:"
                f"{key}"
            )

    return marker


def open_candidate_no_follow(
    output_root: Path,
    candidate_name: str,
) -> tuple[int, int]:
    root_fd = os.open(
        output_root,
        os.O_RDONLY
        | getattr(
            os,
            "O_DIRECTORY",
            0,
        ),
    )

    try:
        candidate_fd = os.open(
            candidate_name,
            os.O_RDONLY
            | getattr(
                os,
                "O_DIRECTORY",
                0,
            )
            | getattr(
                os,
                "O_NOFOLLOW",
                0,
            ),
            dir_fd=root_fd,
        )

    except Exception:
        os.close(root_fd)
        raise

    return root_fd, candidate_fd


def install_supervisor_signal_handlers(
) -> dict[int, Any]:
    previous: dict[int, Any] = {}
    installed: list[int] = []

    def handler(
        signum: int,
        _frame: Any,
    ) -> None:
        raise SupervisorSignalReceived(
            signum
        )

    try:
        for signum in (
            signal.SIGINT,
            signal.SIGTERM,
        ):
            previous[signum] = signal.getsignal(
                signum
            )

            signal.signal(
                signum,
                handler,
            )

            installed.append(signum)

    except BaseException:
        for signum in reversed(
            installed
        ):
            signal.signal(
                signum,
                previous[signum],
            )

        raise

    return previous

def restore_supervisor_signal_handlers(
    previous: dict[int, Any],
) -> None:
    for signum, handler in previous.items():
        signal.signal(signum, handler)


def cleanup_reserved_candidate_on_launch_failure(
    output_root: Path,
    reservation: CandidateReservation,
) -> None:
    if not reservation.candidate.exists():
        return

    cleanup_owned_candidate_after_barrier(
        output_root,
        reservation,
        reservation.token,
    )


def terminate_worker_process_group(
    process: subprocess.Popen[Any],
    grace_seconds: int,
) -> None:
    if process.poll() is not None:
        return

    os.killpg(
        process.pid,
        signal.SIGTERM,
    )

    deadline = (
        time.monotonic()
        + max(0, grace_seconds)
    )

    while (
        process.poll() is None
        and time.monotonic() < deadline
    ):
        time.sleep(0.1)

    if process.poll() is None:
        os.killpg(
            process.pid,
            signal.SIGKILL,
        )

    process.wait()


def _directory_open_flags() -> int:
    return (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )


def _remove_directory_entry_fd(
    parent_fd: int,
    name: str,
    *,
    expected_st_dev: int | None = None,
    expected_st_ino: int | None = None,
) -> None:
    if not name or Path(name).name != name:
        raise ValueError(
            f"INVALID_DIRECTORY_ENTRY_NAME:{name}"
        )

    directory_fd = os.open(
        name,
        _directory_open_flags(),
        dir_fd=parent_fd,
    )

    try:
        opened_stat = os.fstat(
            directory_fd
        )

        linked_stat = os.stat(
            name,
            dir_fd=parent_fd,
            follow_symlinks=False,
        )

        if not stat.S_ISDIR(
            linked_stat.st_mode
        ):
            raise ValueError(
                "DIRECTORY_ENTRY_NOT_DIRECTORY:"
                f"{name}"
            )

        if (
            opened_stat.st_dev
            != linked_stat.st_dev
            or opened_stat.st_ino
            != linked_stat.st_ino
        ):
            raise ValueError(
                "DIRECTORY_ENTRY_IDENTITY_RACE:"
                f"{name}"
            )

        if (
            expected_st_dev is not None
            and opened_stat.st_dev
            != expected_st_dev
        ):
            raise ValueError(
                "DIRECTORY_ENTRY_DEVICE_MISMATCH:"
                f"{name}"
            )

        if (
            expected_st_ino is not None
            and opened_stat.st_ino
            != expected_st_ino
        ):
            raise ValueError(
                "DIRECTORY_ENTRY_INODE_MISMATCH:"
                f"{name}"
            )

        for child_name in sorted(
            os.listdir(directory_fd)
        ):
            child_stat = os.stat(
                child_name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )

            if stat.S_ISDIR(
                child_stat.st_mode
            ):
                _remove_directory_entry_fd(
                    directory_fd,
                    child_name,
                    expected_st_dev=(
                        child_stat.st_dev
                    ),
                    expected_st_ino=(
                        child_stat.st_ino
                    ),
                )

            else:
                os.unlink(
                    child_name,
                    dir_fd=directory_fd,
                )

        os.rmdir(
            name,
            dir_fd=parent_fd,
        )

    finally:
        os.close(directory_fd)


def remove_tree_fd_relative(
    parent_fd: int,
    name: str,
    *,
    expected_st_dev: int,
    expected_st_ino: int,
) -> None:
    _remove_directory_entry_fd(
        parent_fd,
        name,
        expected_st_dev=expected_st_dev,
        expected_st_ino=expected_st_ino,
    )


def wait_for_worker_process_barrier_after_termination_failure(
    process: subprocess.Popen[Any],
    grace_seconds: int,
) -> int:
    timeout = max(
        0,
        grace_seconds,
    )

    try:
        return process.wait(
            timeout=timeout,
        )

    except TypeError:
        return process.wait()

    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            "PROCESS_BARRIER_NOT_REACHED_"
            "AFTER_TERMINATION_FAILURE"
        ) from exc


def cleanup_owned_candidate_after_barrier(
    output_root: Path,
    reservation: CandidateReservation,
    token: str,
) -> None:
    verify_candidate_ownership(
        reservation,
        token,
    )

    root_fd = os.open(
        output_root,
        _directory_open_flags(),
    )

    try:
        remove_tree_fd_relative(
            root_fd,
            reservation.candidate.name,
            expected_st_dev=(
                reservation.st_dev
            ),
            expected_st_ino=(
                reservation.st_ino
            ),
        )

    finally:
        os.close(root_fd)

    if reservation.candidate.exists():
        raise RuntimeError(
            "CANDIDATE_CLEANUP_INCOMPLETE"
        )

def cleanup_candidate_after_barrier(
    output_root: Path,
    reservation: CandidateReservation,
    token: str,
) -> None:
    cleanup_owned_candidate_after_barrier(
        output_root,
        reservation,
        token,
    )


def worker_command(
    args: argparse.Namespace,
) -> list[str]:
    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--mode",
        "_worker-execute",
        "--contract",
        str(args.contract),
        "--runs-root",
        str(args.runs_root),
        "--b2-run",
        str(args.b2_run),
        "--f2-run",
        str(args.f2_run),
        "--c2-run",
        str(args.c2_run),
        "--g2-run",
        str(args.g2_run),
        "--output-root",
        str(args.output_root),
        "--run-id",
        str(args.run_id),
        "--batch-rows",
        str(args.batch_rows),
        "--validator",
        str(args.validator),
        "--failure-injection",
        str(args.failure_injection),
    ]

    return command


def validator_command(
    args: argparse.Namespace,
    candidate_run: Path,
) -> list[str]:
    return [
        sys.executable,
        str(Path(args.validator).resolve()),
        "--mode",
        "validate",
        "--contract",
        str(args.contract),
        "--candidate-run",
        str(candidate_run),
        "--runs-root",
        str(args.runs_root),
        "--b2-run",
        str(args.b2_run),
        "--f2-run",
        str(args.f2_run),
        "--c2-run",
        str(args.c2_run),
        "--g2-run",
        str(args.g2_run),
    ]


def load_c2_pair_dimension(
    *_args: Any,
    **_kwargs: Any,
) -> Any:
    raise DraftRuntimeBlocked(
        "H2_C2_DIMENSION_RUNTIME_NOT_IMPLEMENTED"
    )


def stream_b2_f2_batches(
    *_args: Any,
    **_kwargs: Any,
) -> Iterator[Any]:
    raise DraftRuntimeBlocked(
        "H2_B2_F2_STREAM_RUNTIME_NOT_IMPLEMENTED"
    )


def stream_g2_family_day_cursor(
    *_args: Any,
    **_kwargs: Any,
) -> Iterator[Any]:
    raise DraftRuntimeBlocked(
        "H2_G2_CURSOR_RUNTIME_NOT_IMPLEMENTED"
    )


def assemble_output_batch(
    *_args: Any,
    **_kwargs: Any,
) -> pa.RecordBatch:
    raise DraftRuntimeBlocked(
        "H2_OUTPUT_ASSEMBLY_RUNTIME_NOT_IMPLEMENTED"
    )


def write_partition(
    *_args: Any,
    **_kwargs: Any,
) -> None:
    raise DraftRuntimeBlocked(
        "H2_PARTITION_WRITE_RUNTIME_NOT_IMPLEMENTED"
    )


def release_process_memory() -> None:
    gc.collect()

    try:
        pa.default_memory_pool().release_unused()
    except Exception:
        pass


def _assert_no_symlink_path_components(
    path: Path,
    *,
    label: str,
) -> Path:
    raw_path = Path(path)

    if ".." in raw_path.parts:
        raise ValueError(
            f"{label}_PARENT_TRAVERSAL_FORBIDDEN:"
            f"{raw_path}"
        )

    absolute_path = (
        raw_path
        if raw_path.is_absolute()
        else Path.cwd() / raw_path
    )

    current = Path(
        absolute_path.anchor
    )

    for component in absolute_path.parts[1:]:
        current = current / component

        try:
            mode = current.lstat().st_mode

        except FileNotFoundError as exc:
            raise ValueError(
                f"{label}_PATH_COMPONENT_MISSING:"
                f"{current}"
            ) from exc

        if stat.S_ISLNK(mode):
            raise ValueError(
                f"{label}_PATH_COMPONENT_"
                "SYMLINK_FORBIDDEN:"
                f"{current}"
            )

    return absolute_path


def list_partition_parquet_files(
    dataset_root: Path,
    partition: str,
) -> list[Path]:
    unresolved_root = (
        _assert_no_symlink_path_components(
            Path(dataset_root),
            label="DATASET_ROOT",
        )
    )

    root = unresolved_root.resolve(
        strict=True
    )

    if not root.is_dir():
        raise ValueError(
            "DATASET_ROOT_DIRECTORY_INVALID"
        )

    if partition == "__ROOT__":
        partition_path = root

    else:
        relative = Path(partition)

        if (
            relative.is_absolute()
            or ".." in relative.parts
            or str(relative) in {"", "."}
        ):
            raise ValueError(
                "INVALID_PARTITION_PATH:"
                f"{partition}"
            )

        unresolved_partition = root

        for component in relative.parts:
            unresolved_partition = (
                unresolved_partition
                / component
            )

            if unresolved_partition.is_symlink():
                raise ValueError(
                    "PARTITION_PATH_COMPONENT_"
                    "SYMLINK_FORBIDDEN:"
                    f"{partition};"
                    f"component={component}"
                )

        partition_path = (
            unresolved_partition.resolve(
                strict=True
            )
        )

        try:
            partition_path.relative_to(
                root
            )

        except ValueError as exc:
            raise ValueError(
                "PARTITION_OUTSIDE_DATASET_ROOT:"
                f"{partition}"
            ) from exc

    if (
        not partition_path.is_dir()
        or partition_path.is_symlink()
    ):
        raise ValueError(
            "PARTITION_DIRECTORY_INVALID:"
            f"{partition}"
        )

    files = sorted(
        partition_path.rglob(
            "*.parquet"
        )
    )

    if not files:
        raise ValueError(
            "PARTITION_PARQUET_FILES_MISSING:"
            f"{partition}"
        )

    safe_files: list[Path] = []

    for parquet_path in files:
        if parquet_path.is_symlink():
            raise ValueError(
                "PARQUET_FILE_SYMLINK_FORBIDDEN:"
                f"{parquet_path}"
            )

        relative_file = (
            parquet_path.relative_to(
                partition_path
            )
        )

        unresolved_component = (
            partition_path
        )

        for component in relative_file.parts:
            unresolved_component = (
                unresolved_component
                / component
            )

            if unresolved_component.is_symlink():
                raise ValueError(
                    "PARQUET_PATH_COMPONENT_"
                    "SYMLINK_FORBIDDEN:"
                    f"{parquet_path};"
                    f"component={component}"
                )

        resolved = parquet_path.resolve(
            strict=True
        )

        try:
            resolved.relative_to(root)

        except ValueError as exc:
            raise ValueError(
                "PARQUET_FILE_OUTSIDE_DATASET_ROOT:"
                f"{parquet_path}"
            ) from exc

        safe_files.append(
            resolved
        )

    return safe_files


def _selected_arrow_schema(
    schema: pa.Schema,
    columns: tuple[str, ...] | None,
) -> pa.Schema:
    if columns is None:
        return schema

    missing = [
        column
        for column in columns
        if schema.get_field_index(
            column
        ) < 0
    ]

    if missing:
        raise ValueError(
            "PARQUET_COLUMNS_MISSING:"
            + ",".join(missing)
        )

    return pa.schema(
        [
            schema.field(column)
            for column in columns
        ]
    )


def iter_parquet_record_batches(
    files: list[Path],
    *,
    columns: tuple[str, ...] | None,
    batch_rows: int,
    source_label: str,
) -> Iterator[pa.RecordBatch]:
    if batch_rows <= 0:
        raise ValueError(
            "BATCH_ROWS_MUST_BE_POSITIVE"
        )

    if not files:
        raise ValueError(
            "PARQUET_FILE_LIST_EMPTY:"
            f"{source_label}"
        )

    expected_schema: pa.Schema | None = None

    for parquet_path in files:
        parquet_file = pq.ParquetFile(
            parquet_path
        )

        selected_schema = (
            _selected_arrow_schema(
                parquet_file.schema_arrow,
                columns,
            )
        )

        if expected_schema is None:
            expected_schema = selected_schema

        elif not selected_schema.equals(
            expected_schema,
            check_metadata=False,
        ):
            raise ValueError(
                "PARQUET_SCHEMA_DRIFT:"
                f"source={source_label};"
                f"file={parquet_path}"
            )

        for batch in parquet_file.iter_batches(
            batch_size=batch_rows,
            columns=(
                list(columns)
                if columns is not None
                else None
            ),
            use_threads=False,
        ):
            if batch.num_rows == 0:
                continue

            if not batch.schema.equals(
                expected_schema,
                check_metadata=False,
            ):
                raise ValueError(
                    "PARQUET_BATCH_SCHEMA_DRIFT:"
                    f"source={source_label};"
                    f"file={parquet_path}"
                )

            yield batch


class RecordBatchCursor:
    def __init__(
        self,
        files: list[Path],
        *,
        columns: tuple[str, ...] | None,
        batch_rows: int,
        source_label: str,
    ) -> None:
        self.source_label = source_label
        self._iterator = iter(
            iter_parquet_record_batches(
                files,
                columns=columns,
                batch_rows=batch_rows,
                source_label=source_label,
            )
        )
        self._batch: pa.RecordBatch | None = None
        self._offset = 0
        self._exhausted = False
        self.rows_consumed = 0

    def _ensure_batch(self) -> None:
        while (
            not self._exhausted
            and (
                self._batch is None
                or self._offset
                >= self._batch.num_rows
            )
        ):
            try:
                self._batch = next(
                    self._iterator
                )
                self._offset = 0

            except StopIteration:
                self._batch = None
                self._offset = 0
                self._exhausted = True

    def has_rows(self) -> bool:
        self._ensure_batch()

        return not self._exhausted

    def available_rows(self) -> int:
        self._ensure_batch()

        if (
            self._exhausted
            or self._batch is None
        ):
            return 0

        return (
            self._batch.num_rows
            - self._offset
        )

    def take(
        self,
        maximum_rows: int,
    ) -> pa.RecordBatch:
        if maximum_rows <= 0:
            raise ValueError(
                "CURSOR_TAKE_ROWS_MUST_BE_POSITIVE"
            )

        self._ensure_batch()

        if (
            self._exhausted
            or self._batch is None
        ):
            raise EOFError(
                "RECORD_BATCH_CURSOR_EXHAUSTED:"
                f"{self.source_label}"
            )

        row_count = min(
            maximum_rows,
            self.available_rows(),
        )

        result = self._batch.slice(
            self._offset,
            row_count,
        )

        self._offset += row_count
        self.rows_consumed += row_count

        return result


def assert_lockstep_key_equality(
    b2_batch: pa.RecordBatch,
    f2_batch: pa.RecordBatch,
    *,
    key_columns: tuple[str, ...],
    partition: str,
    global_row_offset: int,
) -> None:
    canonical_key_columns = (
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
    )

    provided_key_columns = tuple(
        key_columns
    )

    if (
        provided_key_columns
        != canonical_key_columns
    ):
        raise ValueError(
            "LOCKSTEP_CANONICAL_KEY_COLUMNS_REQUIRED:"
            f"expected={canonical_key_columns};"
            f"actual={provided_key_columns}"
        )

    if b2_batch.num_rows != f2_batch.num_rows:
        raise ValueError(
            "LOCKSTEP_BATCH_ROW_COUNT_MISMATCH:"
            f"partition={partition};"
            f"offset={global_row_offset};"
            f"b2={b2_batch.num_rows};"
            f"f2={f2_batch.num_rows}"
        )

    for key_column in canonical_key_columns:
        b2_index = (
            b2_batch.schema.get_field_index(
                key_column
            )
        )

        f2_index = (
            f2_batch.schema.get_field_index(
                key_column
            )
        )

        if (
            b2_index < 0
            or f2_index < 0
        ):
            raise ValueError(
                "LOCKSTEP_KEY_COLUMN_MISSING:"
                f"partition={partition};"
                f"column={key_column}"
            )

        b2_array = b2_batch.column(
            b2_index
        )

        f2_array = f2_batch.column(
            f2_index
        )

        if not b2_array.equals(
            f2_array
        ):
            mismatch_index: int | None = None

            for index, (
                b2_value,
                f2_value,
            ) in enumerate(
                zip(
                    b2_array.to_pylist(),
                    f2_array.to_pylist(),
                )
            ):
                if b2_value != f2_value:
                    mismatch_index = index
                    break

            raise ValueError(
                "LOCKSTEP_KEY_VALUE_MISMATCH:"
                f"partition={partition};"
                f"column={key_column};"
                f"global_offset={global_row_offset};"
                f"batch_offset={mismatch_index}"
            )


def iter_b2_f2_lockstep_batches(
    b2_files: list[Path],
    f2_files: list[Path],
    *,
    batch_rows: int,
    key_columns: tuple[str, ...] = (
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
    ),
    partition: str,
    b2_columns: tuple[str, ...] | None = None,
    f2_columns: tuple[str, ...] | None = None,
) -> Iterator[
    tuple[
        pa.RecordBatch,
        pa.RecordBatch,
    ]
]:
    canonical_key_columns = (
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
    )

    provided_key_columns = tuple(
        key_columns
    )

    if (
        provided_key_columns
        != canonical_key_columns
    ):
        raise ValueError(
            "LOCKSTEP_CANONICAL_KEY_COLUMNS_REQUIRED:"
            f"expected={canonical_key_columns};"
            f"actual={provided_key_columns}"
        )

    if batch_rows <= 0:
        raise ValueError(
            "BATCH_ROWS_MUST_BE_POSITIVE"
        )

    b2_cursor = RecordBatchCursor(
        b2_files,
        columns=b2_columns,
        batch_rows=batch_rows,
        source_label=(
            f"B2:{partition}"
        ),
    )

    f2_cursor = RecordBatchCursor(
        f2_files,
        columns=f2_columns,
        batch_rows=batch_rows,
        source_label=(
            f"F2:{partition}"
        ),
    )

    emitted_rows = 0

    while True:
        b2_has_rows = (
            b2_cursor.has_rows()
        )

        f2_has_rows = (
            f2_cursor.has_rows()
        )

        if (
            not b2_has_rows
            and not f2_has_rows
        ):
            break

        if b2_has_rows != f2_has_rows:
            raise ValueError(
                "LOCKSTEP_PREMATURE_EOF:"
                f"partition={partition};"
                f"emitted_rows={emitted_rows};"
                f"b2_has_rows={b2_has_rows};"
                f"f2_has_rows={f2_has_rows}"
            )

        slice_rows = min(
            batch_rows,
            b2_cursor.available_rows(),
            f2_cursor.available_rows(),
        )

        if slice_rows <= 0:
            raise RuntimeError(
                "LOCKSTEP_ZERO_PROGRESS:"
                f"partition={partition};"
                f"emitted_rows={emitted_rows}"
            )

        b2_batch = b2_cursor.take(
            slice_rows
        )

        f2_batch = f2_cursor.take(
            slice_rows
        )

        assert_lockstep_key_equality(
            b2_batch,
            f2_batch,
            key_columns=canonical_key_columns,
            partition=partition,
            global_row_offset=(
                emitted_rows
            ),
        )

        emitted_rows += slice_rows

        yield (
            b2_batch,
            f2_batch,
        )

    if (
        b2_cursor.rows_consumed
        != f2_cursor.rows_consumed
    ):
        raise ValueError(
            "LOCKSTEP_FINAL_ROW_COUNT_MISMATCH:"
            f"partition={partition};"
            f"b2={b2_cursor.rows_consumed};"
            f"f2={f2_cursor.rows_consumed}"
        )


class FamilyDayCursor:
    def __init__(
        self,
        files: list[Path],
        *,
        columns: tuple[str, ...],
        batch_rows: int,
        source_label: str,
    ) -> None:
        canonical_keys = (
            "data",
            "famiglia",
        )

        selected_columns = tuple(
            columns
        )

        missing_keys = [
            key
            for key in canonical_keys
            if key not in selected_columns
        ]

        if missing_keys:
            raise ValueError(
                "G2_CURSOR_KEY_COLUMNS_MISSING:"
                + ",".join(missing_keys)
            )

        if batch_rows <= 0:
            raise ValueError(
                "G2_CURSOR_BATCH_ROWS_MUST_BE_POSITIVE"
            )

        self.source_label = source_label
        self._iterator = iter(
            iter_parquet_record_batches(
                files,
                columns=selected_columns,
                batch_rows=batch_rows,
                source_label=source_label,
            )
        )
        self._batch: pa.RecordBatch | None = None
        self._offset = 0
        self._exhausted = False
        self._last_consumed_key: (
            tuple[object, object] | None
        ) = None
        self._last_matched_key: (
            tuple[object, object] | None
        ) = None
        self._last_matched_row: (
            pa.RecordBatch | None
        ) = None
        self.rows_consumed = 0
        self.rows_matched = 0
        self.g2_only_rows_skipped = 0

    def _ensure_current(self) -> None:
        while (
            not self._exhausted
            and (
                self._batch is None
                or self._offset
                >= self._batch.num_rows
            )
        ):
            try:
                self._batch = next(
                    self._iterator
                )
                self._offset = 0

            except StopIteration:
                self._batch = None
                self._offset = 0
                self._exhausted = True

        if (
            not self._exhausted
            and self._batch is not None
        ):
            for key_column in (
                "data",
                "famiglia",
            ):
                if (
                    self._batch.schema.get_field_index(
                        key_column
                    )
                    < 0
                ):
                    raise ValueError(
                        "G2_CURSOR_KEY_COLUMN_MISSING:"
                        f"{key_column}"
                    )

    def has_row(self) -> bool:
        self._ensure_current()

        return not self._exhausted

    def current_key(
        self,
    ) -> tuple[object, object]:
        self._ensure_current()

        if (
            self._exhausted
            or self._batch is None
        ):
            raise EOFError(
                "G2_CURSOR_EXHAUSTED:"
                f"{self.source_label}"
            )

        data_index = (
            self._batch.schema.get_field_index(
                "data"
            )
        )

        family_index = (
            self._batch.schema.get_field_index(
                "famiglia"
            )
        )

        return (
            self._batch.column(
                data_index
            )[self._offset].as_py(),
            self._batch.column(
                family_index
            )[self._offset].as_py(),
        )

    def current_row(
        self,
    ) -> pa.RecordBatch:
        self._ensure_current()

        if (
            self._exhausted
            or self._batch is None
        ):
            raise EOFError(
                "G2_CURSOR_EXHAUSTED:"
                f"{self.source_label}"
            )

        return self._batch.slice(
            self._offset,
            1,
        )

    def _consume_current(
        self,
        *,
        matched: bool,
    ) -> None:
        key = self.current_key()

        if (
            self._last_consumed_key is not None
            and not (
                self._last_consumed_key
                < key
            )
        ):
            raise ValueError(
                "G2_KEY_NOT_STRICTLY_INCREASING:"
                f"source={self.source_label};"
                f"previous={self._last_consumed_key};"
                f"current={key}"
            )

        self._last_consumed_key = key
        self._offset += 1
        self.rows_consumed += 1

        if matched:
            self.rows_matched += 1
        else:
            self.g2_only_rows_skipped += 1

        self._ensure_current()

    def row_for_prefix(
        self,
        target_prefix: tuple[object, object],
    ) -> pa.RecordBatch:
        if len(target_prefix) != 2:
            raise ValueError(
                "PAIR_PREFIX_MUST_HAVE_TWO_COLUMNS"
            )

        if self._last_matched_key is not None:
            if target_prefix == self._last_matched_key:
                if self._last_matched_row is None:
                    raise RuntimeError(
                        "G2_MATCH_CACHE_MISSING"
                    )

                return self._last_matched_row

            if target_prefix < self._last_matched_key:
                raise ValueError(
                    "PAIR_PREFIX_REGRESSION:"
                    f"previous={self._last_matched_key};"
                    f"current={target_prefix}"
                )

        while self.has_row():
            current_key = self.current_key()

            if current_key < target_prefix:
                self._consume_current(
                    matched=False
                )
                continue

            if current_key > target_prefix:
                raise ValueError(
                    "G2_PREFIX_MATCH_MISSING:"
                    f"target={target_prefix};"
                    f"next_g2={current_key}"
                )

            matched_row = self.current_row()

            self._last_matched_key = (
                target_prefix
            )

            self._last_matched_row = (
                matched_row
            )

            self._consume_current(
                matched=True
            )

            return matched_row

        raise ValueError(
            "G2_PREFIX_MATCH_MISSING_AT_EOF:"
            f"target={target_prefix}"
        )

    def drain(self) -> None:
        while self.has_row():
            self._consume_current(
                matched=False
            )


def broadcast_g2_rows_for_pair_batch(
    pair_batch: pa.RecordBatch,
    g2_cursor: FamilyDayCursor,
    *,
    partition: str,
) -> pa.RecordBatch:
    if pair_batch.num_rows <= 0:
        raise ValueError(
            "PAIR_BATCH_MUST_NOT_BE_EMPTY"
        )

    pair_indexes: dict[str, int] = {}

    for key_column in (
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
    ):
        index = (
            pair_batch.schema.get_field_index(
                key_column
            )
        )

        if index < 0:
            raise ValueError(
                "PAIR_BATCH_KEY_COLUMN_MISSING:"
                f"{key_column}"
            )

        pair_indexes[key_column] = index

    data_values = pair_batch.column(
        pair_indexes["data"]
    ).to_pylist()

    family_values = pair_batch.column(
        pair_indexes["famiglia"]
    ).to_pylist()

    priceband_values = pair_batch.column(
        pair_indexes[
            "fascia_prezzo_iva_inc"
        ]
    ).to_pylist()

    matched_rows: list[
        pa.RecordBatch
    ] = []

    take_indices: list[int] = []

    previous_full_key: (
        tuple[object, object, object] | None
    ) = None

    previous_prefix: (
        tuple[object, object] | None
    ) = None

    unique_index = -1

    for (
        data_value,
        family_value,
        priceband_value,
    ) in zip(
        data_values,
        family_values,
        priceband_values,
    ):
        if (
            data_value is None
            or family_value is None
            or priceband_value is None
        ):
            raise ValueError(
                "PAIR_BATCH_NULL_KEY_FORBIDDEN:"
                f"partition={partition}"
            )

        full_key = (
            data_value,
            family_value,
            priceband_value,
        )

        if (
            previous_full_key is not None
            and not (
                previous_full_key
                < full_key
            )
        ):
            raise ValueError(
                "PAIR_KEY_NOT_STRICTLY_INCREASING:"
                f"partition={partition};"
                f"previous={previous_full_key};"
                f"current={full_key}"
            )

        prefix = (
            data_value,
            family_value,
        )

        if (
            previous_prefix is None
            or prefix != previous_prefix
        ):
            matched_rows.append(
                g2_cursor.row_for_prefix(
                    prefix
                )
            )

            unique_index += 1
            previous_prefix = prefix

        take_indices.append(
            unique_index
        )

        previous_full_key = full_key

    if not matched_rows:
        raise RuntimeError(
            "G2_MATCHED_ROW_SET_EMPTY"
        )

    unique_table = pa.Table.from_batches(
        matched_rows
    )

    broadcast_table = unique_table.take(
        pa.array(
            take_indices,
            type=pa.int32(),
        )
    ).combine_chunks()

    output_batches = (
        broadcast_table.to_batches(
            max_chunksize=(
                pair_batch.num_rows
            )
        )
    )

    if len(output_batches) != 1:
        raise RuntimeError(
            "G2_BROADCAST_BATCH_COUNT_INVALID:"
            f"count={len(output_batches)}"
        )

    output = output_batches[0]

    if output.num_rows != pair_batch.num_rows:
        raise RuntimeError(
            "G2_BROADCAST_ROW_COUNT_MISMATCH:"
            f"partition={partition};"
            f"pair_rows={pair_batch.num_rows};"
            f"g2_rows={output.num_rows}"
        )

    return output

class C2PairLookup:
    def __init__(
        self,
        table: pa.Table,
        *,
        source_label: str,
    ) -> None:
        if table.num_rows <= 0:
            raise ValueError(
                "C2_LOOKUP_TABLE_EMPTY:"
                f"{source_label}"
            )

        combined = table.combine_chunks()

        key_columns = (
            "famiglia",
            "fascia_prezzo_iva_inc",
        )

        key_indexes: dict[str, int] = {}

        for key_column in key_columns:
            index = (
                combined.schema.get_field_index(
                    key_column
                )
            )

            if index < 0:
                raise ValueError(
                    "C2_LOOKUP_KEY_COLUMN_MISSING:"
                    f"{key_column}"
                )

            key_indexes[key_column] = index

        family_values = combined.column(
            key_indexes["famiglia"]
        ).to_pylist()

        priceband_values = combined.column(
            key_indexes[
                "fascia_prezzo_iva_inc"
            ]
        ).to_pylist()

        row_index_by_key: dict[
            tuple[object, object],
            int,
        ] = {}

        for row_index, (
            family_value,
            priceband_value,
        ) in enumerate(
            zip(
                family_values,
                priceband_values,
            )
        ):
            if (
                family_value is None
                or priceband_value is None
            ):
                raise ValueError(
                    "C2_LOOKUP_NULL_KEY_FORBIDDEN:"
                    f"row={row_index}"
                )

            key = (
                family_value,
                priceband_value,
            )

            if key in row_index_by_key:
                raise ValueError(
                    "C2_LOOKUP_DUPLICATE_KEY:"
                    f"key={key};"
                    f"first_row={row_index_by_key[key]};"
                    f"duplicate_row={row_index}"
                )

            row_index_by_key[key] = row_index

        self.source_label = source_label
        self._table = combined
        self._row_index_by_key = (
            row_index_by_key
        )
        self.rows_broadcast = 0
        self.lookup_requests = 0

    @property
    def row_count(self) -> int:
        return self._table.num_rows

    @property
    def column_count(self) -> int:
        return self._table.num_columns

    @property
    def schema(self) -> pa.Schema:
        return self._table.schema

    def broadcast_for_pair_batch(
        self,
        pair_batch: pa.RecordBatch,
        *,
        partition: str,
    ) -> pa.RecordBatch:
        if pair_batch.num_rows <= 0:
            raise ValueError(
                "C2_PAIR_BATCH_MUST_NOT_BE_EMPTY"
            )

        indexes: dict[str, int] = {}

        for key_column in (
            "data",
            "famiglia",
            "fascia_prezzo_iva_inc",
        ):
            index = (
                pair_batch.schema.get_field_index(
                    key_column
                )
            )

            if index < 0:
                raise ValueError(
                    "C2_PAIR_BATCH_KEY_COLUMN_MISSING:"
                    f"{key_column}"
                )

            indexes[key_column] = index

        data_values = pair_batch.column(
            indexes["data"]
        ).to_pylist()

        family_values = pair_batch.column(
            indexes["famiglia"]
        ).to_pylist()

        priceband_values = pair_batch.column(
            indexes[
                "fascia_prezzo_iva_inc"
            ]
        ).to_pylist()

        take_indices: list[int] = []

        previous_full_key: (
            tuple[object, object, object] | None
        ) = None

        for (
            data_value,
            family_value,
            priceband_value,
        ) in zip(
            data_values,
            family_values,
            priceband_values,
        ):
            if (
                data_value is None
                or family_value is None
                or priceband_value is None
            ):
                raise ValueError(
                    "C2_PAIR_BATCH_NULL_KEY_FORBIDDEN:"
                    f"partition={partition}"
                )

            full_key = (
                data_value,
                family_value,
                priceband_value,
            )

            if (
                previous_full_key is not None
                and not previous_full_key < full_key
            ):
                raise ValueError(
                    "C2_PAIR_KEY_NOT_STRICTLY_INCREASING:"
                    f"partition={partition};"
                    f"previous={previous_full_key};"
                    f"current={full_key}"
                )

            pair_key = (
                family_value,
                priceband_value,
            )

            row_index = (
                self._row_index_by_key.get(
                    pair_key
                )
            )

            if row_index is None:
                raise ValueError(
                    "C2_PAIR_MATCH_MISSING:"
                    f"partition={partition};"
                    f"key={pair_key}"
                )

            take_indices.append(
                row_index
            )

            previous_full_key = full_key

        selected = self._table.take(
            pa.array(
                take_indices,
                type=pa.int32(),
            )
        ).combine_chunks()

        batches = selected.to_batches(
            max_chunksize=pair_batch.num_rows
        )

        if len(batches) != 1:
            raise RuntimeError(
                "C2_BROADCAST_BATCH_COUNT_INVALID:"
                f"count={len(batches)}"
            )

        output = batches[0]

        if output.num_rows != pair_batch.num_rows:
            raise RuntimeError(
                "C2_BROADCAST_ROW_COUNT_MISMATCH:"
                f"partition={partition};"
                f"pair_rows={pair_batch.num_rows};"
                f"c2_rows={output.num_rows}"
            )

        self.lookup_requests += 1
        self.rows_broadcast += output.num_rows

        return output


def load_c2_pair_lookup(
    files: list[Path],
    *,
    columns: tuple[str, ...],
    batch_rows: int,
    source_label: str,
) -> C2PairLookup:
    selected_columns = tuple(
        columns
    )

    missing_keys = [
        key
        for key in (
            "famiglia",
            "fascia_prezzo_iva_inc",
        )
        if key not in selected_columns
    ]

    if missing_keys:
        raise ValueError(
            "C2_LOOKUP_PROJECTION_KEYS_MISSING:"
            + ",".join(missing_keys)
        )

    batches = list(
        iter_parquet_record_batches(
            files,
            columns=selected_columns,
            batch_rows=batch_rows,
            source_label=source_label,
        )
    )

    if not batches:
        raise ValueError(
            "C2_LOOKUP_SOURCE_EMPTY:"
            f"{source_label}"
        )

    table = pa.Table.from_batches(
        batches
    ).combine_chunks()

    return C2PairLookup(
        table,
        source_label=source_label,
    )


def broadcast_c2_rows_for_pair_batch(
    pair_batch: pa.RecordBatch,
    c2_lookup: C2PairLookup,
    *,
    partition: str,
) -> pa.RecordBatch:
    return c2_lookup.broadcast_for_pair_batch(
        pair_batch,
        partition=partition,
    )


def validate_canonical_projection_plan(
    projection_plan: list[dict[str, object]],
    *,
    expected_output_columns: int,
) -> list[dict[str, object]]:
    if not isinstance(
        projection_plan,
        list,
    ):
        raise ValueError(
            "CANONICAL_PROJECTION_PLAN_LIST_REQUIRED"
        )

    if (
        len(projection_plan)
        != expected_output_columns
    ):
        raise ValueError(
            "CANONICAL_PROJECTION_PLAN_COUNT_MISMATCH:"
            f"expected={expected_output_columns};"
            f"actual={len(projection_plan)}"
        )

    validated: list[
        dict[str, object]
    ] = []

    output_names: list[str] = []

    for expected_ordinal, raw in enumerate(
        projection_plan
    ):
        if not isinstance(raw, dict):
            raise ValueError(
                "CANONICAL_PROJECTION_RECORD_OBJECT_REQUIRED"
            )

        ordinal = int(
            raw.get("ordinal", -1)
        )

        output_column = str(
            raw.get(
                "output_column",
                "",
            )
        ).strip()

        source_role = str(
            raw.get(
                "source_role",
                "",
            )
        ).strip().upper()

        source_column = str(
            raw.get(
                "source_column",
                "",
            )
        ).strip()

        if ordinal != expected_ordinal:
            raise ValueError(
                "CANONICAL_PROJECTION_ORDINAL_INVALID:"
                f"expected={expected_ordinal};"
                f"actual={ordinal}"
            )

        if not output_column:
            raise ValueError(
                "CANONICAL_PROJECTION_OUTPUT_COLUMN_EMPTY:"
                f"ordinal={ordinal}"
            )

        if source_role not in {
            "B2",
            "F2",
            "C2",
            "G2",
        }:
            raise ValueError(
                "CANONICAL_PROJECTION_SOURCE_ROLE_INVALID:"
                f"ordinal={ordinal};"
                f"role={source_role}"
            )

        if not source_column:
            raise ValueError(
                "CANONICAL_PROJECTION_SOURCE_COLUMN_EMPTY:"
                f"ordinal={ordinal}"
            )

        output_names.append(
            output_column
        )

        validated.append(
            {
                "ordinal": ordinal,
                "output_column": output_column,
                "source_role": source_role,
                "source_column": source_column,
            }
        )

    if len(output_names) != len(
        set(output_names)
    ):
        raise ValueError(
            "CANONICAL_PROJECTION_OUTPUT_NAMES_NOT_UNIQUE"
        )

    return validated


def assert_output_source_key_coherence(
    source_batches: dict[str, pa.RecordBatch],
    *,
    partition: str,
) -> None:
    required_roles = {
        "B2",
        "F2",
        "C2",
        "G2",
    }

    if set(source_batches) != required_roles:
        raise ValueError(
            "OUTPUT_SOURCE_ROLE_SET_INVALID:"
            f"expected={sorted(required_roles)};"
            f"actual={sorted(source_batches)}"
        )

    row_counts = {
        role: batch.num_rows
        for role, batch in source_batches.items()
    }

    if len(set(row_counts.values())) != 1:
        raise ValueError(
            "OUTPUT_SOURCE_ROW_COUNT_MISMATCH:"
            f"partition={partition};"
            f"counts={row_counts}"
        )

    row_count = next(
        iter(row_counts.values())
    )

    if row_count <= 0:
        raise ValueError(
            "OUTPUT_SOURCE_BATCH_EMPTY:"
            f"partition={partition}"
        )

    comparisons = (
        (
            "B2",
            "F2",
            (
                "data",
                "famiglia",
                "fascia_prezzo_iva_inc",
            ),
        ),
        (
            "B2",
            "G2",
            (
                "data",
                "famiglia",
            ),
        ),
        (
            "B2",
            "C2",
            (
                "famiglia",
                "fascia_prezzo_iva_inc",
            ),
        ),
    )

    for left_role, right_role, columns in comparisons:
        left_batch = source_batches[
            left_role
        ]

        right_batch = source_batches[
            right_role
        ]

        for column in columns:
            left_index = (
                left_batch.schema.get_field_index(
                    column
                )
            )

            right_index = (
                right_batch.schema.get_field_index(
                    column
                )
            )

            if (
                left_index < 0
                or right_index < 0
            ):
                raise ValueError(
                    "OUTPUT_SOURCE_KEY_COLUMN_MISSING:"
                    f"partition={partition};"
                    f"column={column};"
                    f"left={left_role};"
                    f"right={right_role}"
                )

            if not left_batch.column(
                left_index
            ).equals(
                right_batch.column(
                    right_index
                )
            ):
                raise ValueError(
                    "OUTPUT_SOURCE_KEY_COHERENCE_MISMATCH:"
                    f"partition={partition};"
                    f"column={column};"
                    f"left={left_role};"
                    f"right={right_role}"
                )


def assemble_canonical_output_batch(
    source_batches: dict[str, pa.RecordBatch],
    projection_plan: list[dict[str, object]],
    *,
    partition: str,
    expected_output_columns: int,
) -> pa.RecordBatch:
    validated_plan = (
        validate_canonical_projection_plan(
            projection_plan,
            expected_output_columns=(
                expected_output_columns
            ),
        )
    )

    assert_output_source_key_coherence(
        source_batches,
        partition=partition,
    )

    arrays: list[pa.Array] = []
    fields: list[pa.Field] = []

    for record in validated_plan:
        role = str(
            record["source_role"]
        )

        source_column = str(
            record["source_column"]
        )

        output_column = str(
            record["output_column"]
        )

        batch = source_batches[
            role
        ]

        index = (
            batch.schema.get_field_index(
                source_column
            )
        )

        if index < 0:
            raise ValueError(
                "OUTPUT_SOURCE_COLUMN_MISSING:"
                f"partition={partition};"
                f"role={role};"
                f"source_column={source_column};"
                f"output_column={output_column}"
            )

        array = batch.column(
            index
        )

        arrays.append(
            array
        )

        fields.append(
            pa.field(
                output_column,
                array.type,
                nullable=True,
            )
        )

    output = pa.RecordBatch.from_arrays(
        arrays,
        schema=pa.schema(fields),
    )

    expected_names = [
        str(record["output_column"])
        for record in validated_plan
    ]

    if output.schema.names != expected_names:
        raise RuntimeError(
            "OUTPUT_CANONICAL_COLUMN_ORDER_MISMATCH"
        )

    if (
        output.num_columns
        != expected_output_columns
    ):
        raise RuntimeError(
            "OUTPUT_CANONICAL_COLUMN_COUNT_MISMATCH:"
            f"expected={expected_output_columns};"
            f"actual={output.num_columns}"
        )

    return output

_H2P_RUN_ID_RE = _h2p_re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
)


def _h2p_canonical_json_bytes(
    value,
):
    return _h2p_json.dumps(
        value,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _h2p_schema_fingerprint(
    schema,
):
    payload = [
        {
            "ordinal": ordinal,
            "name": field.name,
            "type": str(field.type),
            "nullable": bool(field.nullable),
        }
        for ordinal, field in enumerate(
            schema
        )
    ]

    return _h2p_hashlib.sha256(
        _h2p_canonical_json_bytes(
            payload
        )
    ).hexdigest()


def _h2p_assert_absolute_no_symlink_chain(
    path,
    *,
    label,
    require_exists,
):
    candidate = _H2PPath(
        path
    )

    if not candidate.is_absolute():
        raise ValueError(
            "PIPELINE_PATH_MUST_BE_ABSOLUTE:"
            f"label={label};path={candidate}"
        )

    current = _H2PPath(
        candidate.anchor
    )

    for part in candidate.parts[1:]:
        current = current / part

        if current.is_symlink():
            raise ValueError(
                "PIPELINE_PATH_COMPONENT_SYMLINK:"
                f"label={label};path={current}"
            )

        if not current.exists():
            break

    if (
        require_exists
        and not candidate.exists()
    ):
        raise ValueError(
            "PIPELINE_PATH_MISSING:"
            f"label={label};path={candidate}"
        )

    return candidate


def _h2p_write_json_atomic(
    path,
    value,
):
    target = _H2PPath(
        path
    )

    temporary = target.with_name(
        "." + target.name + ".tmp"
    )

    if temporary.exists():
        temporary.unlink()

    temporary.write_text(
        _h2p_json.dumps(
            value,
            indent=2,
            ensure_ascii=True,
            allow_nan=False,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    _h2p_os.replace(
        temporary,
        target,
    )


def _h2p_projection_columns(
    projection_plan,
):
    role_columns = {
        role: []
        for role in (
            "B2",
            "F2",
            "C2",
            "G2",
        )
    }

    for expected_ordinal, record in enumerate(
        projection_plan
    ):
        if not isinstance(
            record,
            dict,
        ):
            raise ValueError(
                "PIPELINE_PROJECTION_RECORD_INVALID:"
                f"ordinal={expected_ordinal}"
            )

        if int(
            record.get(
                "ordinal",
                -1,
            )
        ) != expected_ordinal:
            raise ValueError(
                "PIPELINE_PROJECTION_ORDINAL_INVALID:"
                f"expected={expected_ordinal};"
                f"actual={record.get('ordinal')}"
            )

        role = str(
            record.get(
                "source_role",
                "",
            )
        ).strip().upper()

        source_column = str(
            record.get(
                "source_column",
                "",
            )
        ).strip()

        if role not in role_columns:
            raise ValueError(
                "PIPELINE_PROJECTION_ROLE_INVALID:"
                f"ordinal={expected_ordinal};"
                f"role={role}"
            )

        if not source_column:
            raise ValueError(
                "PIPELINE_PROJECTION_SOURCE_COLUMN_EMPTY:"
                f"ordinal={expected_ordinal}"
            )

        if (
            source_column
            not in role_columns[role]
        ):
            role_columns[role].append(
                source_column
            )

    return role_columns


_H2P_APPROVED_VALIDATOR_SHA256 = (
    "7b401aa3a578513fb848a6bd60d236c0"
    "de31f0dd25693e19d1383cec5bec5bf0"
)

_H2P_ACTIVE_CANDIDATES = {}

_H2P_ACTIVE_CANDIDATES_LOCK = (
    _h2p_trust_threading.RLock()
)


def _h2p_sha256_file(path):
    source = _H2PPath(path)

    _h2p_assert_absolute_no_symlink_chain(
        source,
        label="sha256_source",
        require_exists=True,
    )

    if (
        source.is_symlink()
        or not source.is_file()
    ):
        raise ValueError(
            "PIPELINE_HASH_SOURCE_INVALID:"
            f"{source}"
        )

    digest = (
        _h2p_trust_hashlib.sha256()
    )

    with source.open("rb") as handle:
        for chunk in iter(
            lambda: handle.read(
                1024 * 1024
            ),
            b"",
        ):
            digest.update(chunk)

    return digest.hexdigest()


def _h2p_validate_validator_callback_provenance(
    validator_callback,
):
    if not callable(
        validator_callback
    ):
        raise ValueError(
            "PIPELINE_VALIDATOR_CALLBACK_REQUIRED"
        )

    callback_name = getattr(
        validator_callback,
        "__name__",
        "",
    )

    if (
        callback_name
        != "validate_candidate_dataset_streaming"
    ):
        raise ValueError(
            "PIPELINE_VALIDATOR_CALLBACK_NAME_INVALID:"
            f"{callback_name!r}"
        )

    callback_code = getattr(
        validator_callback,
        "__code__",
        None,
    )

    if callback_code is None:
        raise ValueError(
            "PIPELINE_VALIDATOR_CALLBACK_CODE_REQUIRED"
        )

    callback_source = _H2PPath(
        callback_code.co_filename
    )

    callback_source = (
        _h2p_assert_absolute_no_symlink_chain(
            callback_source,
            label="validator_callback_source",
            require_exists=True,
        )
    )

    if (
        callback_source.is_symlink()
        or not callback_source.is_file()
    ):
        raise ValueError(
            "PIPELINE_VALIDATOR_CALLBACK_SOURCE_INVALID:"
            f"{callback_source}"
        )

    callback_source_sha256 = (
        _h2p_sha256_file(
            callback_source
        )
    )

    if (
        callback_source_sha256
        != _H2P_APPROVED_VALIDATOR_SHA256
    ):
        raise ValueError(
            "PIPELINE_VALIDATOR_CALLBACK_SOURCE_"
            "SHA256_MISMATCH:"
            f"expected={_H2P_APPROVED_VALIDATOR_SHA256};"
            f"actual={callback_source_sha256};"
            f"path={callback_source}"
        )

    return {
        "ok": True,
        "function_name": callback_name,
        "source_path": str(
            callback_source
        ),
        "source_sha256": (
            callback_source_sha256
        ),
    }


def _h2p_candidate_parquet_inventory(
    candidate_root,
    *,
    expected_file_count,
):
    root = (
        _h2p_assert_absolute_no_symlink_chain(
            candidate_root,
            label="candidate_inventory_root",
            require_exists=True,
        )
    )

    if (
        root.is_symlink()
        or not root.is_dir()
    ):
        raise ValueError(
            "PIPELINE_CANDIDATE_INVENTORY_ROOT_INVALID:"
            f"{root}"
        )

    records = []

    for path in sorted(
        root.rglob("*"),
        key=lambda item: str(
            item.relative_to(root)
        ),
    ):
        if path.is_symlink():
            raise ValueError(
                "PIPELINE_CANDIDATE_INVENTORY_SYMLINK:"
                f"{path}"
            )

        if path.is_dir():
            continue

        relative = path.relative_to(
            root
        )

        if (
            len(relative.parts) == 1
            and relative.name in {
                "dataset_manifest.json",
                "_VALIDATION.json",
                "_SUCCESS",
            }
        ):
            continue

        if (
            not path.is_file()
            or path.suffix != ".parquet"
            or len(relative.parts) != 3
            or not relative.parts[0].startswith(
                "year="
            )
            or not relative.parts[1].startswith(
                "month="
            )
        ):
            raise ValueError(
                "PIPELINE_CANDIDATE_INVENTORY_"
                "UNEXPECTED_ARTIFACT:"
                f"{relative}"
            )

        stat = path.stat()

        records.append(
            {
                "relative_path": str(
                    relative
                ),
                "size_bytes": stat.st_size,
                "mtime_ns": stat.st_mtime_ns,
                "inode": stat.st_ino,
                "device": stat.st_dev,
            }
        )

    if (
        len(records)
        != int(expected_file_count)
        or not records
    ):
        raise ValueError(
            "PIPELINE_CANDIDATE_PARQUET_FILE_"
            "COUNT_MISMATCH:"
            f"expected={expected_file_count};"
            f"actual={len(records)}"
        )

    fingerprint = (
        _h2p_trust_hashlib.sha256(
            _h2p_canonical_json_bytes(
                records
            )
        ).hexdigest()
    )

    return {
        "file_count": len(records),
        "fingerprint": fingerprint,
        "records": records,
    }


def _h2p_register_candidate_for_promotion(
    *,
    candidate_root,
    final_root,
    build_report,
    validation_report,
):
    candidate_root = _H2PPath(
        candidate_root
    )

    final_root = _H2PPath(
        final_root
    )

    inventory = (
        _h2p_candidate_parquet_inventory(
            candidate_root,
            expected_file_count=int(
                build_report.get(
                    "file_count",
                    -1,
                )
            ),
        )
    )

    token = (
        _h2p_trust_os.urandom(
            32
        ).hex()
    )

    record = {
        "token": token,
        "candidate_root": str(
            candidate_root
        ),
        "final_root": str(
            final_root
        ),
        "build_report_sha256": (
            _h2p_trust_hashlib.sha256(
                _h2p_canonical_json_bytes(
                    build_report
                )
            ).hexdigest()
        ),
        "validation_report_sha256": (
            _h2p_trust_hashlib.sha256(
                _h2p_canonical_json_bytes(
                    validation_report
                )
            ).hexdigest()
        ),
        "parquet_inventory_fingerprint": (
            inventory["fingerprint"]
        ),
        "parquet_file_count": (
            inventory["file_count"]
        ),
    }

    with _H2P_ACTIVE_CANDIDATES_LOCK:
        key = str(candidate_root)

        if key in _H2P_ACTIVE_CANDIDATES:
            raise ValueError(
                "PIPELINE_CANDIDATE_ALREADY_REGISTERED:"
                f"{candidate_root}"
            )

        _H2P_ACTIVE_CANDIDATES[
            key
        ] = record

    return token

def _h2p_load_json_object(
    path,
    *,
    label,
):
    source = _H2PPath(path)

    _h2p_assert_absolute_no_symlink_chain(
        source,
        label=label,
        require_exists=True,
    )

    if (
        source.is_symlink()
        or not source.is_file()
    ):
        raise ValueError(
            "PIPELINE_ATTESTATION_FILE_INVALID:"
            f"label={label};path={source}"
        )

    try:
        value = _h2p_json.loads(
            source.read_text(
                encoding="utf-8",
                errors="strict",
            )
        )

    except Exception as exc:
        raise ValueError(
            "PIPELINE_ATTESTATION_JSON_INVALID:"
            f"label={label};path={source}"
        ) from exc

    if not isinstance(value, dict):
        raise ValueError(
            "PIPELINE_ATTESTATION_OBJECT_REQUIRED:"
            f"label={label};path={source}"
        )

    return value


def _h2p_validate_build_validation_attestation(
    build_report,
    validation_report,
    *,
    expected_partition_rows=None,
    expected_run_id=None,
    expected_candidate_root=None,
    expected_final_root=None,
):
    if (
        not isinstance(build_report, dict)
        or build_report.get("ok") is not True
    ):
        raise ValueError(
            "PIPELINE_BUILD_ATTESTATION_NOT_OK"
        )

    if (
        not isinstance(validation_report, dict)
        or validation_report.get("ok") is not True
    ):
        raise ValueError(
            "PIPELINE_VALIDATOR_DID_NOT_RETURN_OK"
        )

    build_partition_count = int(
        build_report.get(
            "partition_count",
            -1,
        )
    )

    validation_partition_count = int(
        validation_report.get(
            "partition_count",
            -1,
        )
    )

    if (
        build_partition_count <= 0
        or validation_partition_count
        != build_partition_count
    ):
        raise ValueError(
            "PIPELINE_VALIDATION_PARTITION_COUNT_MISMATCH"
        )

    if int(
        build_report.get(
            "partition_pass_count",
            -1,
        )
    ) != build_partition_count:
        raise ValueError(
            "PIPELINE_BUILD_PARTITION_PASS_COUNT_INVALID"
        )

    if int(
        validation_report.get(
            "partition_pass_count",
            -1,
        )
    ) != build_partition_count:
        raise ValueError(
            "PIPELINE_VALIDATION_PARTITION_PASS_COUNT_INVALID"
        )

    build_total_rows = int(
        build_report.get(
            "total_rows",
            -1,
        )
    )

    validation_total_rows = int(
        validation_report.get(
            "total_rows",
            -1,
        )
    )

    if (
        build_total_rows <= 0
        or validation_total_rows
        != build_total_rows
    ):
        raise ValueError(
            "PIPELINE_BUILD_VALIDATION_ROW_COUNT_MISMATCH"
        )

    build_column_count = int(
        build_report.get(
            "column_count",
            -1,
        )
    )

    validation_column_count = int(
        validation_report.get(
            "column_count",
            -1,
        )
    )

    if (
        build_column_count <= 0
        or validation_column_count
        != build_column_count
    ):
        raise ValueError(
            "PIPELINE_BUILD_VALIDATION_COLUMN_COUNT_MISMATCH"
        )

    build_schema_fingerprint = str(
        build_report.get(
            "schema_fingerprint",
            "",
        )
    )

    validation_schema_fingerprint = str(
        validation_report.get(
            "schema_fingerprint",
            "",
        )
    )

    if (
        not _h2p_re.fullmatch(
            r"[0-9a-f]{64}",
            build_schema_fingerprint,
        )
        or validation_schema_fingerprint
        != build_schema_fingerprint
    ):
        raise ValueError(
            "PIPELINE_BUILD_VALIDATION_SCHEMA_"
            "FINGERPRINT_MISMATCH"
        )

    if validation_report.get(
        "strict_global_key_order"
    ) is not True:
        raise ValueError(
            "PIPELINE_VALIDATION_GLOBAL_KEY_ORDER_INVALID"
        )

    if int(
        validation_report.get(
            "batch_count",
            -1,
        )
    ) <= 0:
        raise ValueError(
            "PIPELINE_VALIDATION_BATCH_COUNT_INVALID"
        )

    build_partitions = build_report.get(
        "partitions"
    )

    validation_partitions = (
        validation_report.get(
            "partitions"
        )
    )

    if (
        not isinstance(build_partitions, list)
        or len(build_partitions)
        != build_partition_count
    ):
        raise ValueError(
            "PIPELINE_BUILD_PARTITION_ATTESTATION_INVALID"
        )

    if (
        not isinstance(
            validation_partitions,
            list,
        )
        or len(validation_partitions)
        != build_partition_count
    ):
        raise ValueError(
            "PIPELINE_VALIDATION_PARTITION_ATTESTATION_INVALID"
        )

    def normalize(records, *, label):
        normalized = {}

        for record in records:
            if not isinstance(record, dict):
                raise ValueError(
                    "PIPELINE_PARTITION_ATTESTATION_"
                    f"RECORD_INVALID:label={label}"
                )

            partition = str(
                record.get(
                    "partition",
                    "",
                )
            )

            actual_rows = int(
                record.get(
                    "actual_rows",
                    -1,
                )
            )

            if (
                not partition
                or partition in normalized
                or actual_rows <= 0
                or record.get("result")
                != "PASS"
            ):
                raise ValueError(
                    "PIPELINE_PARTITION_ATTESTATION_INVALID:"
                    f"label={label};partition={partition}"
                )

            normalized[
                partition
            ] = actual_rows

        return normalized

    normalized_build = normalize(
        build_partitions,
        label="build",
    )

    normalized_validation = normalize(
        validation_partitions,
        label="validation",
    )

    if (
        normalized_build
        != normalized_validation
    ):
        raise ValueError(
            "PIPELINE_BUILD_VALIDATION_PARTITION_ROWS_MISMATCH"
        )

    if expected_partition_rows is not None:
        normalized_expected = {
            str(partition): int(
                row_count
            )
            for partition, row_count
            in expected_partition_rows.items()
        }

        if (
            normalized_build
            != normalized_expected
        ):
            raise ValueError(
                "PIPELINE_EXPECTED_PARTITION_"
                "ATTESTATION_MISMATCH"
            )

    if (
        expected_run_id is not None
        and str(
            build_report.get(
                "run_id",
                "",
            )
        )
        != str(expected_run_id)
    ):
        raise ValueError(
            "PIPELINE_BUILD_RUN_ID_ATTESTATION_MISMATCH"
        )

    if (
        expected_candidate_root is not None
        and str(
            build_report.get(
                "candidate_root",
                "",
            )
        )
        != str(
            _H2PPath(
                expected_candidate_root
            )
        )
    ):
        raise ValueError(
            "PIPELINE_BUILD_CANDIDATE_ROOT_"
            "ATTESTATION_MISMATCH"
        )

    if (
        expected_final_root is not None
        and str(
            build_report.get(
                "final_root",
                "",
            )
        )
        != str(
            _H2PPath(
                expected_final_root
            )
        )
    ):
        raise ValueError(
            "PIPELINE_BUILD_FINAL_ROOT_"
            "ATTESTATION_MISMATCH"
        )

    return {
        "ok": True,
        "partition_count": (
            build_partition_count
        ),
        "total_rows": build_total_rows,
        "column_count": (
            build_column_count
        ),
        "schema_fingerprint": (
            build_schema_fingerprint
        ),
        "partitions": normalized_build,
    }

def build_candidate_dataset_streaming(
    *,
    b2_root,
    f2_root,
    c2_root,
    g2_root,
    output_root,
    run_id,
    projection_plan,
    expected_partition_rows,
    batch_rows=1024,
    compression="snappy",
):
    if not _H2P_RUN_ID_RE.fullmatch(
        str(run_id)
    ):
        raise ValueError(
            "PIPELINE_RUN_ID_INVALID:"
            f"{run_id!r}"
        )

    if int(batch_rows) <= 0:
        raise ValueError(
            "PIPELINE_BATCH_ROWS_INVALID:"
            f"{batch_rows}"
        )

    b2_root = (
        _h2p_assert_absolute_no_symlink_chain(
            b2_root,
            label="b2_root",
            require_exists=True,
        )
    )

    f2_root = (
        _h2p_assert_absolute_no_symlink_chain(
            f2_root,
            label="f2_root",
            require_exists=True,
        )
    )

    c2_root = (
        _h2p_assert_absolute_no_symlink_chain(
            c2_root,
            label="c2_root",
            require_exists=True,
        )
    )

    g2_root = (
        _h2p_assert_absolute_no_symlink_chain(
            g2_root,
            label="g2_root",
            require_exists=True,
        )
    )

    output_root = (
        _h2p_assert_absolute_no_symlink_chain(
            output_root,
            label="output_root",
            require_exists=True,
        )
    )

    if not output_root.is_dir():
        raise ValueError(
            "PIPELINE_OUTPUT_ROOT_NOT_DIRECTORY:"
            f"{output_root}"
        )

    candidate_root = (
        output_root
        / f".{run_id}.candidate"
    )

    final_root = (
        output_root
        / str(run_id)
    )

    if candidate_root.exists():
        raise FileExistsError(
            "PIPELINE_CANDIDATE_ALREADY_EXISTS:"
            f"{candidate_root}"
        )

    if final_root.exists():
        raise FileExistsError(
            "PIPELINE_FINAL_ALREADY_EXISTS:"
            f"{final_root}"
        )

    if not isinstance(
        expected_partition_rows,
        dict,
    ):
        raise ValueError(
            "PIPELINE_EXPECTED_PARTITION_ROWS_MAP_REQUIRED"
        )

    normalized_expected_rows = {
        str(partition): int(row_count)
        for partition, row_count
        in expected_partition_rows.items()
    }

    if not normalized_expected_rows:
        raise ValueError(
            "PIPELINE_EXPECTED_PARTITIONS_EMPTY"
        )

    if any(
        row_count <= 0
        for row_count
        in normalized_expected_rows.values()
    ):
        raise ValueError(
            "PIPELINE_EXPECTED_PARTITION_ROWS_INVALID"
        )

    role_columns = (
        _h2p_projection_columns(
            projection_plan
        )
    )

    pair_key_columns = (
        "data",
        "famiglia",
        "fascia_prezzo_iva_inc",
    )

    c2_key_columns = (
        "famiglia",
        "fascia_prezzo_iva_inc",
    )

    g2_key_columns = (
        "data",
        "famiglia",
    )

    b2_columns = tuple(
        dict.fromkeys(
            [
                *pair_key_columns,
                *role_columns["B2"],
            ]
        )
    )

    f2_columns = tuple(
        dict.fromkeys(
            [
                *pair_key_columns,
                *role_columns["F2"],
            ]
        )
    )

    c2_columns = tuple(
        dict.fromkeys(
            [
                *c2_key_columns,
                *role_columns["C2"],
            ]
        )
    )

    g2_columns = tuple(
        dict.fromkeys(
            [
                *g2_key_columns,
                *role_columns["G2"],
            ]
        )
    )

    c2_files = (
        list_partition_parquet_files(
            c2_root,
            "__ROOT__",
        )
    )

    c2_lookup = load_c2_pair_lookup(
        c2_files,
        columns=c2_columns,
        batch_rows=max(
            4096,
            int(batch_rows),
        ),
        source_label="PIPELINE_C2",
    )

    candidate_root.mkdir(
        parents=False,
        exist_ok=False,
        mode=0o700,
    )

    reference_schema = None
    total_rows = 0
    total_batches = 0
    total_files = 0
    partition_reports = []

    try:
        for partition_index, partition in enumerate(
            sorted(
                normalized_expected_rows
            ),
            start=1,
        ):
            b2_files = (
                list_partition_parquet_files(
                    b2_root,
                    partition,
                )
            )

            f2_files = (
                list_partition_parquet_files(
                    f2_root,
                    partition,
                )
            )

            g2_files = (
                list_partition_parquet_files(
                    g2_root,
                    partition,
                )
            )

            partition_root = (
                candidate_root
                / partition
            )

            partition_root.mkdir(
                parents=True,
                exist_ok=False,
            )

            g2_cursor = FamilyDayCursor(
                g2_files,
                columns=g2_columns,
                batch_rows=int(batch_rows),
                source_label=(
                    f"PIPELINE_G2:{partition}"
                ),
            )

            partition_rows = 0
            partition_batches = 0

            for batch_index, (
                b2_batch,
                f2_batch,
            ) in enumerate(
                iter_b2_f2_lockstep_batches(
                    b2_files,
                    f2_files,
                    batch_rows=int(batch_rows),
                    key_columns=pair_key_columns,
                    partition=partition,
                    b2_columns=b2_columns,
                    f2_columns=f2_columns,
                )
            ):
                g2_batch = (
                    broadcast_g2_rows_for_pair_batch(
                        b2_batch,
                        g2_cursor,
                        partition=partition,
                    )
                )

                c2_batch = (
                    broadcast_c2_rows_for_pair_batch(
                        b2_batch,
                        c2_lookup,
                        partition=partition,
                    )
                )

                output_batch = (
                    assemble_canonical_output_batch(
                        {
                            "B2": b2_batch,
                            "F2": f2_batch,
                            "C2": c2_batch,
                            "G2": g2_batch,
                        },
                        projection_plan,
                        partition=partition,
                        expected_output_columns=len(
                            projection_plan
                        ),
                    )
                )

                if reference_schema is None:
                    reference_schema = (
                        output_batch.schema
                    )

                elif not output_batch.schema.equals(
                    reference_schema,
                    check_metadata=False,
                ):
                    raise ValueError(
                        "PIPELINE_OUTPUT_SCHEMA_DIVERGENCE:"
                        f"partition={partition};"
                        f"batch={batch_index}"
                    )

                output_path = (
                    partition_root
                    / f"part-{batch_index:05d}.parquet"
                )

                _h2p_pq.write_table(
                    _h2p_pa.Table.from_batches(
                        [output_batch]
                    ),
                    output_path,
                    compression=str(
                        compression
                    ),
                    row_group_size=max(
                        1,
                        min(
                            int(batch_rows),
                            output_batch.num_rows,
                        ),
                    ),
                )

                partition_rows += (
                    output_batch.num_rows
                )

                partition_batches += 1
                total_rows += (
                    output_batch.num_rows
                )

                total_batches += 1
                total_files += 1

            g2_cursor.drain()

            expected_rows = (
                normalized_expected_rows[
                    partition
                ]
            )

            if partition_rows != expected_rows:
                raise ValueError(
                    "PIPELINE_PARTITION_ROW_COUNT_MISMATCH:"
                    f"partition={partition};"
                    f"expected={expected_rows};"
                    f"actual={partition_rows}"
                )

            if partition_batches <= 0:
                raise ValueError(
                    "PIPELINE_PARTITION_HAS_NO_OUTPUT_BATCHES:"
                    f"{partition}"
                )

            partition_reports.append(
                {
                    "partition_index": (
                        partition_index
                    ),
                    "partition": partition,
                    "expected_rows": (
                        expected_rows
                    ),
                    "actual_rows": (
                        partition_rows
                    ),
                    "batch_count": (
                        partition_batches
                    ),
                    "file_count": (
                        partition_batches
                    ),
                    "g2_rows_consumed": (
                        g2_cursor.rows_consumed
                    ),
                    "g2_rows_matched": (
                        g2_cursor.rows_matched
                    ),
                    "g2_only_rows_skipped": (
                        g2_cursor.g2_only_rows_skipped
                    ),
                    "result": "PASS",
                }
            )

        if reference_schema is None:
            raise ValueError(
                "PIPELINE_OUTPUT_SCHEMA_MISSING"
            )

        expected_total_rows = sum(
            normalized_expected_rows.values()
        )

        if total_rows != expected_total_rows:
            raise ValueError(
                "PIPELINE_TOTAL_ROW_COUNT_MISMATCH:"
                f"expected={expected_total_rows};"
                f"actual={total_rows}"
            )

        build_report = {
            "ok": True,
            "run_id": str(run_id),
            "candidate_root": str(
                candidate_root
            ),
            "final_root": str(
                final_root
            ),
            "partition_count": len(
                partition_reports
            ),
            "partition_pass_count": len(
                partition_reports
            ),
            "total_rows": total_rows,
            "batch_count": total_batches,
            "file_count": total_files,
            "column_count": len(
                reference_schema
            ),
            "schema_fingerprint": (
                _h2p_schema_fingerprint(
                    reference_schema
                )
            ),
            "partitions": (
                partition_reports
            ),
        }

        _h2p_write_json_atomic(
            candidate_root
            / "dataset_manifest.json",
            build_report,
        )

        return (
            candidate_root,
            build_report,
            reference_schema,
        )

    except Exception:
        if candidate_root.exists():
            _h2p_shutil.rmtree(
                candidate_root
            )

        raise


def promote_validated_candidate_dataset(
    *,
    candidate_root,
    final_root,
    promotion_token,
):
    candidate_root = (
        _h2p_assert_absolute_no_symlink_chain(
            candidate_root,
            label="candidate_root",
            require_exists=True,
        )
    )

    final_root = _H2PPath(
        final_root
    )

    if not final_root.is_absolute():
        raise ValueError(
            "PIPELINE_PATH_MUST_BE_ABSOLUTE:"
            f"label=final_root;path={final_root}"
        )

    final_parent = (
        _h2p_assert_absolute_no_symlink_chain(
            final_root.parent,
            label="final_root_parent",
            require_exists=True,
        )
    )

    if (
        candidate_root.is_symlink()
        or not candidate_root.is_dir()
    ):
        raise ValueError(
            "PIPELINE_CANDIDATE_ROOT_INVALID:"
            f"{candidate_root}"
        )

    if candidate_root.parent != final_parent:
        raise ValueError(
            "PIPELINE_PROMOTION_PARENT_MISMATCH"
        )

    run_id = final_root.name

    if not _H2P_RUN_ID_RE.fullmatch(
        run_id
    ):
        raise ValueError(
            "PIPELINE_FINAL_RUN_ID_INVALID:"
            f"{run_id!r}"
        )

    expected_candidate_name = (
        f".{run_id}.candidate"
    )

    if (
        candidate_root.name
        != expected_candidate_name
    ):
        raise ValueError(
            "PIPELINE_CANDIDATE_NAME_MISMATCH:"
            f"expected={expected_candidate_name};"
            f"actual={candidate_root.name}"
        )

    if (
        final_root.exists()
        or final_root.is_symlink()
    ):
        raise FileExistsError(
            "PIPELINE_FINAL_ALREADY_EXISTS:"
            f"{final_root}"
        )

    registration_key = str(
        candidate_root
    )

    with _H2P_ACTIVE_CANDIDATES_LOCK:
        registration = (
            _H2P_ACTIVE_CANDIDATES.get(
                registration_key
            )
        )

    if registration is None:
        raise ValueError(
            "PIPELINE_PROMOTION_REGISTRATION_MISSING:"
            f"{candidate_root}"
        )

    if (
        not isinstance(
            promotion_token,
            str,
        )
        or not promotion_token
        or registration.get(
            "token"
        )
        != promotion_token
    ):
        raise ValueError(
            "PIPELINE_PROMOTION_TOKEN_INVALID"
        )

    if (
        registration.get(
            "candidate_root"
        )
        != str(candidate_root)
        or registration.get(
            "final_root"
        )
        != str(final_root)
    ):
        raise ValueError(
            "PIPELINE_PROMOTION_REGISTRATION_"
            "PATH_MISMATCH"
        )

    manifest_path = (
        candidate_root
        / "dataset_manifest.json"
    )

    validation_path = (
        candidate_root
        / "_VALIDATION.json"
    )

    success_path = (
        candidate_root
        / "_SUCCESS"
    )

    build_report = (
        _h2p_load_json_object(
            manifest_path,
            label="dataset_manifest",
        )
    )

    validation_report = (
        _h2p_load_json_object(
            validation_path,
            label="validation_report",
        )
    )

    build_report_sha256 = (
        _h2p_trust_hashlib.sha256(
            _h2p_canonical_json_bytes(
                build_report
            )
        ).hexdigest()
    )

    validation_report_sha256 = (
        _h2p_trust_hashlib.sha256(
            _h2p_canonical_json_bytes(
                validation_report
            )
        ).hexdigest()
    )

    if (
        build_report_sha256
        != registration.get(
            "build_report_sha256"
        )
    ):
        raise ValueError(
            "PIPELINE_PROMOTION_BUILD_REPORT_"
            "DIGEST_MISMATCH"
        )

    if (
        validation_report_sha256
        != registration.get(
            "validation_report_sha256"
        )
    ):
        raise ValueError(
            "PIPELINE_PROMOTION_VALIDATION_REPORT_"
            "DIGEST_MISMATCH"
        )

    inventory = (
        _h2p_candidate_parquet_inventory(
            candidate_root,
            expected_file_count=int(
                registration.get(
                    "parquet_file_count",
                    -1,
                )
            ),
        )
    )

    if (
        inventory["fingerprint"]
        != registration.get(
            "parquet_inventory_fingerprint"
        )
    ):
        raise ValueError(
            "PIPELINE_PROMOTION_PARQUET_"
            "INVENTORY_MISMATCH"
        )

    _h2p_assert_absolute_no_symlink_chain(
        success_path,
        label="success_marker",
        require_exists=True,
    )

    if (
        success_path.is_symlink()
        or not success_path.is_file()
    ):
        raise ValueError(
            "PIPELINE_SUCCESS_MARKER_INVALID:"
            f"{success_path}"
        )

    success_value = (
        success_path.read_text(
            encoding="utf-8",
            errors="strict",
        ).strip()
    )

    if success_value != "VALIDATED":
        raise ValueError(
            "PIPELINE_SUCCESS_MARKER_VALUE_INVALID:"
            f"{success_value!r}"
        )

    _h2p_validate_build_validation_attestation(
        build_report,
        validation_report,
        expected_run_id=run_id,
        expected_candidate_root=(
            candidate_root
        ),
        expected_final_root=(
            final_root
        ),
    )

    _h2p_os.replace(
        candidate_root,
        final_root,
    )

    with _H2P_ACTIVE_CANDIDATES_LOCK:
        _H2P_ACTIVE_CANDIDATES.pop(
            registration_key,
            None,
        )

    return final_root




def execute_full_pipeline_integration(
    *,
    b2_root,
    f2_root,
    c2_root,
    g2_root,
    output_root,
    run_id,
    projection_plan,
    expected_partition_rows,
    validator_callback,
    batch_rows=1024,
    compression="snappy",
):
    validator_provenance = (
        _h2p_validate_validator_callback_provenance(
            validator_callback
        )
    )

    output_root = _H2PPath(
        output_root
    )

    candidate_root = (
        output_root
        / f".{run_id}.candidate"
    )

    final_root = (
        output_root
        / str(run_id)
    )

    promotion_token = None

    try:
        (
            candidate_root,
            build_report,
            output_schema,
        ) = build_candidate_dataset_streaming(
            b2_root=b2_root,
            f2_root=f2_root,
            c2_root=c2_root,
            g2_root=g2_root,
            output_root=output_root,
            run_id=run_id,
            projection_plan=projection_plan,
            expected_partition_rows=(
                expected_partition_rows
            ),
            batch_rows=batch_rows,
            compression=compression,
        )

        validation_report = (
            validator_callback(
                candidate_root,
                projection_plan,
                expected_partition_rows,
                expected_total_rows=sum(
                    int(value)
                    for value
                    in expected_partition_rows.values()
                ),
                expected_output_columns=len(
                    projection_plan
                ),
                expected_schema=output_schema,
                batch_rows=batch_rows,
            )
        )

        attestation = (
            _h2p_validate_build_validation_attestation(
                build_report,
                validation_report,
                expected_partition_rows=(
                    expected_partition_rows
                ),
                expected_run_id=run_id,
                expected_candidate_root=(
                    candidate_root
                ),
                expected_final_root=(
                    final_root
                ),
            )
        )

        _h2p_write_json_atomic(
            candidate_root
            / "_VALIDATION.json",
            validation_report,
        )

        (
            candidate_root
            / "_SUCCESS"
        ).write_text(
            "VALIDATED\n",
            encoding="utf-8",
        )

        promotion_token = (
            _h2p_register_candidate_for_promotion(
                candidate_root=(
                    candidate_root
                ),
                final_root=final_root,
                build_report=build_report,
                validation_report=(
                    validation_report
                ),
            )
        )

        promoted_root = (
            promote_validated_candidate_dataset(
                candidate_root=(
                    candidate_root
                ),
                final_root=final_root,
                promotion_token=(
                    promotion_token
                ),
            )
        )

        return {
            "ok": True,
            "run_id": str(run_id),
            "final_root": str(
                promoted_root
            ),
            "validator_provenance": (
                validator_provenance
            ),
            "build": build_report,
            "validation": (
                validation_report
            ),
            "attestation": attestation,
            "promotion": "PASS",
        }

    except Exception:
        if candidate_root.exists():
            _h2p_shutil.rmtree(
                candidate_root
            )

        raise

    finally:
        with _H2P_ACTIVE_CANDIDATES_LOCK:
            _H2P_ACTIVE_CANDIDATES.pop(
                str(candidate_root),
                None,
            )



def worker_execute(
    args: argparse.Namespace,
    contract: dict[str, Any],
) -> int:
    del args, contract

    raise DraftRuntimeBlocked(
        "H2_FULL_MATERIALIZATION_NOT_IMPLEMENTED:"
        "worker execution is disabled in the "
        "report-only source scaffold"
    )


def supervisor_execute(
    args: argparse.Namespace,
    contract: dict[str, Any],
) -> int:
    del contract

    if not FULL_MATERIALIZATION_IMPLEMENTED:
        raise DraftRuntimeBlocked(
            "H2_FULL_MATERIALIZATION_NOT_IMPLEMENTED:"
            "supervisor execution is disabled in the "
            "report-only source scaffold"
        )

    output_root = Path(
        args.output_root
        or args.runs_root
    ).resolve(strict=True)

    if not args.run_id:
        raise ValueError(
            "RUN_ID_REQUIRED_FOR_EXECUTE"
        )

    previous_handlers: dict[int, Any] = {}
    reservation: CandidateReservation | None = None
    process: subprocess.Popen[Any] | None = None

    try:
        previous_handlers = (
            install_supervisor_signal_handlers()
        )

        environment = os.environ.copy()

        reservation = reserve_candidate_atomically(
            output_root,
            args.run_id,
        )

        environment[
            OWNER_ENVIRONMENT_VARIABLE
        ] = reservation.token

        process = subprocess.Popen(
            worker_command(args),
            env=environment,
            shell=False,
            start_new_session=True,
        )

        try:
            return_code = process.wait()

            if return_code != 0:
                raise subprocess.CalledProcessError(
                    return_code,
                    process.args,
                )

        except BaseException as primary_error:
            termination_error: BaseException | None = None
            barrier_error: BaseException | None = None

            try:
                terminate_worker_process_group(
                    process,
                    args.termination_grace_seconds,
                )

            except ProcessLookupError:
                try:
                    wait_for_worker_process_barrier_after_termination_failure(
                        process,
                        args.termination_grace_seconds,
                    )

                except BaseException as exc:
                    barrier_error = exc

            except BaseException as exc:
                termination_error = exc

                try:
                    wait_for_worker_process_barrier_after_termination_failure(
                        process,
                        args.termination_grace_seconds,
                    )

                except BaseException as inner_exc:
                    barrier_error = inner_exc

            if barrier_error is not None:
                raise barrier_error from (
                    termination_error
                    or primary_error
                )

            if reservation.candidate.exists():
                cleanup_candidate_after_barrier(
                    output_root,
                    reservation,
                    reservation.token,
                )

            if termination_error is not None:
                raise termination_error from (
                    primary_error
                )

            raise

        return 0

    except BaseException:
        if (
            process is None
            and reservation is not None
            and reservation.candidate.exists()
        ):
            cleanup_reserved_candidate_on_launch_failure(
                output_root,
                reservation,
            )

        raise

    finally:
        restore_supervisor_signal_handlers(
            previous_handlers
        )

def dry_run(
    args: argparse.Namespace,
    contract: dict[str, Any],
) -> int:
    resolved = resolve_inputs(
        args,
        contract,
    )

    inventories = {
        role: inventory_partitions(
            payload.dataset_root
        )
        for role, payload in (
            resolved.items()
        )
    }

    validate_partition_alignment(
        inventories
    )

    summary = {
        "ok": True,
        "mode": "dry-run",
        "full_materialization_implemented": (
            FULL_MATERIALIZATION_IMPLEMENTED
        ),
        "contract_fingerprint": contract[
            "contract_fingerprint"
        ],
        "resolved_inputs": {
            role: {
                "run_id": payload.run_id,
                "dataset_root": str(
                    payload.dataset_root
                ),
                "partition_files": len(
                    inventories[role]
                ),
                "rows": sum(
                    int(row["rows"])
                    for row in inventories[
                        role
                    ]
                ),
            }
            for role, payload in (
                resolved.items()
            )
        },
    }

    print(
        json.dumps(
            summary,
            indent=2,
            ensure_ascii=True,
            sort_keys=True,
        )
    )

    return 0


def main(
    argv: Sequence[str] | None = None,
) -> int:
    args = parse_args(argv)

    try:
        contract = load_contract(
            Path(args.contract)
        )

        if args.mode == "dry-run":
            return dry_run(
                args,
                contract,
            )

        if args.mode == "execute":
            return supervisor_execute(
                args,
                contract,
            )

        if args.mode == "_worker-execute":
            return worker_execute(
                args,
                contract,
            )

        if args.mode == "validate-only":
            if not args.existing_run:
                raise ValueError(
                    "EXISTING_RUN_REQUIRED_FOR_VALIDATE_ONLY"
                )

            command = validator_command(
                args,
                Path(args.existing_run),
            )

            completed = subprocess.run(
                command,
                check=False,
            )

            return completed.returncode

        raise AssertionError(
            f"UNREACHABLE_MODE:{args.mode}"
        )

    except DraftRuntimeBlocked as exc:
        print(
            f"ERROR={exc}",
            file=sys.stderr,
        )
        return EXIT_DRAFT_RUNTIME_BLOCKED

    except Exception as exc:
        print(
            f"ERROR={type(exc).__name__}:{exc}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
