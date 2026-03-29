---
name: lint-typecheck
description: Run linting, formatting, and type checks; fix issues and ensure clean state with minimal changes.
---

# Lint & Typecheck

## Goal
Ensure code passes lint, format, and type checks with minimal valid changes.

---

## Command Discovery (priority order)

1. `just pre-commit`
2. `pre-commit run --all-files`

3. Node (package.json scripts, in order):
   - `npm run lint`
   - `npm run typecheck`
   - `npm run check`
   - `npm run format`

4. Node (tool fallback):
   - `biome check .`
   - `eslint .`
   - `tsc --noEmit`

5. Python:
   - `ruff check`
   - `black --check`
   - `mypy`

6. PHP:
   - `vendor/bin/php-cs-fixer fix`
   - `vendor/bin/phpstan`

7. Go:
   - `golangci-lint run`

---

## Execution Rules

- Run from repository root
- Prefer a **single command** if available (`just pre-commit` or `pre-commit`)
- Do not run multiple tools redundantly
- Only execute commands that clearly exist

---

## Fix Strategy

### Formatting
- Use auto-fix tools when available
- Do not manually reformat unnecessarily

### Linting
- Fix root cause
- Do not disable rules unless required

### Type errors
- Fix properly
- Avoid bypasses (`any`, ignores)

---

## Fix Loop

1. Run command
2. Fix issues
3. Re-run
4. Repeat until success

---

## Constraints

- No skipping checks
- No weakening rules to pass
- No unrelated refactors
- No tool installation unless required

---

## Fallback Behavior

- If no lint/typecheck system exists → do nothing
- Do not introduce new tools

---

## Output Rules

- Follow CLAUDE.md strictly
- Minimal diffs only
