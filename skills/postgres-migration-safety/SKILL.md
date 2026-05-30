---
name: postgres-migration-safety
description: "Plan safe PostgreSQL Flyway migrations for production Quarkus APIs. Use when adding columns, constraints, indexes, backfills, table refactors, nullable to non-null transitions, data migrations, rollback notes, large-table changes, and zero-downtime compatibility."
---

# postgres-migration-safety

## Goal

Make schema changes safe for existing data and predictable during deployment.

## Workflow

1. Inspect current Flyway sequence and choose the next version.
2. Classify the migration as additive, backfill, constraint enforcement, rename, split, merge, or destructive.
3. Prefer expand-and-contract for breaking schema changes: add new shape, backfill, deploy compatible code, then remove old shape later.
4. Add constraints only after existing data satisfies them.
5. Consider index creation cost, table locks, default values, and large table rewrites.
6. Document rollback limits and manual recovery for risky data migrations.

## Safety Rules

- Avoid dropping columns or tables in the same release that stops writing them.
- Add nullable columns first, backfill, then enforce `not null`.
- Add unique constraints only after duplicate detection or cleanup.
- Keep seed data idempotent where repeated local setup is likely.
- Test migrations with existing-like data, not only an empty database.

## Example

To require `album_images.object_key`, add the nullable column, populate existing rows, update code to write it, then add `not null` in a later migration after verification.
