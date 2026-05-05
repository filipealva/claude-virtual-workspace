---
name: virtual-workspace
description: Use when the user wants to set up a parent folder that hosts multiple sibling git repos and unifies their Claude Code agents, commands, skills, and hooks into one session — e.g. "create a workspace for these repos", "I want one Claude session across my frontend and backend repos", "set up a multi-repo workspace", "combine repos for Claude", "make a workspace shell so I can use agents from multiple repos at once". Walks the user through naming the workspace, listing repo URLs (clones any missing), and generates the canonical scaffolding (bootstrap.sh, pull-all.sh, workspace.conf, CLAUDE.md, README.md, .gitignore, .code-workspace), then runs bootstrap to wire up the symlinks.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---

# /virtual-workspace:create — Build a multi-repo Claude Code workspace shell

This skill creates a **workspace shell**: a parent folder that hosts multiple sibling git repos and exposes the union of their `.claude/{agents,commands,skills,hooks}/` to a single Claude Code session via symlinks. It is the canonical workaround for the fact that Claude Code does not natively merge `.claude/` configs across sibling roots.

The workspace shell never tracks changes inside the sub-repos — they are gitignored. The shell only owns the cross-repo glue.

---

## Plugin asset locations

This skill ships canonical scripts and templates in `${CLAUDE_PLUGIN_ROOT}/skills/virtual-workspace/assets/`:

- `bootstrap.sh` — copy verbatim into every new workspace
- `pull-all.sh` — copy verbatim into every new workspace
- `templates/workspace.conf.tmpl`
- `templates/CLAUDE.md.tmpl`
- `templates/README.md.tmpl`
- `templates/gitignore.tmpl`
- `templates/code-workspace.tmpl`

Read the asset files using their absolute paths under `${CLAUDE_PLUGIN_ROOT}`. Never inline the script bodies into this SKILL.md — always source them from disk so the skill stays a thin orchestrator.

---

## Flow when invoked

Follow these steps in order. Do not skip the confirmation step.

### 1. Frame the work (1 short message)

Tell the user, in 2-3 sentences, what you're about to build and that the shell will not track sub-repo contents. Example:

> I'll create a workspace shell — a thin parent folder that holds your repos side-by-side and surfaces all their Claude Code agents/commands/skills/hooks in one session via symlinks. The shell itself never tracks the sub-repos' contents; it only owns the cross-repo glue (bootstrap script, workspace.conf, etc.).

### 2. Gather inputs

Collect these via plain conversation (free-text) or `AskUserQuestion` (choices). Use the tool that fits each input type.

**a) Workspace name** — free text.
Ask: "What should I call the workspace? (e.g. `AcmeWorkspace`, `acme-monorepo-shell`)". Use the answer verbatim as the directory name; do NOT lowercase or sluggify unless the user uses spaces (in which case suggest a kebab or PascalCase replacement and confirm).

**b) Parent directory** — `AskUserQuestion`.
Default options: `~/Developer/` (recommended), `~/Code/`, `~/Projects/`, `Other` (free-text path). Resolve `~` and any env vars. The workspace will land at `<parent>/<name>/`.

**c) Sub-repo list** — free text, multi-line.
Ask: "Paste the git URLs of the repos you want in this workspace, one per line. SSH or HTTPS, both work. I'll auto-derive each repo's folder name from the URL — you can override after."

For each URL the user provides:
- Derive the folder name: take the last path segment, strip a trailing `.git`. E.g. `git@github.com:acme/web-app.git` → `web-app`; `https://github.com/torvalds/linux` → `linux`.
- Show the user the parsed list as `name → url` and ask whether to rename any. Only rename if they explicitly say so.

**d) Pre-existence check** — only ask if needed.
For each `<parent>/<name>/<sub-repo-name>` path that already exists, run `git -C <path> remote get-url origin 2>/dev/null` to check if it's already the right repo. If yes, silently keep it. If it exists but is unrelated (different remote, or no `.git`), use `AskUserQuestion`:
- "Use as-is" — leave it; bootstrap will skip cloning.
- "Replace" — `rm -rf <path>` then bootstrap clones fresh. **Confirm again** with a yes/no before deleting; this is destructive.
- "Pick a different sub-repo name" — re-prompt for the name.

### 3. Confirm before writing

Print a summary block and ask for explicit confirmation:

```
Workspace: <Name>
Location:  <parent>/<Name>/
Sub-repos:
  - <name1> → <url1>
  - <name2> → <url2>
  ...

Files I will create at <parent>/<Name>/:
  workspace.conf
  bootstrap.sh
  pull-all.sh
  CLAUDE.md
  README.md
  .gitignore
  <Name>.code-workspace

I will then run ./bootstrap.sh to clone any missing sub-repos and create symlinks.
Sound good? (yes / no / changes)
```

Wait for "yes" (or equivalent). If the user wants changes, loop back to step 2.

### 4. Generate the workspace

Use absolute paths throughout. Let `WS=<parent>/<Name>` and `ASSETS=${CLAUDE_PLUGIN_ROOT}/skills/virtual-workspace/assets`.

