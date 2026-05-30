---
name: add-fault-tolerance
description: "Harden external integrations in a Quarkus project with SmallRye Fault Tolerance — applies @Timeout, @Retry with exponential backoff, @CircuitBreaker, @Bulkhead, and @Fallback annotations to REST Clients and the services that call them, plus Micrometer metrics so the circuit-breaker state is observable. Use when the user mentions retry, timeout, circuit breaker, resilience, \"stop a slow upstream from killing us\", or any external HTTP call without protection."
---

# add-fault-tolerance

Apply MicroProfile Fault Tolerance (`quarkus-smallrye-fault-tolerance`) to external integration points so a slow / failing upstream doesn't cascade into the rest of the API.

The target is typically a class in `integration/` (REST Client) or `service/` (the service method that calls it) — **not** business services or DB writes.

## When to invoke

- "The regional API is flaky, add retries"
- "Add a circuit breaker"
- "Make this resilient to upstream failures"
- Implicitly: every time `add-scheduled-rest-client` is used and the upstream is third-party.

## Inputs to collect

| Input | Default |
|---|---|
| Target class & method | required (must be CDI-managed) |
| Timeout (ms) | `5000` |
| Max retries | `3` |
| Retry delay (ms) | `200` |
| Retry jitter (ms) | `100` |
| Circuit breaker request threshold | `10` |
| Circuit breaker failure ratio | `0.5` |
| Circuit breaker delay (ms) | `30000` |
| Fallback strategy | required — "empty list", "cached value", "throw mapped exception", or "graceful degrade" |

## Dependency

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-smallrye-fault-tolerance</artifactId>
</dependency>
```

> Combine with `quarkus-micrometer-registry-prometheus` (already added by `/add-observability`) to expose `ft_circuitbreaker_*` and `ft_retry_*` metrics automatically.

## `application.properties` additions

```properties
# Make the metrics about fault tolerance observable
quarkus.fault-tolerance.metrics.enabled=true

# Test profile: shorter timings so tests don't hang
%test.<full.qualified.class>/<method>.Timeout/value=200
%test.<full.qualified.class>/<method>.Retry/maxRetries=1
```

## Where to apply the annotations

**Recommended**: wrap the **service method** that calls the REST Client, not the REST Client interface itself. This keeps fault tolerance composable with the service's business logic and fallback method.

```java
package {{packageRoot}}.service;

import {{packageRoot}}.dto.RegionalDto;
import {{packageRoot}}.integration.RegionalApiClient;
import io.quarkus.logging.Log;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.faulttolerance.*;
import org.eclipse.microprofile.rest.client.inject.RestClient;

import java.time.temporal.ChronoUnit;
import java.util.List;

@ApplicationScoped
public class RegionalSyncService {

    @Inject @RestClient RegionalApiClient client;

    @Timeout(value = 5000, unit = ChronoUnit.MILLIS)
    @Retry(
        maxRetries = 3,
        delay = 200, delayUnit = ChronoUnit.MILLIS,
        jitter = 100, jitterDelayUnit = ChronoUnit.MILLIS,
        retryOn = { jakarta.ws.rs.WebApplicationException.class, java.io.IOException.class },
        abortOn = { jakarta.ws.rs.BadRequestException.class }
    )
    @CircuitBreaker(
        requestVolumeThreshold = 10,
        failureRatio = 0.5,
        delay = 30_000, delayUnit = ChronoUnit.MILLIS,
        successThreshold = 2
    )
    @Fallback(fallbackMethod = "syncFallback")
    public List<RegionalDto> fetchRemote() {
        return client.getRegionais();
    }

