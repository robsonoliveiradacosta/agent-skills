---
name: postgres-query-patterns
description: "Design predictable PostgreSQL query patterns for Quarkus Panache and JPA repositories. Use when implementing filters, pagination, sorting, joins, counts, text search, existence checks, uniqueness checks, dynamic queries, and performance-aware repository methods."
---

# postgres-query-patterns

## Goal

Keep repository queries correct, bounded, and easy to index.

## Workflow

1. Start from the API filters, sort options, and response DTO requirements.
2. Define allowed sort fields explicitly; never pass arbitrary client strings into query construction.
3. Use pagination for list endpoints that can grow.
4. Add count queries only when the API needs total pages or totals.
5. Use joins intentionally and fetch related data only when needed for the response.
6. Match common filters and sort paths with database indexes.

## Query Rules

- Prefer parameter binding over string interpolation.
- Use existence queries for uniqueness checks instead of loading full entities.
- Keep default sorting deterministic by including a stable tie-breaker such as ID.
- Avoid unbounded `listAll()` in production-facing endpoints.
- Review generated SQL when performance or joins are non-trivial.

## Example

For `GET /v1/albums?artistType=BAND&sort=title:asc`, whitelist `title`, join artists only as needed, paginate results, and ensure indexes support join keys and title sorting.
