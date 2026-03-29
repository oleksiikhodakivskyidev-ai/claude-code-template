# Claude Code Template

Production-ready template for Claude Code with:

- strict output control (code-only, no noise)
- automated testing, linting, and type checking
- security validation
- optimized token usage
- minimal-diff enforcement

## Goals

- eliminate repetitive prompts (tests, lint, checks)
- ensure high-quality, production-safe code
- minimize token consumption and cost
- enforce deterministic, senior-level output

## Includes

- `CLAUDE.md` → global behavior rules
- `skills/` → reusable execution patterns
- `hooks/` → automated validation pipeline
- `.claudeignore` → context/token optimization

## Usage

```bash
degit <your-username>/claude-code-template
