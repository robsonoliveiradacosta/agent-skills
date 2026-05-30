---
name: add-flyway-migration
description: "Create the next Flyway migration file under src/main/resources/db/migration/ with correct sequential numbering (V<n+1>__*.sql) and a template body matching the kind of change requested — create table, add column, alter, junction, index, or seed data. Use whenever the user asks for a schema change, \"add a migration\", \"alter table X\", or proposes changes that touch persistent data."
---

# add-flyway-migration

Generate a properly numbered, idempotent-friendly Flyway migration that respects this project's "schema owned by Flyway" rule (`quarkus.hibernate-orm.database.generation=none`).

## When to invoke

- "Add a column `country` to artists"
- "Crie uma migração para a tabela `genres`"
- "Need a Flyway file to seed default categories"
- Or implicitly: whenever a new entity is added (the `add-crud-resource` skill defers to this one).

## Workflow

1. List existing files in `src/main/resources/db/migration/`. Pick the **highest** `Vn` and use `n+1`.
   - If files use any prefix variation, follow the dominant pattern; do not invent a new one.
2. Confirm the migration filename with the user before writing it.
3. Write the SQL with the appropriate template (below).
4. Remind the user that Flyway runs at startup (`migrate-at-start=true`) and that tests use `clean-at-start=true` against `<dbName>_test` — so the migration **will** run on the next test invocation.

## Numbering rules

- Find the max `Vn` across all files matching `V<digits>__*.sql`. Use **decimal**, not lexical, comparison (`V10` > `V9`).
- Never reuse a number, even if a previous migration was reverted by deleting the file — pick the next free integer.
- Never edit a migration that has already been applied to any environment. Always add a new one.

## Templates

### Create table

```sql
-- V{{n}}__create_{{table}}_table.sql

CREATE TABLE {{table}} (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_{{table}}_name UNIQUE (name)
);

CREATE INDEX idx_{{table}}_name ON {{table}} (name);
```

### Junction table (many-to-many)

Use this when generating a relationship; mirrors `V3__create_album_artist_junction.sql`.

```sql
-- V{{n}}__create_{{left}}_{{right}}_junction.sql

CREATE TABLE {{left}}_{{right}} (
    {{left}}_id  BIGINT NOT NULL REFERENCES {{leftPlural}}(id) ON DELETE CASCADE,
    {{right}}_id BIGINT NOT NULL REFERENCES {{rightPlural}}(id) ON DELETE CASCADE,
    PRIMARY KEY ({{left}}_id, {{right}}_id)
);

CREATE INDEX idx_{{left}}_{{right}}_{{right}} ON {{left}}_{{right}}({{right}}_id);
```

### Alter / add column

```sql
-- V{{n}}__add_{{column}}_to_{{table}}.sql

ALTER TABLE {{table}} ADD COLUMN {{column}} VARCHAR(100);

-- Optional backfill before adding NOT NULL:
-- UPDATE {{table}} SET {{column}} = 'default-value' WHERE {{column}} IS NULL;
-- ALTER TABLE {{table}} ALTER COLUMN {{column}} SET NOT NULL;
```

> **Two-step pattern for NOT NULL on existing data**: add nullable → backfill → set NOT NULL. Do not combine into a single ALTER on a populated table.

### Add index

```sql
-- V{{n}}__add_index_{{table}}_{{column}}.sql

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_{{table}}_{{column}} ON {{table}}({{column}});
```

> `CONCURRENTLY` requires the migration to run outside a transaction. If using Flyway with PostgreSQL, you may need `-- executeInTransaction=false` (script-level) and to confirm Flyway version supports it. For local dev / small tables, omit `CONCURRENTLY` and the standard transactional migration is fine.

### Seed data

```sql
-- V{{n}}__insert_default_{{table}}.sql

INSERT INTO {{table}} (name, priority)
VALUES
    ('Rock', 1),
    ('Jazz', 2),
    ('Classical', 3)
ON CONFLICT (name) DO NOTHING;
```

> `ON CONFLICT DO NOTHING` makes the migration safe under `flyway.clean-at-start=true` during tests and under repeat runs in misconfigured environments.

### Drop (rare — see warning)

Generally **don't drop in a normal migration** — write an explicit "deprecation + cleanup" migration after confirming with the user.

```sql
-- V{{n}}__drop_legacy_{{table}}.sql

DROP TABLE IF EXISTS {{table}};
```

Make sure the user has confirmed:
1. No code still references the table.
2. Production data has been backed up / exported.
3. No other migration in flight references it.

## Anti-patterns to refuse

- Editing an already-applied migration. Refuse and create a new one instead.
- Using `DROP ... CASCADE` without explicit user confirmation.
- Renumbering existing migrations to "fit in" — never. Pick the next integer.
- Including `BEGIN;` / `COMMIT;` manually — Flyway wraps statements in a transaction by default. Adding your own breaks the safety net.
- Adding `IF NOT EXISTS` to make a migration idempotent against the same `V` number — Flyway already guarantees this via its history table. The exception is `INSERT` data, which benefits from `ON CONFLICT`.

## After writing

Tell the user:
- Filename created.
- Whether the change is destructive / requires backfill.
- That tests will fail until they re-run with the new schema (`./mvnw test` triggers `clean-at-start`).

---

## Strategic considerations & governance

## Goal

Create deterministic, reviewable database migrations that align with JPA entities and service behavior.

## Workflow

1. Inspect existing `V*.sql` files and choose the next integer version.
2. Name the migration with a short action phrase, for example `V12__create_genres_table.sql`.
3. Define tables with explicit primary keys, foreign keys, `not null` constraints, uniqueness rules, and useful indexes.
4. Match Java entity names to database tables intentionally; use snake_case for table and column names.
5. Add seed data only when the application or tests require deterministic defaults.
6. Update entities, repositories, and tests in the same change when schema behavior changes.

## PostgreSQL Practices

- Prefer `bigserial` or identity columns consistently with nearby migrations.
- Use `timestamp` or `timestamp with time zone` intentionally; do not mix without a reason.
- Add indexes for foreign keys and common filters such as status, type, slug, or external ID.
- Use junction tables for many-to-many relationships and enforce composite uniqueness.
- Avoid destructive migrations unless the user explicitly accepts data loss.

## Review Checklist

- Migration version is unique and ordered.
- Constraints express the real domain rules.
- Roll-forward behavior is clear even without a down migration.
- Existing tests do not depend on stale schema assumptions.

## Example

```sql
create table genres (
    id bigserial primary key,
    name varchar(120) not null unique,
    created_at timestamp not null default current_timestamp
);
```
