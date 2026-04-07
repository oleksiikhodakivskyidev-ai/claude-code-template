---
name: test-runner
description: Detect the project's test command, run it, and fix failures attributable to the current change with minimal edits.
---

# Test Runner

## Goal
Run the test suite, fix failures caused by the current change, and leave the suite green.

## Detect, then run
Pick the first command whose marker file exists:

| Marker                                   | Command                                                    |
|------------------------------------------|------------------------------------------------------------|
| `justfile`                               | `just test`                                                |
| `Makefile` with a `test` target          | `make test`                                                |
| `pnpm-workspace.yaml` / `pnpm-lock.yaml` | `pnpm test`; fallback `pnpm -r test` if root has no script |
| `yarn.lock`                              | `yarn test`; fallback `yarn workspaces foreach run test`   |
| `bun.lockb`                              | `bun test`                                                 |
| `package.json`                           | `npm test`                                                 |
| `uv.lock`                                | `uv run pytest`                                            |
| `poetry.lock`                            | `poetry run pytest`                                        |
| `pyproject.toml` / `pytest.ini`          | `pytest`                                                   |
| `Cargo.toml`                             | `cargo test`                                               |
| `go.mod`                                 | `go test ./...`                                            |
| `pom.xml`                                | `mvn -q test` (prefer `./mvnw` if present)                 |
| `build.gradle` / `build.gradle.kts`      | `gradle test --quiet` (prefer `./gradlew` if present)      |
| `*.sln` / `*.csproj`                     | `dotnet test --nologo --verbosity quiet`                   |
| `composer.json`                          | `vendor/bin/pest` → `vendor/bin/phpunit` → `composer test` |

`just` / `make` always win when present — they are the project owner's canonical entry point.

Run from the repository root.

**Polyglot monorepos.** If multiple markers match and there is no `just`/`make` entry point, do not blindly take the first row. Instead:
1. Run `git diff HEAD --name-only` to see which files were touched
2. Pick the runner whose language matches the touched files (`.py` → pytest stack, `.ts/.js` → node stack, `.go` → go, etc.)
3. If the touched files span multiple languages, run each matching runner in turn
4. Prefer workspace-aware commands (`pnpm -r test`, `cargo test --workspace`, `go test ./...`) over single-package fallbacks

## Scoped-first fix loop
Iterate from the narrowest scope outward. Only widen when the narrower scope is green. Do not invent flags — use the framework's native filter syntax.

**Scope tiers (fastest → broadest):**

1. **Single test name** — fastest feedback while iterating
2. **Single test file** — when the failure isn't isolated to one test
3. **Affected package / module** — for cross-test interactions inside one component (workspaces, monorepos)
4. **Whole suite** — final confirmation pass only

**Filter syntax by framework:**

| Framework      | Single test name                                                       | Affected package / module                       |
|----------------|------------------------------------------------------------------------|-------------------------------------------------|
| pytest         | `pytest path/to/test_file.py::test_name`                               | `pytest path/to/pkg/`                           |
| jest           | `jest path/to/file.test.ts -t "test name"`                             | `jest path/to/pkg/`                             |
| vitest         | `vitest run path/to/file.test.ts -t "test name"`                       | `vitest run path/to/pkg/`                       |
| mocha          | `mocha path/to/file.spec.ts --grep "test name"`                        | `mocha "path/to/pkg/**/*.spec.ts"`              |
| pnpm workspace | (delegate to underlying runner)                                        | `pnpm --filter <pkg> test`                      |
| go test        | `go test -run TestName ./pkg/...`                                      | `go test ./pkg/...`                             |
| cargo test     | `cargo test test_name`                                                 | `cargo test -p <crate>`                         |
| phpunit / pest | `vendor/bin/phpunit --filter testName` / `vendor/bin/pest --filter`    | `vendor/bin/phpunit tests/Pkg/`                 |
| mvn            | `mvn -Dtest=ClassName#methodName test`                                 | `mvn -pl <module> test`                         |
| gradle         | `gradle test --tests Class.method`                                     | `./gradlew :<module>:test`                      |
| dotnet test    | `dotnet test --filter "FullyQualifiedName~TestName"`                   | `dotnet test path/to/Project.csproj`            |

**Loop:**
1. Identify the failing test(s) from the first full-suite run
2. Re-run at the narrowest tier that reproduces the failure
3. Iterate fixes at that tier until green
4. Widen one tier and re-run to catch interactions; repeat
5. Final pass: full suite. Done when green.

## Failure attribution
- "Current change" = `git diff HEAD` (staged + unstaged). On a feature branch, also consider `git diff <base>...HEAD` for cumulative scope.
- Failures caused by the current change → fix
- Pre-existing failures unrelated to the change → report, do not fix or mask
- If unsure whether a failure is pre-existing, check `git stash` + re-run, or inspect `git blame` on the failing assertion
- If failures indicate missing environment or stale build inputs → report and stop. Do not patch product or test code to mask a setup problem. Common cases:
  - Infra: DB unreachable, env var unset, network unavailable, missing fixture file
  - Migrations: schema drift, unapplied migrations, "relation does not exist"
  - Generated code: stale protobuf/gRPC stubs, stale Prisma/SQLAlchemy/Drizzle clients, stale GraphQL codegen, stale OpenAPI clients — surface as type/import errors that look like real bugs but are fixed by re-running codegen, not by editing code
- If the runner exits successfully but reports zero tests collected/run → treat as a configuration issue and report. Do not declare success.

## Flakes and hangs
- If a failure looks non-deterministic (timing, network, ordering), re-run that test once. If it fails again, treat as real.
- "No progress" = no new stdout/stderr lines for ~2 minutes. If a run hits that, abort and report — do not sit blocked. Investigate the hang separately rather than retrying.

## Fix policy
- Prefer fixing product code; update tests only when the change intentionally altered the tested behavior
- If both sides are plausible, or the failing test is in an area unrelated to the current change, stop and ask — do not guess
- Modifying both product and test in the same change is allowed when:
  - API / schema / contract change (signature, route, response shape)
  - Renamed symbol or interface
  - Intentional behavior change explicitly described in the task
- Outside those cases, prefer one side; stop and ask if both seem necessary
- No skipping, disabling, or weakening assertions
- No unrelated refactors

## Reporting
When reporting a failure, include: test name, assertion message, and `file:line`. Skip stack frames from third-party code.
