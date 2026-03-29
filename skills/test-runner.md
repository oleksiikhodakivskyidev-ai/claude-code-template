---
name: test-runner
description: Run project tests, fix failures, and ensure full test suite passes using minimal changes.
---

# Test Runner

## Goal
Ensure the full test suite passes with minimal, correct changes.

---

## Test Command Discovery (priority order)

1. `just test`
2. `make test`
3. PHP (`vendor/bin/pest`, `vendor/bin/phpunit`, `composer test`)
4. Node (`npm test`)
5. Python (`pytest`)
6. Go (`go test ./...`)

Use the first valid command only.

---

## Execution

- Run from repository root
- Capture only relevant failure output
- Treat multi-stage suites as sequential gates

---

## Failure Classification

- Product code issue → fix implementation
- Test issue → update tests
- Environment issue → fix setup, not coverage

---

## Decision Rule

- Prefer fixing product code
- Update tests only if behavior intentionally changed
- Do not modify both without clear reason

---

## Fix Loop

1. Fix smallest failing unit
2. Re-run focused tests if possible
3. Re-run full suite
4. Repeat until all pass

---

## Constraints

- No skipping or disabling tests
- No weakening assertions
- No unrelated refactors
- No assumptions about stack

---

## Output Rules

- Follow CLAUDE.md strictly
- Minimal diffs only
