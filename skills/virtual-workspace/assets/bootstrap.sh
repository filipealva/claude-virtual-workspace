#!/usr/bin/env bash
#
# Clone any missing sub-repos, create any declared worktrees, and (re)build
# .claude/ and .codex/ symlinks so AI coding assistants (Claude Code, Codex),
# launched from this workspace root, see every agent / command / skill / hook
# defined in any sub-repo or worktree.
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
CODEX_DIRS=(agents skills)

is_git_work_tree() {
  [ -d "$1/.git" ] || [ -f "$1/.git" ]
}

# 1. Clone repos and create worktrees.
for entry in "${REPOS[@]}"; do
  IFS='|' read -r name url_or_ref branch <<< "$entry"

  if [[ "$url_or_ref" == worktree:* ]]; then
    # Worktree entry: "dirname|worktree:<source-repo>|<branch>"
    source_repo="${url_or_ref#worktree:}"
    if [ ! -d "$source_repo/.git" ]; then
      echo "Error: source repo '$source_repo' not cloned yet. Clone it first." >&2
      exit 1
    fi
    if ! is_git_work_tree "$name"; then
      echo "Creating worktree $name (branch: $branch) from $source_repo..."
      # Create branch if it doesn't exist in the source repo
      if ! git -C "$source_repo" rev-parse --verify "$branch" >/dev/null 2>&1; then
        git -C "$source_repo" branch "$branch"
      fi
      git -C "$source_repo" worktree add "../$name" "$branch"
    fi
  else
    # Standard clone entry: "name|git-url" or "name|git-url|branch"
    if ! is_git_work_tree "$name"; then
      echo "Cloning $name..."
      if [ -n "${branch:-}" ]; then
        git clone -b "$branch" "$url_or_ref" "$name"
      else
        git clone "$url_or_ref" "$name"
      fi
    fi
  fi
done

# 2. Prune dead symlinks under .claude/ and .codex/ (handles deleted/renamed agents).
mkdir -p .claude .codex
find .claude -type l ! -exec test -e {} \; -print -delete 2>/dev/null || true
find .codex -type l ! -exec test -e {} \; -print -delete 2>/dev/null || true

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

# 4. Symlink every <repo>/.codex/<kind>/* into .codex/<kind>/.
for entry in "${REPOS[@]}"; do
  name="${entry%%|*}"
  for kind in "${CODEX_DIRS[@]}"; do
    src_dir="$name/.codex/$kind"
    [ -d "$src_dir" ] || continue
    mkdir -p ".codex/$kind"
    shopt -s nullglob
    for src in "$src_dir"/*; do
      ln -sfn "../../$src" ".codex/$kind/$(basename "$src")"
    done
    shopt -u nullglob
  done
done

echo "Bootstrap complete."
