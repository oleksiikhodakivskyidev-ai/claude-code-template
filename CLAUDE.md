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

## Advisor Tool

The advisor should respond in under 100 words and use enumerated steps, not explanations.

You have access to an `advisor` tool backed by a stronger reviewer model. It takes NO parameters — when you call advisor(), your entire conversation history is automatically forwarded. They see the task, every tool call you've made, every result you've seen.

Call advisor BEFORE substantive work — before writing, before committing to an interpretation, before building on an assumption. If the task requires orientation first (finding files, fetching a source, seeing what's there), do that, then call advisor. Orientation is not substantive work. Writing, editing, and declaring an answer are.

Also call advisor:
- When you believe the task is complete. BEFORE this call, make your deliverable durable: write the file, save the result, commit the change. The advisor call takes time; if the session ends during it, a durable result persists and an unwritten one doesn't.
- When stuck — errors recurring, approach not converging, results that don't fit.
- When considering a change of approach.

On tasks longer than a few steps, call advisor at least once before committing to an approach and once before declaring done. On short reactive tasks where the next action is dictated by tool output you just read, you don't need to keep calling — the advisor adds most of its value on the first call, before the approach crystallizes.

Give the advice serious weight. If you follow a step and it fails empirically, or you have primary-source evidence that contradicts a specific claim (the file says X, the paper states Y), adapt. A passing self-test is not evidence the advice is wrong — it's evidence your test doesn't check what the advice is checking.

If you've already retrieved data pointing one way and the advisor points another: don't silently switch. Surface the conflict in one more advisor call — "I found X, you suggest Y, which constraint breaks the tie?" The advisor saw your evidence but may have underweighted it; a reconcile call is cheaper than committing to the wrong branch.

### Effort settings
- Sonnet executor at medium effort + Opus advisor ≈ Sonnet at default effort, at lower cost.
- For maximum intelligence, keep the executor at default effort.

### Cost control
- Count advisor calls client-side. When you reach your cap, remove the advisor tool from `tools` **and** strip all `advisor_tool_result` blocks from message history (omitting either causes a `400 invalid_request_error`).
- Enable `caching` only when expecting three or more advisor calls per conversation.

### Limitations
- Advisor output does not stream — expect a pause while the sub-inference runs.
- No built-in conversation-level cap on advisor calls — track and cap client-side.
- `max_tokens` applies to executor output only; it does not bound advisor tokens.
- Anthropic Priority Tier is per model — executor's tier does not extend to the advisor.
