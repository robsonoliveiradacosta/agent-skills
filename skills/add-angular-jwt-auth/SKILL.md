---
name: add-angular-jwt-auth
description: "Wire JWT authentication into an Angular SPA against a Quarkus SmallRye JWT backend (RS256, short-lived token + /v1/auth/refresh, roles USER/ADMIN). Generates an AuthService (login/refresh/logout), a functional HttpInterceptor that attaches the Bearer token, PROACTIVE token refresh before expiry (because the backend's refresh endpoint needs a still-valid token), functional route guards (authGuard + roleGuard), and a login component. Use whenever the user needs login on the frontend, protected Angular routes, role-based UI, 'add auth to my Angular app', token handling, or asks why their token expires / 401s after a few minutes."
---

# add-angular-jwt-auth

Add JWT login and role-based route protection to an Angular SPA that talks to a Quarkus backend secured with this repo's [`add-jwt-auth`](../add-jwt-auth/SKILL.md) skill. Assumes the project was scaffolded with [`bootstrap-angular-app`](../bootstrap-angular-app/SKILL.md).

After running, the app has:

- `POST /v1/auth/login` → store token; `logout()` to clear it
- A functional interceptor attaching `Authorization: Bearer <token>` to API calls
- **Proactive refresh**: the token is renewed shortly before it expires
- `authGuard` (must be logged in) and `roleGuard(['ADMIN'])` (must have a role)
- A `LoginComponent` and reactive auth state via signals

## The one thing that drives this whole design

The Quarkus backend issues a **5-minute** token and exposes `POST /v1/auth/refresh` annotated `@RolesAllowed({"USER","ADMIN"})` — meaning **refresh requires a still-valid token**. There is no separate long-lived refresh token or httpOnly cookie.

The naive "catch a 401, then refresh, then retry" pattern **does not work here**: by the time a request 401s, the token is already expired, and the refresh call will itself 401. So the correct approach is **proactive refresh** — schedule a renewal a little before `expiresIn` elapses, while the current token is still valid.

Make sure the user understands this; it's the difference between "auth works" and "users get logged out every 5 minutes for no clear reason."

## When to invoke

- "Add login to the Angular app"
- "Protect these routes / hide admin buttons from regular users"
- "My token keeps expiring / I get 401 after a few minutes"
- Implicitly: right after `bootstrap-angular-app`.

## Inputs to collect

| Input | Default |
|---|---|
| Auth endpoints | `POST /{{apiPrefix}}/auth/login`, `POST /{{apiPrefix}}/auth/refresh` |
| Token response shape | `{ token, expiresIn, username, role }` (matches `add-jwt-auth`) |
| Roles | `USER`, `ADMIN` |
| Token storage | in-memory (default) or `localStorage` — see the security note |
| Refresh lead time | refresh at `expiresIn − 30s` |

## Token storage: pick the trade-off deliberately

| Option | Survives page reload? | XSS exposure | Use when |
|---|---|---|---|
| **In-memory (default)** | No — user re-logs in on refresh/reopen | Lowest | You want the safest option and re-login on reload is acceptable |
| `localStorage` | Yes, until expiry | Token readable by any injected script | Reloads must keep the session and you accept the risk |

Because the backend has no httpOnly refresh cookie, **persisting across reloads securely isn't possible from the frontend alone**. If the product needs durable sessions, the right fix is on the backend (a long-lived refresh token in an httpOnly, SameSite cookie) — call that out rather than papering over it with `localStorage`. Default to in-memory.

## Workflow

1. Confirm the project came from `bootstrap-angular-app` (standalone, `provideHttpClient`, env + `API_BASE_URL`).
2. Create `AuthService`, the interceptor, and the guards (below).
3. Register the interceptor in `app.config.ts` via `withInterceptors([...])`.
4. Add a `/login` route + `LoginComponent`; protect feature routes with the guards.
5. Verify: log in, watch the network tab show a refresh call before the 5-minute mark, and confirm a protected route redirects when logged out.

## Files to generate

### `core/auth/auth.service.ts`

