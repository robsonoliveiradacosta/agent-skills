---
name: add-rate-limit
description: "Add a per-principal in-process rate limiter to a Quarkus REST API using bucket4j and a JAX-RS ContainerRequestFilter. Adds the bucket4j-core dependency, generates RateLimitFilter that runs after authentication (Priorities.AUTHENTICATION+1), tags responses with X-RateLimit-* headers, and wires a config flag (app.rate-limit.enabled) so tests can disable it. Use when the user asks for rate limiting, throttling, abuse protection, or \"limit X requests per minute per user\"."
---

# add-rate-limit

Add per-authenticated-user rate limiting using bucket4j and a JAX-RS filter, matching this repo's `RateLimitFilter` exactly.

## When to invoke

- "Add rate limiting"
- "Limit requests per user"
- "Protect the API from abuse"

## Scope and limitations

- **Per JWT principal name**, in-process state (ConcurrentHashMap of `Bucket`). Does **not** scale horizontally without an external store (Redis bucket4j extension).
- Skips unauthenticated requests — so `/auth/login` and `@PermitAll` endpoints are not rate-limited by this filter. If the user needs IP-based limiting for those, generate a second filter.
- One global limit (e.g. 10 req/min). Per-endpoint or per-role limits require a different design — push back and ask the user to confirm scope before generating something more elaborate.

## Inputs to collect

| Input | Default |
|---|---|
| Requests per period | `10` |
| Refill period | `1 minute` |
| Disable in tests? | `yes` — set `%test.app.rate-limit.enabled=false` |

## Dependency

```xml
<dependency>
    <groupId>com.bucket4j</groupId>
    <artifactId>bucket4j-core</artifactId>
    <version>8.10.1</version>
</dependency>
```

## `application.properties` addition

```properties
app.rate-limit.enabled=true
%test.app.rate-limit.enabled=false
```

## File to generate — `security/RateLimitFilter.java`

```java
package {{packageRoot}}.security;

import io.github.bucket4j.Bandwidth;
import io.github.bucket4j.Bucket;
import io.github.bucket4j.ConsumptionProbe;
import io.github.bucket4j.Refill;
import jakarta.annotation.Priority;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.security.Principal;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Provider
@Priority(Priorities.AUTHENTICATION + 1)
public class RateLimitFilter implements ContainerRequestFilter, ContainerResponseFilter {

    private static final int    LIMIT         = {{limit}};
    private static final Duration REFILL_PERIOD = Duration.ofMinutes({{refillMinutes}});
    private static final String REMAINING_PROP = "rateLimitRemaining";

    private final Map<String, Bucket> buckets = new ConcurrentHashMap<>();

    @ConfigProperty(name = "app.rate-limit.enabled", defaultValue = "true")
    boolean enabled;

    private Bucket createBucket() {
        return Bucket.builder()
                .addLimit(Bandwidth.classic(LIMIT, Refill.intervally(LIMIT, REFILL_PERIOD)))
                .build();
    }

    @Override
    public void filter(ContainerRequestContext ctx) {
        if (!enabled) return;
        Principal principal = ctx.getSecurityContext().getUserPrincipal();
        if (principal == null) return;

        Bucket bucket = buckets.computeIfAbsent(principal.getName(), k -> createBucket());
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);

        if (!probe.isConsumed()) {
            long waitSec = probe.getNanosToWaitForRefill() / 1_000_000_000;
            ctx.abortWith(Response.status(429)
                .header("X-RateLimit-Limit", LIMIT)
                .header("X-RateLimit-Remaining", 0)
                .header("X-RateLimit-Reset", waitSec)
                .entity("{\"status\":429,\"error\":\"Too Many Requests\"}")
                .type("application/json")
                .build());
        } else {
            ctx.setProperty(REMAINING_PROP, probe.getRemainingTokens());
        }
    }

    @Override
    public void filter(ContainerRequestContext req, ContainerResponseContext resp) {
        Long remaining = (Long) req.getProperty(REMAINING_PROP);
        if (remaining != null) {
            resp.getHeaders().add("X-RateLimit-Limit", LIMIT);
            resp.getHeaders().add("X-RateLimit-Remaining", remaining);
        }
    }
}
```

## Test pattern (optional, generate only if requested)

If the user wants test coverage, generate a small `RateLimitFilterIntegrationTest` that flips `app.rate-limit.enabled=true` via `@TestProfile`, hits an endpoint LIMIT+1 times, and asserts the last call returns 429.

## Anti-patterns to refuse

- Caching the `Bucket` map across deployments — it's intentionally process-local. If the user needs distributed limits, recommend the bucket4j-redis extension explicitly rather than fudging it.
- Pinning to IP for authenticated endpoints — principal is more reliable. For unauthenticated endpoints (login), a separate IP-based filter is appropriate.
- Forgetting `%test.app.rate-limit.enabled=false`. Without it, REST Assured tests that hammer endpoints will flake.

## Post-generation

- Confirm at runtime: hit a protected endpoint 11 times rapidly and observe `429` on the 11th, with `X-RateLimit-Remaining: 0` and `X-RateLimit-Reset`.
- Tell the user the per-process caveat explicitly.
