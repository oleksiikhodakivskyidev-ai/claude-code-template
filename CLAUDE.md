# Project Rules

## Output (CRITICAL)
- Output ONLY code changes
- No explanations
- No summaries
- No justifications
- No commentary
- No markdown outside code
- No comments inside code unless explicitly requested
- No example usage unless explicitly requested
- No documentation files unless explicitly requested
- If no changes are required → output nothing

## Behavior (CRITICAL)
- Follow instructions exactly
- Do not infer additional requirements
- Do not expand scope
- Prefer smallest valid solution
- Prefer simple implementations unless requirements clearly demand complexity

## Code Quality (IMPORTANT)
- Code must compile
- Code must pass tests
- Code must pass lint and type checks
- No TODOs
- No incomplete implementations

## Performance (CRITICAL)
- Avoid O(n^2) or worse complexity unless required
- Avoid repeated I/O (DB/API) inside loops
- Avoid unnecessary memory allocations or large copies
- Prefer efficient data structures
- Avoid blocking operations in async/concurrent code

## Diff Control (CRITICAL)
- Apply minimal diffs only
- Do not rewrite entire files if partial change is possible
- Do not modify unrelated code
- Do not refactor unless explicitly required
- Do not change formatting outside modified lines

## Implementation Strategy
- Modify only necessary files
- Avoid large refactors
- Reuse existing code
- Follow existing patterns exactly

## Token Efficiency (CRITICAL)
- Do not repeat prompt content
- Do not restate requirements
- Avoid redundant output
- Prefer minimal diffs over full rewrites

## Testing & Validation (CRITICAL)
- Ensure all tests pass before finishing
- If tests fail, fix them
- Ensure lint passes
- Ensure typecheck passes
- Fix failures automatically

## Security (CRITICAL)
- Do not introduce hardcoded secrets
- Validate and sanitize all external input
- Avoid unsafe dynamic execution (eval, shell, SQL string concat)
- Enforce proper authentication and authorization checks

## Constraints
- Assume user is senior engineer
- No educational explanations
- No simplifications
