---
name: persistence-test-patterns
description: "Test repository, ORM, Flyway, and transactional behavior in Quarkus APIs. Use when writing persistence tests for Panache repositories, constraints, migrations, pagination, sorting, relationships, lazy loading, transaction rollback, concurrent writes, and Testcontainers-backed PostgreSQL behavior."
---

# persistence-test-patterns

## Goal

Prove that mappings, migrations, queries, constraints, and transaction behavior work against PostgreSQL, not only mocks.

## Workflow

1. Use service tests for business rules and persistence tests for database behavior.
2. Run repository and migration tests with Quarkus test support and PostgreSQL Testcontainers when behavior depends on the database.
3. Create explicit fixture data with unique identifiers per test.
4. Test constraints through real persistence failures and API/service mapping where relevant.
5. Test pagination, sorting, joins, and not-found behavior for custom queries.
6. Test transaction rollback for important failure paths.

## Required Cases

- Unique and foreign-key constraint enforcement.
- Query filters and default sort order.
- Relationship mapping and DTO loading behavior.
- Flyway migration success on clean and representative existing data.
- Concurrent write behavior when duplicate prevention matters.

## Example

For `ArtistRepository`, test case-insensitive name filtering if supported, pagination order, duplicate name constraint, delete restriction when albums exist, and query behavior after Flyway migrations run.
