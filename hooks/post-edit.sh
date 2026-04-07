#!/usr/bin/env bash
set -e
set -o pipefail

# ----------------------
# TEST RUNNER (deferred — runs at end of script, only if APPLIED_FIXES=1)
# ----------------------

# Read edited file from PostToolUse hook payload (stdin), if present.
EDITED_FILE=""
if [ ! -t 0 ]; then
  PAYLOAD=$(cat)
  if [ -n "$PAYLOAD" ] && command -v jq >/dev/null 2>&1; then
    EDITED_FILE=$(echo "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
  fi
fi

# Scoped-first lint target. When the hook fires per-edit, narrow to that file;
# when invoked manually with no payload, fall back to the whole repo.
TARGET="${EDITED_FILE:-.}"

# Tracks whether any auto-fix was written during format/lint stages.
# Spec: tests re-run only when fixes were applied, to verify behavior unchanged.
APPLIED_FIXES=0

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

run_tests() {
  local DETECTION_ORDER="php node python rust go jvm dotnet"
  local TEST_CMD lang

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

  [ -z "$TEST_CMD" ] && return 0

  local TIMEOUT_DURATION="${CLAUDE_TEST_TIMEOUT:-10m}"
  local TIMEOUT_BIN=""
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout $TIMEOUT_DURATION"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout $TIMEOUT_DURATION"
  fi

  echo "== TESTS (post-fix) =="
  echo "Running tests: $TEST_CMD"
  local log status=0
  log=$(mktemp)
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
}

# ----------------------
# LINT / TYPECHECK
# ----------------------

# Project-owner entry points always win. Note: these `exit 0` paths bypass the
# APPLIED_FIXES test gate at the end of the script — by delegating to the
# canonical entry point we trust the owner's recipe to run tests if needed.
if command -v just >/dev/null 2>&1 && { [ -f justfile ] || [ -f Justfile ]; } && grep -q "pre-commit" justfile 2>/dev/null; then
  echo "Running just pre-commit"
  just pre-commit
  exit 0
fi

if command -v pre-commit >/dev/null 2>&1 && [ -f .pre-commit-config.yaml ]; then
  echo "Running pre-commit"
  pre-commit run --all-files
  exit 0
fi

# Per-stack lint runners. Each runs format → lint → typecheck in stage order
# and exits non-zero on failure (set -e propagates).

lint_node() {
  [ -f package.json ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local RUNNER="npm"
  if   [ -f pnpm-lock.yaml ] || [ -f pnpm-workspace.yaml ]; then RUNNER="pnpm"
  elif [ -f yarn.lock ];                                    then RUNNER="yarn"
  elif [ -f bun.lockb ];                                    then RUNNER="bun"
  fi

  local ORIGIN_REF="${ORIGIN_REF:-origin/main}"

  # 1. Canonical "check" script wins — owner picked the order.
  if jq -e '.scripts.check' package.json >/dev/null 2>&1; then
    echo "== CHECK (canonical) =="
    echo "Running $RUNNER run check"
    $RUNNER run check
    return 0
  fi

  # 2. Monorepo orchestrators — affected-only when no canonical script.
  if [ -f nx.json ] && command -v nx >/dev/null 2>&1; then
    echo "== LINT (nx affected) =="
    nx affected -t lint --base="$ORIGIN_REF"
    echo "== TYPECHECK (nx affected) =="
    nx affected -t typecheck --base="$ORIGIN_REF" 2>/dev/null || true
    return 0
  fi
  if [ -f turbo.json ] && command -v turbo >/dev/null 2>&1; then
    echo "== LINT (turbo affected) =="
    turbo run lint --filter="...[$ORIGIN_REF]"
    echo "== TYPECHECK (turbo affected) =="
    turbo run typecheck --filter="...[$ORIGIN_REF]" 2>/dev/null || true
    return 0
  fi

  # 3. Individual scripts.
  local RAN_SCRIPT=0
  if jq -e '.scripts.format' package.json >/dev/null 2>&1; then
    echo "== FORMAT =="
    echo "Running $RUNNER run format"
    $RUNNER run format
    RAN_SCRIPT=1
  fi
  if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
    echo "== LINT =="
    echo "Running $RUNNER run lint"
    $RUNNER run lint
    RAN_SCRIPT=1
  fi
  if jq -e '.scripts.typecheck' package.json >/dev/null 2>&1; then
    echo "== TYPECHECK =="
    echo "Running $RUNNER run typecheck"
    $RUNNER run typecheck
    RAN_SCRIPT=1
  fi

  # 4. Direct-tool fallback when no scripts are defined.
  if [ $RAN_SCRIPT -eq 0 ]; then
    local HAS_PRETTIER_CFG=0
    local HAS_BIOME_CFG=0
    local HAS_ESLINT_CFG=0
    local f
    for f in .prettierrc .prettierrc.json .prettierrc.js .prettierrc.cjs .prettierrc.mjs .prettierrc.yaml .prettierrc.yml prettier.config.js prettier.config.cjs prettier.config.mjs prettier.config.ts; do
      [ -f "$f" ] && HAS_PRETTIER_CFG=1
    done
    jq -e '.prettier' package.json >/dev/null 2>&1 && HAS_PRETTIER_CFG=1
    { [ -f biome.json ] || [ -f biome.jsonc ]; } && HAS_BIOME_CFG=1
    for f in eslint.config.js eslint.config.cjs eslint.config.mjs eslint.config.ts .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yaml .eslintrc.yml; do
      [ -f "$f" ] && HAS_ESLINT_CFG=1
    done

    if [ $HAS_PRETTIER_CFG -eq 1 ] && [ $HAS_BIOME_CFG -eq 1 ]; then
      echo "✗ Both prettier and biome configs found — ambiguous. Define a canonical 'check' script to disambiguate."
      return 1
    fi

    # Format (and biome's combined lint).
    if [ $HAS_BIOME_CFG -eq 1 ] && command -v biome >/dev/null 2>&1; then
      echo "== FORMAT/LINT (biome) =="
      biome check --write "$TARGET"
      APPLIED_FIXES=1
    elif [ $HAS_PRETTIER_CFG -eq 1 ] && command -v prettier >/dev/null 2>&1; then
      echo "== FORMAT (prettier) =="
      prettier --write "$TARGET"
      APPLIED_FIXES=1
    fi

    # Lint (eslint, only when biome isn't already covering it).
    if [ $HAS_BIOME_CFG -eq 0 ] && [ $HAS_ESLINT_CFG -eq 1 ] \
       && jq -e '.devDependencies.eslint // .dependencies.eslint' package.json >/dev/null 2>&1; then
      echo "== LINT (eslint) =="
      case "$RUNNER" in
        npm)  npx eslint --fix "$TARGET" ;;
        pnpm) pnpm exec eslint --fix "$TARGET" ;;
        yarn) yarn eslint --fix "$TARGET" ;;
        bun)  bun x eslint --fix "$TARGET" ;;
      esac
      APPLIED_FIXES=1
    fi

    # Typecheck (tsc, when tsconfig.json + typescript dep present).
    if [ -f tsconfig.json ] \
       && jq -e '.devDependencies.typescript // .dependencies.typescript' package.json >/dev/null 2>&1; then
      echo "== TYPECHECK (tsc) =="
      local TSC_ARGS="--noEmit"
      if jq -e '.references' tsconfig.json >/dev/null 2>&1; then
        TSC_ARGS="-b"
      fi
      case "$RUNNER" in
        npm)  npx tsc $TSC_ARGS ;;
        pnpm) pnpm exec tsc $TSC_ARGS ;;
        yarn) yarn tsc $TSC_ARGS ;;
        bun)  bun x tsc $TSC_ARGS ;;
      esac
    fi
  fi
}

