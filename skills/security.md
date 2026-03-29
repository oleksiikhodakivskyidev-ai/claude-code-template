---
name: security
description: Scan code for security vulnerabilities and report only actionable issues with severity and exact locations.
---

# Security Scan

## Goal
Identify real security risks with precise locations and minimal noise.

---

## Scope

- Focus on changed files or relevant code paths
- Expand only if necessary
- Avoid full-project scans unless explicitly required

---

## Detection Areas (priority)

### 1. Secrets
- Hardcoded credentials, API keys, tokens
- Secrets in code, configs, logs
- Exposed environment variables

---

### 2. Injection
- SQL/NoSQL string concatenation
- Command execution with user input
- eval / dynamic imports
- Path traversal

---

### 3. Auth / Access
- Missing authorization checks
- IDOR patterns
- Weak JWT/session handling

---

### 4. Data Exposure
- Sensitive data in logs/responses
- Stack traces in production
- Overly broad API responses

---

### 5. External Calls
- SSRF (unvalidated URLs)
- Missing webhook verification
- Unsafe redirects

---

### 6. Dependencies
- Known vulnerable packages
- Unsafe install scripts

---

## Severity

- Critical → exploitable now
- High → likely exploitable
- Medium → conditional
- Low → hygiene

---

## Output Rules

- Only real issues
- Include:
  - severity
  - file path
  - short issue
  - fix direction
- No explanations
- No generic advice

---

## Fix Rules

- Never auto-fix secrets
- Suggest fixes only
- Fix code issues only if trivial and safe

---

## Constraints

- No full audits unless requested
- No dependency installation
- No large rewrites
