---
name: virtual-workspace
description: Use when the user wants to set up a parent folder that hosts multiple sibling git repos and unifies their Claude Code agents, commands, skills, and hooks into one session — e.g. "create a workspace for these repos", "I want one Claude session across my frontend and backend repos", "set up a multi-repo workspace", "combine repos for Claude", "make a workspace shell so I can use agents from multiple repos at once". Also use when the user wants to manage worktrees in an existing workspace — e.g. "create worktrees for feature/x", "set up feature branch across repos", "start a multi-repo feature", "remove worktrees for feature/x", "show worktree status", "I want to work on feature/x across all repos", "clean up the feature branch worktrees", "also create worktree for backend", "add backend to feature/x worktrees", "need worktree for another repo on this branch", "extend worktrees to include api".
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---

# /virtual-workspace — Multi-repo Claude Code workspace management

This skill has two modes:

1. **Create** — build a new workspace shell from scratch (invoked when no `workspace.conf` exists in the working directory).
2. **Manage worktrees** — create, inspect, or remove worktrees for multi-repo feature branches in an existing workspace (invoked when `workspace.conf` exists).

## Routing

When this skill is invoked, check whether `workspace.conf` exists in the current working directory (or any parent up to 3 levels):

- **If `workspace.conf` is NOT found**: run the **Create flow** (section below).
- **If `workspace.conf` IS found**: run the **Worktree management flow** (section below). The workspace root is the directory containing `workspace.conf`.

---

# Create flow — Build a new multi-repo Claude Code workspace shell

This flow creates a **workspace shell**: a parent folder that hosts multiple sibling git repos and exposes the union of their `.claude/{agents,commands,skills,hooks}/` to a single Claude Code session via symlinks. It is the canonical workaround for the fact that Claude Code does not natively merge `.claude/` configs across sibling roots.

The workspace shell never tracks changes inside the sub-repos — they are gitignored. The shell only owns the cross-repo glue.

The workspace supports **worktrees** for multi-repo feature development: create synchronized feature branches across multiple repos, work on them in one Claude session, commit/push independently, and open PRs per repo.

---

## Plugin asset locations

This skill ships canonical scripts and templates in `${CLAUDE_PLUGIN_ROOT}/skills/virtual-workspace/assets/`:

- `bootstrap.sh` — copy verbatim into every new workspace
- `pull-all.sh` — copy verbatim into every new workspace
- `worktree-create.sh` — copy verbatim into every new workspace
- `worktree-remove.sh` — copy verbatim into every new workspace
- `worktree-status.sh` — copy verbatim into every new workspace
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

> I'll create a workspace shell — a thin parent folder that holds your repos side-by-side and surfaces all their Claude Code agents/commands/skills/hooks in one session via symlinks. The shell itself never tracks the sub-repos' contents; it only owns the cross-repo glue (bootstrap script, workspace.conf, etc.). It also includes worktree scripts for multi-repo feature branches.

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
  worktree-create.sh
  worktree-remove.sh
  worktree-status.sh
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
2. **Copy** (do not edit) `$ASSETS/bootstrap.sh`, `$ASSETS/pull-all.sh`, `$ASSETS/worktree-create.sh`, `$ASSETS/worktree-remove.sh`, and `$ASSETS/worktree-status.sh` into `$WS/`. Use `cp` via Bash. Then `chmod +x "$WS/bootstrap.sh" "$WS/pull-all.sh" "$WS/worktree-create.sh" "$WS/worktree-remove.sh" "$WS/worktree-status.sh"`.
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
4. Stage **only the shell files** (NOT the sub-repo dirs):
   ```sh
   git add .gitignore CLAUDE.md README.md bootstrap.sh pull-all.sh worktree-create.sh worktree-remove.sh worktree-status.sh workspace.conf <Name>.code-workspace
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
  ./pull-all.sh                   # fast-forward pull every sub-repo and worktree
  ./bootstrap.sh                  # rerun whenever a sub-repo adds/renames/removes an agent or skill

Multi-repo features:
  ./worktree-create.sh feature/x  # create worktrees for all repos on branch feature/x
  ./worktree-status.sh            # check branch + dirty state across all repos/worktrees
  ./worktree-remove.sh feature/x  # clean up when the feature is merged

To add a new sub-repo later:
  1. Append "name|git-url" to workspace.conf
  2. Add "name/" to .gitignore
  3. (optional) add it to <Name>.code-workspace
  4. ./bootstrap.sh
```

