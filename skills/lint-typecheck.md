---
name: lint-typecheck
description: Detect the project's format, lint, and typecheck commands; run them in stage order; fix only the issues attributable to the current change.
---

# Lint & Typecheck

## Goal
Run format, lint, and typecheck checks; fix issues caused by the current change with minimal edits; leave the codebase in a clean state.

## Stage order
Always run in this order — each stage emits cheaper signal than the next:

1. **Format** — mechanical fixes (whitespace, quotes, import order). Auto-applies cleanly.
2. **Lint** — structural issues (unused vars, dead code, common bugs). Often auto-fixable; review before applying.
3. **Typecheck** — semantic correctness. Hardest to fix, never auto-fixable. Run after lint so structural noise is already cleared.
4. **Tests (conditional)** — if any auto-fix was applied in stages 1–2, re-run the project's tests via the test-runner skill to verify behavior is unchanged. Skip if no code-modifying changes were made (pure check runs, formatter no-ops).

**Stop on the first failing stage.** Fix all of that stage's issues before proceeding to the next. Do not run typecheck while lint is red — the noise wastes iterations and structural fixes often resolve type errors as a side effect.

**Do not run stages in parallel.** Each stage depends on the previous one (format normalizes whitespace before lint sees it; lint clears structural noise before typecheck sees it). Running format + lint concurrently produces interleaved output and can race on the same files.

If the project has a single canonical entry point (`just pre-commit`, `pre-commit run`, `npm run check`), prefer it — the project owner has chosen the order and tooling. **Canonical entry points are also typically what CI runs**, so using them gives local/CI parity by construction. Do not invent a different command set just because individual tools are available.

**Canonical vs scoped during iteration.** Canonical entry points win for the **initial scan** and the **final confirmation run**. The initial scan should use the canonical command (typically full-repo) unless it supports affected/scoped execution natively (e.g. `nx affected`, `turbo run --filter=...[origin/main]`, `pre-commit run --files`) — in which case use the scoped form. During the iteration fix loop, use scoped direct tools (file/directory granularity) even if a canonical command exists — a 3-minute full-repo `npm run check` defeats the purpose of scoped-first iteration.

## Detect, then run

**Canonical entry points (always prefer when present):**

| Marker                                       | Command                                                          |
|----------------------------------------------|------------------------------------------------------------------|
| `justfile` with a `pre-commit` recipe        | `just pre-commit`                                                |
| `.pre-commit-config.yaml`                    | `pre-commit run --all-files` (or `pre-commit run` for staged)    |
| `package.json` script `check`                | `<pm> run check` (npm/pnpm/yarn/bun)                             |
| `package.json` scripts `lint` + `typecheck`  | run both, in stage order                                         |

**Direct tools (when no canonical entry point exists):**

| Stack    | Format                                            | Lint                                                                 | Typecheck                                                                   |
|----------|---------------------------------------------------|----------------------------------------------------------------------|-----------------------------------------------------------------------------|
| Node/TS  | `prettier --check` / `biome format`               | `eslint .` / `biome lint .` / `oxlint`                               | `tsc --noEmit` / `tsc -b` / `vue-tsc` / `astro check` / `svelte-check`      |
| Python   | `ruff format --check` (or `black --check`)        | `ruff check`                                                         | `pyright` / `basedpyright` / `mypy`                                         |
| Rust     | `cargo fmt --check`                               | `cargo clippy --all-targets -- -D warnings`                          | (clippy already typechecks)                                                 |
| Go       | `gofmt -l .`                                      | `golangci-lint run` / `go vet ./...`                                 | `go build ./...`                                                            |
| Java/JVM | `mvn spotless:check` / `./gradlew spotlessCheck`  | `mvn checkstyle:check` / `./gradlew ktlintCheck` / `detekt`          | `mvn -q compile` / `./gradlew compileJava`                                  |
| .NET     | `dotnet format --verify-no-changes`               | `dotnet format analyzers --verify-no-changes`                        | `dotnet build --no-restore`                                                 |
| PHP      | `vendor/bin/php-cs-fixer fix --dry-run`           | `vendor/bin/phpstan` / `vendor/bin/psalm`                            | (phpstan / psalm cover both)                                                |

**Polyglot monorepos.** If multiple stacks are present (e.g. TS + Python in one repo) and there is no canonical entry point, do not run every linter for every stack. Instead:
1. Run `git diff HEAD --name-only` to see which files were touched
2. Pick the linters/typecheckers whose stack matches the touched files (`.py` → ruff/pyright, `.ts/.tsx` → eslint/tsc, `.go` → go vet, etc.)
3. If the touched files span multiple stacks, run each matching toolchain in turn
4. Editing one Python file should not trigger eslint+tsc

**Formatter / linter disambiguation.** When multiple tools of the same kind are installed (common mid-migration), pick the one whose **config file is present** — that is the source of truth:

