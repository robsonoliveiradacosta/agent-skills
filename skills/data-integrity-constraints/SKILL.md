---
name: data-integrity-constraints
description: "Design database-backed integrity rules for Quarkus APIs. Use when deciding not-null, unique, foreign key, check constraints, cascade rules, composite keys, state constraints, duplicate prevention, concurrency-safe uniqueness, and alignment between Bean Validation and PostgreSQL constraints."
---

# data-integrity-constraints

## Goal

Put non-negotiable domain rules in the database, not only in Java code.

## Workflow

1. Identify invariants that must survive concurrent requests and future code changes.
2. Express required fields with `not null` in Flyway and Bean Validation in DTOs.
3. Use unique constraints for natural keys, slugs, usernames, external IDs, and junction pairs.
4. Add foreign keys for relationships and choose delete behavior deliberately.
5. Use check constraints for simple state, size, or range rules when they are stable.
6. Map constraint violations to predictable API errors.

## Design Rules

- Bean Validation improves client feedback; database constraints protect data.
- Do not rely on a pre-insert existence check without a unique constraint.
- Avoid broad cascades that can delete more data than intended.
- Use composite unique constraints for many-to-many junction tables.
- Test duplicate, missing reference, and delete-restricted cases.

## Example

For users, enforce unique `username`, non-null `password_hash`, and valid role values. Tests should prove duplicate usernames return `409` even under concurrent attempts.
