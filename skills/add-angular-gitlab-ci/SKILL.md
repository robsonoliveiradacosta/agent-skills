---
name: add-angular-gitlab-ci
description: "Generate a GitLab CI/CD pipeline (.gitlab-ci.yml) for an Angular SPA repo — install, lint, headless unit tests, prod build, an OpenAPI-client drift check (fails if the committed generated client is stale vs the backend spec), and deploy of the static build. Supports three deploy targets: a Kaniko-built Nginx image pushed to the GitLab Container Registry, AWS S3 + CloudFront (via GitLab ID tokens/OIDC), and Vercel. Use whenever the user wants CI/CD on GitLab for an Angular frontend, a .gitlab-ci.yml for their SPA, GitLab pipelines for the frontend, automated frontend deploys on GitLab, or asks to 'set up the pipeline'/'deploy the Angular app' on GitLab. This is the GitLab counterpart to add-angular-ci (which targets GitHub Actions)."
---

# add-angular-gitlab-ci

Generate a `.gitlab-ci.yml` for an Angular SPA in its **own repo** (scaffolded by [`bootstrap-angular-app`](../bootstrap-angular-app/SKILL.md)) that deploys to a **static host** — the GitLab counterpart to [`add-angular-ci`](../add-angular-ci/SKILL.md) (GitHub Actions). Same pipeline, GitLab idioms: stages, `cache:`, `rules:`, CI/CD variables, ID tokens for OIDC, and the built-in Container Registry.

After running, the repo has:

- `.gitlab-ci.yml` — install + lint + headless test + client-drift check on every MR
- A deploy job for the chosen target (Nginx image, S3+CloudFront, or Vercel)
- Headless-Chrome test config so unit tests run in CI
- A documented set of CI/CD variables

## When to invoke

- "Set up GitLab CI for the Angular app"
- "Deploy the frontend automatically on GitLab"
- "Add a `.gitlab-ci.yml` / build + deploy for my SPA"
- Implicitly: after `bootstrap-angular-app` and `add-angular-jwt-auth`, on a GitLab-hosted repo.

## Inputs to collect

| Input | Default |
|---|---|
| Node version | `24` (current LTS, matches Angular 21) |
| Package manager | `npm` (uses `npm ci`) |
| Deploy target | ask: `nginx` \| `s3-cloudfront` \| `vercel` |
| Deploy on | default branch (and tags, if releasing) |
| Backend OpenAPI URL for drift check | `${PROD_OR_STAGING}/q/openapi`, or the committed `openapi.yaml` |
| Prod API base URL | for the build's `environment.prod.ts` / runtime config |

## Why a client-drift check

The frontend consumes a **generated** OpenAPI client (see `bootstrap-angular-app`). If the backend contract changes and the committed client isn't regenerated, the app compiles against a stale contract and breaks at runtime. The pipeline regenerates the client in CI and fails if it differs from what's committed — turning a silent runtime break into a loud, early pipeline failure. If CI can't reach a running backend, point the check at the committed `openapi.yaml` and treat that file as the contract of record.

## Library / framework grounding (context7)

GitLab CI keyword semantics (`rules:`, `workflow:`, `id_tokens:`), the OIDC/ID-token flow for AWS, and the `openapi-generator-cli` flags all change across releases. Before writing the file, verify current syntax via `mcp__context7__query-docs` (e.g. `"gitlab ci id_tokens aws oidc"`, `"gitlab ci rules if merge_request"`, `"openapi-generator-cli typescript-angular"`). A wrong ID-token audience makes the AWS role assumption fail at deploy time.

