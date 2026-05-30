---
name: add-idempotency-key
description: "Add Stripe-style Idempotency-Key header support to a Quarkus REST API so retries of POST/PUT/PATCH operations are safe — generates a Flyway migration for the idempotency_keys table with TTL, a JAX-RS filter that intercepts before the resource method and returns the cached response when the same key+method+path is replayed, a scheduled purge job for expired keys, and a target annotation @Idempotent for opting endpoints in. Use whenever the user mentions idempotency, retry-safe POST, duplicate request prevention, Stripe-style Idempotency-Key, exactly-once semantics, or any payment/order/transaction-creation endpoint."
---

# add-idempotency-key

Add an `Idempotency-Key` HTTP header pattern so that a client retrying the same POST (network blip, timeout, manual retry) doesn't create duplicate resources. The server records `(key, method, path, user) → (status, headers, body)` for 24h; the second call returns the recorded response without re-executing the handler.

This pattern is **strictly more useful** than idempotent endpoints alone — a `PUT /resource/{id}` is naturally idempotent, but `POST /payments` isn't, and clients have no other safe way to retry it.

## When to invoke

- "Add idempotency"
- "Make POST retry-safe"
- "Stripe-style Idempotency-Key"
- "Prevent duplicate orders / payments / submissions"

## Inputs to collect

| Input | Default |
|---|---|
| Endpoints that need it | required; typically POST/PUT/PATCH on critical resources |
| Key TTL | `24 hours` (matches Stripe) |
| Scope | per-user (default) or global per-key |
| Max stored body size | `100 KB` — reject larger payloads |
| Required vs optional? | optional (default) — if present, enforce; if missing, normal flow |

## Files to generate

### Flyway migration — `V<n>__create_idempotency_keys.sql`

```sql
CREATE TABLE idempotency_keys (
    id                  BIGSERIAL    PRIMARY KEY,
    idempotency_key     VARCHAR(255) NOT NULL,
    user_principal      VARCHAR(255) NOT NULL,    -- '__anon' for unauthenticated
    request_method      VARCHAR(10)  NOT NULL,
    request_path        VARCHAR(500) NOT NULL,
    request_fingerprint VARCHAR(64)  NOT NULL,    -- SHA-256 of body — detect different body, same key
    response_status     INTEGER      NOT NULL,
    response_headers    JSONB        NOT NULL DEFAULT '{}'::jsonb,
    response_body       TEXT,
    state               VARCHAR(16)  NOT NULL,    -- IN_FLIGHT, COMPLETED
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ  NOT NULL,
    CONSTRAINT uq_idempotency UNIQUE (idempotency_key, user_principal, request_method, request_path)
);

-- Purge job index
CREATE INDEX idx_idempotency_expires_at ON idempotency_keys (expires_at);
```

> **Why the unique constraint covers `(key, user, method, path)`**: scoping by user prevents key collisions between tenants; including method+path prevents the same key being reused for a different operation (which would silently return the wrong response).

> **`request_fingerprint`**: SHA-256 of the request body. If the same key is reused with a **different** body, we return 422 — Stripe's behavior. This catches client bugs where keys are reused across unrelated requests.

### Entity — `entity/IdempotencyRecord.java`

```java
package {{packageRoot}}.entity;

import com.fasterxml.jackson.databind.JsonNode;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Entity
@Table(name = "idempotency_keys")
public class IdempotencyRecord extends PanacheEntityBase {

    public enum State { IN_FLIGHT, COMPLETED }

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "idempotency_key", nullable = false)  private String idempotencyKey;
    @Column(name = "user_principal", nullable = false)   private String userPrincipal;
    @Column(name = "request_method", nullable = false)   private String requestMethod;
    @Column(name = "request_path", nullable = false)     private String requestPath;
    @Column(name = "request_fingerprint", nullable = false) private String requestFingerprint;

    @Column(name = "response_status", nullable = false)  private Integer responseStatus;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "response_headers", nullable = false, columnDefinition = "jsonb")
    private JsonNode responseHeaders;

    @Column(name = "response_body", columnDefinition = "text")
    private String responseBody;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private State state;

    @Column(name = "created_at",   nullable = false) private OffsetDateTime createdAt;
    @Column(name = "completed_at")                   private OffsetDateTime completedAt;
    @Column(name = "expires_at",   nullable = false) private OffsetDateTime expiresAt;

    // Getters / setters …
}
```

