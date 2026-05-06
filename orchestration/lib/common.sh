#!/usr/bin/env bash

# GreenBrain orchestration shared helpers
# Source-only library. Do not execute directly.

set -o pipefail

export GB_BASE="${GB_BASE:-/opt/greenbrain-platform}"

gb_enter_root() {
  cd "$GB_BASE"
}

gb_load_env() {
  export APP_ENV="${APP_ENV:-dev}"

  if [ -f "$GB_BASE/infra/scripts/load_env.sh" ]; then
    # shellcheck disable=SC1091
    source "$GB_BASE/infra/scripts/load_env.sh"
  fi
}

gb_now() {
  date --iso-8601=seconds
}

gb_header() {
  echo
  echo "===== $* ====="
}

gb_require_file() {
  local f="$1"

  if [ ! -f "$f" ]; then
    echo "ERROR missing file: $f" >&2
    return 1
  fi
}

gb_require_exec() {
  local f="$1"

  if [ ! -x "$f" ]; then
    echo "ERROR missing executable: $f" >&2
    return 1
  fi
}

gb_run() {
  echo "+ $*"
  "$@"
}

gb_psql() {
  if [ -z "${DATABASE_URL:-}" ]; then
    echo "ERROR DATABASE_URL not loaded" >&2
    return 1
  fi

  psql "$DATABASE_URL" "$@"
}

gb_systemd_units() {
  cat <<'UNITS'
gh-daily-pipeline
gh-parquet-export
gh-refresh-registry
gh-train-missing
gh-predict-all
gh-train-biweekly-all
gh-train-quarterly
UNITS
}
