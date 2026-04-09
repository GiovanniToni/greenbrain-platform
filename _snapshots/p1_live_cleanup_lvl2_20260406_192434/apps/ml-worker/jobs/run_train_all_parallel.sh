#!/usr/bin/env bash
set -euo pipefail

BASE="/opt/greenhouse"
REPO="$BASE/repo"
LIST="$BASE/tmp/families.txt"
JOBS="${1:-4}"

cd "$REPO"

if [[ ! -f "$LIST" ]]; then
  echo "families list not found: $LIST"
  exit 1
fi

echo "[TRAIN_ALL] families from prepared list: $(wc -l < "$LIST")"

LOCK="$BASE/tmp/train_all_parallel.lock"
mkdir -p "$BASE/tmp"

exec 9>"$LOCK"
flock -n 9 || { echo "train_all_parallel already running"; exit 1; }

grep -v '^[[:space:]]*$' "$LIST" | xargs -I{} -P "$JOBS" bash -lc "$REPO/jobs/train_one_safe.sh \"{}\""
