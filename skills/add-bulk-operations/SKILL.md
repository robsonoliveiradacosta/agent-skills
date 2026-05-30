---
name: add-bulk-operations
description: "Enable efficient bulk inserts, updates, and deletes in a Quarkus + Hibernate project — configures hibernate.jdbc.batch_size with order_inserts/order_updates, shows the Panache repository pattern for batched persists with periodic flush+clear to avoid memory bloat, JPQL @Modifying bulk update/delete that bypasses the session, and native SQL escape hatch for the truly massive case. Use whenever the user mentions slow bulk inserts, \"Hibernate is slow\", batch processing, importing data, \"1M rows\", or any time a service iterates persist in a loop."
---

# add-bulk-operations

Hibernate is fast — except when used like JDBC. The classic "Hibernate is slow" diagnosis is almost always **one INSERT per row, no batching**. This skill enables batching at three levels and shows when to use each.

## When to invoke

- "Importing 100k rows takes 20 minutes"
- "Bulk update lots of records"
- "Add batch processing"
- Implicitly: any service method with `for (item : items) repository.persist(item);`

## The three levels

| Level | When to use | Speed |
|---|---|---|
| 1. **Batched persists** with `batch_size` | < 100k rows, need entity lifecycle (events, listeners, audit) | ~10x faster than naive |
| 2. **JPQL bulk `@Modifying`** | 100k+ rows, same update/delete logic per row, can skip lifecycle | ~100x faster |
| 3. **Native SQL `executeUpdate()`** | Millions of rows, complex JOIN/SET logic, lifecycle definitely skippable | ~1000x faster |

Go up the levels deliberately — each one trades flexibility for speed.

## Inputs to collect

| Input | Default |
|---|---|
| Operation type | persist / update / delete |
| Approximate row count | required — guides the level choice |
| Lifecycle hooks required? | check entity for `@PrePersist`, `@PreUpdate`, listeners |
| Idempotency requirement | for inserts: handle duplicates? |

## Level 1: Batched persists

### `application.properties` additions

```properties
# Enable JDBC batching at the driver level
quarkus.hibernate-orm.jdbc.statement-batch-size=50

# Sort statements so batches stay contiguous (same table, same operation)
quarkus.hibernate-orm.statement-batch.batch-versioned-data=true

# These belong in the Hibernate config; Quarkus surfaces them as raw properties
quarkus.hibernate-orm.unsupported-properties."hibernate.order_inserts"=true
quarkus.hibernate-orm.unsupported-properties."hibernate.order_updates"=true
```

> **batch_size 50** is the sweet spot for PostgreSQL — bigger batches help less and start eating memory. Tune up if profiling shows benefit.

### Service pattern — flush + clear per batch

```java
@ApplicationScoped
public class AlbumImportService {

    @Inject AlbumRepository albumRepository;
    @Inject EntityManager  em;     // Quarkus injects the configured one

    @Transactional
    public void importAll(List<AlbumRequest> requests) {
        int batchSize = 50;
        int i = 0;
        for (AlbumRequest req : requests) {
            Album a = new Album(req.title(), req.year());
            albumRepository.persist(a);

            if (++i % batchSize == 0) {
                em.flush();   // send to DB
                em.clear();   // detach managed entities — frees memory
            }
        }
        em.flush();
        em.clear();
    }
}
```

> **Critical**: `flush()` without `clear()` doesn't help — managed entities accumulate in the session and OOM kills the JVM at ~50k rows. **Both** are required.

> The `@PrePersist` and `@PostPersist` lifecycle callbacks **still fire** with this pattern (batching is JDBC-level, not entity-level). Audit columns, soft-delete logic, etc. all work.

## Level 2: JPQL bulk update/delete

For "set status=archived where created_at < ?", iterating in Java is wasteful. Use JPQL `@Modifying`:

```java
@Transactional
public int archiveOldAlbums(LocalDateTime cutoff) {
    return em.createQuery("""
            UPDATE Album a
               SET a.archived = true, a.updatedAt = :now
             WHERE a.createdAt < :cutoff
              AND a.archived = false
        """)
        .setParameter("now", LocalDateTime.now())
        .setParameter("cutoff", cutoff)
        .executeUpdate();
}
```