---

# Worktree management flow — Manage feature branches in an existing workspace

This flow runs when `workspace.conf` is found. It handles creating, inspecting, and removing worktrees for multi-repo feature development.

## Detect the user's intent

Determine which action the user wants. If unclear, use `AskUserQuestion`:

| Intent | Triggers | Action |
|--------|----------|--------|
| **Create** | "create worktrees for...", "start feature/x", "work on feature/x across repos", "set up branch..." | → Run **Worktree Create** |
| **Status** | "show worktree status", "what branches are active", "status" | → Run **Worktree Status** |
| **Remove** | "remove worktrees for...", "clean up feature/x", "done with feature/x" | → Run **Worktree Remove** |
| **Pull** | "pull all repos", "update everything", "sync" | → Run **Pull All** |

---

## Worktree Create

### 1. Gather inputs

**a) Branch name** — free text.
Ask: "What branch name for this feature? (e.g. `feature/payments`, `fix/auth-bug`)"

If the user already stated the branch in their message (e.g. "create worktrees for feature/payments"), use that directly — don't re-ask.

**b) Detect existing worktrees for this branch.**
Read `workspace.conf` and check for any existing worktree entries matching the branch. Partition the standard repos into two lists:

- **Already has worktree**: repos that already have a `worktree:<repo>|<branch>` entry.
- **Available**: repos that don't have a worktree for this branch yet.

If **all standard repos already have worktrees** for this branch, tell the user and stop — there's nothing to create.

**c) Route: fresh vs. incremental.**

- **Fresh** (no existing worktrees for this branch): continue to step (d) below.
- **Incremental** (some repos already have worktrees): skip to the **Incremental add** path (section below).

**d) Which repos** — `AskUserQuestion` (multi-select) or free text (fresh path only).
Present the full list of standard repos:

> Which repos should get a worktree on `<branch>`?
> - **All repos** (recommended) — creates worktrees for every standard repo
> - **Select specific repos** — let me pick

If "specific", show a multi-select with the repo names. If the user already specified repos in their message, use those directly.

### 2. Confirm

Print a summary:

```
I'll create worktrees for branch '<branch>' in:
  - <repo1> → <repo1>--<sanitized-branch>/
  - <repo2> → <repo2>--<sanitized-branch>/

This will:
  1. Create the branch in each repo (if it doesn't exist)
  2. Create worktree directories
  3. Update workspace.conf and .gitignore
  4. Run bootstrap.sh to wire up .claude/ symlinks

Proceed? (yes / no / changes)
```

Wait for confirmation.

### 3. Execute

```sh
cd "<workspace-root>"
./worktree-create.sh "<branch>" <repo1> <repo2> ...
./bootstrap.sh
```

Stream output from both commands.

### 4. Verify and report

Run `./worktree-status.sh` and show the user the result. Highlight the newly created worktrees. Then print:

```
Worktrees ready. You can now work in:
  <repo1>--<sanitized-branch>/
  <repo2>--<sanitized-branch>/

These share git history with the source repos — commits are lightweight.
When done, commit in each worktree independently and open PRs per repo.
To clean up later: ask me to "remove worktrees for <branch>"
```

---

### Incremental add — Extending worktrees to additional repos

This path runs when worktrees for `<branch>` already exist for some repos and the user (or an agent) wants to add more. This commonly happens when agents discover mid-flight that another repo needs changes for the same feature.

