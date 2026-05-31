---
name: dockerize-frontend-backend
description: "Write hardened, production-grade Dockerfiles (and a secure docker-compose) for a backend service and/or a frontend SPA — multi-stage builds, minimal pinned base images, non-root runtime, build-layer caching, HEALTHCHECK, .dockerignore, and runtime hardening (read-only rootfs, dropped capabilities, no secrets baked into layers). Use whenever the user wants to containerize/Dockerize an app, write or review a Dockerfile or docker-compose, asks for 'multistage build', 'smaller/secure image', 'distroless', 'non-root container', image hardening, or 'best practices for Docker'. Covers Quarkus (JVM + native) backends and Angular/Node SPAs, with portable principles for any stack."
---

# dockerize-frontend-backend

Produce **small, reproducible, and hardened** container images for a backend service, a frontend SPA, or both — and a `docker-compose.yml` that runs them safely for local/dev. This skill owns the *image best-practices* layer (multi-stage, minimal base, non-root, pinning, hardening). For the Quarkus runtime topology (Postgres/MinIO services, health-gated `depends_on`, env defaults, `start.sh`) defer to [`dockerized-quarkus-runtime`](../dockerized-quarkus-runtime/SKILL.md), and for CVE/SBOM/registry gates to [`dependency-supply-chain-security`](../dependency-supply-chain-security/SKILL.md).

After running, the repo has:

- A multi-stage `Dockerfile` per service (builder stage → minimal runtime stage)
- A `.dockerignore` that keeps build context (and secrets) out of the image
- A `docker-compose.yml` wiring the services with runtime hardening
- Base images pinned by **tag + digest**, running as a **non-root** user

## When to invoke

- "Dockerize my backend / frontend / app"
- "Write a Dockerfile for this Quarkus API / Angular app"
- "Make the image smaller / more secure" · "use multistage" · "use distroless"
- "Run my container as non-root" · "harden my docker-compose"
- Reviewing an existing `Dockerfile`/`docker-compose.yml` for best practices.

## Inputs to collect

| Input | Default |
|---|---|
| Targets | ask: `backend` \| `frontend` \| `both` |
| Backend stack | Quarkus (JVM unless native requested) |
| Backend build mode | `jvm` (use `native` only when GraalVM/native is in play) |
| Frontend stack | Angular SPA served by Nginx |
| Node version (frontend build) | `24` (current LTS) |
| JDK version (backend build) | `21` (current LTS) |
| Compose deps | none unless asked (defer dep topology to `dockerized-quarkus-runtime`) |

## Library / framework grounding (context7)

Base image tags, digests, and recommended variants move constantly — `eclipse-temurin`, `gcr.io/distroless/*`, `nginxinc/nginx-unprivileged`, `node`, and Quarkus' own `quarkus-micro`/`ubi-minimal` images all get rebuilt with new digests and occasional path/user changes. Before pinning, verify the current tag, digest, and default user via `mcp__context7__query-docs` (e.g. `"distroless java21 nonroot image"`, `"nginx-unprivileged default user port"`, `"quarkus container image native ubi minimal"`). A stale digest fails to pull; a wrong runtime user breaks the non-root setup.

