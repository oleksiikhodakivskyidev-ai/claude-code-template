---
name: docker
description: Enforce Docker best practices for portable, performant, OS-independent containerized projects.
---

# Docker Standards

## Goal
Ensure any dockerized project is fully portable (clone → `cp .env.example .env` → `docker compose up` works on any OS), performant, and follows current best practices.

## Applicability
Active when the project has a `Dockerfile`, `docker-compose.yml`, `.docker/` directory, or user requests dockerization. This skill enforces standards when creating or modifying Docker files — it does not orchestrate docker commands.

## Project structure

```
.docker/
  Dockerfile                  # or per-service: app.Dockerfile, worker.Dockerfile
.dockerignore                 # MUST be at project root — Docker ignores it anywhere else
docker-compose.yml            # base services, shared config
docker-compose.override.yml   # dev: hot reload, debug ports, source mounts (auto-loaded)
docker-compose.prod.yml       # prod: resource limits, restart policy, no source mounts
.env.example                  # working test values, committed
.env                          # gitignored, created from .env.example
```

- Dockerfiles live in `.docker/`. Compose files and `.dockerignore` stay at project root.
- **`.dockerignore` must be at the project root when using `context: .`** (the standard setup in this skill). Docker only reads `.dockerignore` from the build context root — placing it in `.docker/` will be silently ignored and the full context sent.
- For multi-service projects, name Dockerfiles per service: `.docker/app.Dockerfile`, `.docker/worker.Dockerfile`.
- Reference from compose: `build: { context: ., dockerfile: .docker/app.Dockerfile }`.

## Docker Compose v2

- Always `docker compose` (v2 CLI plugin), never `docker-compose` (v1 standalone).
- Omit the top-level `version:` key — it is deprecated in Compose v2 and ignored.
- Use `depends_on` with `condition: service_healthy` when the dependency has a health check. This does not guarantee full readiness — only that the container passed its healthcheck at least once. Applications must still implement connection retries.
- Named volumes for persistent data (databases, caches). Bind mounts only for dev source code in `docker-compose.override.yml`.
- Define a dedicated bridge network. Do not rely on the default network — its name is auto-generated from the project directory name, making it non-deterministic in scripts and references across environments.
- Environment variables: reference `.env` file or use `environment:` with variable substitution (`${VAR}`). Never hardcode values in compose files.
- **Tag built images explicitly.** Always set `image: <name>:${TAG:-dev}` on services with a `build:` block. Never rely on the implicit `latest` tag — it breaks CI reproducibility, cache invalidation, and rollback safety.
  - Name images as `<project>-<service>` to avoid collisions across projects (`chatty-api-app`, not `app`).
  - For registry-pushed images, include the registry prefix: `ghcr.io/org/chatty-api-app:${TAG:-dev}`.
  - `TAG` is set by CI (commit SHA or semver). Locally defaults to `dev`.
  ```yaml
  services:
    app:
      build:
        context: .
        dockerfile: .docker/app.Dockerfile
      image: ghcr.io/org/chatty-api-app:${TAG:-dev}
  ```
- **`docker-compose.override.yml` is automatically merged** by Compose without any flags. Dev-only settings (source mounts, debug ports, relaxed resource limits) go here. This means running `docker compose up` in dev automatically picks up overrides — ensure the override file is never deployed to production.
- Production services must define `restart: unless-stopped` (or `always` for critical services) and logging limits to prevent disk exhaustion:
  ```yaml
  restart: unless-stopped
  logging:
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"
  ```

## Dockerfile best practices

**Base images:** Pin to a specific version and variant. `node:20.11-slim`, not `node:latest` or `node:20`. Prefer `-slim`. Use `-alpine` only when image size is critical and all dependencies are confirmed compatible (Alpine uses musl libc, which breaks some native extensions and glibc-linked binaries).

**Multi-stage builds:** Separate build and runtime stages. Copy only build artifacts into the final stage. The runtime image should not contain compilers, build tools, or source code beyond what's needed.

