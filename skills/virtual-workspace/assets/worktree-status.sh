#!/usr/bin/env bash
#
# Show status of all repos and worktrees in the workspace.
# Displays: branch, dirty state, ahead/behind tracking branch.

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

printf "%-30s %-8s %-25s %s\n" "DIRECTORY" "TYPE" "BRANCH" "STATUS"
printf "%-30s %-8s %-25s %s\n" "---------" "----" "------" "------"

for entry in "${REPOS[@]}"; do
  IFS='|' read -r name url_or_ref branch <<< "$entry"

  if [[ "$url_or_ref" == worktree:* ]]; then
    type="wt"
  else
    type="clone"
  fi

  if ! is_git_work_tree "$name"; then
    printf "%-30s %-8s %-25s %s\n" "$name" "$type" "(not checked out)" ""
    continue
  fi

  current_branch=$(git -C "$name" branch --show-current 2>/dev/null || echo "detached")

  # Dirty state
  status=""
  dirty_count=$(git -C "$name" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$dirty_count" -gt 0 ]; then
    status="dirty ($dirty_count files)"
  else
    status="clean"
  fi

  # Ahead/behind
  tracking=$(git -C "$name" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo "")
  if [ -n "$tracking" ]; then
    ahead=$(git -C "$name" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
    behind=$(git -C "$name" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
      status="$status [+${ahead}/-${behind}]"
    fi
  fi

  printf "%-30s %-8s %-25s %s\n" "$name" "$type" "$current_branch" "$status"
done
