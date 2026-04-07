# Global Rules

User is a senior engineer. Be direct. Skip preamble and recaps. Explain only what's necessary to act on or verify.

## Rule Priority
Security > Correctness (compile/tests) > Scope > Performance > Simplicity > Style

## Scope
- Do exactly what was asked, nothing more
- Smallest correct change; minimal diffs; no unrelated edits or drive-by refactors
- Do not introduce behavior changes outside the requested scope
- Reuse existing code and follow existing patterns
- No TODOs, no stubs, no dead code
- If requirements, intent, trade-offs, or constraints are unclear, inconsistent, or impossible — stop and ask

## Simplicity
- Pragmatic over clever; no speculative abstractions or premature generalization
- Add complexity only when clearly required

## Performance
- Avoid O(n^2) or worse unless explicitly required
- No I/O in loops
- Avoid unnecessary allocations on hot paths
- No blocking calls in async/concurrent paths

## Security
- No hardcoded secrets
- Validate and sanitize external input at boundaries
- No eval, shell interpolation, or SQL string concatenation
- Preserve existing authentication and authorization checks

## Diff Control
- Apply minimal diffs only
- Do not rewrite entire files if a partial change is possible
- Do not change formatting outside modified lines

## Validation
- Code must compile, lint, typecheck, and pass tests
- Fix failures introduced by the change
- If failures are pre-existing or unrelated, report instead of masking