```ts
import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { environment } from '../../../environments/environment';
import { firstValueFrom } from 'rxjs';

interface TokenResponse {
  token: string;
  expiresIn: number; // seconds
  username: string;
  role: 'USER' | 'ADMIN';
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);
  private router = inject(Router);
  private base = environment.apiBaseUrl;

  // In-memory auth state. Swap to a storage-backed read here if the user opted into localStorage.
  private token = signal<string | null>(null);
  readonly user = signal<{ username: string; role: 'USER' | 'ADMIN' } | null>(null);
  readonly isLoggedIn = computed(() => this.token() !== null);
  private refreshTimer: ReturnType<typeof setTimeout> | null = null;

  getToken(): string | null {
    return this.token();
  }

  async login(username: string, password: string): Promise<void> {
    const res = await firstValueFrom(
      this.http.post<TokenResponse>(`${this.base}/auth/login`, { username, password }),
    );
    this.apply(res);
  }

  logout(): void {
    this.clearRefresh();
    this.token.set(null);
    this.user.set(null);
    this.router.navigateByUrl('/login');
  }

  private apply(res: TokenResponse): void {
    this.token.set(res.token);
    this.user.set({ username: res.username, role: res.role });
    this.scheduleRefresh(res.expiresIn);
  }

  // Proactive refresh: renew while the current token is still valid, because the
  // backend's /auth/refresh requires a valid token (it cannot revive an expired one).
  private scheduleRefresh(expiresInSeconds: number): void {
    this.clearRefresh();
    const leadMs = 30_000; // refresh 30s before expiry
    const delay = Math.max(expiresInSeconds * 1000 - leadMs, 0);
    this.refreshTimer = setTimeout(() => void this.refresh(), delay);
  }

  private async refresh(): Promise<void> {
    try {
      const res = await firstValueFrom(
        this.http.post<TokenResponse>(`${this.base}/auth/refresh`, {}),
      );
      this.apply(res);
    } catch {
      // Refresh failed (e.g. token already gone) — the only safe move is to re-authenticate.
      this.logout();
    }
  }

  private clearRefresh(): void {
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = null;
    }
  }
}
```

> The token response already carries `role` and `username`, so we don't decode the JWT on the client — simpler and avoids shipping a JWT-parsing dependency. (If you ever need claims the response omits, decode the payload but never *trust* it for security decisions; the server enforces authorization regardless.)

### `core/auth/auth.interceptor.ts`

```ts
import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthService } from './auth.service';
import { environment } from '../../../environments/environment';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const token = auth.getToken();

  // Only attach the token to our own API, never to third-party hosts.
  const isApiCall = req.url.startsWith(environment.apiBaseUrl) || req.url.startsWith('/');
  if (token && isApiCall) {
    req = req.clone({ setHeaders: { Authorization: `Bearer ${token}` } });
  }
  return next(req);
};
```

> Scope the header to your API. Blindly attaching the Bearer token to every outbound request would leak it to any third-party URL the app happens to call.

### `core/auth/auth.guards.ts`

```ts
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from './auth.service';

export const authGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth.isLoggedIn() ? true : router.createUrlTree(['/login']);
};

export const roleGuard = (allowed: Array<'USER' | 'ADMIN'>): CanActivateFn => {
  return () => {
    const auth = inject(AuthService);
    const router = inject(Router);
    const role = auth.user()?.role;
    if (role && allowed.includes(role)) return true;
    return router.createUrlTree([auth.isLoggedIn() ? '/forbidden' : '/login']);
  };
};
```

> Guards are a **UX** layer, not a security boundary. They hide routes the user can't use, but the server is the real gate — every protected endpoint is enforced by `@RolesAllowed` on the backend. Never move an authorization decision into the SPA only.

### Register in `app.config.ts`

```ts
import { provideHttpClient, withFetch, withInterceptors } from '@angular/common/http';
import { authInterceptor } from './core/auth/auth.interceptor';

// inside providers:
provideHttpClient(withFetch(), withInterceptors([authInterceptor])),
```

### Protect routes in `app.routes.ts`