| Signal                                                                                  | Tool to run     |
|-----------------------------------------------------------------------------------------|-----------------|
| `.prettierrc` / `.prettierrc.*` / `prettier.config.*` / `"prettier"` key in `package.json` | `prettier`      |
| `biome.json` / `biome.jsonc`                                                            | `biome`         |
| `eslint.config.*` / `.eslintrc.*`                                                       | `eslint`        |
| `[tool.ruff.format]` in `pyproject.toml`                                                | `ruff format`   |
| `[tool.black]` in `pyproject.toml`                                                      | `black`         |
| `[tool.ruff]` (lint section) in `pyproject.toml` / `ruff.toml`                          | `ruff check`    |

If only `.editorconfig` is present, respect the existing tool — do not introduce a new formatter. If multiple config files coexist (e.g. both `.prettierrc` and `biome.json`), stop and ask which is canonical rather than guessing.

**Use the project's package manager prefix.** Pick the prefix from the lockfile, never invoke globally when a manifest indicates a manager:

| Lockfile / marker                          | Prefix                |
|--------------------------------------------|-----------------------|
| `uv.lock`                                  | `uv run <tool>`       |
| `poetry.lock`                              | `poetry run <tool>`   |
| `pnpm-lock.yaml` / `pnpm-workspace.yaml`   | `pnpm exec <tool>`    |
| `yarn.lock`                                | `yarn <tool>`         |
| `bun.lockb`                                | `bun x <tool>`        |
| `package-lock.json`                        | `npx <tool>`          |

## Monorepo strategies
If the repo uses a monorepo orchestrator, **prefer affected-only commands** over full-repo runs — they understand the dependency graph and only re-check what changed:

| Marker / tool                              | Affected-only command                                       | Full-repo command                  |
|--------------------------------------------|--------------------------------------------------------------|-------------------------------------|
| `nx.json`                                  | `nx affected -t lint`, `nx affected -t typecheck`            | `nx run-many -t lint`               |
| `turbo.json`                               | `turbo run lint --filter=...[origin/main]`                   | `turbo run lint`                    |
| `pnpm-workspace.yaml`                      | `pnpm --filter ...[origin/main] lint`                        | `pnpm -r lint`                      |
| `yarn.lock` + workspaces                   | `yarn workspaces foreach -A --since run lint`                | `yarn workspaces foreach -A run lint` |
| `lerna.json`                               | `lerna run lint --since`                                     | `lerna run lint`                    |
| TypeScript project references (`tsc -b`)   | `tsc -b path/to/changed/tsconfig.json`                       | `tsc -b`                            |

**Rules:**
- In monorepos, never run a full-repo command during the iteration loop — it's slow and wastes context. Use affected-only.
- TypeScript project references (`"references": [...]` in `tsconfig.json`) require `tsc -b` (build mode), not `tsc --noEmit`. `tsc -b` is incremental and respects the dependency graph.
- For per-package work, also pass the package's own `tsconfig.json`: `tsc --noEmit -p packages/foo/tsconfig.json`.
- nx and turbo handle caching automatically — re-runs of unchanged code are near-instant. Trust the cache; do not bypass it without reason.

## Scoped-first fix loop
Iterate from narrowest scope outward. Most lint tools accept file or directory paths and give sub-second feedback at file scope.

**Scope tiers (fastest → broadest):**

1. **Single file** — feedback in <1s for most tools
2. **Affected directory / package** — for cross-file rules (unused exports, circular deps)
3. **Whole project** — final confirmation pass only

**Filter syntax by tool:**

| Tool          | Single file                                    | Directory / package                          |
|---------------|------------------------------------------------|----------------------------------------------|
| eslint        | `eslint path/to/file.ts`                       | `eslint path/to/dir`                         |
| prettier      | `prettier --check path/to/file.ts`             | `prettier --check 'path/to/dir/**'`          |
| biome         | `biome check path/to/file.ts`                  | `biome check path/to/dir`                    |
| ruff          | `ruff check path/to/file.py`                   | `ruff check path/to/dir`                     |
| pyright       | `pyright path/to/file.py`                      | `pyright path/to/dir`                        |
| mypy          | `mypy path/to/file.py`                         | `mypy path/to/dir`                           |
| tsc           | (no per-file mode — use `-p`)                  | `tsc --noEmit -p path/to/tsconfig.json`      |
| cargo clippy  | (per-crate only)                               | `cargo clippy -p <crate>`                    |
| go vet        | `go vet ./pkg/foo/...`                         | `go vet ./pkg/foo/...`                       |
| pre-commit    | `pre-commit run --files file1 file2`           | `pre-commit run --files <glob>`              |

**Loop:**
1. Identify the issues from the first run at the right scope (file if you only touched one file; directory if multiple)
2. Fix at the narrowest tier
3. Widen one tier and re-run to catch interactions; repeat
4. Final pass: full project. Done when clean.

## Auto-fix policy

