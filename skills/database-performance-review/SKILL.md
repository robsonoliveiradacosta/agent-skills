---
name: database-performance-review
description: "Review PostgreSQL, Flyway, JPA, and Panache performance for Quarkus APIs. Use when checking indexes, constraints, pagination, query plans, N+1 risks, transaction boundaries, lock behavior, migration impact, repository methods, or slow endpoint causes."
---

# database-performance-review

## Goal

Catch schema and query choices that will become slow, inconsistent, or hard to migrate.

## Workflow

1. Inspect migrations, entities, repositories, and service access patterns together.
2. Check indexes for foreign keys, unique lookups, filters, sorting, and joins.
3. Review pagination and sorting for deterministic order and bounded result size.
4. Look for N+1 risks in entity relationships and response mapping.
5. Check transaction boundaries and lock duration.
6. Evaluate migration cost for large tables and destructive changes.
7. Recommend targeted tests or query inspection when risk is high.

## Review Checklist

- Foreign keys and common filters have indexes.
- Unique domain rules are enforced in the database, not only in Java.
- List endpoints do not load unbounded results.
- DTO mapping does not trigger unexpected lazy loads.
- Writes are transactional and avoid unnecessary remote calls inside transactions.
- Migrations can run safely on existing data.

## Example

For album search by artist type and title sort, verify indexes on join keys and sortable/filterable columns, and ensure the repository uses pagination instead of loading all albums.