### Repository — `repository/IdempotencyRepository.java`

```java
package {{packageRoot}}.repository;

import {{packageRoot}}.entity.IdempotencyRecord;
import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;

import java.time.OffsetDateTime;
import java.util.Optional;

@ApplicationScoped
public class IdempotencyRepository implements PanacheRepositoryBase<IdempotencyRecord, Long> {

    public Optional<IdempotencyRecord> findActive(
            String key, String user, String method, String path) {
        return find("""
                idempotencyKey = ?1
                AND userPrincipal = ?2
                AND requestMethod = ?3
                AND requestPath = ?4
                AND expiresAt > ?5
                """,
                key, user, method, path, OffsetDateTime.now()
        ).firstResultOptional();
    }
}
```

### Annotation — `security/Idempotent.java`

```java
package {{packageRoot}}.security;

import jakarta.ws.rs.NameBinding;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** Marks a JAX-RS endpoint as idempotency-key aware. The filter only runs on annotated methods. */
@NameBinding
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE, ElementType.METHOD})
public @interface Idempotent {}
```

> Using `@NameBinding` (instead of a global filter) means idempotency only applies where it's opted in — keeps the overhead off endpoints that don't need it (like `GET`s).

### Filter — `security/IdempotencyFilter.java`

```java
package {{packageRoot}}.security;

import {{packageRoot}}.entity.IdempotencyRecord;
import {{packageRoot}}.repository.IdempotencyRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import jakarta.annotation.Priority;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.*;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.OffsetDateTime;
import java.util.HexFormat;

@Provider
@Idempotent
@Priority(Priorities.AUTHENTICATION + 50)   // After auth, before business logic
public class IdempotencyFilter implements ContainerRequestFilter, ContainerResponseFilter {

    public static final String HEADER = "Idempotency-Key";
    private static final String PROP_RECORD = "idempotency.record";

    @Inject IdempotencyRepository repository;
    @Inject ObjectMapper mapper;

    @ConfigProperty(name = "app.idempotency.ttl-hours", defaultValue = "24")
    long ttlHours;

    @ConfigProperty(name = "app.idempotency.max-body-bytes", defaultValue = "102400")
    int maxBodyBytes;

    @Override
    @Transactional
    public void filter(ContainerRequestContext ctx) throws IOException {
        String key = ctx.getHeaderString(HEADER);
        if (key == null || key.isBlank()) return;   // header absent → normal flow

        if (key.length() > 255) {
            ctx.abortWith(Response.status(400).entity("Idempotency-Key too long").build());
            return;
        }

        // Read & buffer body so we can both fingerprint it AND let the resource consume it
        byte[] body = ctx.hasEntity() ? ctx.getEntityStream().readAllBytes() : new byte[0];
        if (body.length > maxBodyBytes) {
            ctx.abortWith(Response.status(413).entity("Body too large for idempotency").build());
            return;
        }
        ctx.setEntityStream(new ByteArrayInputStream(body));   // restore for handler

        String user = ctx.getSecurityContext().getUserPrincipal() != null
                ? ctx.getSecurityContext().getUserPrincipal().getName()
                : "__anon";
        String method = ctx.getMethod();
        String path   = ctx.getUriInfo().getPath();
        String fp     = sha256(body);

        var existing = repository.findActive(key, user, method, path);
        if (existing.isPresent()) {
            IdempotencyRecord r = existing.get();
            if (!r.getRequestFingerprint().equals(fp)) {
                ctx.abortWith(Response.status(422)
                        .entity("Idempotency-Key reused with different request body")
                        .build());
                return;
            }
            if (r.getState() == IdempotencyRecord.State.IN_FLIGHT) {
                ctx.abortWith(Response.status(409)
                        .header("Retry-After", 1)
                        .entity("Request with this Idempotency-Key is in flight")
                        .build());
                return;
            }
            // Cached COMPLETED — replay the response
            ctx.abortWith(Response.status(r.getResponseStatus())
                    .entity(r.getResponseBody())
                    .type("application/json")
                    .build());
            return;
        }

        // First time: insert IN_FLIGHT record; concurrent duplicate request hits UNIQUE constraint
        IdempotencyRecord rec = new IdempotencyRecord();
        rec.setIdempotencyKey(key);
        rec.setUserPrincipal(user);
        rec.setRequestMethod(method);
        rec.setRequestPath(path);
        rec.setRequestFingerprint(fp);
        rec.setState(IdempotencyRecord.State.IN_FLIGHT);
        rec.setResponseStatus(0);
        rec.setResponseHeaders(JsonNodeFactory.instance.objectNode());
        rec.setCreatedAt(OffsetDateTime.now());
        rec.setExpiresAt(OffsetDateTime.now().plusHours(ttlHours));

        try {
            repository.persist(rec);
        } catch (Exception e) {
            // Concurrent request won the insert — treat the same as IN_FLIGHT
            ctx.abortWith(Response.status(409)
                    .header("Retry-After", 1)
                    .entity("Concurrent request with this Idempotency-Key")
                    .build());
            return;
        }

        ctx.setProperty(PROP_RECORD, rec);
    }

    @Override
    @Transactional
    public void filter(ContainerRequestContext req, ContainerResponseContext resp) throws IOException {
        IdempotencyRecord rec = (IdempotencyRecord) req.getProperty(PROP_RECORD);
        if (rec == null) return;

        // Serialize the response body once; reuse for the replay path next time
        String body = resp.getEntity() == null ? null : mapper.writeValueAsString(resp.getEntity());

        rec.setResponseStatus(resp.getStatus());
        rec.setResponseBody(body);
        rec.setState(IdempotencyRecord.State.COMPLETED);
        rec.setCompletedAt(OffsetDateTime.now());
        // Repository's persist() already managed; flush happens at tx commit.
    }

    private static String sha256(byte[] body) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(body));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
```

