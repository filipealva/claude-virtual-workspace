#!/usr/bin/env bash
#
# Add missing repo-local assistant config for Claude Code and/or Codex.
#
# Usage:
#   ./assistant-support.sh codex   # mirror .claude agents/skills into .codex
#   ./assistant-support.sh claude  # mirror .codex agents/skills into .claude
#   ./assistant-support.sh both    # do both directions
#
# This updates the sub-repos listed in workspace.conf, then runs bootstrap.sh so
# the workspace-level symlinks are rebuilt.

set -euo pipefail
cd "$(dirname "$0")"

usage() {
  echo "Usage: $0 codex|claude|both" >&2
  exit 2
}

mode="${1:-}"
case "$mode" in
  codex|claude|both) ;;
  *) usage ;;
esac

if [ ! -f workspace.conf ]; then
  echo "Missing workspace.conf" >&2
  exit 1
fi
# shellcheck source=/dev/null
source workspace.conf

is_git_work_tree() {
  [ -d "$1/.git" ] || [ -f "$1/.git" ]
}

skill_name_from_path() {
  local path="$1"
  local base
  base="$(basename "$path")"
  printf "%s" "${base%.md}"
}

first_heading_or_name() {
  local file="$1"
  local fallback="$2"
  local heading
  heading="$(grep -m 1 '^# ' "$file" 2>/dev/null | sed 's/^# *//' || true)"
  if [ -n "$heading" ]; then
    printf "%s" "$heading"
  else
    printf "%s" "$fallback"
  fi
}

has_frontmatter() {
  [ "$(sed -n '1p' "$1" 2>/dev/null || true)" = "---" ]
}

copy_claude_agents_to_codex() {
  local repo="$1"
  local src_dir="$repo/.claude/agents"
  local dst_dir="$repo/.codex/agents"
  [ -d "$src_dir" ] || return 0
  mkdir -p "$dst_dir"
  shopt -s nullglob
  for src in "$src_dir"/*.md; do
    cp "$src" "$dst_dir/$(basename "$src")"
    echo "codex agent: $dst_dir/$(basename "$src")"
  done
  shopt -u nullglob
}

copy_codex_agents_to_claude() {
  local repo="$1"
  local src_dir="$repo/.codex/agents"
  local dst_dir="$repo/.claude/agents"
  [ -d "$src_dir" ] || return 0
  mkdir -p "$dst_dir"
  shopt -s nullglob
  for src in "$src_dir"/*.md; do
    cp "$src" "$dst_dir/$(basename "$src")"
    echo "claude agent: $dst_dir/$(basename "$src")"
  done
  shopt -u nullglob
}

copy_claude_skills_to_codex() {
  local repo="$1"
  local src_dir="$repo/.claude/skills"
  local dst_root="$repo/.codex/skills"
  [ -d "$src_dir" ] || return 0
  mkdir -p "$dst_root"
  shopt -s nullglob

  for src in "$src_dir"/*.md; do
    local name dst heading
    name="$(skill_name_from_path "$src")"
    dst="$dst_root/$name/SKILL.md"
    mkdir -p "$(dirname "$dst")"
    if has_frontmatter "$src"; then
      cp "$src" "$dst"
    else
      heading="$(first_heading_or_name "$src" "$name")"
      {
        printf -- "---\n"
        printf "name: %s\n" "$name"
        printf "description: %s\n" "$heading"
        printf -- "---\n\n"
        cat "$src"
      } > "$dst"
    fi
    echo "codex skill: $dst"
  done

  for src in "$src_dir"/*; do
    [ -d "$src" ] || continue
    [ -f "$src/SKILL.md" ] || continue
    local name dst
    name="$(basename "$src")"
    dst="$dst_root/$name"
    mkdir -p "$dst"
    cp -R "$src/." "$dst/"
    echo "codex skill: $dst"
  done

  shopt -u nullglob
}

copy_codex_skills_to_claude() {
  local repo="$1"
  local src_root="$repo/.codex/skills"
  local dst_root="$repo/.claude/skills"
  [ -d "$src_root" ] || return 0
  mkdir -p "$dst_root"
  shopt -s nullglob

  for src in "$src_root"/*; do
    [ -d "$src" ] || continue
    local name dst
    name="$(basename "$src")"
    if [ -f "$src/SKILL.md" ]; then
      dst="$dst_root/$name"
      mkdir -p "$dst"
      cp -R "$src/." "$dst/"
      echo "claude skill: $dst"
    fi
  done

  shopt -u nullglob
}

for entry in "${REPOS[@]}"; do
  IFS='|' read -r name url_or_ref branch <<< "$entry"
  if ! is_git_work_tree "$name"; then
    echo "Skipping $name (not checked out)"
    continue
  fi

  case "$mode" in
    codex)
      copy_claude_agents_to_codex "$name"
      copy_claude_skills_to_codex "$name"
      ;;
    claude)
      copy_codex_agents_to_claude "$name"
      copy_codex_skills_to_claude "$name"
      ;;
    both)
      copy_claude_agents_to_codex "$name"
      copy_claude_skills_to_codex "$name"
      copy_codex_agents_to_claude "$name"
      copy_codex_skills_to_claude "$name"
      ;;
  esac
done

if [ -x ./bootstrap.sh ]; then
  ./bootstrap.sh
else
  echo "bootstrap.sh is missing or not executable; run it manually after fixing permissions." >&2
  exit 1
fi
