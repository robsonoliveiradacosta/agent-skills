---
name: add-optimistic-locking
description: "Add JPA optimistic locking via @Version to selected entities in a Quarkus project — generates the Flyway migration that adds the version column with default 0 and backfills existing rows, applies @Version to the entity, wires an OptimisticLockExceptionMapper that returns 409 Conflict (RFC 7807), and shows the service-layer retry pattern for safe-to-retry write paths. Use whenever the user mentions optimistic locking, concurrent updates, \"last write wins\", lost-update problem, @Version, OptimisticLockException, or any scenario where two clients can edit the same record."
---

# add-optimistic-locking

Add JPA optimistic locking so two concurrent updates can't silently overwrite each other. After this skill, the second `PUT /v1/<resource>/{id}` to a stale version returns **409 Conflict** with a Problem Details body, and the caller knows to refetch + retry.

## When to invoke

- "Add optimistic locking"
- "Two admins editing the same album overwrite each other"
- "Implement @Version"
- "Handle OptimisticLockException"

## When NOT to invoke

- Append-only tables (events, audit logs) — concurrency by design isn't a problem.
- Single-writer workflows where there's only ever one updater (a scheduled job).
- Strongly-consistent counters — those need **pessimistic** locking (`SELECT ... FOR UPDATE`), not optimistic.

## Inputs to collect

| Input | Default |
|---|---|
| Entities to add `@Version` to | required |
| Expose `version` in response DTOs? | yes — clients need it to send back |
| Require `If-Match` header for updates? | optional; mention but don't force |
| Service-layer auto-retry on conflict? | no by default — propagate to client |

## Files to generate

### Flyway migration — `V<n>__add_version_to_albums.sql`

```sql
-- Add nullable, backfill, then NOT NULL — same three-step pattern as add-audit-trail.
ALTER TABLE albums ADD COLUMN version BIGINT;

UPDATE albums SET version = 0 WHERE version IS NULL;

ALTER TABLE albums ALTER COLUMN version SET NOT NULL;
ALTER TABLE albums ALTER COLUMN version SET DEFAULT 0;
```

> If the entity uses `AuditableEntity` from `add-audit-trail`, add the `@Version` field to a separate `VersionedEntity` superclass OR put it directly on each entity. Don't shove it into `AuditableEntity` — not every auditable entity needs locking.

### Entity change

```java
@Entity
@Table(name = "albums")
public class Album extends AuditableEntity {

    // existing fields ...

    @Version
    @Column(nullable = false)
    private Long version;

    public Long getVersion() { return version; }
}
```

> `@Version` requires `Long` (or `Integer`/`Timestamp`). **Don't** use a primitive `long` — JPA needs the wrapper to detect first-persist.

### Response DTO change

```java
public record AlbumResponse(
    Long id, String title, Integer year, Long version
) {
    public static AlbumResponse from(Album a) {
        return new AlbumResponse(a.getId(), a.getTitle(), a.getYear(), a.getVersion());
    }
}
```

### Request DTO change

```java
public record AlbumUpdateRequest(
    @NotBlank @Size(max = 200) String title,
    @NotNull @Min(1900) Integer year,
    @NotNull Long version       // ← client must echo the version it last saw
) {}
```

### Service — apply version on update

```java
@Transactional
public AlbumResponse update(Long id, AlbumUpdateRequest req) {
    Album album = albumRepository.findByIdOptional(id)
        .orElseThrow(() -> new NotFoundException("Album not found: " + id));

    // Detect the stale-version case BEFORE committing; throws OptimisticLockException
    // on flush if versions don't match.
    if (!album.getVersion().equals(req.version())) {
        throw new OptimisticLockException(
            "Stale version: expected " + album.getVersion() + ", got " + req.version());
    }

    album.setTitle(req.title());
    album.setYear(req.year());
    // Hibernate increments version on the flush.

    return AlbumResponse.from(album);
}
```

> **Two safety nets**: the early `if` gives a clear, deterministic 409. Hibernate's automatic version check is the backup if some other transaction commits between our `find` and `flush`.

### Exception mapper — `exception/OptimisticLockExceptionMapper.java`

```java
package {{packageRoot}}.exception;

import jakarta.persistence.OptimisticLockException;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import org.hibernate.StaleObjectStateException;

@Provider
public class OptimisticLockExceptionMapper implements ExceptionMapper<OptimisticLockException> {

    @Context UriInfo uriInfo;
    @Context ContainerRequestContext ctx;

    @Override
    public Response toResponse(OptimisticLockException ex) {
        return ProblemBuilder.build(
            409,
            "Conflict",
            "The resource was modified by another request. Refetch and retry.",
            uriInfo, ctx, null
        );
    }
}

@Provider
class StaleObjectStateExceptionMapper implements ExceptionMapper<StaleObjectStateException> {

    @Context UriInfo uriInfo;
    @Context ContainerRequestContext ctx;

    @Override
    public Response toResponse(StaleObjectStateException ex) {
        return ProblemBuilder.build(
            409, "Conflict",
            "The resource was modified by another request. Refetch and retry.",
            uriInfo, ctx, null
        );
    }
}
```

> Hibernate sometimes throws `StaleObjectStateException` (a `HibernateException`, not a JPA one) — map both. Uses `ProblemBuilder` from `add-error-handling`. If that skill hasn't been run, generate a simpler `Response.status(409).entity(...).build()` fallback.