> **Critical design choices:**
> - **`IN_FLIGHT` state**: first request inserts immediately so concurrent retries see "in flight" and either wait or 409 — prevents the race where two retries both miss the cache and both execute.
> - **Body fingerprint** prevents key reuse across different operations.
> - **`@NameBinding`** scopes the filter to opted-in methods; the filter doesn't run on `GET`s.
> - **The response is buffered as JSON string**, not the original entity, because the entity can be a stream consumed once.

### Apply to a resource

```java
@POST
@RolesAllowed("USER")
@Idempotent                              // ← opt in
@Operation(summary = "Create a payment")
public Response createPayment(@Valid PaymentRequest req) { ... }
```

### Purge job — `scheduler/IdempotencyPurgeJob.java`

```java
package {{packageRoot}}.scheduler;

import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import org.jboss.logging.Logger;

import java.time.OffsetDateTime;

@ApplicationScoped
public class IdempotencyPurgeJob {

    private static final Logger LOG = Logger.getLogger(IdempotencyPurgeJob.class);

    @Inject EntityManager em;

    @Scheduled(cron = "0 0 4 * * ?", identity = "idempotency-purge")
    @Transactional
    public void purgeExpired() {
        int deleted = em.createNativeQuery("""
            DELETE FROM idempotency_keys
             WHERE id IN (
                 SELECT id FROM idempotency_keys
                  WHERE expires_at < ?1
                  LIMIT 10000
             )
        """).setParameter(1, OffsetDateTime.now())
            .executeUpdate();
        LOG.infof("Purged %d expired idempotency keys", deleted);
    }
}
```

> Re-uses the `add-purge-job` pattern: `LIMIT` per run, scheduled, idempotent.

### `application.properties`

