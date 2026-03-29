# claude-code-template

Global Claude Code configuration with strict output rules, automated hooks, and reusable skills.

## What's included

- `CLAUDE.md` — global behavior rules (code-only output, minimal diffs, no noise)
- `settings.json` — hooks that run tests, lint, and security checks automatically after every file edit
- `skills/` — reusable execution patterns (test runner, lint, security scan, performance, minimal diff)
- `commands/` — slash commands that invoke skills manually
- `hooks/` — shell scripts executed by the hooks pipeline

## Install

**bash / zsh**

```bash
claude-init() { git clone --depth=1 https://github.com/oleksiikhodakivskyidev-ai/claude-code-template ~/.claude-tmp; rm -rf ~/.claude; mkdir -p ~/.claude; rsync -av --exclude ".git" --exclude "README.md" --exclude "LICENSE" ~/.claude-tmp/ ~/.claude/; rm -rf ~/.claude-tmp; chmod +x ~/.claude/hooks/*.sh; }; echo 'claude-init() { git clone --depth=1 https://github.com/oleksiikhodakivskyidev-ai/claude-code-template ~/.claude-tmp; rm -rf ~/.claude; mkdir -p ~/.claude; rsync -av --exclude ".git" --exclude "README.md" --exclude "LICENSE" ~/.claude-tmp/ ~/.claude/; rm -rf ~/.claude-tmp; chmod +x ~/.claude/hooks/*.sh; }' >> ~/.bashrc
```

**fish**

```fish
eval 'function claude-init; git clone --depth=1 https://github.com/oleksiikhodakivskyidev-ai/claude-code-template ~/.claude-tmp; rm -rf ~/.claude; mkdir -p ~/.claude; rsync -av --exclude ".git" --exclude "README.md" --exclude "LICENSE" ~/.claude-tmp/ ~/.claude/; rm -rf ~/.claude-tmp; chmod +x ~/.claude/hooks/*.sh; end'; funcsave claude-init
```

Then run:

```bash
claude-init
```

## Update

**bash / zsh**

```bash
claude-update() { git clone --depth=1 https://github.com/oleksiikhodakivskyidev-ai/claude-code-template ~/.claude-tmp; rsync -av --delete --exclude ".git" --exclude "README.md" --exclude "LICENSE" ~/.claude-tmp/ ~/.claude/; rm -rf ~/.claude-tmp; chmod +x ~/.claude/hooks/*.sh; }; echo 'claude-update() { git clone --depth=1 https://github.com/oleksiikhodakivskyidev-ai/claude-code-template ~/.claude-tmp; rsync -av --delete --exclude ".git" --exclude "README.md" --exclude "LICENSE" ~/.claude-tmp/ ~/.claude/; rm -rf ~/.claude-tmp; chmod +x ~/.claude/hooks/*.sh; }' >> ~/.bashrc
```

**fish**

```fish
eval 'function claude-update; git clone --depth=1 https://github.com/oleksiikhodakivskyidev-ai/claude-code-template ~/.claude-tmp; rsync -av --delete --exclude ".git" --exclude "README.md" --exclude "LICENSE" ~/.claude-tmp/ ~/.claude/; rm -rf ~/.claude-tmp; chmod +x ~/.claude/hooks/*.sh; end'; funcsave claude-update
```

Then run:

```bash
claude-update
```

## Slash commands

Invoke manually inside any Claude Code session:

| Command | What it does |
|---|---|
| `/tests` | Run test suite, fix failures |
| `/lint` | Run lint + typecheck, fix issues |
| `/security-scan` | Scan for security vulnerabilities |
| `/perf` | Detect performance issues |
| `/diff-check` | Enforce minimal diff on current changes |

## Automatic hooks

After every `Edit`, `Write`, or `NotebookEdit`:

1. `post-edit.sh` — runs tests + lint (blocking, must pass)
2. `security-check.sh` — runs secret and dependency scans (async, non-blocking)

Both run from the project working directory and auto-detect the stack (Node, Python, Go, PHP).
