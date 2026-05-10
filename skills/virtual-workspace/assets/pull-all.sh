#!/usr/bin/env bash
#
# Fast-forward pull every sub-repo and worktree declared in workspace.conf.
# Skips entries that aren't checked out yet.

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f workspace.conf ]; then
  echo "Missing workspace.conf" >&2
  exit 1
fi
# shellcheck source=/dev/null
source workspace.conf

is_git_work_tree() {
  [ -d "$1/.git" ] || [ -f "$1/.git" ]
}

for entry in "${REPOS[@]}"; do
  IFS='|' read -r name url_or_ref branch <<< "$entry"

  if [[ "$url_or_ref" == worktree:* ]]; then
    # Worktree — pull the tracking branch
    if is_git_work_tree "$name"; then
      echo "=== $name (worktree: $branch) ==="
      git -C "$name" pull --ff-only 2>/dev/null || \
        echo "  (no upstream tracking branch or not fast-forwardable)"
    else
      echo "=== $name (worktree not created, skipping) ==="
    fi
  else
    # Standard clone
    if is_git_work_tree "$name"; then
      echo "=== $name ==="
      git -C "$name" pull --ff-only
    else
      echo "=== $name (not cloned, skipping) ==="
    fi
  fi
done