- **If context7 is not installed** (the `mcp__context7__*` tools aren't present): proceed with training data, but say so once at the end and point the user at `AGENTS.md` §"MCP servers (context7)" for the install one-liner.

## Headless test config

If the project uses Karma, add a CI launcher in `karma.conf.js`:

```js
browsers: ['ChromeHeadlessCI'],
customLaunchers: {
  ChromeHeadlessCI: { base: 'ChromeHeadless', flags: ['--no-sandbox'] },
},
singleRun: true,
```

Run with `ng test --watch=false --browsers=ChromeHeadlessCI`. (Projects using Jest/Vitest can skip this and call their runner directly.)

## Core pipeline — `.gitlab-ci.yml`

```yaml
stages: [test, build, deploy]

variables:
  npm_config_cache: "$CI_PROJECT_DIR/.npm"

workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG

.node:
  image: node:24
  cache:
    key:
      files: [package-lock.json]
    paths: [.npm, node_modules]
  before_script:
    - npm ci --cache .npm --prefer-offline

# ──────────────────────────────────────────────────────────────
lint:
  extends: .node
  stage: test
  script:
    - npm run lint --if-present

unit-tests:
  extends: .node
  stage: test
  image: node:24                       # has Chromium deps? if not, use a browsers image
  variables:
    CHROME_BIN: /usr/bin/chromium
  before_script:
    - apt-get update && apt-get install -y chromium
    - npm ci --cache .npm --prefer-offline
  script:
    - npm test -- --watch=false --browsers=ChromeHeadlessCI
  artifacts:
    when: always
    reports:
      junit: ["junit/*.xml"]           # if your runner emits JUnit; else omit
    expire_in: 1 week

client-drift:
  extends: .node
  stage: test
  script:
    - npm run api:gen
    - |
      if ! git diff --quiet -- src/app/api; then
        echo "Generated API client is out of date. Run 'npm run api:gen' and commit the result."
        git diff --stat -- src/app/api
        exit 1
      fi

build:
  extends: .node
  stage: build
  script:
    - npm run build -- --configuration=production
  artifacts:
    paths: [dist/]
    expire_in: 1 week
```

> The drift job runs `api:gen` then fails if it produced changes — a clean working tree means the committed client matches the spec. Use `api:gen:offline` against the committed `openapi.yaml` if CI has no backend to reach.

## Deploy job — pick ONE target

Each deploy job `needs: [build]`, runs only on the default branch, and must provide **history-API fallback** (every unknown path serves `index.html`) so deep links and refresh work.

### Target A — Nginx image (GitLab Container Registry, via Kaniko)

`Dockerfile`:

```dockerfile
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/*/browser/ /usr/share/nginx/html/
```

`nginx.conf` (SPA fallback + immutable hashed assets; unprivileged Nginx listens on 8080):

```nginx
server {
  listen 8080;
  root /usr/share/nginx/html;
  location / {
    try_files $uri $uri/ /index.html;   # history-API fallback
  }
  location /assets/ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }
}
```

Deploy job:

```yaml
deploy:
  stage: deploy
  needs: [build]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  image:
    name: gcr.io/kaniko-project/executor:debug
    entrypoint: [""]
  script:
    - mkdir -p /kaniko/.docker
    - echo "{\"auths\":{\"$CI_REGISTRY\":{\"username\":\"$CI_REGISTRY_USER\",\"password\":\"$CI_REGISTRY_PASSWORD\"}}}" > /kaniko/.docker/config.json
    - /kaniko/executor --context "$CI_PROJECT_DIR" --dockerfile "$CI_PROJECT_DIR/Dockerfile"
        --destination "$CI_REGISTRY_IMAGE:latest"
        --destination "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA"
```

> Kaniko builds the image without a privileged Docker daemon — works on shared runners. `CI_REGISTRY*` variables are predefined by GitLab for the built-in registry.

### Target B — AWS S3 + CloudFront (OIDC via GitLab ID tokens)

```yaml
deploy:
  stage: deploy
  needs: [build]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  image: amazon/aws-cli:latest
  id_tokens:
    AWS_ID_TOKEN:
      aud: https://gitlab.com            # must match the IAM OIDC provider's audience
  before_script:
    - >
      export $(aws sts assume-role-with-web-identity
      --role-arn "$AWS_DEPLOY_ROLE_ARN"
      --role-session-name "gitlab-$CI_PIPELINE_ID"
      --web-identity-token "$AWS_ID_TOKEN"
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'
      --output text | awk '{print "AWS_ACCESS_KEY_ID="$1" AWS_SECRET_ACCESS_KEY="$2" AWS_SESSION_TOKEN="$3}')
  script:
    - aws s3 sync dist/*/browser/ "s3://$S3_BUCKET/" --delete
    - aws cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" --paths "/*"
```

> Configure the CloudFront distribution (or S3 error document) to return `/index.html` with 200 for 403/404 so client routes resolve. GitLab **ID tokens** let you assume an AWS role with no long-lived keys stored in the project — far safer than static `AWS_ACCESS_KEY_ID` variables.

### Target C — Vercel

```yaml
deploy:
  stage: deploy
  needs: [build]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  image: node:24
  script:
    - npx vercel deploy --prebuilt --prod --token="$VERCEL_TOKEN"
  variables:
    VERCEL_ORG_ID: "$VERCEL_ORG_ID"
    VERCEL_PROJECT_ID: "$VERCEL_PROJECT_ID"
```

> Add a `vercel.json` with a catch-all rewrite to `/index.html` for SPA routing. Vercel handles caching and immutable hashed assets by default.

## CI/CD variables (by target)

| Target | Variables (Settings → CI/CD → Variables, masked + protected) |
|---|---|
| Nginx/Registry | none beyond predefined `CI_REGISTRY*` |
| S3+CloudFront | `AWS_DEPLOY_ROLE_ARN`, `S3_BUCKET`, `CF_DISTRIBUTION_ID` (no static AWS keys — OIDC) |
| Vercel | `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` |

> Prefer **GitLab ID tokens (OIDC)** over long-lived AWS keys — nothing to leak or rotate. Store the prod API URL as build/runtime config, not as a secret baked into the repo.

## Anti-patterns to refuse

- **Skipping the SPA history fallback.** Without it, refreshing on `/albums/42` 404s. Every target must serve `index.html` for unknown paths.
- **Deploying without the client-drift check.** Lets a stale contract ship silently. Keep the gate.
- **Static AWS keys** in CI/CD variables when ID tokens are available. Use OIDC role assumption.
- **`npm install` in CI.** Use `npm ci` for reproducible, lockfile-exact installs.
- **`docker build` on shared runners.** No daemon; use Kaniko.
- **Caching `index.html` aggressively.** Hashed assets are immutable and cache forever; `index.html` must stay short-lived so new deploys are picked up.
- **Running the full pipeline on every branch push.** `workflow.rules` scopes to MRs, default branch, and tags.

## Post-generation

Tell the user:
- Which target was wired and the exact CI/CD variables to add under Settings → CI/CD → Variables.
- That the first deploy needs the host provisioned (bucket+distribution + IAM OIDC trust for `gitlab.com`, Vercel project, or registry access for the image).
- For S3/CloudFront OIDC: the IAM identity provider must trust GitLab's issuer and the role's trust policy must match the `aud` and `sub` (e.g. `project_path:...:ref_type:branch:ref:main`).
- The backend `CORS_ALLOWED_ORIGINS` must include the deployed frontend origin.
- How to test: open an MR (test/drift run), merge to the default branch (deploy runs).

---

## Strategic considerations & governance

## Goal

Make every merge to the default branch produce a tested, contract-verified, deployed frontend with no manual steps — and make a broken API contract or a routing misconfiguration fail loudly in the pipeline rather than silently in production. Same guarantees as the GitHub pipeline, in GitLab idioms.

## Pipeline rules

- Test/lint/drift on every MR; deploy only from the default branch (or tags).
- The generated client is verified against the contract of record on each run.
- Static hosting always serves `index.html` for unknown routes; hashed assets are immutable, `index.html` is not cached.
- Credentials come from CI/CD variables or ID tokens (OIDC), never the repo.

## Quality gates

- An MR that changes the backend contract without regenerating the client fails the drift job.
- Deep-linking and refresh work on the deployed host (history fallback present).
- A new deploy is visible to users without a hard refresh (cache invalidation / non-cached index).
- No secret appears in committed files or job logs.

## Example

For the catalog SPA on S3+CloudFront: MRs run lint/test/drift/build; merges to `main` assume an AWS role via a GitLab ID token, sync `dist` to the bucket, and invalidate the distribution; CloudFront returns `index.html` for client routes; the prod API URL is injected at build and the backend allows the CloudFront origin via CORS.
