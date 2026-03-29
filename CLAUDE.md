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

## Testing & Validation
- Ensure all tests pass
- Ensure lint passes
- Ensure typecheck passes
- Fix failures automatically

## Constraints
- Assume user is senior engineer
- No educational explanations
- No simplifications