#### 1. Show current state

Print what already exists:

```
Branch '<branch>' already has worktrees in this workspace:
  - <repo1>--<sanitized-branch>/ (exists)
  - <repo2>--<sanitized-branch>/ (exists)

Repos without a worktree for this branch:
  - <repo3>
  - <repo4>
```

#### 2. Which repos to add

If the user already specified which repos to add (e.g. "also create worktree for backend"), use those directly — don't re-ask. Otherwise, use `AskUserQuestion` (multi-select) with the **available** repos only:

> Which additional repos should get a worktree on `<branch>`?

Show only repos that don't already have a worktree for this branch.

#### 3. Confirm (lightweight)

```
I'll add worktrees for branch '<branch>' to:
  - <repo3> → <repo3>--<sanitized-branch>/

Existing worktrees are not affected.
Proceed? (yes / no)
```

Wait for confirmation.

#### 4. Execute

Same as the fresh path:

```sh
cd "<workspace-root>"
./worktree-create.sh "<branch>" <repo3> ...
./bootstrap.sh
```

The script skips repos that already have worktrees, so passing the full list is safe — but prefer passing only the new repos for clearer output.

#### 5. Verify and report

Run `./worktree-status.sh` and show the result. Then print:

```
Added worktree for '<branch>':
  - <repo3>--<sanitized-branch>/ (new)

All worktrees for this branch:
  - <repo1>--<sanitized-branch>/ (already existed)
  - <repo2>--<sanitized-branch>/ (already existed)
  - <repo3>--<sanitized-branch>/ (new)
```

---

## Worktree Status

Run:
```sh
cd "<workspace-root>" && ./worktree-status.sh
```

Present the output to the user. If any worktrees are dirty, highlight them. If any are ahead of their remote, suggest pushing.

---

## Worktree Remove

### 1. Gather inputs

**a) Branch name** — from the user's message or ask.

**b) Which repos** — if the user didn't specify, default to ALL worktrees matching that branch.

### 2. Safety check

Run `./worktree-status.sh` and check if any of the target worktrees are dirty. If so, warn:

```
WARNING: These worktrees have uncommitted changes:
  - <repo>--<branch>/ (3 files modified)

Options:
  - Commit changes first (I can help with that)
  - Stash changes
  - Force remove (changes will be lost!)
```

Use `AskUserQuestion` to let the user decide. Do NOT force-remove without explicit confirmation.

### 3. Check for unpushed commits

For each worktree, check if there are commits ahead of the remote:
```sh
git -C "<worktree-dir>" log --oneline @{upstream}..HEAD 2>/dev/null
```

If there are unpushed commits, warn the user and ask whether to push first.

### 4. Execute removal

```sh
cd "<workspace-root>"
./worktree-remove.sh "<branch>" <repo1> <repo2> ...
./bootstrap.sh
```

Stream output.

### 5. Report

```
Removed worktrees for '<branch>':
  - <repo1>--<branch>/ ✓
  - <repo2>--<branch>/ ✓

workspace.conf and .gitignore updated. Stale .claude/ symlinks pruned.

To also delete the local branches:
  git -C <repo1> branch -d <branch>
  git -C <repo2> branch -d <branch>

Want me to delete the local branches too? (yes / no)
```

If yes, run the branch delete commands.

---

## Pull All

Run:
```sh
cd "<workspace-root>" && ./pull-all.sh
```

Stream the output. If any pull fails (diverged history, not fast-forwardable), report which repos failed and suggest next steps (rebase, merge, etc.).

After pulling, ask if the user wants to run `./bootstrap.sh` in case any pulled changes added/removed agents.

---

## Worktree workflow details

### How worktrees are represented in workspace.conf

The extended pipe format supports three entry types:

