#!/usr/bin/env bash
#
# Fast-forward pull every sub-repo declared in workspace.conf.
# Skips repos that aren't cloned yet.

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f workspace.conf ]; then
  echo "Missing workspace.conf" >&2
  exit 1
fi
# shellcheck source=/dev/null
source workspace.conf

for entry in "${REPOS[@]}"; do
  name="${entry%%|*}"
  if [ -d "$name/.git" ]; then
    echo "=== $name ==="
    git -C "$name" pull --ff-only
  else
    echo "=== $name (not cloned, skipping) ==="
  fi
done
