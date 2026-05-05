#!/usr/bin/env bash
#
# Clone any missing sub-repos and (re)build .claude/ symlinks so Claude Code,
# launched from this workspace root, sees every agent / command / skill / hook
# defined in any sub-repo.
#
# Idempotent — safe to rerun any time (after pulling, after adding repos, etc.).
# Source of truth for sub-repos is workspace.conf.

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f workspace.conf ]; then
  echo "Missing workspace.conf — expected REPOS=(\"name|git-url\" ...)" >&2
  exit 1
fi
# shellcheck source=/dev/null
source workspace.conf

CLAUDE_DIRS=(agents commands skills hooks)

# 1. Clone any missing sub-repos.
for entry in "${REPOS[@]}"; do
  name="${entry%%|*}"
  url="${entry##*|}"
  if [ ! -d "$name/.git" ]; then
    echo "Cloning $name..."
    git clone "$url" "$name"
  fi
done

# 2. Prune dead symlinks under .claude/ (handles deleted/renamed agents).
mkdir -p .claude
find .claude -type l ! -exec test -e {} \; -print -delete 2>/dev/null || true

# 3. Symlink every <repo>/.claude/<kind>/* into .claude/<kind>/.
for entry in "${REPOS[@]}"; do
  name="${entry%%|*}"
  for kind in "${CLAUDE_DIRS[@]}"; do
    src_dir="$name/.claude/$kind"
    [ -d "$src_dir" ] || continue
    mkdir -p ".claude/$kind"
    shopt -s nullglob
    for src in "$src_dir"/*; do
      ln -sfn "../../$src" ".claude/$kind/$(basename "$src")"
    done
    shopt -u nullglob
  done
done

echo "Bootstrap complete."
