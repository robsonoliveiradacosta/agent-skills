---
name: add-primeng-ui
description: "Wire PrimeNG (the Angular component library) into a standalone Angular app that already uses Tailwind, the modern v18+ way: install primeng + @primeng/themes, register providePrimeNG with a theme preset, and — critically — configure the CSS layer order so PrimeNG's theme and Tailwind's utilities stop fighting over specificity. Covers Reactive Forms integration, accessibility, and a p-table example. Use whenever the user wants PrimeNG, a component library for Angular, ready-made tables/dialogs/forms/datepickers, 'add PrimeNG', themed UI components, or asks why PrimeNG styles look broken / are overridden by Tailwind (or vice-versa)."
---

# add-primeng-ui

Add PrimeNG as the component library for a standalone Angular app that already uses Tailwind (scaffolded by [`bootstrap-angular-app`](../bootstrap-angular-app/SKILL.md)). PrimeNG supplies the rich widgets (tables, dialogs, dropdowns, date pickers, toasts); Tailwind stays for layout and spacing.

After running, the app has:

- `primeng` + `@primeng/themes` installed and `providePrimeNG` registered with a theme preset
- A **CSS layer order** that lets Tailwind utilities and the PrimeNG theme coexist predictably
- `provideAnimationsAsync()` wired (PrimeNG needs Angular animations)
- A working `p-table` example bound to data from the generated API client
- Reactive-Forms-friendly usage and a11y notes

## The one thing this skill exists to get right

PrimeNG v18+ dropped the old "import a theme CSS file" model. It now uses a **token-based theming engine** (`@primeng/themes`, presets like `Aura`) configured in code via `providePrimeNG`. And when Tailwind is also present, the two style systems collide on specificity unless you declare an explicit **CSS `@layer` order**.

The symptom users hit: *"my Tailwind classes don't override PrimeNG"* or *"PrimeNG components look unstyled / wrong after adding Tailwind."* The cause is layer ordering, not a bug. Get the `@layer` declaration right and both behave. This is the part the model routinely gets wrong, so it's the heart of the skill.

## When to invoke

- "Add PrimeNG to my Angular app"
- "I need a data table / dialog / dropdown component"
- "PrimeNG styles are broken / overridden by Tailwind"
- Implicitly: the UI step after `bootstrap-angular-app`, when the user wants a component library rather than hand-built widgets.

## Inputs to collect

| Input | Default |
|---|---|
| Theme preset | `Aura` (also: `Material`, `Lara`, `Nora`) |
| Dark mode selector | `.dark` (Tailwind-compatible class strategy) |
| Ripple effect | on |
| Tailwind present? | yes — assume the `bootstrap-angular-app` setup |

## Prerequisites

- A standalone Angular 21 app with Tailwind already configured (`bootstrap-angular-app`).
- Angular animations available — this skill adds `provideAnimationsAsync()` if missing.

## Workflow

1. Install dependencies.
2. Register `providePrimeNG` + animations in `app.config.ts`.
3. **Set the CSS layer order** in `styles.css` (the critical step).
4. Add a PrimeNG component (the `p-table` example) consuming the generated API client.
5. Verify: the table renders themed, and a Tailwind utility (e.g. `mt-4`) visibly applies to a PrimeNG element.

## Install

```bash
npm i primeng @primeng/themes
npm i -D primeicons   # icon font used by many components
```

## `app.config.ts` — theme + animations

```ts
import { ApplicationConfig } from '@angular/core';
import { provideAnimationsAsync } from '@angular/platform-browser/animations/async';
import { providePrimeNG } from 'primeng/config';
import Aura from '@primeng/themes/aura';

export const appConfig: ApplicationConfig = {
  providers: [
    // ...existing providers (router, http) from bootstrap-angular-app
    provideAnimationsAsync(),
    providePrimeNG({
      theme: {
        preset: Aura,
        options: {
          // Render PrimeNG's theme into a named CSS layer so we control ordering
          // relative to Tailwind. Without this, specificity battles are unpredictable.
          cssLayer: { name: 'primeng', order: 'theme, base, primeng, utilities' },
          // Tailwind-compatible dark mode: toggled by a `.dark` class on <html>.
          darkModeSelector: '.dark',
        },
      },
    }),
  ],
};
```

> `provideAnimationsAsync()` is required — PrimeNG overlays (dialogs, dropdowns, toasts) animate, and they silently misbehave without it. Import the theme **preset object** from `@primeng/themes`, not a CSS file; the v17-and-earlier `styles.css` theme imports no longer apply.

## `styles.css` — the CSS layer order (critical)

```css
/* Declare the layer order ONCE, before anything else.
   Later layers win specificity ties, so utilities must come last to let
   Tailwind classes override PrimeNG component defaults when you need them to. */
@layer tailwind-base, primeng, tailwind-utilities;

@import "tailwindcss";
```

If you're on Tailwind v4 with its single `@import "tailwindcss"`, pair it with the matching `cssLayer` name in `providePrimeNG` (above). The rule of thumb: **the layer holding Tailwind utilities is declared last**, so `class="mt-4"` on a `<p-button>` wins. If PrimeNG should win for a given element, don't fight it with `!important` — drop the Tailwind class instead.