    /** Fallback signature must match the protected method exactly. */
    public List<RegionalDto> syncFallback() {
        Log.warn("RegionalApiClient unavailable — returning empty list");
        return List.of();
    }
}
```

> **Key choices to explain to the user**:
> - `Retry` only on **transient** errors. `abortOn` lists exceptions where retrying is pointless (4xx client errors).
> - `CircuitBreaker.successThreshold = 2` requires two consecutive successes before fully closing — prevents flapping.
> - `Fallback` method must have the **same signature** (return type + parameters) as the protected method. The compiler doesn't enforce this; runtime will fail at startup if mismatched.

## When to use `@Bulkhead`

Add `@Bulkhead` when:
- The upstream is slow (≥ 1s) AND
- Concurrent calls would saturate the worker pool.

```java
@Bulkhead(value = 10, waitingTaskQueue = 20)
```

Otherwise skip it — bulkhead adds queue latency for no benefit.

## Async vs sync

Use `@Asynchronous` only if the calling code can handle a `CompletionStage<T>` / `Uni<T>` return value. Forcing async on a synchronous business service ripples through every caller. If unsure, leave it sync.

## Metrics produced

Once enabled, Prometheus scrape exposes:

- `ft_retry_calls_total{result="valueReturned|exceptionNotRetryable|maxRetriesReached", retried="true|false"}`
- `ft_circuitbreaker_state_total{state="closed|open|halfOpen"}`
- `ft_circuitbreaker_calls_total{result="success|failure|circuitBreakerOpen"}`
- `ft_timeout_calls_total`

Suggest a Grafana panel: `rate(ft_circuitbreaker_state_total{state="open"}[5m])` — alert when nonzero for >2 min.

## Tests

WireMock test that proves retry behavior:

```java
@Test
void retriesOn5xx() {
    wiremock.stubFor(get("/v1/regionais")
        .inScenario("retry")
        .whenScenarioStateIs(Scenario.STARTED)
        .willReturn(serverError())
        .willSetStateTo("ok"));
    wiremock.stubFor(get("/v1/regionais")
        .inScenario("retry")
        .whenScenarioStateIs("ok")
        .willReturn(okJson("[]")));

    assertNotNull(service.fetchRemote());
    wiremock.verify(2, getRequestedFor(urlEqualTo("/v1/regionais")));
}

@Test
void fallbackOnTimeout() {
    wiremock.stubFor(get("/v1/regionais")
        .willReturn(aResponse().withFixedDelay(2000)));

    assertEquals(List.of(), service.fetchRemote()); // fallback returned empty list
}
```

## Anti-patterns to refuse

- **Retrying POSTs / PUTs without idempotency guarantees.** Side effects double-apply. Either make the upstream idempotent (idempotency key) or skip retry on non-GET.
- **`@Retry` without `@Timeout`.** A retry on a hanging call multiplies the hang.
- **Circuit breaker on a database call.** That's not the right tool — fix the slow query.
- **`@Fallback` that swallows the error silently** without logging or metric. Always log at WARN with context.
- **Tight retry loops** (no `delay`). DOS your own upstream.
- **Annotations on private methods.** SmallRye uses CDI interceptors which require public/protected methods on CDI-managed beans.

## Post-generation

- Confirm `quarkus.fault-tolerance.metrics.enabled=true`.
- Run the WireMock-backed tests.
- Tell the user to wire an alert on `ft_circuitbreaker_state_total{state="open"} > 0`.

---

## Strategic considerations & governance

## Goal

Make remote dependencies and background sync jobs fail predictably and recover safely.

## Workflow

1. Set explicit connect and read timeouts for every external client.
2. Retry only safe operations or operations made idempotent by keys or unique constraints.
3. Use bounded retries with backoff; avoid retry storms.
4. Consider circuit breakers for repeatedly failing dependencies.
5. Design partial failure responses with created, updated, skipped, and failed counts.
6. Log failure context and expose safe operational status.
7. Test timeout, server error, malformed payload, and retry/idempotency paths.

## Rules

- Do not retry non-idempotent writes unless an idempotency key exists.
- Keep scheduled jobs safe to rerun.
- Fail fast when a dependency is required for request completion.
- Degrade gracefully only when the product can tolerate stale or partial data.
- Make fallback behavior explicit in tests and docs.

## Example

For regional synchronization, use external IDs or natural keys to upsert records, return a `SyncResult`, and ensure repeated scheduler runs do not duplicate rows.
