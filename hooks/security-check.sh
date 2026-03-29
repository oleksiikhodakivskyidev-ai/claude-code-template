#!/usr/bin/env bash
set -e

# ----------------------
# Secrets scanning (fast, high value)
# ----------------------
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --no-banner --redact || true
fi

# ----------------------
# Dependency scanning (choose ONE heavy scanner)
# ----------------------
if command -v osv-scanner >/dev/null 2>&1; then
  osv-scanner ./... || true

elif command -v trivy >/dev/null 2>&1; then
  trivy fs \
    --quiet \
    --severity HIGH,CRITICAL \
    --skip-dirs node_modules,vendor \
    . || true
fi

# ----------------------
# Node
# ----------------------
if [ -f package.json ] && command -v npm >/dev/null 2>&1; then
  npm audit --omit=dev || true
fi

# ----------------------
# Python (poetry preferred)
# ----------------------
if [ -f poetry.lock ] && command -v poetry >/dev/null 2>&1; then
  poetry audit || true

elif command -v pip-audit >/dev/null 2>&1; then
  pip-audit || true
fi

# ----------------------
# PHP
# ----------------------
if command -v composer >/dev/null 2>&1; then
  composer audit || true
fi

# ----------------------
# Go
# ----------------------
if command -v govulncheck >/dev/null 2>&1; then
  govulncheck ./... || true
fi
