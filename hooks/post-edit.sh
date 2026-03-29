#!/usr/bin/env bash
set -e
set -o pipefail

# ----------------------
# TEST RUNNER (fail fast)
# ----------------------

TEST_CMD=""

if command -v just >/dev/null 2>&1 && [ -f justfile -o -f Justfile ]; then
  TEST_CMD="just test"

elif [ -f Makefile ]; then
  TEST_CMD="make test"

elif [ -f composer.json ]; then
  if [ -f vendor/bin/pest ]; then
    TEST_CMD="vendor/bin/pest"
  elif [ -f vendor/bin/phpunit ]; then
    TEST_CMD="vendor/bin/phpunit"
  elif command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' composer.json >/dev/null 2>&1; then
    TEST_CMD="composer test"
  else
    echo "No PHP test runner found"
    exit 1
  fi

elif [ -f package.json ] && command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
  TEST_CMD="npm test --silent"

elif [ -f pyproject.toml ] || [ -f requirements.txt ]; then
  if command -v pytest >/dev/null 2>&1; then
    TEST_CMD="pytest -q"
  else
    echo "pytest not found"
    exit 1
  fi

elif [ -f go.mod ]; then
  TEST_CMD="go test ./..."

fi

if [ -n "$TEST_CMD" ]; then
  echo "Running tests: $TEST_CMD"
  $TEST_CMD 2>&1 | "$(dirname "$0")/filter-test-output.sh"
fi

# ----------------------
# LINT / TYPECHECK
# ----------------------

# Prefer just pre-commit
if command -v just >/dev/null 2>&1 && [ -f justfile -o -f Justfile ]; then
  if grep -q "pre-commit" justfile 2>/dev/null; then
    echo "Running just pre-commit"
    just pre-commit
    exit 0
  fi
fi

# pre-commit fallback
if command -v pre-commit >/dev/null 2>&1; then
  echo "Running pre-commit"
  pre-commit run --all-files
  exit 0
fi

# Node (scripts first)
if [ -f package.json ] && command -v jq >/dev/null 2>&1; then
  if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
    echo "Running npm run lint"
    npm run lint
  fi

  if jq -e '.scripts.typecheck' package.json >/dev/null 2>&1; then
    echo "Running npm run typecheck"
    npm run typecheck
  fi

  if jq -e '.scripts.check' package.json >/dev/null 2>&1; then
    echo "Running npm run check"
    npm run check
  fi

  # Biome fallback
  if command -v biome >/dev/null 2>&1; then
    echo "Running biome"
    biome check .
  fi
fi

# Python
if command -v ruff >/dev/null 2>&1; then
  echo "Running ruff"
  ruff check .
fi

if command -v black >/dev/null 2>&1; then
  echo "Running black"
  black --check .
fi

if command -v mypy >/dev/null 2>&1; then
  echo "Running mypy"
  mypy .
fi

# PHP
if [ -f vendor/bin/php-cs-fixer ]; then
  echo "Running php-cs-fixer"
  vendor/bin/php-cs-fixer fix --dry-run
fi

if [ -f vendor/bin/phpstan ]; then
  echo "Running phpstan"
  vendor/bin/phpstan
fi

# Go
if command -v golangci-lint >/dev/null 2>&1; then
  echo "Running golangci-lint"
  golangci-lint run
fi
