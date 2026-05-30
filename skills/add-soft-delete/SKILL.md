---
name: add-soft-delete
description: "Convert a JPA entity in a Quarkus project from hard-delete to soft-delete — adds a deleted_at column via Flyway, applies Hibernate's @SoftDelete or @SQLDelete + @SQLRestriction so the entity is filtered automatically, exposes restore and listIncludingDeleted operations in the service, and refactors the resource to use a 410 Gone status for deleted IDs when appropriate. Use when the user asks for soft delete, \"don't actually delete\", \"restore deleted records\", \"trash/recycle bin\", or a deleted_at column."
---

# add-soft-delete

Replace hard-delete with soft-delete on an entity so:

- `DELETE /v1/albums/{id}` marks `deleted_at = NOW()` instead of removing the row.
- Subsequent reads (`findAll`, `findById`) **automatically** filter out deleted rows — service and resource code stays unchanged.
- A separate `restore(id)` and `listIncludingDeleted()` exist for admin recovery.
- Existing unique constraints still work (no two non-deleted rows with the same key) — but soft-deleted rows don't collide.

## When to invoke

- "Implement soft delete"
- "I want to be able to restore deleted users"
- "Add a deleted_at column"

## Inputs to collect

| Input | Default |
|---|---|
| Entity to soft-delete | required |
| Expose `restore` endpoint? | yes (ADMIN only) |
| Expose `listIncludingDeleted`? | yes (ADMIN only) |
| Unique constraints to relax | list any (typically all UNIQUE columns) |

## Implementation choice

Two options exist; pick **option A** unless the user is on Hibernate < 6.4.

### Option A — Hibernate 6.4+ `@SoftDelete`

```java
import org.hibernate.annotations.SoftDelete;
import org.hibernate.annotations.SoftDeleteType;

@Entity
@Table(name = "albums")
@SoftDelete(strategy = SoftDeleteType.TIMESTAMP, columnName = "deleted_at")
public class Album extends AuditableEntity {
    // ...
}
```

Hibernate intercepts every query and write — no extra code. `albumRepository.delete(entity)` sets the timestamp instead of running `DELETE`.

### Option B — `@SQLDelete` + `@SQLRestriction` (older Hibernate)

```java
import org.hibernate.annotations.SQLDelete;
import org.hibernate.annotations.SQLRestriction;

@Entity
@Table(name = "albums")
@SQLDelete(sql = "UPDATE albums SET deleted_at = NOW() WHERE id = ?")
@SQLRestriction("deleted_at IS NULL")
public class Album extends AuditableEntity {
    // ...
}
```

Use option B only if the project pins Hibernate < 6.4 — verify via `mvn dependency:tree | grep hibernate-core`.

## Migration

Use `/add-flyway-migration`:

```sql
-- V<n>__add_soft_delete_to_albums.sql

ALTER TABLE albums ADD COLUMN deleted_at TIMESTAMPTZ;

CREATE INDEX idx_albums_deleted_at ON albums (deleted_at) WHERE deleted_at IS NULL;
```

> The **partial index** on `WHERE deleted_at IS NULL` keeps the live-row queries fast and skips deleted rows from the index — typical pattern for partial soft-delete indexing.

### Relaxing existing unique constraints

If `albums.title` was `UNIQUE`, two soft-deleted rows would still collide. Either:

1. **Partial unique index** (recommended):
   ```sql
   ALTER TABLE albums DROP CONSTRAINT IF EXISTS uq_albums_title;
   CREATE UNIQUE INDEX uq_albums_title_active ON albums (title) WHERE deleted_at IS NULL;
   ```
2. **Include `deleted_at` in the unique key** (avoid — uses a magic sentinel value).

## Repository & service changes

The repository's standard finders (`findAll`, `findById`, `count`) automatically respect `@SoftDelete` — no change. Add **explicit** methods for admin operations:

