#!/usr/bin/env bash
#
# Remove worktrees for a feature branch across multiple sub-repos.
#
# Usage:
#   ./worktree-remove.sh <branch> [repo1 repo2 ...]
#
# If no repos are specified, removes worktrees for ALL repos matching that branch.
# Removes entries from workspace.conf and .gitignore automatically.
# Run ./bootstrap.sh after to prune stale .claude/ symlinks.

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f workspace.conf ]; then
  echo "Missing workspace.conf" >&2
  exit 1
fi

if [ $# -lt 1 ]; then
  echo "Usage: $0 <branch> [repo1 repo2 ...]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  $0 feature/auth              # remove all worktrees for that branch" >&2
  echo "  $0 feature/auth web-app api  # specific repos only" >&2
  exit 1
fi

# shellcheck source=/dev/null
source workspace.conf

BRANCH="$1"
shift
SELECTED_REPOS=("$@")

sanitize_branch() {
  echo "$1" | sed 's/[^a-zA-Z0-9._-]/-/g'
}

SAFE_BRANCH=$(sanitize_branch "$BRANCH")

# If no repos specified, find all worktrees matching this branch
if [ ${#SELECTED_REPOS[@]} -eq 0 ]; then
  for entry in "${REPOS[@]}"; do
    IFS='|' read -r name url_or_ref entry_branch <<< "$entry"
    if [[ "$url_or_ref" == worktree:* ]] && [ "${entry_branch:-}" = "$BRANCH" ]; then
      source_repo="${url_or_ref#worktree:}"
      SELECTED_REPOS+=("$source_repo")
    fi
  done
fi

if [ ${#SELECTED_REPOS[@]} -eq 0 ]; then
  echo "No worktrees found for branch '$BRANCH'"
  exit 0
fi

REMOVED=()

for repo in "${SELECTED_REPOS[@]}"; do
  wt_name="${repo}--${SAFE_BRANCH}"

  if [ ! -d "$repo/.git" ]; then
    echo "Warning: source repo '$repo' not found, skipping worktree removal" >&2
    continue
  fi

  # Check for uncommitted changes before removing
  if [ -d "$wt_name" ] || [ -f "$wt_name/.git" ]; then
    if [ -n "$(git -C "$wt_name" status --porcelain 2>/dev/null)" ]; then
      echo "WARNING: $wt_name has uncommitted changes!" >&2
      echo "  Skipping. Commit or stash changes first, then retry." >&2
      continue
    fi

    echo "Removing worktree: $wt_name..."
    git -C "$repo" worktree remove "../$wt_name" 2>/dev/null || \
      git -C "$repo" worktree remove --force "../$wt_name"
    REMOVED+=("$wt_name")
  else
    echo "Skipping $wt_name (not found)"
  fi
done

if [ ${#REMOVED[@]} -eq 0 ]; then
  echo "No worktrees removed."
  exit 0
fi

# Remove entries from workspace.conf
for wt_name in "${REMOVED[@]}"; do
  sed -i '' "/${wt_name}|worktree:/d" workspace.conf
done

# Remove from .gitignore
for wt_name in "${REMOVED[@]}"; do
  sed -i '' "/^${wt_name}\/$/d" .gitignore
done

echo ""
echo "Removed ${#REMOVED[@]} worktree(s) for branch '$BRANCH':"
for wt_name in "${REMOVED[@]}"; do
  echo "  $wt_name/"
done
echo ""
echo "Run ./bootstrap.sh to prune stale .claude/ symlinks."
echo ""
echo "To also delete the local branch:"
for repo in "${SELECTED_REPOS[@]}"; do
  echo "  git -C $repo branch -d $BRANCH"
done