```ts
import { Routes } from '@angular/router';
import { authGuard, roleGuard } from './core/auth/auth.guards';

export const routes: Routes = [
  { path: 'login', loadComponent: () => import('./features/auth/login.component').then(m => m.LoginComponent) },
  {
    path: 'albums',
    canActivate: [authGuard],
    loadComponent: () => import('./features/albums/albums.component').then(m => m.AlbumsComponent),
  },
  {
    path: 'admin',
    canActivate: [roleGuard(['ADMIN'])],
    loadComponent: () => import('./features/admin/admin.component').then(m => m.AdminComponent),
  },
];
```

### `features/auth/login.component.ts`

```ts
import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth/auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [FormsModule],
  template: `
    <form (ngSubmit)="submit()" class="mx-auto max-w-sm space-y-4 p-6">
      <input [(ngModel)]="username" name="username" placeholder="Username"
             class="w-full rounded border px-3 py-2" />
      <input [(ngModel)]="password" name="password" type="password" placeholder="Password"
             class="w-full rounded border px-3 py-2" />
      @if (error()) { <p class="text-sm text-red-600">{{ error() }}</p> }
      <button class="w-full rounded bg-black py-2 text-white" [disabled]="loading()">
        {{ loading() ? 'Signing in…' : 'Sign in' }}
      </button>
    </form>
  `,
})
export class LoginComponent {
  private auth = inject(AuthService);
  private router = inject(Router);
  username = '';
  password = '';
  loading = signal(false);
  error = signal<string | null>(null);

  async submit() {
    this.loading.set(true);
    this.error.set(null);
    try {
      await this.auth.login(this.username, this.password);
      await this.router.navigateByUrl('/');
    } catch {
      this.error.set('Invalid credentials'); // generic — don't reveal which field was wrong
    } finally {
      this.loading.set(false);
    }
  }
}
```

> Show a **generic** error on failed login. Telling the user "wrong password" vs "no such user" leaks which usernames exist — mirror the backend, which returns the same error for both.

### Role-aware UI

```html
@if (auth.user()?.role === 'ADMIN') {
  <button class="rounded bg-blue-600 px-3 py-1 text-white">New album</button>
}
```

## Anti-patterns to refuse

- **Reactive-only refresh (refresh on 401).** The backend can't refresh an expired token; you'll just chain 401s. Refresh proactively before expiry.
- **Treating guards as security.** They're UX. Authorization is enforced server-side; never drop a backend `@RolesAllowed` because "the route is guarded."
- **Attaching the Bearer token to every URL.** Scope it to the API origin so it never leaks to third parties.
- **Persisting the token in `localStorage` by default.** It's XSS-readable. Use it only when the user explicitly accepts the trade-off; prefer in-memory.
- **Decoding the JWT to make trust decisions.** Read display claims if needed, but the server is the authority.
- **Leaking which credential was wrong.** Keep login errors generic.

## Post-generation

Tell the user:
- How to test: log in with the backend's seeded `admin/admin123` or `user/user123`, then watch the refresh fire ~30s before the 5-minute mark.
- The storage choice made and its reload behavior (in-memory = re-login after reload).
- That durable sessions need a backend refresh-token/cookie change, not a frontend workaround.
- Guards added and which routes they protect.

---

## Strategic considerations & governance

## Goal

Give the SPA a correct, honest auth experience on top of a short-lived-token backend: keep sessions alive while the user is active, fail safe when they aren't, and never pretend the client enforces security.

## Security rules

- The server is the single source of authorization truth; the frontend only improves UX.
- Minimize token exposure: in-memory by default, scoped Bearer header, no secrets in the bundle.
- Refresh proactively while valid; on refresh failure, log out cleanly rather than looping.
- Generic auth errors; no user-enumeration via login responses.

## Quality gates

- A logged-in user stays logged in across the token lifespan without manual action (proactive refresh works).
- A logged-out user hitting a guarded route is redirected to `/login`.
- A `USER` hitting an `ADMIN` route is refused client-side AND the backend still returns 403 if called directly.
- No protected endpoint relies on the guard alone.

## Example

For the catalog app, protect `/albums` with `authGuard`, gate `/admin` behind `roleGuard(['ADMIN'])`, show the "New album" button only to admins, and confirm the token silently refreshes during a long editing session.