```dockerfile
# Build stage
FROM node:20.11-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Runtime stage
FROM node:20.11-slim
WORKDIR /app
RUN addgroup --system app && adduser --system --ingroup app app
COPY --from=build --chown=app:app /app/dist ./dist
COPY --from=build --chown=app:app /app/node_modules ./node_modules
USER app
EXPOSE 3000
# requires curl — install it or use a language-native alternative (see Healthcheck section)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -f http://localhost:3000/health || exit 1
CMD ["node", "dist/server.js"]
```

**Layer caching order:** Least to most frequently changing:
1. OS-level dependencies (`apt-get`, `apk add`)
2. Language dependencies (`package.json` + lockfile → `npm ci`, `requirements.txt` → `pip install`)
3. Source code (`COPY . .`)

**Non-root user:** Create a dedicated user and group in the runtime stage. Switch to it with `USER` before `CMD`. Never run the application as root.

**Exec-form CMD:** Always `CMD ["executable", "arg"]`, never `CMD executable arg`. Shell form wraps in `/bin/sh -c` which breaks signal handling (SIGTERM not forwarded, PID 1 issues).

**Entrypoint scripts:** If using a shell entrypoint (`entrypoint.sh`) for init logic (migrations, wait-for-db, etc.), it must end with `exec "$@"` to hand off to CMD with correct PID 1 and signal forwarding:
```sh
#!/bin/sh
set -e
# ... init logic ...
exec "$@"
```

**Health checks:** Define `HEALTHCHECK` in the Dockerfile. Use the application's health endpoint. Set explicit `--interval`, `--timeout`, `--retries`. If using `curl`, ensure it is installed in the final image — slim and Alpine images do not include it by default. Alternatives that avoid the curl dependency:
- `wget -qO- http://localhost:3000/health || exit 1` (available in most slim images)
- Node: `node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"`
- A compiled healthcheck binary copied into the image

**No secrets in build:** Never pass secrets via `ARG` or `ENV` — they persist in image layers. Use BuildKit secrets (`--mount=type=secret`) if secrets are needed at build time.

**Minimal final image:** In the same `RUN` layer, install and clean up: `RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*`.

**.dockerignore:** Must exist at the **project root** (co-located with `context: .`) and exclude: `.git`, `node_modules`, `.env`, `.env.*` (except `.env.example`), IDE/editor files, test fixtures, documentation, build output that gets regenerated.

## OS independence

This is the most important section. The containerized project must work identically on macOS, Linux (Debian/Ubuntu/etc.), and Windows (WSL2).

**File ownership:** Use explicit `--chown` on every `COPY` that places files the app user needs. For dev bind mounts, UID/GID alignment between host and container is mandatory — not optional. A mismatch causes permission errors and breaks any git operation inside the container (pre-commit hooks, captainhook, husky, etc.) with `fatal: detected dubious ownership in repository`.

The canonical fix is build-time UID matching. Create the container user with the same UID/GID as the host user:

```dockerfile
ARG UID=1000
ARG GID=1000
RUN addgroup --system --gid ${GID} app && adduser --system --uid ${UID} --ingroup app app
```

Pass the host values via compose:
```yaml
build:
  context: .
  dockerfile: .docker/Dockerfile
  args:
    UID: ${UID:-1000}
    GID: ${GID:-1000}
```

With matching UIDs, the container user owns the bind-mounted files at the OS level — git sees no mismatch, file writes from the container have correct host ownership. Do not work around ownership mismatches with `git config --global --add safe.directory` — that suppresses a valid security check without fixing the root cause.

Note: UID/GID build args make images host-specific and reduce build cache reuse. This is an intentional tradeoff — correctness over cache efficiency. In CI, use a fixed UID (typically `1000`) and build once.

**Line endings:** Add to `.gitattributes`:
```
* text=auto eol=lf
```
This ensures all files entering the container have Unix line endings regardless of host OS. Shell scripts and entrypoints with `\r\n` will fail silently.

**Path separators:** Only forward slashes in Dockerfile, compose files, and entrypoint scripts. Never backslash.

**File permissions:** Set explicitly in Dockerfile with `chmod`. Do not rely on host filesystem permissions being preserved — they are not consistent across OS and Docker storage drivers.

**No host-specific paths:** Only relative paths from project root in compose volume mounts. Never absolute host paths (`/Users/...`, `/home/...`). Never reference host binaries or tools.