```properties
app.idempotency.ttl-hours=24
app.idempotency.max-body-bytes=102400
```

## OpenAPI documentation

For every `@Idempotent` endpoint, document the header in OpenAPI:

```java
@POST
@Idempotent
@Parameter(
    in = ParameterIn.HEADER,
    name = "Idempotency-Key",
    description = "Unique key (UUID recommended). Retries with the same key replay the original response for 24h.",
    schema = @Schema(type = SchemaType.STRING, maxLength = 255)
)
public Response createPayment(@Valid PaymentRequest req) { ... }
```

Or factor into a custom annotation. Either way, document it once per endpoint.

## Tests

```java
@QuarkusTest
@QuarkusTestResource(PostgresResource.class)
class IdempotencyTest {

    @Test
    void firstCall_executes_secondCall_replaysResponse() {
        String key = UUID.randomUUID().toString();
        String body = """{"amount":100,"currency":"BRL"}""";

        var first = given().auth().oauth2(TestTokenHelper.userToken())
            .header("Idempotency-Key", key)
            .contentType("application/json").body(body)
        .when().post("/v1/payments")
        .then().statusCode(201).extract().response();

        var second = given().auth().oauth2(TestTokenHelper.userToken())
            .header("Idempotency-Key", key)
            .contentType("application/json").body(body)
        .when().post("/v1/payments")
        .then().statusCode(201).extract().response();

        assertEquals(first.path("id"), second.path("id"));   // Same record
        assertEquals(1, paymentRepository.count());           // Only one row
    }

    @Test
    void sameKey_differentBody_returns422() {
        String key = UUID.randomUUID().toString();
        given().auth().oauth2(TestTokenHelper.userToken())
            .header("Idempotency-Key", key)
            .contentType("application/json").body("""{"amount":100,"currency":"BRL"}""")
        .when().post("/v1/payments").then().statusCode(201);

        given().auth().oauth2(TestTokenHelper.userToken())
            .header("Idempotency-Key", key)
            .contentType("application/json").body("""{"amount":999,"currency":"BRL"}""")
        .when().post("/v1/payments").then().statusCode(422);
    }

    @Test
    void noHeader_normalFlow() {
        // Should NOT consult idempotency table; each call creates a new payment
        given().auth().oauth2(TestTokenHelper.userToken())
            .contentType("application/json").body("""{"amount":100,"currency":"BRL"}""")
        .when().post("/v1/payments").then().statusCode(201);

        given().auth().oauth2(TestTokenHelper.userToken())
            .contentType("application/json").body("""{"amount":100,"currency":"BRL"}""")
        .when().post("/v1/payments").then().statusCode(201);

        assertEquals(2, paymentRepository.count());
    }
}
```

## Anti-patterns to refuse

- **Idempotency by deduplication on business fields** (e.g. "same email + same amount within 1 minute = duplicate"). Brittle and confuses retries with legitimate repeated business events.
- **Caching the response in memory** instead of the DB. Process restarts, multi-instance — the cache evaporates exactly when retries happen most.
- **No TTL** on the cache. Keys accumulate forever, table inflates.
- **Returning the cached response with new `created_at` / `updated_at` headers** as if it were fresh. Be honest: replay the exact original response.
- **Allowing the same key across different methods** (e.g. POST and PUT). The unique constraint includes method; reusing across methods is a client bug.
- **`@Idempotent` on GET / DELETE**. GET is already idempotent by definition; DELETE is idempotent by REST semantics (`DELETE /x` twice → second is 404 or 204). Adding the filter overhead is wasteful.
- **Required header.** Make it optional — clients that don't send it get normal behavior. Forcing it breaks naive clients.

## Post-generation

- Add `Idempotency-Key` to the OpenAPI servers/security documentation.
- Tell the user: clients SHOULD generate a UUID per logical operation and reuse it across retries of that operation; they SHOULD NOT reuse the key across logically different requests.
- Monitor table growth: `SELECT count(*) FROM idempotency_keys` should plateau at roughly `(requests/day) * (ttl_hours/24)`.