Or via Panache:

```java
public long archiveOld(LocalDateTime cutoff) {
    return Album.update("archived = true, updatedAt = ?1 WHERE createdAt < ?2 AND archived = false",
                        LocalDateTime.now(), cutoff);
}
```

> Returns the number of affected rows — log it.

### **The lifecycle caveat**

Bulk `@Modifying` operations bypass the Hibernate session entirely:

- ❌ `@PreUpdate` / `@PostUpdate` callbacks do **not** fire.
- ❌ `@Version` is **not** incremented (concurrent updates may be lost on later flush).
- ❌ Cached entities in the session become **stale** — call `em.clear()` afterward if any subsequent code reads from the affected rows.
- ❌ Audit columns from `@EntityListeners` are **not** populated — set them explicitly in the SQL (`SET updated_at = :now`).

Document this in the service method's comment. Generate it for every `@Modifying` call.

## Level 3: Native SQL — the escape hatch

For massive operations (millions of rows, complex CTE, server-side JOIN):

```java
@Transactional
public int rebuildSearchIndex() {
    return em.createNativeQuery("""
        INSERT INTO search_index (album_id, tsv)
        SELECT id, to_tsvector('portuguese', title || ' ' || coalesce(metadata->>'isrc', ''))
          FROM albums
        ON CONFLICT (album_id) DO UPDATE
          SET tsv = EXCLUDED.tsv
    """).executeUpdate();
}
```

> Native SQL is the right call when the SET expression involves database-specific features (`tsvector`, window functions, recursive CTEs). The trade-off: zero portability across databases. Document the dependency explicitly.

## Tests

```java
@Test
@QuarkusTestResource(PostgresResource.class)
void importAll_persistsAllInOneTransaction() {
    List<AlbumRequest> hundred = IntStream.range(0, 100)
        .mapToObj(i -> new AlbumRequest("Album " + i, 2024 + (i%5), List.of(1L)))
        .toList();

    service.importAll(hundred);

    assertEquals(100, albumRepository.count());
}

@Test
void archiveOld_bypassesAuditListener() {
    // Document the trade-off in a test so future contributors don't expect
    // updatedBy to be set by the listener for bulk operations.
    LocalDateTime cutoff = LocalDateTime.now();
    Long id = createAlbumOlderThan(cutoff);

    int affected = service.archiveOldAlbums(cutoff);

    assertEquals(1, affected);
    Album reloaded = albumRepository.findById(id);
    assertTrue(reloaded.isArchived());
    // The audit listener did NOT run — updatedBy is whatever it was before.
}
```

## Profiling

Before claiming "it's fast now", measure:

```sql
-- PostgreSQL: log slow statements
SET log_min_duration_statement = 100; -- ms
```

Or use Quarkus's built-in metrics (`add-observability` skill): `hibernate.statements_count`, `hibernate.flush_count`, JDBC `db.client.connections.usage`.

A naive import of 10k rows should produce ~200 SQL statements (10k / 50 batch_size), not 10k.

## Anti-patterns to refuse

- **Forgetting `em.clear()`** after `em.flush()` in a loop. Memory grows linearly with iterations.
- **Mixing entity persists with bulk `@Modifying`** in the same transaction without `em.clear()` between them. The cached entity state goes stale; subsequent reads see ghosts.
- **Using `cascade = ALL` on a `@OneToMany`** as a "bulk insert" — Hibernate still persists one-by-one, just hidden. Use explicit batching.
- **Batch size 1000** because "bigger is better". PostgreSQL parser starts thrashing; batch protocol message size limits kick in. Stay around 50.
- **`@Modifying` inside a `@Transactional(readOnly = true)` method**. Silent failure in some configs; verbose error in others. Use a non-readonly tx.
- **Bulk inserts via REST endpoint without a size cap.** Someone POSTs a 500 MB JSON, the JVM OOMs. Always validate `requests.size() < N_MAX` at the resource layer.

## Post-generation

- Tell the user the **lifecycle caveat** for `@Modifying` — most surprises come from there.
- Add a regression test: time a 1000-row insert before and after enabling batching. The numbers tell the story.
- For real ETL workloads (millions+), recommend looking at `COPY FROM` (PostgreSQL native) — out of scope here, but link to it.