**Concrete flags by tool:**

| Tool                | Preview / dry-run                       | Apply                              |
|---------------------|------------------------------------------|------------------------------------|
| eslint              | `eslint --fix-dry-run`                   | `eslint --fix`                     |
| prettier            | `prettier --check`                       | `prettier --write`                 |
| biome               | `biome check`                            | `biome check --write`              |
| ruff (lint)         | `ruff check --diff`                      | `ruff check --fix`                 |
| ruff (format)       | `ruff format --diff`                     | `ruff format`                      |
| black               | `black --check --diff`                   | `black`                            |
| gofmt               | `gofmt -d`                               | `gofmt -w`                         |
| cargo fmt           | `cargo fmt --check`                      | `cargo fmt`                        |
| dotnet format       | `dotnet format --verify-no-changes`      | `dotnet format`                    |

**Rules:**
- **Formatters** (prettier, black, ruff format, gofmt, cargo fmt, dotnet format): apply directly. Whitespace-only changes are safe.
- **Linters with `--fix`**: preview first when the changeset is non-trivial. Auto-fixers occasionally rewrite code in surprising ways:
  - eslint `prefer-const` can convert mutable refs incorrectly
  - eslint `no-unused-imports` can remove imports needed for side effects
  - ruff `I001` reorders imports across `# noqa` boundaries
  - eslint `no-useless-return` can remove early returns inside loops
- After applying any auto-fix, **re-run tests**. Auto-fixed code can change behavior.
- Never chain `--fix` across the whole repo without review — scope to changed files only.

## Performance helpers
The biggest speedup is the scoped-first fix loop above (file → directory → project). For repeated runs at the same scope, use these:

- **eslint**: `eslint --cache` — caches successful files; subsequent runs only re-check changed files. Safe for iterative fix loops.
- **tsc**: `tsc -b` (build mode) is incremental and uses `.tsbuildinfo` to skip unchanged files. Required for project references; recommended even for single-package TS projects.
- **biome**: `biome check` is already incremental; no flag needed.
- **ruff**: already fast enough that caching is unnecessary; `ruff check --watch` exists for live mode if iterating heavily.
- **nx / turbo**: caching is automatic and remote-cache-aware. Don't pass `--skip-nx-cache` or `--force` unless investigating cache poisoning.

If a single tool run is taking >30s on a small change, the scope is probably too broad — narrow it before reaching for caching flags.

## Issue attribution
- "Current change" = `git diff HEAD` (staged + unstaged); on a feature branch also `git diff <base>...HEAD`
- Fix issues introduced by the current change
- Pre-existing issues unrelated to the change → report, do not fix
- Do not run `--fix` on the whole repo to mass-fix legacy issues — that bloats the diff and breaks attribution

## Type errors: how to fix them
Type errors must be fixed properly when the type system can express the right shape. Three principles, in priority order:

1. **Fix root cause, not leaf errors.** If the same wrong type propagates through 5 call sites and each errors, fix the source (the function signature, the schema, the cast at the boundary), not the 5 sites. One leaf fix often masks 4 real bugs.
2. **Prefer narrowing over assertions.** Use the language's narrowing primitives — `if (x)`, type guards, discriminated unions, `isinstance()`, pattern matching — over assertions (`x as Foo`, `cast(Foo, x)`). Narrowing lets the type checker verify; assertions disable it.
3. **Don't widen types upstream to hide a downstream error.** If function `A` returns `string | undefined` and caller `B` can't handle `undefined`, the wrong fix is to change `A` to return `string`. The right fix is to handle `undefined` in `B`. Widening upstream silently hides every other consumer's bug too.

**Escape hatches** are allowed only in these cases, and **each one requires a comment with the reason**:

- **Truly dynamic data** (parsed JSON without a schema, untyped third-party return values): use `any` / `Any` / `unknown` with a comment explaining why a precise type is unavailable
- **Known false positive in the type checker**: use a *coded* ignore — `# type: ignore[attr-defined]`, `// @ts-expect-error: <reason>`. Never bare `# type: ignore` or `// @ts-ignore`
- **TypeScript**: prefer `@ts-expect-error` over `@ts-ignore` — it auto-errors when the underlying issue is fixed, preventing stale suppressions
- **Python**: prefer `cast()` over `# type: ignore` when the runtime value is known correct but the inference is too narrow

If the right fix isn't clear, stop and ask — do not paper over with an escape hatch.

## Constraints
- No skipping or disabling rules to make checks pass
- No global config edits (`.eslintrc`, `pyproject.toml [tool.ruff]`, `tsconfig.json`) to silence rules unless explicitly asked
- No tool installation unless explicitly asked
- If the project has no lint/typecheck configuration → do nothing (do not introduce one)

## Reporting
When reporting issues, include: `file:line`, the rule code (e.g., `no-unused-vars`, `E501`, `TS2322`), and a one-line message. Group by file when reporting multiple.
