# claude-virtual-workspace

A Claude Code plugin that creates **virtual multi-repo workspaces** for Claude Code.

Claude Code loads `.claude/` configs (agents, commands, skills, hooks) only from the working directory it was launched from — it does **not** merge configs across sibling repos. This plugin packages the canonical workaround: a thin "workspace shell" that hosts multiple sibling git repos and symlinks each repo's `.claude/{agents,commands,skills,hooks}/*` into a unified workspace `.claude/` so a single Claude Code session sees the union of all of them.

## What you get

When invoked, the `virtual-workspace` skill walks you through:

1. Naming the workspace.
2. Listing the git URLs of the repos you want included.
3. Picking a parent directory.

Then it generates the canonical scaffolding at `<parent>/<Name>/`:

```
<Name>/
├── workspace.conf              # source of truth: list of sub-repos
├── bootstrap.sh                # clones missing repos + (re)builds .claude/ symlinks
├── pull-all.sh                 # fast-forward pull every sub-repo
├── CLAUDE.md                   # Claude Code conventions for the workspace
├── README.md                   # human-facing setup guide
├── .gitignore                  # excludes sub-repos and generated symlinks
└── <Name>.code-workspace       # multi-root file for VS Code / Cursor
```

It runs `bootstrap.sh` for you (cloning any missing repos, creating symlinks), and optionally pushes the workspace shell to a new GitHub repo so teammates can clone it.

After setup, `cd <Name> && claude` starts a session that sees every sub-repo's agents in one place.

## Install

### Recommended: via the marketplace

```sh
/plugin marketplace add https://github.com/filipealva/claude-virtual-workspace
/plugin install virtual-workspace@filipealva
```

Restart your Claude Code session. Then trigger the skill by saying something like:

> Create a virtual workspace with `<repo-url-1>` and `<repo-url-2>`

…or invoke it directly:

```
/virtual-workspace:create
```

### Manual install (no marketplace)

```sh
git clone https://github.com/filipealva/claude-virtual-workspace /tmp/cvw
mkdir -p ~/.claude/skills
cp -r /tmp/cvw/skills/virtual-workspace ~/.claude/skills/
```

## Maintaining a generated workspace

The generated workspace is self-sufficient — you don't need this plugin installed to use it. The `bootstrap.sh` it ships with is plain bash that reads `workspace.conf`. To add or remove a sub-repo:

1. Edit `workspace.conf`.
2. Update `.gitignore` and the `.code-workspace` if needed.
3. Run `./bootstrap.sh`.

That's it.

## Why a "workspace shell"?

Each sub-repo is gitignored by the workspace shell, so the shell never tracks code from the actual projects. It only owns the cross-repo glue. The result is a clean separation:

- **Sub-repos** stay normal. Coworkers who only work on one of them ignore the workspace shell entirely; agents committed to each repo's `.claude/agents/` load natively when they `cd` into that repo.
- **Workspace shell** is a one-time setup for people who regularly work across multiple repos in a single Claude session.

## Limitations

Claude Code has no built-in feature to merge `.claude/` across sibling roots — confirmed against current docs. This plugin is a workaround, not a wrapper around an official mechanism. If Claude Code adds native multi-repo support in the future, the symlink approach can be retired.

## License

MIT