lint_python() {
  [ -f pyproject.toml ] || [ -f setup.py ] || [ -f requirements.txt ] || return 0

  local PREFIX=""
  if   [ -f uv.lock ];     then PREFIX="uv run"
  elif [ -f poetry.lock ]; then PREFIX="poetry run"
  fi

  if command -v ruff >/dev/null 2>&1 || [ -n "$PREFIX" ]; then
    echo "== FORMAT (ruff) =="
    $PREFIX ruff format "$TARGET"
    APPLIED_FIXES=1
    echo "== LINT (ruff) =="
    $PREFIX ruff check "$TARGET"
  elif command -v black >/dev/null 2>&1; then
    echo "== FORMAT (black) =="
    black "$TARGET"
    APPLIED_FIXES=1
  fi

  if command -v pyright >/dev/null 2>&1; then
    echo "== TYPECHECK (pyright) =="
    $PREFIX pyright "$TARGET"
  elif command -v basedpyright >/dev/null 2>&1; then
    echo "== TYPECHECK (basedpyright) =="
    $PREFIX basedpyright "$TARGET"
  elif command -v mypy >/dev/null 2>&1; then
    echo "== TYPECHECK (mypy) =="
    $PREFIX mypy "$TARGET"
  fi
}

lint_rust() {
  [ -f Cargo.toml ] || return 0
  command -v cargo >/dev/null 2>&1 || return 0

  echo "== FORMAT (cargo fmt) =="
  cargo fmt --check

  if rustup component list --installed 2>/dev/null | grep -q clippy; then
    echo "== LINT (clippy) =="
    cargo clippy --all-targets --quiet -- -D warnings
  fi
}

