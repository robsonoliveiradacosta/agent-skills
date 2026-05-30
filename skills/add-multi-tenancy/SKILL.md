---
name: add-multi-tenancy
description: "Add row-level multi-tenancy to a Quarkus + Hibernate 6.4+ project via @TenantId discriminator column with TenantResolver that reads the tenant claim from SecurityIdentity — generates the Flyway migration to add tenant_id to every relevant table with composite unique constraints, a CurrentTenantIdentifierResolver wired to JWT claims, application of @TenantId to entities, and a strong recommendation pattern for testing tenant isolation. Use ONLY when the project genuinely needs multiple tenants (separate customer organizations sharing the same database); otherwise this adds noise without value."
---

# add-multi-tenancy

Add row-level multi-tenancy: every relevant row carries a `tenant_id`, Hibernate auto-filters every query by the current tenant, and the current tenant is resolved from the JWT.

**This is an architectural skill.** Applying it after the fact is hard — every existing row needs a `tenant_id`, every unique constraint needs to be widened. Run this **early**.

## When NOT to invoke

- Project is **single-tenant** (one org owns the data). Don't add this preemptively.
- "Multi-environment" (dev/staging/prod) — that's deployment, not tenancy.
- "Multiple types of users" — that's roles (`@RolesAllowed`), not tenancy.

If unsure, push back and ask: **"Will two distinct customer organizations ever access this system with isolation between them?"** If no → don't apply.

## Strategies

Three patterns exist; this skill implements **#1 (row-level)** because it's the simplest. Mention the alternatives so the user can choose deliberately.

| Strategy | When | Cost |
|---|---|---|
| **1. Row-level** (`@TenantId`, this skill) | < 1000 tenants, similar load patterns | Single DB to back up; mistakes leak data across tenants |
| **2. Schema-per-tenant** | 100-1000 tenants, varied load | More schemas to migrate; one bad migration affects all |
| **3. Database-per-tenant** | Few large tenants, strict isolation | Massive ops overhead; isolation is real |

If the user wants #2 or #3, this skill is the wrong tool — recommend Hibernate's `MULTI_TENANT_CONNECTION_PROVIDER` setup and stop.

## Inputs to collect

| Input | Default |
|---|---|
| Tenant identifier source | JWT claim `tenant_id` (most common) |
| Tenant id type | `String` (UUID) — never `Long` (sequence collisions between tenants) |
| Entities to scope | required — typically all business entities; **not** `User` if users span tenants |
| Cross-tenant entities | list any (e.g. `Plan`, `Country`) — these stay shared |

## Flyway migrations

One migration per entity. Schema change is **always destructive** (drops/widens uniques) — do it in a careful single migration per table.

### `V<n>__add_tenant_id_to_albums.sql`

```sql
-- 1. Add nullable
ALTER TABLE albums ADD COLUMN tenant_id VARCHAR(36);

-- 2. Backfill — use a SENTINEL value for migration of legacy data
-- The DEFAULT below is INTENTIONALLY removed in step 4 so future inserts
-- without an explicit tenant_id fail loudly.
UPDATE albums SET tenant_id = 'LEGACY' WHERE tenant_id IS NULL;

-- 3. NOT NULL
ALTER TABLE albums ALTER COLUMN tenant_id SET NOT NULL;

-- 4. Widen existing uniques (e.g. title was UNIQUE globally; now unique per tenant)
ALTER TABLE albums DROP CONSTRAINT IF EXISTS uq_albums_title;
CREATE UNIQUE INDEX uq_albums_title_per_tenant ON albums (tenant_id, title);

-- 5. Compound index for the common query pattern (filtered by tenant + something)
CREATE INDEX idx_albums_tenant ON albums (tenant_id);
```

> **Composite indexes**: leftmost-prefix rule. Every common query gets a `(tenant_id, ...)` index. Generate one per common filter.

## Entity changes

Hibernate 6.4+ adds `@TenantId`:

```java
import org.hibernate.annotations.TenantId;

@Entity
@Table(name = "albums")
public class Album extends AuditableEntity {

    // ... existing fields ...

    @TenantId
    @Column(name = "tenant_id", nullable = false, updatable = false, length = 36)
    private String tenantId;

    public String getTenantId() { return tenantId; }
}
```

> `updatable = false` — once set, a row's tenant can't change. Anyone moving it crosses an isolation boundary.

## Tenant resolver — `config/JwtTenantResolver.java`

```java
package {{packageRoot}}.config;

import io.quarkus.arc.Arc;
import io.quarkus.hibernate.orm.runtime.tenant.TenantResolver;
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class JwtTenantResolver implements TenantResolver {

    /** Sentinel used when no tenant context exists (system jobs, anonymous endpoints). */
    public static final String NO_TENANT = "__system";

    @Override
    public String getDefaultTenantId() {
        return NO_TENANT;
    }

    @Override
    public String resolveTenantId() {
        // TenantResolver isn't request-scoped; look up SecurityIdentity dynamically.
        SecurityIdentity identity = Arc.container().instance(SecurityIdentity.class).get();
        if (identity == null || identity.isAnonymous()) {
            return NO_TENANT;
        }
        Object claim = identity.getAttribute("tenant_id");
        if (claim == null) {
            // Reject early — better than silently using NO_TENANT
            throw new IllegalStateException("JWT missing tenant_id claim for " + identity.getPrincipal().getName());
        }
        return claim.toString();
    }
}
```