```java
@ApplicationScoped
public class AlbumRepository implements PanacheRepositoryBase<Album, Long> {

    public List<Album> listIncludingDeleted() {
        return getEntityManager()
            .createNativeQuery("SELECT * FROM albums", Album.class)
            .getResultList();
    }

    public Optional<Album> findByIdIncludingDeleted(Long id) {
        Object row = getEntityManager()
            .createNativeQuery("SELECT * FROM albums WHERE id = ?1", Album.class)
            .setParameter(1, id)
            .getResultStream().findFirst().orElse(null);
        return Optional.ofNullable((Album) row);
    }
}
```

> Native query bypasses Hibernate's soft-delete filter. Use sparingly — only for admin endpoints.

### Service additions

```java
@Transactional
public void restore(Long id) {
    Album a = repository.findByIdIncludingDeleted(id)
        .orElseThrow(() -> new NotFoundException("Album " + id));
    // Native update — Hibernate sees no entity change otherwise.
    repository.getEntityManager()
        .createNativeQuery("UPDATE albums SET deleted_at = NULL WHERE id = ?1")
        .setParameter(1, id)
        .executeUpdate();
}
```

## Resource changes

```java
@POST @Path("/{id}/restore")
@RolesAllowed("ADMIN")
@Operation(summary = "Restore a soft-deleted album")
public Response restore(@PathParam("id") Long id) {
    service.restore(id);
    return Response.noContent().build();
}

@GET @Path("/admin/all")
@RolesAllowed("ADMIN")
@Operation(summary = "List all albums including soft-deleted")
public List<AlbumResponse> listAll() {
    return service.listIncludingDeleted();
}
```

For attempts to read a soft-deleted id via the **normal** endpoint, the existing `NotFoundException` flow returns 404 — which is the right call most of the time. **Only** use HTTP 410 Gone if the API explicitly distinguishes "never existed" from "was deleted" to clients:

```java
public AlbumResponse findById(Long id) {
    if (repository.findByIdOptional(id).isEmpty()
        && repository.findByIdIncludingDeleted(id).isPresent()) {
        throw new WebApplicationException("Resource was deleted", 410);
    }
    // existing logic
}
```

## Tests

```java
@Test
void deleteIsSoft() {
    Long id = createAlbum();
    given().auth().oauth2(TestTokenHelper.adminToken())
    .when().delete("/v1/albums/" + id)
    .then().statusCode(204);

    // Normal find = 404
    given().auth().oauth2(TestTokenHelper.userToken())
    .when().get("/v1/albums/" + id)
    .then().statusCode(404);

    // Admin listing all = sees it
    given().auth().oauth2(TestTokenHelper.adminToken())
    .when().get("/v1/albums/admin/all")
    .then().body("findAll { it.id == " + id + " }.size()", equalTo(1));
}

@Test
void restoreBringsItBack() {
    Long id = createAlbum();
    given().auth().oauth2(TestTokenHelper.adminToken()).delete("/v1/albums/" + id);
    given().auth().oauth2(TestTokenHelper.adminToken()).post("/v1/albums/" + id + "/restore")
        .then().statusCode(204);

    given().auth().oauth2(TestTokenHelper.userToken())
    .when().get("/v1/albums/" + id)
    .then().statusCode(200);
}
```

## Anti-patterns to refuse

- **Soft-deleting via a `boolean deleted` column** instead of timestamp. The timestamp tells you **when** — invaluable for incident response and compliance.
- **Not relaxing unique constraints.** New rows will collide with deleted ones; users will be confused.
- **Cascading soft delete** through `@OneToMany` automatically. Always discuss with the user — silent recursive soft-delete is hard to undo.
- **Returning soft-deleted rows in the normal listing endpoint** behind a `?includeDeleted=true` query param available to all users. Restrict it to ADMIN.
- **Mixing soft and hard delete in the same entity tree.** If `Album` is soft, `AlbumImage` probably should be too (or be explicitly cascaded on hard delete).

## Post-generation

- Run the migration.
- Confirm at least one delete-then-list round-trip on the new endpoint.
- Tell the user the storage trade-off: **soft delete grows the table**. Plan a periodic purge job (separate skill / cron) if retention has a limit.