lint_go() {
  [ -f go.mod ] || return 0

  if command -v gofmt >/dev/null 2>&1; then
    echo "== FORMAT (gofmt) =="
    gofmt -w "$TARGET"
    APPLIED_FIXES=1
  fi

  if command -v go >/dev/null 2>&1; then
    echo "== LINT (go vet) =="
    go vet ./...
  fi

  if command -v golangci-lint >/dev/null 2>&1; then
    echo "== LINT (golangci-lint) =="
    if [ -n "$EDITED_FILE" ]; then
      golangci-lint run "$EDITED_FILE"
    else
      golangci-lint run
    fi
  fi
}

lint_jvm() {
  if [ -f pom.xml ]; then
    echo "== FORMAT (spotless) =="
    if [ -x ./mvnw ]; then
      ./mvnw -q spotless:check
    elif command -v mvn >/dev/null 2>&1; then
      mvn -q spotless:check
    fi
  elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    echo "== FORMAT (spotless) =="
    if [ -x ./gradlew ]; then
      ./gradlew -q spotlessCheck
    elif command -v gradle >/dev/null 2>&1; then
      gradle -q spotlessCheck
    fi
  fi
}

lint_dotnet() {
  compgen -G "*.sln" >/dev/null 2>&1 || compgen -G "*.csproj" >/dev/null 2>&1 || return 0
  command -v dotnet >/dev/null 2>&1 || return 0

  echo "== FORMAT (dotnet) =="
  if [ -n "$EDITED_FILE" ]; then
    dotnet format --include "$EDITED_FILE" --no-restore
  else
    dotnet format --no-restore
  fi
  APPLIED_FIXES=1
}

lint_php() {
  [ -f composer.json ] || return 0

  if [ -f vendor/bin/php-cs-fixer ]; then
    echo "== FORMAT (php-cs-fixer) =="
    vendor/bin/php-cs-fixer fix "$TARGET"
    APPLIED_FIXES=1
  fi
  if [ -f vendor/bin/phpstan ]; then
    echo "== LINT (phpstan) =="
    if [ -n "$EDITED_FILE" ]; then
      vendor/bin/phpstan analyse "$EDITED_FILE"
    else
      vendor/bin/phpstan
    fi
  fi
  if [ -f vendor/bin/psalm ]; then
    echo "== LINT (psalm) =="
    if [ -n "$EDITED_FILE" ]; then
      vendor/bin/psalm "$EDITED_FILE"
    else
      vendor/bin/psalm
    fi
  fi
}

# Polyglot: prefer the language matching the edited file.
LINT_RAN=0
if [ -n "$PREFERRED_LANG" ]; then
  case "$PREFERRED_LANG" in
    node)   if [ -f package.json ]; then lint_node; LINT_RAN=1; fi ;;
    python) if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f requirements.txt ]; then lint_python; LINT_RAN=1; fi ;;
    rust)   if [ -f Cargo.toml ]; then lint_rust; LINT_RAN=1; fi ;;
    go)     if [ -f go.mod ]; then lint_go; LINT_RAN=1; fi ;;
    jvm)    if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then lint_jvm; LINT_RAN=1; fi ;;
    dotnet) if compgen -G "*.sln" >/dev/null 2>&1 || compgen -G "*.csproj" >/dev/null 2>&1; then lint_dotnet; LINT_RAN=1; fi ;;
    php)    if [ -f composer.json ]; then lint_php; LINT_RAN=1; fi ;;
  esac
fi

# Fall back to running every detected stack.
if [ $LINT_RAN -eq 0 ]; then
  lint_node
  lint_python
  lint_rust
  lint_go
  lint_jvm
  lint_dotnet
  lint_php
fi

# ----------------------
# TESTS (deferred — only when an auto-fix was written)
# ----------------------
# Spec: format → lint → typecheck → tests (conditional). Tests re-run only when
# fixes were applied, to verify behavior is unchanged.
if [ "$APPLIED_FIXES" = "1" ]; then
  run_tests
fi
