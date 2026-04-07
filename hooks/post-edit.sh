#!/usr/bin/env bash
set -e
set -o pipefail

# ----------------------
# TEST RUNNER (fail fast)
# ----------------------

# Read edited file from PostToolUse hook payload (stdin), if present.
EDITED_FILE=""
if [ ! -t 0 ]; then
  PAYLOAD=$(cat)
  if [ -n "$PAYLOAD" ] && command -v jq >/dev/null 2>&1; then
    EDITED_FILE=$(echo "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
  fi
fi

# Map extension → preferred language family.
PREFERRED_LANG=""
case "$EDITED_FILE" in
  *.py)                                PREFERRED_LANG="python" ;;
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)   PREFERRED_LANG="node"   ;;
  *.go)                                PREFERRED_LANG="go"     ;;
  *.rs)                                PREFERRED_LANG="rust"   ;;
  *.java|*.kt|*.kts|*.groovy|*.scala)  PREFERRED_LANG="jvm"    ;;
  *.cs)                                PREFERRED_LANG="dotnet" ;;
  *.php)                               PREFERRED_LANG="php"    ;;
esac

# Detection functions: each prints a TEST_CMD if its stack applies.
detect_just()   { command -v just >/dev/null 2>&1 && { [ -f justfile ] || [ -f Justfile ]; } && echo "just test"; }
detect_make()   { [ -f Makefile ] && grep -qE "^test[[:space:]]*:" Makefile && echo "make test"; }

detect_php() {
  [ -f composer.json ] || return 0
  if   [ -f vendor/bin/pest ];    then echo "vendor/bin/pest"
  elif [ -f vendor/bin/phpunit ]; then echo "vendor/bin/phpunit"
  elif command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' composer.json >/dev/null 2>&1; then
    echo "composer test"
  fi
}

detect_node() {
  if   [ -f pnpm-workspace.yaml ] || [ -f pnpm-lock.yaml ]; then echo "pnpm test --silent"
  elif [ -f yarn.lock ];                                    then echo "yarn test --silent"
  elif [ -f bun.lockb ];                                    then echo "bun test"
  elif [ -f package.json ] && command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    echo "npm test --silent"
  fi
}

detect_python() {
  if   [ -f uv.lock ];     then echo "uv run pytest -q --tb=short"
  elif [ -f poetry.lock ]; then echo "poetry run pytest -q --tb=short"
  elif { [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f requirements.txt ]; } && command -v pytest >/dev/null 2>&1; then
    echo "pytest -q --tb=short"
  fi
}

detect_rust() { [ -f Cargo.toml ] && echo "cargo test --quiet"; }
detect_go()   { [ -f go.mod ]     && echo "go test -failfast ./..."; }

detect_jvm() {
  if [ -f pom.xml ]; then
    if [ -x ./mvnw ]; then echo "./mvnw -q test"
    else                   echo "mvn -q test"
    fi
  elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    if [ -x ./gradlew ]; then echo "./gradlew test --quiet"
    else                       echo "gradle test --quiet"
    fi
  fi
}

detect_dotnet() {
  if compgen -G "*.sln" >/dev/null 2>&1 || compgen -G "*.csproj" >/dev/null 2>&1; then
    echo "dotnet test --nologo --verbosity quiet"
  fi
}

# Default detection order (used after just/make and after the preferred lang).
DETECTION_ORDER="php node python rust go jvm dotnet"

# 1. Project-owner entry points always win.
TEST_CMD=$(detect_just || true)
[ -z "$TEST_CMD" ] && TEST_CMD=$(detect_make || true)

# 2. Polyglot monorepo: prefer the language matching the edited file.
if [ -z "$TEST_CMD" ] && [ -n "$PREFERRED_LANG" ]; then
  TEST_CMD=$(detect_"$PREFERRED_LANG" 2>/dev/null || true)
fi

# 3. Fall back to the default detection order.
if [ -z "$TEST_CMD" ]; then
  for lang in $DETECTION_ORDER; do
    TEST_CMD=$(detect_"$lang" 2>/dev/null || true)
    [ -n "$TEST_CMD" ] && break
  done
fi

if [ -n "$TEST_CMD" ]; then
  TIMEOUT_DURATION="${CLAUDE_TEST_TIMEOUT:-10m}"
  TIMEOUT_BIN=""
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout $TIMEOUT_DURATION"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout $TIMEOUT_DURATION"
  fi

  echo "Running tests: $TEST_CMD"
  log=$(mktemp)
  status=0
  $TIMEOUT_BIN $TEST_CMD > "$log" 2>&1 || status=$?
  if [ $status -eq 0 ]; then
    echo "✓ tests passed"
    rm -f "$log"
  elif [ $status -eq 124 ]; then
    echo "✗ tests timed out after $TIMEOUT_DURATION"
    tail -n 80 "$log"
    rm -f "$log"
    exit $status
  else
    tail -n 80 "$log"
    rm -f "$log"
    exit $status
  fi
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
