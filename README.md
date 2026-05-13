# virtual-workspace

A plugin that creates **virtual multi-repo workspaces** with **synchronized worktree support** for cross-repo feature development. Works with **Claude Code** and **Codex**.

AI coding assistants like Claude Code and Codex load configs (agents, commands, skills, hooks) only from the working directory they were launched from — they do **not** merge configs across sibling repos. This plugin creates a thin "workspace shell" that hosts multiple sibling git repos and symlinks each repo's config directories into a unified layout, so a single session sees the union of all of them:

- **Claude Code**: `.claude/{agents,commands,skills,hooks}/*`
- **Codex**: `.codex/{agents,skills}/*`

## Features

- **Unified AI assistant session** — agents, commands, skills, and hooks from all repos available in one session
- **Works with Claude Code and Codex** — symlinks both `.claude/` and `.codex/` config directories
- **Worktree-based feature branches** — create synchronized feature branches across multiple repos with lightweight git worktrees
- **Incremental worktree expansion** — add repos to an existing feature branch mid-flight without disrupting work already in progress
- **Status dashboard** — see branch, dirty state, and ahead/behind tracking across all repos and worktrees at a glance
- **Self-sufficient workspaces** — generated workspaces run standalone; the plugin is only needed for initial creation

## What you get

When invoked, the `virtual-workspace` skill walks you through naming the workspace, listing repo URLs, and picking a parent directory. It generates:

```
<Name>/
├── workspace.conf              # source of truth: list of sub-repos and worktrees
├── bootstrap.sh                # clones repos, creates worktrees, (re)builds symlinks
├── assistant-support.sh        # mirror repo-local config when adding Codex or Claude Code later
├── pull-all.sh                 # fast-forward pull every sub-repo and worktree
├── worktree-create.sh          # create worktrees for a feature branch across repos
├── worktree-remove.sh          # clean up worktrees when a feature is merged
├── worktree-status.sh          # show branch + dirty state for all repos and worktrees
├── CLAUDE.md                   # workspace conventions (Claude Code)
├── AGENTS.md                   # workspace conventions (Codex)
├── README.md                   # human-facing setup guide
├── .gitignore                  # excludes sub-repos, worktrees, and generated symlinks
└── <Name>.code-workspace       # multi-root file for VS Code / Cursor
```

It runs `bootstrap.sh` for you (cloning repos, creating symlinks), and optionally pushes the workspace shell to a new GitHub repo.

After setup, `cd <Name> && claude` (or `codex`) starts a session that sees every sub-repo's agents in one place.

If you add one assistant CLI after the workspace already exists, run `./assistant-support.sh codex`, `./assistant-support.sh claude`, or `./assistant-support.sh both`. It mirrors repo-local config into the missing layout and reruns `./bootstrap.sh`.

## Install

### Claude Code

```sh
/plugin marketplace add https://github.com/filipealva/virtual-workspace
/plugin install virtual-workspace@filipealva
```

Restart your session, then trigger the skill:

> Create a virtual workspace with `<repo-url-1>` and `<repo-url-2>`

Or invoke it directly with `/virtual-workspace`.

### Codex

```sh
codex plugin marketplace add filipealva/virtual-workspace
```

Then use the `$virtual-workspace` skill in a Codex session.

### Manual install

```sh
git clone https://github.com/filipealva/virtual-workspace /tmp/vw

# Claude Code
mkdir -p ~/.claude/skills
cp -r /tmp/vw/skills/virtual-workspace ~/.claude/skills/

# Codex
mkdir -p ~/.codex/skills
cp -r /tmp/vw/skills/virtual-workspace ~/.codex/skills/
```

## Multi-repo feature development with worktrees