> This single `@layer` line is the fix for ~all "Tailwind and PrimeNG don't get along" reports. Keep the layer names consistent between `styles.css` and `providePrimeNG`'s `cssLayer.name`/`order`.

## Component example — `p-table` from the generated client

```ts
import { Component, inject, signal } from '@angular/core';
import { TableModule } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { GenresService } from '../../api'; // generated client (bootstrap-angular-app)

@Component({
  selector: 'app-genres-table',
  standalone: true,
  imports: [TableModule, ButtonModule], // PrimeNG modules are standalone-importable
  template: `
    <p-table [value]="genres()" [paginator]="true" [rows]="10" class="mt-4 block">
      <ng-template pTemplate="header">
        <tr><th>Name</th><th class="w-24">Actions</th></tr>
      </ng-template>
      <ng-template pTemplate="body" let-genre>
        <tr>
          <td>{{ genre.name }}</td>
          <td><button pButton severity="secondary" size="small" label="Edit"></button></td>
        </tr>
      </ng-template>
    </p-table>
  `,
})
export class GenresTableComponent {
  private api = inject(GenresService);
  genres = signal<unknown[]>([]);
  constructor() {
    this.api.list().subscribe((data) => this.genres.set(data));
  }
}
```

> Import PrimeNG **modules** (`TableModule`, `ButtonModule`) directly into the standalone component's `imports` — no NgModule needed. Feed data from the **generated API service**, keeping the contract-driven flow intact.

## Reactive Forms

PrimeNG form controls (`p-inputtext`, `p-select`, `p-datepicker`, `p-checkbox`) implement `ControlValueAccessor`, so they bind with `formControlName` like native inputs:

```html
<form [formGroup]="form">
  <input pInputText formControlName="name" class="w-full" />
  <p-select formControlName="genreId" [options]="genres()" optionLabel="name" optionValue="id" />
  @if (form.controls.name.invalid && form.controls.name.touched) {
    <small class="text-red-600">Name is required</small>
  }
</form>
```

> Prefer **Reactive Forms** over template-driven for anything non-trivial — validation, typed controls, and testability are all better. Don't reach for `[(ngModel)]` on PrimeNG inputs inside a reactive form.

## Accessibility

- PrimeNG ships ARIA roles and keyboard handling, but **labels are on you**: pair every standalone input with a `<label for>` or `aria-label`. An unlabeled `p-select` is invisible to screen readers.
- Don't suppress focus rings to "clean up" the look — keyboard users rely on them.
- For icon-only `pButton`, set `aria-label`; the icon alone announces nothing.

## Anti-patterns to refuse

- **Importing a theme CSS file** (`primeng/resources/themes/...`). That's the pre-v18 model; v18+ themes are configured via `providePrimeNG` + `@primeng/themes`. Mixing both double-styles everything.
- **Skipping the `@layer` declaration**, then fighting overrides with `!important`. Fix the layer order once; `!important` is a smell that compounds.
- **Forgetting `provideAnimationsAsync()`.** Overlays break in subtle ways that look like component bugs.
- **Wrapping PrimeNG inputs in NgModules.** This project is standalone; import the component modules into the component's `imports`.
- **Re-styling components wholesale with Tailwind** instead of customizing the theme preset/tokens. For systemic look changes, edit the preset; use Tailwind for layout, not for re-skinning every widget.
- **Unlabeled form controls.** Accessibility isn't optional.

## Post-generation

Tell the user:
- The preset chosen and how to switch it (swap the `@primeng/themes/*` import).
- That dark mode toggles by adding/removing `.dark` on `<html>` — same class Tailwind uses, so one toggle drives both.
- To verify coexistence: confirm a Tailwind utility visibly affects a PrimeNG element; if not, the `@layer` order is wrong.
- Where to extend: customize the theme via a preset override rather than per-component CSS.

---

## Strategic considerations & governance

## Goal

Let PrimeNG own the complex widgets and Tailwind own layout, with a deterministic styling relationship between them — so the team stops debugging specificity and starts shipping screens.

## Design rules

- One theming engine: PrimeNG presets/tokens for components, Tailwind utilities for layout/spacing. Don't re-skin widgets with utility soup.
- CSS layer order is declared once and kept in sync between `styles.css` and `providePrimeNG`.
- Components are consumed standalone; data comes from the generated API client, not hand-written calls.
- Accessibility (labels, focus, keyboard) is part of "done", not a follow-up.

## Quality gates

- A Tailwind utility applied to a PrimeNG element takes effect (proves layer order is correct).
- Overlays (dialog/dropdown/toast) open and animate (proves animations are wired).
- Form controls bind via `formControlName` and surface validation errors.
- Dark mode toggles PrimeNG and Tailwind together via the shared `.dark` selector.

## Example

For the catalog app, add a `p-table` of albums with pagination and an admin-only Edit button, an album edit form using `p-inputtext`/`p-select` with reactive validation, and the `Aura` preset with `.dark` dark mode — Tailwind handling page layout around it.
