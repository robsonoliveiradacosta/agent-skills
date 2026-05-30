---
name: add-audit-trail
description: "Add automatic audit columns (created_at, updated_at, created_by, updated_by) to JPA entities in a Quarkus project — generates a reusable AuditableEntity superclass with @PrePersist / @PreUpdate hooks, an AuditListener that pulls the principal from SecurityIdentity, and Flyway migrations to add the columns to existing tables. Use when the user asks for audit fields, \"who created this\", \"track when X was modified\", compliance requirements, or a created_at/updated_at column on entities."
---

# add-audit-trail

Add `created_at`, `updated_at`, `created_by`, `updated_by` to entities automatically — no service-layer code touches these fields. The JPA lifecycle hooks populate them via a `@EntityListeners` listener that reads the current `SecurityIdentity`.

## When to invoke

- "Add timestamps to entities"
- "Track who created this record"
- "Audit columns / audit trail"
- Compliance contexts: SOC 2, ISO 27001, LGPD — record changes for retention.

## Inputs to collect

| Input | Default |
|---|---|
| Which entities to make auditable | required; can be "all existing" |
| Use a shared `AuditableEntity` mapped superclass? | yes (preferred — reduces duplication) |
| Username for unauthenticated context (sync jobs etc.) | `system` |

## Files to generate

### `entity/AuditableEntity.java` (mapped superclass)

```java
package {{packageRoot}}.entity;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.EntityListeners;
import jakarta.persistence.MappedSuperclass;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.OffsetDateTime;

@MappedSuperclass
@EntityListeners(AuditListener.class)
public abstract class AuditableEntity extends PanacheEntityBase {

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    protected OffsetDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    protected OffsetDateTime updatedAt;

    @Column(name = "created_by", nullable = false, length = 100, updatable = false)
    protected String createdBy;

    @Column(name = "updated_by", nullable = false, length = 100)
    protected String updatedBy;

    public OffsetDateTime getCreatedAt() { return createdAt; }
    public OffsetDateTime getUpdatedAt() { return updatedAt; }
    public String getCreatedBy()         { return createdBy; }
    public String getUpdatedBy()         { return updatedBy; }
}
```

> Use Hibernate's `@CreationTimestamp` / `@UpdateTimestamp` for the timestamps — they survive bulk inserts and don't require an `EntityListener` round-trip. The listener only handles the principal.

### `entity/AuditListener.java`

```java
package {{packageRoot}}.entity;

import io.quarkus.arc.Arc;
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;

public class AuditListener {

    private static final String SYSTEM = "{{systemPrincipal}}";

    @PrePersist
    public void prePersist(AuditableEntity e) {
        String who = currentPrincipal();
        e.createdBy = who;
        e.updatedBy = who;
    }

    @PreUpdate
    public void preUpdate(AuditableEntity e) {
        e.updatedBy = currentPrincipal();
    }

    /** SecurityIdentity is request-scoped; JPA listeners aren't CDI beans, so we look it up via Arc. */
    private String currentPrincipal() {
        try {
            SecurityIdentity identity = Arc.container().instance(SecurityIdentity.class).get();
            if (identity == null || identity.isAnonymous()) return SYSTEM;
            return identity.getPrincipal().getName();
        } catch (Exception ignored) {
            return SYSTEM;
        }
    }
}
```

> **Critical**: JPA `@EntityListeners` are **not** CDI beans, so `@Inject` doesn't work. We bridge via `Arc.container().instance(...)`. This is the official Quarkus pattern.

### Refactor existing entities

For each entity that should become auditable:

```java
@Entity
@Table(name = "artists")
public class Artist extends AuditableEntity {   // was PanacheEntityBase
    // existing fields...
}
```

Remove any pre-existing `createdAt` / `updatedAt` fields the entity had.

### Flyway migrations — one per existing table

Use `add-flyway-migration` to generate each. Template:

