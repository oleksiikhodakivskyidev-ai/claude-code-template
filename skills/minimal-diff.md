---
name: minimal-diff
description: Ensure only the smallest necessary code changes are made. Prevent unnecessary edits, refactors, or rewrites.
---

# Minimal Diff Enforcement

## Goal
Apply the smallest possible change to satisfy the requirement.

---

## Core Rules

- Modify only what is required
- Do not touch unrelated code
- Do not reformat entire files
- Do not rename or move code unless required
- Do not refactor unless necessary to solve the task

---

## Change Strategy

### 1. Locate exact change point
- Identify minimal scope (function, block, line)

### 2. Apply focused fix
- Change only relevant lines
- Keep surrounding structure untouched

### 3. Preserve behavior
- Do not alter unrelated logic
- Do not introduce side effects

---

## Anti-Patterns (forbidden)

- Rewriting entire files
- Large-scale refactors
- Changing formatting across file
- Reordering imports unnecessarily
- Renaming variables without need
- Replacing working code with alternative implementations

---

## Exceptions (allowed only if required)

- Fixing test failures
- Fixing lint/type errors
- Fixing security or performance issues
- Structural change required to implement feature

---

## Output Rules

- Output only changed code
- No full file rewrites unless unavoidable
- No duplicated unchanged code

---

## Validation

Before finishing:

- Is this the smallest possible change?
- Did I modify unrelated code? (must be no)
- Could this be done with fewer edits?

If yes → reduce further