> **Critical**: throw on missing claim. The alternative — silently falling back to a sentinel — is exactly how cross-tenant data leaks happen. Better to break the request than to return a tenant's data to the wrong tenant.

## `application.properties`

```properties
# Enable Hibernate multi-tenant filtering
quarkus.hibernate-orm.multitenant=DISCRIMINATOR
```

> No connection-provider config needed for row-level. Hibernate auto-applies a `WHERE tenant_id = ?` filter on every query and `INSERT ... VALUES (..., ?)` on every persist.

## JWT — add the tenant claim

If `add-jwt-auth` is in place, update the `TokenService` to include the claim:

```java
public String generateToken(User user) {
    return Jwt.issuer(ISSUER)
            .upn(user.getUsername())
            .groups(Set.of(user.getRole().name()))
            .claim("tenant_id", user.getTenantId())   // ← new
            .expiresIn(TOKEN_LIFESPAN)
            .sign();
}
```

And the `User` entity needs a `tenantId` field too (it's already `@TenantId` if you applied the same pattern to `User`, otherwise just a plain column).

For **`TestTokenHelper`**, generate tenant-aware variants:

```java
public static String adminToken(String tenantId) {
    return token("admin", "ADMIN", tenantId);
}
public static String adminToken() { return adminToken("test-tenant-a"); }

public static String userToken(String tenantId) {
    return token("user", "USER", tenantId);
}
public static String userToken() { return userToken("test-tenant-a"); }

private static String token(String username, String role, String tenantId) {
    return Jwt.issuer("{{issuer}}")
            .upn(username)
            .groups(Set.of(role))
            .claim("tenant_id", tenantId)
            .expiresIn(Duration.ofMinutes(5))
            .sign();
}
```

## Critical test — tenant isolation

Generate this and **do not let the user skip it**. It's the single test that proves the feature works:

```java
@QuarkusTest
@QuarkusTestResource(PostgresResource.class)
class TenantIsolationTest {

    @Test
    void tenantBCannotSeeTenantAsAlbums() {
        // Tenant A creates an album
        given().auth().oauth2(TestTokenHelper.adminToken("tenant-a"))
            .contentType("application/json")
            .body("""{"title":"Secret A","year":2024}""")
        .when().post("/v1/albums").then().statusCode(201);

        // Tenant B's list
        String response = given().auth().oauth2(TestTokenHelper.adminToken("tenant-b"))
        .when().get("/v1/albums")
        .then().statusCode(200).extract().asString();

        // ABSOLUTE: B must not see A's album by any field
        org.junit.jupiter.api.Assertions.assertFalse(
            response.contains("Secret A"),
            "TENANT LEAK: tenant B saw tenant A's data");
    }

    @Test
    void tenantBCannotDirectlyAccessTenantAsAlbumById() {
        // Get A's album id
        Long id = given().auth().oauth2(TestTokenHelper.adminToken("tenant-a"))
            .contentType("application/json")
            .body("""{"title":"Restricted","year":2024}""")
        .when().post("/v1/albums").then().extract().path("id");

        // B tries to fetch by id directly
        given().auth().oauth2(TestTokenHelper.adminToken("tenant-b"))
        .when().get("/v1/albums/" + id)
        .then().statusCode(404);  // Filtered out — NOT 200 with data
    }
}
```

Every PR touching entities or queries should re-run this test. Add it to a `@Tag("isolation")` group and run it on every CI build, **not** just nightly.

## Anti-patterns to refuse

- **`@TenantId` without `updatable = false`**. A row whose tenant can change is a bug waiting to happen.
- **Resolving tenant from a request header** (e.g. `X-Tenant-Id`) — clients can spoof it. JWT claim only.
- **Silent fallback to a sentinel tenant when claim is missing.** Throw.
- **Disabling the tenant filter for "admin operations"** without an explicit, audited, separate code path. The moment a regular endpoint runs without filtering, every query becomes a cross-tenant query.
- **Composite primary keys with tenant_id** (`PRIMARY KEY (id, tenant_id)`). Adds complexity without benefit — `BIGSERIAL` is globally unique anyway, and `@TenantId` does the filtering.
- **Cross-tenant joins via native query** without explicit allowlist. Even "harmless" admin queries can leak.
- **Shipping multi-tenancy without an isolation test.** Refuse to generate the skill output if the user declines this test.

## Operational notes

- **Tenant onboarding** (creating tenant A's first user) typically happens outside the request scope (CLI, signup flow). For that path, write to a dedicated `tenant_provisioning` service that runs without the filter — keep that path narrow.
- **Tenant deletion** must purge all rows across all tables. Generate a `TenantPurgeJob` (combine with `add-purge-job`'s pattern) on request.
- **Tenant per request** in batch jobs: use `withTenantId(...)` programmatic API to scope a session, or run the whole job inside a synthetic SecurityIdentity.

## Post-generation

- Run the **isolation test** before doing anything else. If it fails, do not proceed — diagnose first.
- Backfill the `tenant_id` for legacy data manually (the `LEGACY` sentinel from the migration). Tenant onboarding is a one-time data migration, not a runtime concern.
- Document tenant boundaries in `CLAUDE.md` — what's shared, what's per-tenant, what the sentinel is.