**No host tools required:** Everything runs inside containers. Build, test, lint, migrate, seed — all via `docker compose exec` or `docker compose run`. The host machine only needs Docker and standard tooling like `git` (optionally `just`).

**Port mapping:** Use explicit port mapping in compose (`ports: ["3000:3000"]`). Do not rely on `network_mode: host` — it doesn't work on macOS. If services need to communicate, use the compose network and service names as hostnames.

## Environment handling

- `.env.example` is committed. `.env` is gitignored.
- `.env.example` MUST contain working dev/test values — not placeholders like `YOUR_API_KEY_HERE`. A developer should be able to `cp .env.example .env` and have a working system immediately.
- Add comments in `.env.example` explaining each variable, its purpose, and valid values.
- `docker compose` reads `.env` from the project root automatically. Only use `env_file:` in compose for service-specific env files.
- For service-specific env: `.docker/<service>.env.example` with corresponding `.docker/<service>.env` (gitignored).
- Sensitive production values (real API keys, DB passwords) are never in `.env.example`. Document them in comments with instructions on where to obtain them.
- **Never use `.env` files in production.** Production environments must use orchestrator-provided environment injection (Kubernetes secrets, ECS task environment, Vault, etc.). `.env` is a local dev convenience only.
- **Shell variables take precedence over `.env`.** If a variable is exported in the developer's shell, it silently overrides the `.env` value in Compose. This causes "works on my machine" bugs. Document this in project onboarding.

## Justfile integration

When the project has a `justfile`, all recipes that execute project code MUST go through docker compose. No bare host commands for anything that should run in a container.

```just
# Start all services in background
dev:
    docker compose up -d

# Stop all services
down:
    docker compose down

# Rebuild images
build:
    docker compose build

# View logs (usage: just logs, just logs app, just logs -f app)
logs *args:
    docker compose logs {{ args }}

# Open shell in a service (usage: just shell, just shell worker)
shell service="app":
    docker compose exec {{ service }} sh

# Run tests
test *args:
    docker compose exec app <test-command> {{ args }}

# Run migrations
migrate:
    docker compose exec app <migrate-command>

# Fresh setup from scratch
setup:
    cp -n .env.example .env || true
    docker compose build
    docker compose up -d
    docker compose exec app <migrate-command>
    docker compose exec app <seed-command>

# Stop and remove containers, networks, and volumes (full reset)
reset:
    docker compose down -v
```

- Replace `<test-command>`, `<migrate-command>`, `<seed-command>` with the project's actual commands.
- The `setup` recipe must work on a fresh clone with only Docker installed.
- `down` preserves named volumes (database state). `reset` uses `down -v` to wipe volumes — use when a clean DB state is needed.

## Performance

- **BuildKit:** Ensure BuildKit is enabled. Compose v2 uses it by default. For standalone builds: `DOCKER_BUILDKIT=1`.
- **Build context:** `.dockerignore` keeps the build context small. A bloated context (sending `node_modules`, `.git`) slows every build.
- **Layer caching:** Dependency files (`package.json`, `requirements.txt`, `go.mod`) copied and installed before source code. Source changes don't invalidate the dependency cache.
- **Named volumes for data:** Database volumes must be named volumes, not bind mounts. Bind-mounted databases are slow on macOS (osxfs/virtiofs overhead) and risk permission issues.
- **macOS source mounts:** For dev source code bind mounts on macOS, if performance is poor, use `:cached` consistency flag or consider named volumes with sync (e.g. `docker-compose.override.yml` with mutagen or similar).

## Validation

When creating or reviewing Docker files, verify:

1. Dockerfiles in `.docker/`, `.dockerignore` at project root
2. `docker compose` v2 syntax — no `docker-compose`, no `version:` key
3. Base images pinned to specific version + variant
4. Multi-stage build separates build and runtime
5. Non-root user in runtime stage
6. Exec-form `CMD`
7. `HEALTHCHECK` defined
8. `.dockerignore` exists and covers `.git`, `node_modules`, `.env`
9. `.env.example` has working test values, `.env` is gitignored
10. No absolute host paths, no host-specific assumptions
11. Line endings: `.gitattributes` enforces LF
12. Justfile recipes use `docker compose` (if justfile exists)
13. Fresh clone → `cp .env.example .env` → `docker compose up` works
