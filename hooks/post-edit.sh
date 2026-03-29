#!/usr/bin/env bash
set -e

# Detect test command (strict order)

if command -v just >/dev/null 2>&1 && [ -f justfile -o -f Justfile ]; then
  TEST_CMD="just test"

elif [ -f Makefile ]; then
  TEST_CMD="make test"

# PHP
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

# Node
elif [ -f package.json ] && command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
  TEST_CMD="npm test --silent"

# Python
elif [ -f pyproject.toml ] || [ -f requirements.txt ]; then
  if command -v pytest >/dev/null 2>&1; then
    TEST_CMD="pytest -q"
  else
    echo "pytest not found"
    exit 1
  fi

# Go
elif [ -f go.mod ]; then
  TEST_CMD="go test ./..."

else
  echo "No known test command found"
  exit 0
fi

# Run tests with filtered output
$TEST_CMD 2>&1 | ./hooks/filter-test-output.sh