```bash
REPOS=(
  # Standard clone (default branch)
  "web-app|git@github.com:acme/web-app.git"

  # Clone with specific branch
  "shared-lib|git@github.com:acme/shared-lib.git|v2"

  # Worktree: "dirname|worktree:<source-repo>|<branch>"
  "web-app--feature-auth|worktree:web-app|feature/auth"
  "api--feature-auth|worktree:api|feature/auth"
)
```

### worktree-create.sh behavior

When invoked with `./worktree-create.sh <branch> [repo1 repo2 ...]`:

1. If no repos specified, acts on ALL standard (non-worktree) repos.
2. For each repo: fetches latest, creates the branch if it doesn't exist (from `origin/<branch>` if available, else from HEAD).
3. Creates the worktree at `<repo>--<sanitized-branch>/`.
4. Appends worktree entries to `workspace.conf`.
5. Appends worktree dirs to `.gitignore`.
6. Prints instructions to run `./bootstrap.sh`.

### worktree-remove.sh behavior

When invoked with `./worktree-remove.sh <branch> [repo1 repo2 ...]`:

1. Checks for uncommitted changes — refuses to remove dirty worktrees.
2. Removes worktrees via `git worktree remove`.
3. Removes entries from `workspace.conf` and `.gitignore`.
4. Prints instructions to run `./bootstrap.sh` and optionally delete local branches.

### worktree-status.sh behavior

Prints a table of all repos and worktrees showing: directory name, type (clone/wt), current branch, and status (clean/dirty + ahead/behind).

---

## Constraints and edge cases

- **Never edit `bootstrap.sh`, `pull-all.sh`, or `worktree-*.sh` per workspace.** They are identical across every workspace; everything workspace-specific lives in `workspace.conf`.
- **Never delete `.git` directories or files.** If a sub-repo path exists with a different remote, ask before any destructive action. A `.git` file (not directory) indicates a worktree — treat it the same as a `.git` directory for detection purposes.
- **Do not commit `.claude/agents/` etc.** to the workspace shell — they are symlinks regenerated by `bootstrap.sh` and are gitignored by the template.
- **Worktree detection**: use `[ -d "$name/.git" ] || [ -f "$name/.git" ]` or `git -C "$name" rev-parse --git-dir` to detect both clones and worktrees.
- **Macros & cross-platform**: the shell scripts target `bash` (not POSIX `sh`) and use `find -exec test -e`, `shopt -s nullglob`, `ln -sfn`. These all work on macOS BSD tools and GNU/Linux. Do not switch to symlink commands that require GNU-only flags.
- **`${CLAUDE_PLUGIN_ROOT}`** is set by Claude Code when this skill runs; use it to read assets. If it isn't set, fall back to the path where this SKILL.md lives.
- **URL parsing**: handle both `git@host:owner/repo.git` and `https://host/owner/repo[.git]`. Strip query strings and fragments. If parsing yields an empty name, ask the user explicitly.
- **No emojis** in any generated file unless the user explicitly requests them.
- **Worktree source must be cloned first**: `bootstrap.sh` processes entries in order. Standard clones must appear before any worktree entries that reference them. `worktree-create.sh` enforces this by checking that the source repo exists before creating worktrees.

---

## What this skill does NOT do

- Add or remove repos from an existing workspace. For that, the user edits `workspace.conf` and reruns `./bootstrap.sh`.
- Set up Cursor `.cursor/rules/` aggregation. Cursor multi-root workspaces handle per-root rules natively; the generated `<Name>.code-workspace` is enough.
- Configure Claude Code agents. Agents must already be defined inside the sub-repos under `<repo>/.claude/agents/`.
- Auto-resolve auth issues. If a `git clone` fails for SSH or HTTPS, surface the error and stop.
- Merge git histories across repos. Each repo (and worktree) maintains its own independent git history — commits and PRs are managed per-repo.
- Auto-open PRs. It commits and pushes per-repo, but the user decides when to open PRs (or can ask Claude to do it via `gh pr create` in each worktree).
