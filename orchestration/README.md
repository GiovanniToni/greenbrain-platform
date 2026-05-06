# GreenBrain Orchestration Control Plane

This folder is the canonical control plane for GreenBrain runtime orchestration.

## Purpose

Centralize and govern:

- systemd unit definitions
- runtime job wrappers
- validation commands
- diagnostic commands
- orchestration documentation
- drift detection between canonical files and compatibility mirrors

## Current runtime model

The live runtime still uses compatibility locations:

- `/etc/systemd/system`
- `infra/systemd`
- `apps/ml-worker/jobs`
- `infra/scripts/bin`

The canonical source now lives in:

- `orchestration/systemd`
- `orchestration/jobs`
- `orchestration/scripts`
- `orchestration/validators`
- `orchestration/docs`

## Important rule

Do not change live runtime paths directly.

Safe order:

1. Edit canonical files under `orchestration/`
2. Run validation
3. Run drift checks
4. Sync mirrors only when needed
5. Reinstall or reload systemd only after explicit approval
6. Verify runtime status

## Core commands

- `orchestration/scripts/gh-runtime-status`
- `orchestration/scripts/gh-runtime-validate`
- `orchestration/scripts/gh-runtime-doctor`
- `orchestration/scripts/gh-sync-systemd check`
- `orchestration/scripts/gh-sync-jobs check`
- `orchestration/scripts/gh-runtime-snapshot`

## Canonical daily flow

RAW
  -> gh-daily-pipeline
  -> FACT
  -> DENSE
  -> FEATURES
  -> MONITOR
  -> gh-parquet-export
  -> gh-refresh-registry
  -> gh-train-missing
  -> gh-predict-all
  -> periodic full training

## Shared library

Common helpers live in:

- `orchestration/lib/common.sh`

Current scripts using it:

- `gh-runtime-status`
- `gh-runtime-validate`
- `gh-runtime-doctor`
- `gh-runtime-snapshot`

## Safety

Most scripts in this folder are read-only by default.

Scripts with write behavior must require explicit `apply` or a separate deploy command.