## Optional: `If-Match` header pattern

Some teams prefer HTTP-native concurrency control via `If-Match` / `ETag` headers rather than a body field. Trade-off:

- **Body field** (`version` in request): simpler, visible in any HTTP client, easy for cURL examples.
- **`If-Match` header**: REST-idiomatic, works with HTTP caching, but invisible in body-focused docs.

Choose one — **don't ship both**. Default to body field unless the user explicitly asks for ETag.

If the user picks ETag, generate this resource code instead:

```java
@PUT @Path("/{id}")
@RolesAllowed("ADMIN")
public Response update(
    @PathParam("id") Long id,
    @HeaderParam("If-Match") @NotBlank String ifMatch,
    @Valid AlbumUpdateRequest req
) {
    long expectedVersion = Long.parseLong(ifMatch.replace("\"", ""));
    AlbumResponse updated = service.update(id, req.withVersion(expectedVersion));
    return Response.ok(updated).tag("\"" + updated.version() + "\"").build();
}
```

And include the response `ETag` on every `GET`.

## Auto-retry pattern (use sparingly)

For **idempotent** operations where retry is genuinely safe — typically not "user-driven updates" but "system-driven adjustments" (counters, bookkeeping) — you can wrap the call:

```java
@Transactional(Transactional.TxType.REQUIRES_NEW)
public AlbumResponse updateWithRetry(Long id, AlbumUpdateRequest req) {
    int attempts = 0;
    while (true) {
        try {
            return doUpdate(id, req);
        } catch (OptimisticLockException e) {
            if (++attempts >= 3) throw e;
            // Re-read the entity inside doUpdate next iteration.
        }
    }
}
```

> **Critical**: each retry must be a new transaction (`REQUIRES_NEW`) — otherwise the rolled-back state isn't visible to the retry. **Never** auto-retry user-submitted form data; the user's intent might be stale by the time we retry.

## Tests

```java
@Test
@QuarkusTestResource(PostgresResource.class)
void update_returns409_whenVersionStale() {
    // First create
    Long id = createAlbum();
    Long v0 = fetchAlbum(id).getLong("version");

    // First update bumps version 0 → 1
    given().auth().oauth2(TestTokenHelper.adminToken())
        .contentType("application/json")
        .body(Map.of("title","New","year",1969,"version",v0))
    .when().put("/v1/albums/" + id)
    .then().statusCode(200).body("version", equalTo(v0.intValue() + 1));

    // Second update with the STALE version
    given().auth().oauth2(TestTokenHelper.adminToken())
        .contentType("application/json")
        .body(Map.of("title","Newer","year",1969,"version",v0))
    .when().put("/v1/albums/" + id)
    .then()
        .statusCode(409)
        .contentType("application/problem+json")
        .body("title", equalTo("Conflict"));
}

@Test
void create_setsInitialVersionToZero() {
    // Verify @Version initializes to 0 on first persist (not null)
    Long id = createAlbum();
    given().auth().oauth2(TestTokenHelper.userToken())
    .when().get("/v1/albums/" + id)
    .then().body("version", equalTo(0));
}
```

## Anti-patterns to refuse

- **Returning the entity's full state on 409**. Just say "stale"; the client refetches via GET. Including the new state in the 409 invites the client to "merge" client-side, which is exactly the lost-update problem in user space.
- **Hiding `OptimisticLockException` in the service** with a silent fallback (return the existing entity). Defeats the whole pattern.
- **`@Version` on `@MappedSuperclass` that's used by append-only tables.** Wastes a column.
- **Auto-retry on user updates.** The user's request is stale; retrying just applies stale data twice as fast.
- **Combining `@Version` with `@DynamicUpdate`** without understanding it. `@DynamicUpdate` makes Hibernate emit SQL with only changed columns, which can interact unexpectedly with optimistic locking — leave it off unless you have a reason.
- **Pessimistic locking as a replacement** without a deliberate reason. Pessimistic locks hold for the transaction; under load they cascade into a queue that looks like an outage. Optimistic + retry is almost always better.

## Post-generation

- Run the new migration and verify `version` defaults to 0 on new rows.
- Document in `CLAUDE.md`: clients must read `version` from GET and echo it on PUT, or get 409.
- If `add-error-handling` is in place, the new mapper plugs in cleanly. If not, suggest running that skill so 409 responses follow `application/problem+json`.

---

## Strategic considerations & governance

## Goal

Prevent duplicate creation, lost updates, and inconsistent state under concurrent requests.

## Workflow

1. Identify shared resources and operations that can race.
2. Prefer database constraints for duplicate prevention.
3. Use optimistic locking with a version column for user-edited records that can be updated concurrently.
4. Use pessimistic locking only for short critical sections where conflicts are expected and correctness requires serialization.
5. Make retry behavior explicit and safe.
6. Add concurrent tests for important race conditions.

## Design Rules

- Do not rely on "check then insert" without a unique constraint.
- Keep locks short and avoid remote calls while locks are held.
- Return conflict responses for stale updates or duplicate races.
- Use idempotency keys for repeated client submissions when appropriate.
- Document isolation assumptions when behavior depends on them.

## Example

For concurrent artist creation with the same name, enforce a unique constraint and map the database violation to `409`, even if the service also checks for an existing artist first.