The worktree system is the core workflow for cross-repo features. It uses [git worktrees](https://git-scm.com/docs/git-worktree) to create lightweight checked-out copies of each repo on a shared feature branch — no full re-clone needed.

### Creating worktrees

Create worktrees for a feature branch across all repos, or a specific subset:

```sh
# All repos
./worktree-create.sh feature/payments

# Specific repos only
./worktree-create.sh feature/payments web-app api
```

This will:
1. Fetch the latest from each repo's remote.
2. Create the branch in each repo if it doesn't exist (from `origin/<branch>` if available, otherwise from HEAD).
3. Create worktree directories named `<repo>--<sanitized-branch>/` at the workspace root.
4. Append worktree entries to `workspace.conf` and `.gitignore`.

After creating worktrees, run `./bootstrap.sh` to wire up `.claude/` and `.codex/` symlinks for the new directories.

## Adding Claude Code or Codex after setup

Older workspaces, or workspaces that started with only one assistant's repo-local config, can be upgraded in place:

```sh
# Add Codex config from existing Claude Code config
./assistant-support.sh codex

# Add Claude Code config from existing Codex config
./assistant-support.sh claude

# Sync both directions
./assistant-support.sh both
```

The helper updates each checked-out repo declared in `workspace.conf`:

- `codex` copies `.claude/agents/*.md` to `.codex/agents/` and converts `.claude/skills/*.md` to `.codex/skills/<name>/SKILL.md`.
- `claude` copies `.codex/agents/*.md` to `.claude/agents/` and copies `.codex/skills/<name>/` to `.claude/skills/<name>/`.
- `both` runs both directions.

It then runs `./bootstrap.sh`, which links `.claude/{agents,commands,skills,hooks}` and `.codex/{agents,skills}` into the workspace root. If duplicate names exist across repos, later entries in `workspace.conf` win.

### Incremental worktree expansion

When you discover mid-feature that another repo needs changes, add it without disrupting existing worktrees:

```sh
# Backend worktrees already exist for feature/payments, now add shared-lib
./worktree-create.sh feature/payments shared-lib
./bootstrap.sh
```

The script detects existing worktrees and skips them — only new repos get worktrees created. You can also use the `/virtual-workspace` skill conversationally:

> Also create a worktree for shared-lib on feature/payments

### Checking status

See the state of every repo and worktree at a glance:

```sh
./worktree-status.sh
```

Output:

```
DIRECTORY                      TYPE     BRANCH                    STATUS
---------                      ----     ------                    ------
web-app                        clone    main                      clean
api                            clone    main                      clean
shared-lib                     clone    main                      clean
web-app--feature-payments      wt       feature/payments          dirty (2 files) [+3/-0]
api--feature-payments          wt       feature/payments          clean [+1/-0]
shared-lib--feature-payments   wt       feature/payments          clean
```

Shows: directory name, type (clone vs. worktree), current branch, dirty file count, and commits ahead/behind the remote tracking branch.

### Removing worktrees

When a feature is merged and worktrees are no longer needed:

```sh
# Remove all worktrees for the branch
./worktree-remove.sh feature/payments

# Or specific repos only
./worktree-remove.sh feature/payments web-app

# Then prune stale symlinks
./bootstrap.sh
```

The script refuses to remove worktrees with uncommitted changes — commit or stash first. After removal, it prints commands to optionally delete the local branches.

### How worktrees are tracked

Worktrees are declared in `workspace.conf` using an extended pipe format:

```bash
REPOS=(
  # Standard clone (default branch)
  "web-app|git@github.com:acme/web-app.git"

  # Clone with specific branch
  "shared-lib|git@github.com:acme/shared-lib.git|v2"

  # Worktree entries (managed by worktree-create.sh / worktree-remove.sh)
  "web-app--feature-payments|worktree:web-app|feature/payments"
  "api--feature-payments|worktree:api|feature/payments"
)
```

Standard clones must appear before any worktree entries that reference them. `bootstrap.sh` processes entries in order and handles both types: cloning repos and creating worktrees as needed.

### Committing and opening PRs

Each worktree has its own working tree with independent staging. Commit and push from each worktree separately:

```sh
cd web-app--feature-payments
git add -A && git commit -m "Add payment form"
git push -u origin feature/payments

cd ../api--feature-payments
git add -A && git commit -m "Add payment endpoint"
git push -u origin feature/payments
```

Open PRs per repo — the plugin does not auto-merge across repos. You can ask your AI assistant to help with `gh pr create` in each worktree.

## Updating repos

Pull the latest changes across all repos and worktrees:

```sh
./pull-all.sh
```

Uses `--ff-only` for safety. If a pull isn't fast-forwardable (diverged history), it reports the failure and you can rebase or merge manually.

## Maintaining a generated workspace

Generated workspaces are self-sufficient — you don't need this plugin installed to use them. To add or remove a sub-repo:

1. Edit `workspace.conf` — append `"name|git-url"` or remove an entry.
2. Update `.gitignore` and the `.code-workspace` file if needed.
3. Run `./bootstrap.sh`.

When agents, commands, skills, or hooks change inside a sub-repo (added, renamed, or removed), rerun `./bootstrap.sh` — it prunes stale symlinks and recreates them.

## Why a "workspace shell"?

Each sub-repo is gitignored by the workspace shell, so the shell never tracks code from the actual projects. It only owns the cross-repo glue. The result is a clean separation:

- **Sub-repos** stay normal. Coworkers who only work on one repo ignore the workspace shell entirely; agents committed to each repo's `.claude/agents/`, `.codex/agents/`, or `.codex/skills/` load natively when they `cd` into that repo.
- **Workspace shell** is a one-time setup for people who regularly work across multiple repos in a single AI assistant session.
- **Worktrees** share git history with their source repo — they are lightweight and don't duplicate the object store.

## Limitations

- AI coding assistants have no built-in multi-repo config merging. This plugin is a workaround using symlinks, not a wrapper around an official mechanism.
- The shell scripts target `bash` (not POSIX `sh`) and use macOS-compatible commands. They work on both macOS and GNU/Linux.
- Worktree source repos must be cloned before worktrees can be created from them — `bootstrap.sh` enforces ordering.

## License

MIT
