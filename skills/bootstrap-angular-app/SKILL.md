---
name: bootstrap-angular-app
description: "Scaffold a new standalone Angular frontend (signals, standalone components, Tailwind CSS) in its OWN repository, wired to consume a Quarkus REST API through a generated typescript-angular OpenAPI client. Sets up the project structure (core/features/shared), HttpClient providers, per-environment API URL config, a dev proxy, and the npm scripts that regenerate the API client from the backend's /q/openapi spec. Use whenever the user wants to start an Angular app, create a frontend for a Quarkus/REST backend, scaffold an Angular SPA, or asks 'create the Angular project' / 'set up the frontend' — even if they don't mention OpenAPI or Tailwind explicitly."
---

# bootstrap-angular-app

Scaffold a production-shaped Angular SPA that talks to a Quarkus REST API (the backend this repo's skills build). The frontend lives in its **own repository**, consumes the API over HTTP, and gets its typed client **generated** from the backend's OpenAPI document rather than hand-written — so the contract stays in sync.

After running, the project has:

- A standalone Angular app (no NgModules) using signals and the functional `provideHttpClient` / `provideRouter` APIs
- Tailwind CSS wired into the Angular build
- A `core / features / shared` folder structure
- A generated API client under `src/app/api` (regenerable with `npm run api:gen`)
- Per-environment API base URL (`environment.ts` / `environment.prod.ts`)
- A dev proxy so `ng serve` reaches the backend without CORS pain
- Ready hand-off points for [`add-angular-jwt-auth`](../add-angular-jwt-auth/SKILL.md), [`add-primeng-ui`](../add-primeng-ui/SKILL.md), and [`add-angular-ci`](../add-angular-ci/SKILL.md)

## When to invoke

- "Create the Angular frontend for my API"
- "Set up a new Angular app"
- "Scaffold the SPA that consumes the Quarkus backend"
- Implicitly: the first frontend step, before `add-angular-jwt-auth` (auth) and `add-angular-ci` (pipeline).

## Inputs to collect

Ask these in **one** consolidated message — don't go one at a time.

| Input | Default |
|---|---|
| App name | derive from backend (e.g. `catalog-web`) |
| Backend base URL (dev) | `http://localhost:8080` |
| Backend base URL (prod) | ask — e.g. `https://api.example.com` |
| OpenAPI source | `${devBackend}/q/openapi` (Quarkus serves it here) |
| API path prefix | `/v1` (matches this repo's resources) |
| Package manager | `npm` |

## Prerequisites

- **Node ≥ 24** (current LTS) and the Angular 21 CLI (`npm i -g @angular/cli@21`). Confirm `node -v` before scaffolding; abort with a clear message if older — Angular 21 requires an actively-supported Node line.
- The backend must expose its OpenAPI document. Quarkus serves it at `/q/openapi` (YAML) when `quarkus-smallrye-openapi` is present — which the [`api-docs-openapi-health`](../api-docs-openapi-health/SKILL.md) skill sets up. If it's unreachable, fall back to a committed `openapi.yaml` and tell the user to refresh it when the API changes.

> This skill produces the **Angular-side** client. It complements [`add-openapi-client-gen`](../add-openapi-client-gen/SKILL.md), which generates SDKs from the backend side; here the generated client is owned by and versioned with the frontend repo.

## Workflow

1. Verify Node version and that the target directory is empty / a fresh git repo.
2. Scaffold the app (standalone is the modern default; routing on; CSS so Tailwind owns styling):
   ```bash
   npx @angular/cli@21 new {{appName}} --standalone --routing --style=css --ssr=false
   cd {{appName}}
   ```
3. Add Tailwind (see "Tailwind setup" below).
4. Create the folder structure and the config/env files (below).
5. Add the OpenAPI generator and the `api:gen` script, then generate the client once.
6. Wire `provideHttpClient` and the API base-URL injection token in `app.config.ts`.
7. Add the dev proxy and point `ng serve` at it.
8. Verify: `npm run api:gen && npm run build` succeeds and `ng serve` boots.

## Project structure

Organize by responsibility so features stay independent and the generated client is quarantined in one place:

```
src/app/
  core/            # singletons: interceptors, guards, app-wide services, the API base-url token
  features/        # one folder per feature area (lazy-loaded routes)
  shared/          # dumb/presentational components, pipes, directives
  api/             # GENERATED — do not edit by hand (openapi-generator output)
```

> Keep `api/` generated-only. Editing it by hand means the next `npm run api:gen` silently wipes your changes — a classic source of "it worked yesterday" bugs.

## Tailwind setup

Install and register Tailwind's PostCSS plugin (Tailwind v4 style):

```bash
npm i -D tailwindcss @tailwindcss/postcss postcss
```

`.postcssrc.json` (Angular's esbuild builder picks this up automatically):

```json
{ "plugins": { "@tailwindcss/postcss": {} } }
```

`src/styles.css`:

```css
@import "tailwindcss";
```

> On Tailwind v3, use `npx tailwindcss init`, set `content: ["./src/**/*.{html,ts}"]`, and the three `@tailwind base/components/utilities` directives instead. The design skills (`frontend-design`, `ui-ux-pro-max`) already assume a Tailwind project, so this keeps them effective.

## Files to generate

### `src/environments/environment.ts` / `environment.prod.ts`

```ts
// environment.ts (dev)
export const environment = {
  production: false,
  apiBaseUrl: '/{{apiPrefix}}', // proxied by ng serve to the backend
};
```

```ts
// environment.prod.ts
export const environment = {
  production: true,
  apiBaseUrl: 'https://api.example.com/{{apiPrefix}}',
};
```

> Build-time envs are the simplest path. If you deploy one static build to multiple stages, prefer **runtime config** instead: fetch `assets/config.json` at startup (`APP_INITIALIZER`) and substitute it per environment at deploy time — that keeps one artifact promotable across stages. Mention this option to the user; default to build-time unless they ask.

### `src/app/core/api-base-url.ts`

The generated client takes its base path via DI, so we never hardcode the host inside feature code:

```ts
import { InjectionToken } from '@angular/core';
import { environment } from '../../environments/environment';

export const API_BASE_URL = new InjectionToken<string>('API_BASE_URL', {
  providedIn: 'root',
  factory: () => environment.apiBaseUrl,
});
```

### `src/app/app.config.ts`

```ts
import { ApplicationConfig, provideZoneChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withFetch } from '@angular/common/http';
import { routes } from './app.routes';
import { Configuration } from './api'; // generated client config

export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes),
    provideHttpClient(withFetch()),
    // Point the generated client at our base URL. The exact wiring depends on the
    // generator; for typescript-angular, provide a Configuration with basePath.
    {
      provide: Configuration,
      useFactory: () => new Configuration({ basePath: '' }), // base path handled by interceptor/env
    },
  ],
};
```

> Auth interceptors are added by [`add-angular-jwt-auth`](../add-angular-jwt-auth/SKILL.md) via `withInterceptors([...])`. Leave a clear seam here.

### `proxy.conf.json` (dev only)

```json
{
  "/{{apiPrefix}}": {
    "target": "{{devBackend}}",
    "secure": false,
    "changeOrigin": true
  }
}
```

Wire it into `angular.json` under `serve > options`:

```json
"proxyConfig": "proxy.conf.json"
```

> The proxy means dev requests are same-origin (`/v1/...`), so the browser never blocks them on CORS. In prod the SPA is on a different origin from the API, so the backend must allow it — that's the `CORS_ALLOWED_ORIGINS` env the Quarkus app reads. Remind the user to set it to the deployed frontend origin.

## OpenAPI client generation

Add the generator and a script that rebuilds the typed client from the live spec:

```bash
npm i -D @openapitools/openapi-generator-cli
```

`package.json` scripts:

```json
{
  "scripts": {
    "api:gen": "openapi-generator-cli generate -i {{openapiSource}} -g typescript-angular -o src/app/api --additional-properties=ngVersion=21.0.0,withInterfaces=true,fileNaming=kebab-case",
    "api:gen:offline": "openapi-generator-cli generate -i openapi.yaml -g typescript-angular -o src/app/api --additional-properties=ngVersion=21.0.0,withInterfaces=true,fileNaming=kebab-case"
  }
}
```

> Keep `ngVersion` in step with the Angular major you scaffolded (21 here) so the generated client matches the app's APIs. Commit the **generated output** so the repo builds without the backend running, but always regenerate from the source of truth (`/q/openapi`) when the API changes — never hand-edit. CI verifies the committed client is in sync (see `add-angular-ci`).

### Example feature consuming the client

```ts
// features/genres/genres-list.component.ts
import { Component, inject, signal } from '@angular/core';
import { GenresService } from '../../api'; // generated service

@Component({
  selector: 'app-genres-list',
  standalone: true,
  template: `
    <ul class="divide-y">
      @for (g of genres(); track g.id) {
        <li class="py-2">{{ g.name }}</li>
      }
    </ul>
  `,
})
export class GenresListComponent {
  private api = inject(GenresService);
  genres = signal<unknown[]>([]);

  constructor() {
    this.api.list().subscribe((data) => this.genres.set(data));
  }
}
```

> Feature code depends on the **generated service**, not on raw `HttpClient` URLs. When the backend renames an endpoint or a field, regeneration surfaces the break at compile time instead of at runtime.

## Anti-patterns to refuse

- **Hand-writing HTTP calls / DTO interfaces** that the OpenAPI client already generates. Duplicated, drifts silently. Generate them.
- **Editing files under `src/app/api`.** It's generated; changes vanish on regen. Wrap/extend in `core` or `features` instead.
- **Hardcoding the API host** in components. Use the env + `API_BASE_URL` token so dev/prod differ by config, not code.
- **Baking secrets into the SPA.** Anything in the bundle is public. API keys, client secrets, private config do not belong in an Angular build.
- **Disabling CORS by setting `*` in production** just to make it work. Set `CORS_ALLOWED_ORIGINS` to the real frontend origin.
- **Generating NgModules.** This repo targets standalone Angular; keep it module-free.

## Post-generation

Tell the user:
- The dev workflow: `npm start` (serves on `:4200`, proxies `/v1` to the backend).
- That `npm run api:gen` regenerates the client whenever the API changes.
- The prod API URL they must set in `environment.prod.ts` (or runtime `config.json`), and that the backend's `CORS_ALLOWED_ORIGINS` must include the deployed frontend origin.
- Next steps: run [`add-angular-jwt-auth`](../add-angular-jwt-auth/SKILL.md) for login/guards, [`add-primeng-ui`](../add-primeng-ui/SKILL.md) if you want a component library (PrimeNG + Tailwind), then [`add-angular-ci`](../add-angular-ci/SKILL.md) for the pipeline.

---

## Strategic considerations & governance

## Goal

Stand up a frontend that is decoupled from the backend at the network boundary but coupled to it at the **contract** boundary — so the two repos evolve independently yet a breaking API change is caught at frontend build time.

## Design rules

- The API contract flows one way: backend OpenAPI → generated client → feature code. Never re-describe DTOs by hand.
- Configuration, not code, distinguishes environments. One build artifact should be promotable when runtime config is used.
- Keep the generated client isolated and treat it as a build input, not source to edit.
- Presentational components in `shared` stay free of HTTP and routing concerns; data fetching lives in feature containers or services.

## Quality gates

- `npm run build` (prod) and `npm run api:gen` both succeed from a clean checkout.
- No component imports `HttpClient` to call an endpoint the generated client already covers.
- No secret or environment-specific host is hardcoded in committed source.
- Dev serve reaches the backend via proxy; prod origin is covered by backend CORS.

## Example

For a music catalog API, scaffold `catalog-web` with `features/albums`, `features/artists`, a generated client from `http://localhost:8080/q/openapi`, Tailwind styling, and a dev proxy — leaving auth and CI to the companion skills.
