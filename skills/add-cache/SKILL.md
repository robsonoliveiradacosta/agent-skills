---
name: add-cache
description: "Add declarative method-level caching to a Quarkus service using the quarkus-cache extension — Caffeine for in-process (single instance) or Redis for distributed, with @CacheResult on reads and @CacheInvalidate / @CacheInvalidateAll on writes, plus TTL and size caps. Use when the user mentions caching, \"speed up the listing endpoint\", repeated expensive computations, or external API responses that change slowly."
---

# add-cache

Add `@CacheResult` to expensive read methods and `@CacheInvalidate` / `@CacheInvalidateAll` to the writes that affect them. Defaults to **Caffeine (in-process)** because it's free, fast, and matches the project's single-instance compose setup. Switch to **Redis** when the user explicitly runs multiple replicas.

## When to invoke

- "Cache the regional list — it barely changes"
- "Speed up this endpoint"
- "Cache the response of upstream X for 5 minutes"

## When NOT to invoke

- Per-user / per-request data where every request is unique — cache won't hit.
- Strongly-consistent reads where staleness is unacceptable (financial balance, role checks).
- Write-heavy workloads where every change invalidates the cache.

If the case smells wrong, push back and ask the user to confirm the value is bounded, slow-changing, and shared across callers.

## Inputs to collect

| Input | Default |
|---|---|
| Backend | `caffeine` (single instance) or `redis` |
| Cache name | derive from method (e.g. `regionals-active`) |
| Expire after write (seconds) | `300` |
| Max entries (Caffeine only) | `1000` |
| Methods to cache | required |
| Methods that invalidate | required |

## Dependency

Caffeine (in-process):
```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-cache</artifactId>
</dependency>
```

Redis (distributed):
```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-redis-cache</artifactId>
</dependency>
```

## `application.properties` additions

Caffeine:
```properties
quarkus.cache.caffeine."regionals-active".expire-after-write=300s
quarkus.cache.caffeine."regionals-active".maximum-size=1000
quarkus.cache.caffeine."regionals-active".metrics-enabled=true

# Disable cache in tests so test data changes are immediately visible
%test.quarkus.cache.enabled=false
```

Redis:
```properties
quarkus.cache.type=redis
quarkus.cache.redis."regionals-active".expire-after-write=300s
quarkus.cache.redis."regionals-active".prefix=acme:regionals
quarkus.redis.hosts=${REDIS_URL:redis://localhost:6379}
```

> `quarkus.cache.enabled=false` in tests is **non-optional** — without it, write-test-read sequences will see stale data.

## Files to modify

### Read method — `@CacheResult`

```java
package {{packageRoot}}.service;

import io.quarkus.cache.CacheResult;

@ApplicationScoped
public class RegionalService {

    @Inject RegionalRepository repository;

    @CacheResult(cacheName = "regionals-active")
    public List<RegionalResponse> findAllActive() {
        return repository.findActive().stream().map(RegionalResponse::from).toList();
    }
}
```

### Method with a key derived from a parameter

```java
@CacheResult(cacheName = "regional-by-id")
public RegionalResponse findById(@CacheKey Long id) {
    return repository.findByIdOptional(id)
        .map(RegionalResponse::from)
        .orElseThrow(() -> new NotFoundException("Regional " + id));
}
```

> `@CacheKey` is **required** when the method has multiple parameters and only some of them should compose the key. With a single parameter, Quarkus uses it implicitly.

### Write methods — invalidate

```java
@Transactional
@CacheInvalidateAll(cacheName = "regionals-active")
@CacheInvalidate(cacheName = "regional-by-id")
public void update(@CacheKey Long id, RegionalRequest req) {
    // mutate the entity ...
}

@Transactional
@CacheInvalidateAll(cacheName = "regionals-active")
public void sync() {
    // bulk update — invalidate the whole list cache
}
```

> Rule of thumb: **list caches → `@CacheInvalidateAll`**, **by-id caches → `@CacheInvalidate` with `@CacheKey id`**.

## Tests

Generate one test that proves invalidation works (the trickiest failure mode):

```java
@Test
@TestProfile(CacheEnabledTestProfile.class) // overrides %test.quarkus.cache.enabled=false
void updateInvalidatesListCache() {
    given().auth().oauth2(TestTokenHelper.userToken())
    .when().get("/v1/regionals").then().statusCode(200).body("$.size()", equalTo(2));

    given().auth().oauth2(TestTokenHelper.adminToken())
        .contentType("application/json").body("{\"name\":\"South\"}")
    .when().put("/v1/regionals/1").then().statusCode(200);

    // List should reflect the update — if cache wasn't invalidated, this would still show the old name.
    given().auth().oauth2(TestTokenHelper.userToken())
    .when().get("/v1/regionals").then().body("[0].name", equalTo("South"));
}
```

`CacheEnabledTestProfile` is a small `@TestProfile` implementation that returns `Map.of("quarkus.cache.enabled", "true")`.

## Cache metrics

With `metrics-enabled=true` and Micrometer Prometheus on the classpath, scrape exposes:

- `cache_gets_total{cache="regionals-active", result="hit|miss"}`
- `cache_puts_total{cache="regionals-active"}`
- `cache_evictions_total{cache="regionals-active"}`

Recommend a Grafana panel: `rate(cache_gets_total{result="hit"}[5m]) / rate(cache_gets_total[5m])` — the hit ratio. Below 50% suggests the cache is the wrong solution for the workload.

## Distributed-cache considerations (Redis)

- **Serialization**: values must be Jackson-serializable. Avoid caching JPA entities directly — cache the **response DTO**. Lazy-loaded relationships will throw `LazyInitializationException` outside a session.
- **Key prefixing**: `prefix` keeps the namespace clean. Always set it per cache.
- **No `null` caching**: by default `@CacheResult` will cache `null`. If a method throws `NotFoundException`, it isn't cached — but if it returns `null`, the next call won't try again. Be deliberate.
- **Eviction at scale**: `@CacheInvalidateAll` against Redis requires scanning keys with the prefix. Don't call it on a hot path.

## Anti-patterns to refuse

- **Caching authorization decisions** without an invalidation hook on role changes. Stale role caches → security incident.
- **Caching JPA entities directly.** Cache DTOs.
- **Caching responses that contain `requestId` or per-user data.** They'll leak between callers.
- **No TTL.** Always set `expire-after-write`. Forgotten caches accumulate stale data forever.
- **Wrapping a `@Transactional` method with `@CacheResult` and persisting inside it.** Persists on miss may run inside the cache lookup's transaction — unexpected behavior.

## Post-generation

- Tell the user the new cache name(s) and the metrics they expose.
- Confirm `%test.quarkus.cache.enabled=false` is in place.
- Suggest measuring hit ratio for the first few days — if low, the cache is overhead with no benefit.
