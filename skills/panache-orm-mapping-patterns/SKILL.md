---
name: panache-orm-mapping-patterns
description: "Design JPA and Hibernate ORM with Panache mappings for Quarkus APIs. Use when modeling entities, relationships, join tables, fetch strategy, cascade behavior, orphan removal, DTO mapping, lazy loading, repository methods, and N plus one prevention."
---

# panache-orm-mapping-patterns

## Goal

Model persistence cleanly while keeping REST DTOs independent from JPA entities.

## Workflow

1. Identify aggregate boundaries and ownership before choosing relationships.
2. Map entities with explicit `@Table`, `@Column`, nullability, uniqueness, and relationship annotations.
3. Prefer lazy relationships by default; fetch intentionally in repository queries when DTO mapping needs related data.
4. Use join tables for many-to-many relationships and enforce composite uniqueness in Flyway.
5. Keep cascades narrow. Use `CascadeType.REMOVE` and orphan removal only when the child lifecycle is truly owned.
6. Put query logic in Panache repositories and mapping logic in services or dedicated mappers.

## Mapping Rules

- Do not expose entities directly from REST resources.
- Avoid bidirectional relationships unless navigation is needed and tested.
- Guard DTO mapping against lazy-loading surprises.
- Keep entity equality simple; avoid using mutable relationships in equality.
- Align entity constraints with database constraints.

## Example

For albums and artists, use an album-artist junction table with a unique album and artist pair. Fetch artists for album responses through a repository query or controlled mapping path, not accidental lazy traversal from the resource.
