---
name: add-angular-ci
description: "Generate a GitHub Actions pipeline for an Angular SPA repo — install, lint, headless unit tests, prod build, an OpenAPI-client drift check (fails if the committed generated client is stale vs the backend spec), and deploy of the static build to a static host. Supports three deploy targets: Nginx/Docker image, AWS S3 + CloudFront, and Vercel. Use whenever the user wants CI/CD for an Angular frontend, a build/test/deploy pipeline, GitHub Actions for their SPA, automated frontend deploys, or asks 'set up the pipeline' / 'deploy the Angular app'."
---

# add-angular-ci

Generate a CI/CD pipeline for an Angular SPA that lives in its **own repo** (scaffolded by [`bootstrap-angular-app`](../bootstrap-angular-app/SKILL.md)) and deploys to a **static host**. The pipeline builds, lints, tests headlessly, verifies the generated API client hasn't drifted, and publishes the static bundle.

After running, the repo has:

- `.github/workflows/ci.yml` — build + lint + test + client-drift check on every push/PR
- A deploy job for the chosen target (Nginx image, S3+CloudFront, or Vercel)
- Headless-Chrome test config so unit tests run in CI
- A documented set of required secrets

## When to invoke

- "Set up CI for the Angular app"
- "Deploy the frontend automatically"
- "Add a GitHub Actions pipeline / build + deploy for my SPA"
- Implicitly: after `bootstrap-angular-app` and `add-angular-jwt-auth`.

## Inputs to collect

| Input | Default |
|---|---|
| Node version | `24` (current LTS, matches Angular 21) |
| Package manager | `npm` (uses `npm ci`) |
| Deploy target | ask: `nginx` \| `s3-cloudfront` \| `vercel` |
| Deploy on | push to `main` (and tags, if releasing) |
| Backend OpenAPI URL for drift check | `${PROD_OR_STAGING}/q/openapi`, or the committed `openapi.yaml` |
| Prod API base URL | for the build's `environment.prod.ts` / runtime config |

## Why a client-drift check

The frontend consumes a **generated** OpenAPI client (see `bootstrap-angular-app`). If someone changes the backend contract and the committed client isn't regenerated, the app compiles against a stale contract and breaks at runtime. The pipeline regenerates the client in CI and fails if it differs from what's committed — turning a silent runtime break into a loud, early build failure. If CI can't reach a running backend, point the check at the committed `openapi.yaml` and treat that file as the contract of record.

## Workflow