1. `mkdir -p "$WS"`.
2. **Copy** (do not edit) `$ASSETS/bootstrap.sh` and `$ASSETS/pull-all.sh` into `$WS/`. Use `cp` via Bash. Then `chmod +x "$WS/bootstrap.sh" "$WS/pull-all.sh"`.
3. Read each `*.tmpl` file with the Read tool, perform substitutions, and Write the result to `$WS/`. Substitutions:

   | Template                  | Output filename             | Substitutions |
   | ------------------------- | --------------------------- | ------------- |
   | `workspace.conf.tmpl`     | `workspace.conf`            | `{{NAME}}` → workspace name. `{{REPOS}}` → newline-joined `  "name|url"` entries (note the two-space indent so they align inside the `REPOS=(...)` array). |
   | `CLAUDE.md.tmpl`          | `CLAUDE.md`                 | `{{NAME}}` → workspace name. `{{REPO_LIST}}` → newline-joined bullets in the form `- \`<name>/\` — <one-line description, leave blank if unknown>`. |
   | `README.md.tmpl`          | `README.md`                 | `{{NAME}}` → workspace name. `{{REPO_LIST}}` → same bullets as above. `{{CLONE_INSTRUCTION}}` → see step 6 below; until the workspace is published, write `# (workspace not yet pushed to a remote — clone command will be added when published)`. |
   | `gitignore.tmpl`          | `.gitignore`                | `{{REPO_DIRS}}` → newline-joined `<name>/` lines. |
   | `code-workspace.tmpl`     | `<Name>.code-workspace`     | `{{FOLDERS}}` → for each sub-repo, prepend `,\n    { "name": "<name>", "path": "<name>" }`. (The leading comma + 4-space indent matches the existing `Workspace` entry in the template.) |

4. After writing, sanity-check the JSON in `<Name>.code-workspace` by running `python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$WS/<Name>.code-workspace"`. If it errors, re-render and retry.

### 5. Run bootstrap.sh

```sh
cd "$WS" && ./bootstrap.sh
```

Stream the output. After it completes, verify the result:

- `find "$WS/.claude" -type l | head` — list created symlinks.
- For each symlink, confirm `readlink -f` resolves to a real file.
- Report agent counts to the user as: `<repo-1>: 2 agents, 0 commands; <repo-2>: 1 agent, 0 commands; ...`. Use `find <repo>/.claude/<kind> -maxdepth 1 -type f -name "*.md" | wc -l` for each.

If bootstrap fails (clone failure, auth issue), surface the exact error to the user and stop. Do not auto-retry.

### 6. Offer to publish to GitHub (default no)

`AskUserQuestion`:

> Want to git-init this workspace shell and push it to a new GitHub repo so coworkers can clone it?
> - **No, leave it local** (recommended)
> - **Yes, create a private GitHub repo and push**
> - **Yes, but I'll give you an existing repo URL to push to**

If yes:

1. Ask for the GitHub owner/org (default: detect from `gh api user --jq .login` if `gh` is available).
2. Ask for the repo name (default: workspace name).
3. `cd "$WS"`, then `git init -b main`.
4. Stage **only the seven shell files** (NOT the sub-repo dirs):
   ```sh
   git add .gitignore CLAUDE.md README.md bootstrap.sh pull-all.sh workspace.conf <Name>.code-workspace
   ```
5. Commit with a HEREDOC message ending with the standard `Co-Authored-By: Claude` trailer.
6. For "create new repo": `gh repo create <owner>/<name> --private --source=. --push`. For existing-repo path: `git remote add origin <url> && git push -u origin main`.
7. Re-render `README.md` with `{{CLONE_INSTRUCTION}}` → `git clone <repo-url> <Name>`, commit the README update with message `Update README with clone instructions`, and push.

If anything fails (e.g., `gh` not installed, auth error), report the error and stop — do not invent fallback paths.

### 7. Final summary

Print a concise, copy-pasteable next-step block:

```
Workspace ready at: <parent>/<Name>/

Next steps:
  cd <parent>/<Name>
  claude                          # start a Claude Code session with all sub-repo agents loaded

Maintenance:
  ./pull-all.sh                   # fast-forward pull every sub-repo
  ./bootstrap.sh                  # rerun whenever a sub-repo adds/renames/removes an agent or skill

To add a new sub-repo later:
  1. Append "name|git-url" to workspace.conf
  2. Add "name/" to .gitignore
  3. (optional) add it to <Name>.code-workspace
  4. ./bootstrap.sh
```

---

## Constraints and edge cases

- **Never edit `bootstrap.sh` or `pull-all.sh` per workspace.** They are identical across every workspace; everything workspace-specific lives in `workspace.conf`.
- **Never delete `.git` directories.** If a sub-repo path exists with a different remote, ask before any destructive action.
- **Do not commit `.claude/agents/` etc.** to the workspace shell — they are symlinks regenerated by `bootstrap.sh` and are gitignored by the template.
- **Macros & cross-platform**: the shell scripts target `bash` (not POSIX `sh`) and use `find -exec test -e`, `shopt -s nullglob`, `ln -sfn`. These all work on macOS BSD tools and GNU/Linux. Do not switch to symlink commands that require GNU-only flags.
- **`${CLAUDE_PLUGIN_ROOT}`** is set by Claude Code when this skill runs; use it to read assets. If it isn't set, fall back to the path where this SKILL.md lives.
- **URL parsing**: handle both `git@host:owner/repo.git` and `https://host/owner/repo[.git]`. Strip query strings and fragments. If parsing yields an empty name, ask the user explicitly.
- **No emojis** in any generated file unless the user explicitly requests them.

---

## What this skill does NOT do

- Manage existing workspaces (no add-repo / remove-repo flows). For that, the user edits `workspace.conf` and reruns `./bootstrap.sh`.
- Set up Cursor `.cursor/rules/` aggregation. Cursor multi-root workspaces handle per-root rules natively; the generated `<Name>.code-workspace` is enough.
- Configure Claude Code agents. Agents must already be defined inside the sub-repos under `<repo>/.claude/agents/`.
- Auto-resolve auth issues. If a `git clone` fails for SSH or HTTPS, surface the error and stop.