- **If context7 is not installed** (the `mcp__context7__*` tools aren't present): proceed with training data, but say so once at the end and point the user at `AGENTS.md` §"MCP servers (context7)" for the install one-liner. Always confirm the exact digest with `docker buildx imagetools inspect <image>:<tag>` before committing it.

## Workflow

1. Confirm the targets and that each app builds locally (`./mvnw package` / `npm ci && npm run build`).
2. Write a `.dockerignore` **before** the Dockerfile — it shapes the build context and prevents secrets/`node_modules`/`target` from leaking into layers.
3. Write a multi-stage `Dockerfile` per service: a fat **builder** stage and a minimal **runtime** stage that copies only the artifact.
4. Pin every base image by tag **and** digest; run as a non-root user; add `HEALTHCHECK`.
5. Write/extend `docker-compose.yml` with runtime hardening (`read_only`, `cap_drop`, `no-new-privileges`, `tmpfs`).
6. Validate: `docker compose config`, build, run, hit the health endpoint, and confirm the process is non-root (`docker exec <c> id`).

## Core principles (apply to every image)

- **Multi-stage always.** Build tools (Maven, JDK, npm, source) never reach the runtime image. The runtime stage starts from a minimal base and copies only the built artifact. This is the single biggest win for both size and attack surface.
- **Pin tag + digest.** `FROM image:1.2-variant@sha256:…`. The tag documents intent; the digest makes the build reproducible and immune to a mutated tag. Never use `:latest`.
- **Smallest base that works.** Prefer `distroless` (no shell, no package manager) or `*-alpine`/`ubi-minimal` runtimes. Smaller base = fewer CVEs and faster pulls. Use a debug/shell variant only when you genuinely need to exec in.
- **Run as non-root.** Create or use an unprivileged user (`USER 1001`). A container escape from root is far worse than from an unprivileged uid. Distroless `:nonroot` and `nginx-unprivileged` give you this out of the box.
- **Order layers for cache hits.** Copy dependency manifests (`pom.xml`, `package*.json`) and resolve dependencies *before* copying source. Source changes then don't bust the dependency layer — much faster rebuilds.
- **No secrets in layers.** Never `COPY` a `.env`, keystore, or token into the image, and never bake them via `ENV`. Pass secrets at **runtime** (env/mounts) or at **build time** via `RUN --mount=type=secret`. Layers are forever, even if a later layer deletes the file.
- **One concern per image; let it be configurable.** Config comes from env at runtime, not hard-coded. Log to stdout/stderr.
- **`HEALTHCHECK`** so orchestrators and Compose know when the service is actually ready, not just started.

## Backend — Quarkus (JVM), multi-stage

`.dockerignore`:

```gitignore
target/
!target/quarkus-app/        # if you build outside Docker; omit when building inside
.git
.idea
*.iml
.env*
src/main/resources/**/*.pem  # keys/keystores never enter the build context
```

`Dockerfile` (build inside Docker, layered Quarkus output, JRE-only runtime):

```dockerfile
# ---- build stage: full JDK + Maven, with a cached dependency layer ----
FROM maven:3.9-eclipse-temurin-21@sha256:<pin> AS build
WORKDIR /app
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -B dependency:go-offline   # cached deps layer
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn -B clean package -DskipTests

# ---- runtime stage: JRE only, non-root, layered for fast startup ----
FROM eclipse-temurin:21-jre-alpine@sha256:<pin> AS runtime
WORKDIR /work
RUN addgroup -S app && adduser -S app -G app
# Quarkus' layered output: libs change rarely, app code often — copy in cache-friendly order
COPY --from=build /app/target/quarkus-app/lib/      ./lib/
COPY --from=build /app/target/quarkus-app/*.jar     ./
COPY --from=build /app/target/quarkus-app/app/      ./app/
COPY --from=build /app/target/quarkus-app/quarkus/  ./quarkus/
USER app
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s \
  CMD wget -qO- http://localhost:8080/q/health/ready || exit 1
ENTRYPOINT ["java", "-jar", "quarkus-run.jar"]
```

> Build with BuildKit so `--mount=type=cache` works: `DOCKER_BUILDKIT=1 docker build .`. The `quarkus-app/` layout splits dependencies from app code so the heavy `lib/` layer stays cached across code changes.

**Native variant** (smallest, no JVM): build with `./mvnw package -Dnative -Dquarkus.native.container-build=true`, then run the executable on a minimal base:

```dockerfile
FROM quay.io/quarkus/quarkus-micro-image:2.0@sha256:<pin>
WORKDIR /work
RUN chown 1001 /work
COPY --chown=1001:root --from=build /app/target/*-runner /work/application
USER 1001
EXPOSE 8080
ENTRYPOINT ["./application", "-Dquarkus.http.host=0.0.0.0"]
```

> Native + `quarkus-micro`/`ubi-minimal` (or distroless) yields a tiny image with no JVM and minimal OS surface. Prefer it when cold-start/size matter and your dependencies support native compilation.

## Frontend — Angular SPA → Nginx, multi-stage

`.dockerignore`:

```gitignore
node_modules/
dist/
.git
.angular/
*.log
.env*
```

`Dockerfile` (Node builder → unprivileged Nginx runtime):

```dockerfile
# ---- build stage: compile the SPA ----
FROM node:24-alpine@sha256:<pin> AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci                                   # cached unless the lockfile changes
COPY . .
RUN npm run build -- --configuration=production

# ---- runtime stage: static files on a non-root Nginx ----
FROM nginxinc/nginx-unprivileged:1.27-alpine@sha256:<pin> AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/*/browser/ /usr/share/nginx/html/
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s CMD wget -qO- http://localhost:8080/ || exit 1
```

`nginx.conf` (history-API fallback + immutable hashed assets; `nginx-unprivileged` listens on 8080):

```nginx
server {
  listen 8080;
  root /usr/share/nginx/html;
  location / {
    try_files $uri $uri/ /index.html;        # SPA deep-link / refresh support
  }
  location /assets/ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }
}
```

> `nginxinc/nginx-unprivileged` already runs as a non-root user and binds an unprivileged port (8080), so no `USER`/`setcap` gymnastics. `npm ci` (not `npm install`) keeps installs lockfile-exact and reproducible.

## Secure `docker-compose.yml`

```yaml
services:
  api:
    build: ./backend
    image: app/api:dev
    ports: ["8080:8080"]
    environment:
      QUARKUS_HTTP_HOST: 0.0.0.0
    env_file: [.env]                 # secrets at runtime, never in the image
    read_only: true                  # immutable rootfs; app writes only to tmpfs
    tmpfs: ["/tmp"]
    security_opt: ["no-new-privileges:true"]
    cap_drop: ["ALL"]
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/q/health/ready"]
      interval: 15s
      timeout: 3s
      retries: 5
      start_period: 20s

  web:
    build: ./frontend
    image: app/web:dev
    ports: ["8081:8080"]
    read_only: true
    tmpfs: ["/tmp", "/var/cache/nginx", "/var/run"]
    security_opt: ["no-new-privileges:true"]
    cap_drop: ["ALL"]
    depends_on:
      api: { condition: service_healthy }
```

> `read_only` + `cap_drop: ALL` + `no-new-privileges` is defense in depth: even a compromised process can't write the filesystem, gain capabilities, or escalate. Grant back only what's needed via `tmpfs` mounts (Nginx needs writable cache/run dirs).

## Anti-patterns to refuse

- **Single-stage build** that ships Maven/JDK/npm/source in the final image. Bloated and a huge attack surface — split into builder + runtime.
- **`FROM image:latest`** or tag-only pins. Non-reproducible; a mutated upstream tag silently changes your build. Pin the digest.
- **Running as root.** Default unless you add a `USER`. Use an unprivileged uid or a `:nonroot`/unprivileged base.
- **`COPY . .` without a `.dockerignore`.** Drags `node_modules`, `target`, `.git`, and `.env` into context — slow builds and leaked secrets.
- **Secrets via `ENV`/`ARG` or `COPY`'d keystores.** They persist in image history. Use runtime env/mounts or `RUN --mount=type=secret`.
- **`apk/apt` install without cleanup, or in the runtime stage.** Put tooling in the builder; keep the runtime minimal.
- **No `HEALTHCHECK`.** Orchestrators can't tell ready from merely running.
- **`npm install` in the image build.** Use `npm ci` for lockfile-exact, reproducible installs.

## Post-generation

Tell the user:
- Which targets were containerized and the exact `docker build` / `docker compose up --build` commands.
- That base-image **digests are placeholders** (`@sha256:<pin>`) — resolve real ones with `docker buildx imagetools inspect <image>:<tag>` (or context7) before committing.
- How to verify: build, `docker compose up -d`, hit the health endpoints, and run `docker compose exec api id` to confirm a non-root uid.
- To run an image scan (`trivy image app/api:dev`) and generate an SBOM — see [`dependency-supply-chain-security`](../dependency-supply-chain-security/SKILL.md) for wiring that into CI.
- For multi-service runtime deps (Postgres/MinIO, env defaults, `start.sh`), see [`dockerized-quarkus-runtime`](../dockerized-quarkus-runtime/SKILL.md).

---

## Strategic considerations & governance

## Goal

Every image is small, reproducible, and runs with least privilege: no build tooling or secrets in the final layers, pinned by digest, non-root, health-checked — so a CVE in a build tool or a leaked tag can't reach production, and a compromised process can't escalate.

## Image rules

- Multi-stage with a minimal, digest-pinned runtime base; never `:latest`.
- Non-root user in every runtime image; `HEALTHCHECK` present.
- `.dockerignore` excludes VCS, dependencies, build output, and all secrets.
- Secrets enter at runtime or via build secrets — never via `ENV`/`ARG`/`COPY`.
- Dependency layers are resolved before source is copied, for cache reuse.

## Quality gates

- The final image contains no Maven/JDK/npm/source — only the runtime + artifact.
- `docker history <image>` shows no secret values and no `:latest` bases.
- `docker compose exec <svc> id` reports a non-root uid.
- Containers run with `read_only`, `cap_drop: ALL`, and `no-new-privileges`.
- An image scan (Trivy) passes the agreed severity threshold before release.

## Example

For the catalog app: the Quarkus API builds in a `maven:…temurin-21` stage with a cached `.m2` layer, then ships its `quarkus-app/` layout on `temurin-21-jre-alpine` as uid `app`; the Angular SPA builds with `node:24-alpine` and serves from `nginx-unprivileged:1.27-alpine` on port 8080. Compose runs both read-only with all capabilities dropped, gates `web` on the API's health, and injects secrets from `.env` at runtime — never into a layer.