1. Confirm the repo builds locally (`npm ci && npm run build`).
2. Make unit tests headless (Karma ChromeHeadless or your runner's equivalent).
3. Write `.github/workflows/ci.yml` with the build/test/drift jobs.
4. Append the deploy job for the chosen target.
5. List the secrets the user must add in GitHub repo settings.
6. Verify by pushing a branch and opening a PR.

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

## Core pipeline — `.github/workflows/ci.yml`

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
          cache: 'npm'
      - run: npm ci

      - name: Lint
        run: npm run lint --if-present

      - name: Unit tests (headless)
        run: npm test -- --watch=false --browsers=ChromeHeadlessCI

      - name: Verify generated API client is in sync
        run: |
          npm run api:gen
          if ! git diff --quiet -- src/app/api; then
            echo "::error::Generated API client is out of date. Run 'npm run api:gen' and commit the result."
            git diff --stat -- src/app/api
            exit 1
          fi

      - name: Production build
        run: npm run build -- --configuration=production

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/
```

> The drift step runs `api:gen` then fails if it produced changes — a clean working tree means the committed client matches the spec. Use `api:gen:offline` against the committed `openapi.yaml` if CI has no backend to reach.

## Deploy job — pick ONE target

Add a `deploy` job that needs `build-test` and only runs on `main`. SPAs need **history-API fallback** (every unknown path serves `index.html`) so deep links and refresh work — each target below handles that.

### Target A — Nginx (Docker image)

`Dockerfile`:

```dockerfile
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/*/browser/ /usr/share/nginx/html/
```

`nginx.conf` (SPA fallback + sane caching):

```nginx
server {
  listen 80;
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
    needs: build-test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with: { name: dist, path: dist }
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ghcr.io/${{ github.repository }}:latest
```

### Target B — AWS S3 + CloudFront

```yaml
  deploy:
    needs: build-test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with: { name: dist, path: dist }
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}   # prefer OIDC over static keys
          aws-region: ${{ secrets.AWS_REGION }}
      - name: Sync to S3
        run: aws s3 sync dist/*/browser/ s3://${{ secrets.S3_BUCKET }}/ --delete
      - name: Invalidate CloudFront
        run: aws cloudfront create-invalidation --distribution-id ${{ secrets.CF_DISTRIBUTION_ID }} --paths "/*"
```

> Configure the CloudFront distribution (or S3 static-site error document) to return `/index.html` with 200 for 403/404 so client-side routes resolve. The CloudFront invalidation ensures users get the new bundle instead of a cached old one.

### Target C — Vercel

```yaml
  deploy:
    needs: build-test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with: { name: dist, path: dist }
      - name: Deploy to Vercel
        run: npx vercel deploy --prebuilt --prod --token=${{ secrets.VERCEL_TOKEN }}
        env:
          VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
          VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
```

> Add a `vercel.json` with a catch-all rewrite to `/index.html` for SPA routing. Vercel's static config handles caching and immutable hashed assets by default.

## Required secrets (by target)

| Target | Secrets |
|---|---|
| Nginx/GHCR | none beyond the built-in `GITHUB_TOKEN` |
| S3+CloudFront | `AWS_DEPLOY_ROLE_ARN` (OIDC), `AWS_REGION`, `S3_BUCKET`, `CF_DISTRIBUTION_ID` |
| Vercel | `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` |

> Prefer **OIDC role assumption** over long-lived AWS access keys — no static secret to leak or rotate. Store the prod API URL as config consumed at build (or runtime), not as a secret baked into the repo.

## Anti-patterns to refuse

- **Skipping the SPA history fallback.** Without it, refreshing on `/albums/42` 404s. Every target must serve `index.html` for unknown paths.
- **Deploying without the client-drift check.** Lets a stale contract ship silently. Keep the gate.
- **Committing cloud credentials** or putting them in the workflow file. Use GitHub secrets / OIDC.
- **`npm install` in CI.** Use `npm ci` for reproducible, lockfile-exact installs.
- **Caching `index.html` aggressively.** Hashed assets are immutable and cache forever; `index.html` must stay short-lived so new deploys are picked up.
- **Deploying from PRs.** Gate deploy on `main` (or tags); PRs build and test only.

## Post-generation

Tell the user:
- Which target was wired and the exact secrets to add under repo Settings → Secrets.
- That the first deploy needs the host provisioned (bucket+distribution, Vercel project, or a registry/host for the image).
- The backend `CORS_ALLOWED_ORIGINS` must include the deployed frontend origin (the SPA and API are different origins in prod).
- How to test: push a branch, open a PR (build/test/drift run), merge to `main` (deploy runs).

---

## Strategic considerations & governance

## Goal

Make every merge to `main` produce a tested, contract-verified, deployed frontend with no manual steps — and make a broken API contract or a routing misconfiguration fail loudly in CI rather than silently in production.

## Pipeline rules

- Build/test/drift on every PR; deploy only from the protected branch.
- The generated client is verified against the contract of record on each run.
- Static hosting always serves `index.html` for unknown routes; hashed assets are immutable, `index.html` is not cached.
- Credentials come from secrets/OIDC, never the repo.

## Quality gates

- A PR that changes the backend contract without regenerating the client fails the drift check.
- Deep-linking and refresh work on the deployed host (history fallback present).
- A new deploy is visible to users without a hard refresh (cache invalidation / non-cached index).
- No secret appears in committed files or build logs.

## Example

For the catalog SPA on S3+CloudFront: PRs run lint/test/drift/build; merges to `main` sync `dist` to the bucket and invalidate the distribution; CloudFront returns `index.html` for client routes; the prod API URL is injected at build and the backend allows the CloudFront origin via CORS.