```sql
-- V<n>__add_audit_columns_to_artists.sql

ALTER TABLE artists
    ADD COLUMN created_at TIMESTAMPTZ,
    ADD COLUMN updated_at TIMESTAMPTZ,
    ADD COLUMN created_by VARCHAR(100),
    ADD COLUMN updated_by VARCHAR(100);

-- Backfill existing rows so the next ALTER NOT NULL succeeds
UPDATE artists
SET created_at = NOW(),
    updated_at = NOW(),
    created_by = '{{systemPrincipal}}',
    updated_by = '{{systemPrincipal}}'
WHERE created_at IS NULL;

ALTER TABLE artists
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN updated_at SET NOT NULL,
    ALTER COLUMN created_by SET NOT NULL,
    ALTER COLUMN updated_by SET NOT NULL;
```

> Three-step pattern: **add nullable → backfill → set NOT NULL**. Required because the table already has rows.

## DTO exposure

By default, **don't** expose audit fields on every response DTO. Add only when the user asks. When you do, include the four fields explicitly:

```java
public record AlbumResponse(
    Long id, String title, Integer year,
    OffsetDateTime createdAt, OffsetDateTime updatedAt,
    String createdBy, String updatedBy
) {
    public static AlbumResponse from(Album a) {
        return new AlbumResponse(a.getId(), a.getTitle(), a.getYear(),
                                  a.getCreatedAt(), a.getUpdatedAt(),
                                  a.getCreatedBy(), a.getUpdatedBy());
    }
}
```

## Tests

```java
@Test
@QuarkusTestResource(PostgresResource.class)
class AuditableEntityTest {

    @Test
    void persistSetsCreatedAndUpdated() {
        // create via admin token
        Long id = given().auth().oauth2(TestTokenHelper.adminToken())
            .contentType("application/json")
            .body("""{"name":"Sample","type":"BAND","country":"BR"}""")
        .when().post("/v1/artists")
        .then().statusCode(201).extract().path("id");

        given().auth().oauth2(TestTokenHelper.userToken())
        .when().get("/v1/artists/" + id)
        .then()
            .body("createdBy", equalTo("admin"))
            .body("updatedBy", equalTo("admin"))
            .body("createdAt", notNullValue())
            .body("updatedAt", notNullValue());
    }
}
```

## Anti-patterns to refuse

- **Storing audit data only in application logs.** Logs rotate; audit columns are part of the record. They serve different purposes — recommend both, not one or the other.
- **Reusing the same column for `created_by` and `updated_by` ("modified_by")** to save space. Compliance audits often ask "who originally created this", and the answer is gone.
- **Putting the audit listener inside `service/` and `@Inject`ing it.** JPA listeners aren't CDI beans. Use `Arc.container().instance(...)`.
- **Hardcoding `NOT NULL` on the first ALTER.** Skipping the backfill step breaks any populated environment.
- **Exposing `created_by` / `updated_by` to anonymous users.** Treat usernames as PII unless the project policy says otherwise.

## Post-generation

- Run the new migration(s) and confirm existing rows have non-null audit values.
- Tell the user that every future entity should `extends AuditableEntity` instead of `PanacheEntityBase`.
- For full change-history (not just last-update), recommend a separate `audit_log` table — out of scope for this skill.

---

## Strategic considerations & governance

## Goal

Track important data changes without making normal queries confusing or slow.

## Workflow

1. Decide whether the domain needs basic timestamps, user attribution, soft delete, or full history.
2. Add audit columns consistently in Flyway and entities.
3. Populate timestamps in services, entity callbacks, or a shared audit pattern.
4. Ensure queries exclude soft-deleted rows by default when that is the product rule.
5. Decide how unique constraints behave with soft-deleted rows.
6. Test create, update, delete, restore, and list behavior.

## Design Rules

- Use hard delete for data that does not require retention.
- Use soft delete only when restore, audit, or references require it.
- Avoid silently returning deleted records from normal endpoints.
- Consider partial unique indexes when soft-deleted rows should not block reuse.
- Keep audit fields out of write request DTOs unless explicitly user-controlled.

## Example

For artists, soft delete may require `deleted_at` and repository filters that exclude deleted artists from list endpoints while preserving album references.
