---
name: add-purge-job
description: "Add a scheduled job that hard-deletes soft-deleted rows older than a configurable retention period — generates a @Scheduled job per entity, uses bulk JPQL DELETE for performance, exposes per-entity retention as @ConfigProperty so ops can tune without redeploy, increments a Micrometer counter with the entity tag, and logs counts for audit. Use only when add-soft-delete is already in place; otherwise prefer to delete records directly. Trigger when the user mentions purge, retention, cleanup, \"soft-deleted rows accumulating\", \"GDPR / LGPD retention\", or \"scheduled deletion\"."
---

# add-purge-job

Companion to `add-soft-delete`. Without a purge, soft-deleted rows accumulate forever — disk fills, indexes bloat, queries slow. This skill schedules deterministic cleanup with metrics so operators can audit what was deleted and when.

## When to invoke

- "Purge old soft-deleted records"
- "Set retention period"
- "GDPR / LGPD: delete data after N days"
- Implicitly: every time `add-soft-delete` is applied — pair them.

## When NOT to invoke

- `add-soft-delete` hasn't been applied (or the table uses a different deletion pattern). Pushing back here is correct.
- The data is **legally required to be retained** (financial transactions in some jurisdictions). Verify before generating.

## Inputs to collect

| Input | Default |
|---|---|
| Entities to purge | required; one job per entity (different retentions usually) |
| Retention period per entity | required, e.g. `90 days` |
| Schedule | required, e.g. `0 0 3 * * ?` (3 AM daily) |
| Batch size | `1000` — limit each run so a backlog doesn't lock the table |
| Soft-delete column name | `deleted_at` (matches `add-soft-delete`) |
| Dry-run flag for first deploy? | yes — `app.purge.<entity>.dry-run=true` first run |

## `application.properties` additions

```properties
# Per-entity retention (operators can tune via env without code change)
app.purge.album.retention-days={{albumRetention}}
app.purge.album.batch-size=1000
app.purge.album.dry-run=false
app.purge.album.enabled=true

app.purge.user.retention-days={{userRetention}}
app.purge.user.batch-size=500
app.purge.user.dry-run=false
app.purge.user.enabled=true

# Tests: disable purge so test setup isn't surprised
%test.app.purge.album.enabled=false
%test.app.purge.user.enabled=false
```

> Always make the job **disabled in tests** by default — running a purge during integration tests will wipe seed data and break unrelated suites.

## Files to generate

### `scheduler/AlbumPurgeJob.java`

```java
package {{packageRoot}}.scheduler;

import {{packageRoot}}.repository.AlbumRepository;
import io.micrometer.core.instrument.MeterRegistry;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

import java.time.LocalDateTime;

@ApplicationScoped
public class AlbumPurgeJob {

    private static final Logger LOG = Logger.getLogger(AlbumPurgeJob.class);

    @Inject EntityManager em;
    @Inject MeterRegistry meterRegistry;

    @ConfigProperty(name = "app.purge.album.enabled")          boolean enabled;
    @ConfigProperty(name = "app.purge.album.retention-days")   int retentionDays;
    @ConfigProperty(name = "app.purge.album.batch-size")       int batchSize;
    @ConfigProperty(name = "app.purge.album.dry-run")          boolean dryRun;

    @Scheduled(cron = "{{cron}}", identity = "album-purge")
    @Transactional
    public void purge() {
        if (!enabled) {
            LOG.debug("Album purge disabled — skipping");
            return;
        }

        LocalDateTime cutoff = LocalDateTime.now().minusDays(retentionDays);

        if (dryRun) {
            long candidates = (long) em.createNativeQuery("""
                SELECT count(*) FROM albums
                 WHERE deleted_at IS NOT NULL AND deleted_at < ?1
            """).setParameter(1, cutoff).getSingleResult();
            LOG.infof("DRY-RUN: would purge %d album(s) older than %s", candidates, cutoff);
            meterRegistry.counter("purge.candidates", "entity", "album").increment(candidates);
            return;
        }

        // Native delete — Hibernate's JPQL UPDATE/DELETE can't use ORDER BY + LIMIT.
        // LIMIT prevents a single run from locking the table for too long.
        int affected = em.createNativeQuery("""
            DELETE FROM albums
             WHERE id IN (
                 SELECT id FROM albums
                  WHERE deleted_at IS NOT NULL AND deleted_at < ?1
                  ORDER BY deleted_at ASC
                  LIMIT ?2
             )
        """).setParameter(1, cutoff)
            .setParameter(2, batchSize)
            .executeUpdate();

        LOG.infof("Purged %d album(s) older than %s (cutoff %d days)",
                  affected, cutoff, retentionDays);
        meterRegistry.counter("purge.deleted", "entity", "album").increment(affected);
    }
}
```

> **Why `LIMIT` in the DELETE**: a stale environment may have millions of expired rows. Deleting them all in one transaction locks the table for minutes, breaks the API. `LIMIT batchSize` plus a daily run drains the backlog gradually.

> **`identity = "album-purge"`** lets you reference this specific job in Quarkus's `/q/dev/io.quarkus.scheduler/` UI for manual trigger.

### Manual trigger endpoint (optional, recommended)

Operators sometimes need to force a purge — e.g. after a bulk soft-delete:

```java
package {{packageRoot}}.resource;

import {{packageRoot}}.scheduler.AlbumPurgeJob;
import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;

@Path("/v1/admin/purge")
@RolesAllowed("ADMIN")
public class PurgeAdminResource {

    @Inject AlbumPurgeJob albumPurge;

    @POST @Path("/albums")
    public Response purgeAlbums() {
        albumPurge.purge();
        return Response.accepted().build();
    }
}
```

> Returns 202 Accepted because the job may delete in batches over multiple calls — completion isn't guaranteed in one invocation. Document this in the OpenAPI annotation.

## Cascading considerations

Hard-deleting a parent triggers FK cascade rules:

- `ON DELETE CASCADE` on child FK → children are deleted too. ✓ Usually what you want.
- `ON DELETE RESTRICT` → DELETE fails with a constraint violation. Either add CASCADE to children, or purge children **first** in a separate job.

Check each child table's FK before generating. If RESTRICT, generate child purges with a `@DependsOn`-style ordering note in the comment.

## Tests

```java
@QuarkusTest
@QuarkusTestResource(PostgresResource.class)
class AlbumPurgeJobTest {

    @Inject AlbumPurgeJob job;
    @Inject AlbumRepository repository;
    @Inject EntityManager em;

    @Test
    @Transactional
    void purgeRemovesRowsOlderThanRetention() {
        // Seed: 1 active, 1 recently deleted (within retention), 1 old deletion
        Long activeId  = persistAlbum(/* deletedAt = null */);
        Long recentId  = persistAlbum(/* deletedAt = now - 10 days */);
        Long expiredId = persistAlbum(/* deletedAt = now - 200 days */);

        // Set retention to 90 days for the test (use @TestProfile or direct field)
        job.purge();

        assertNotNull(em.find(Album.class, activeId));
        assertNotNull(em.find(Album.class, recentId));
        assertNull   (em.find(Album.class, expiredId));
    }

    @Test
    @Transactional
    void dryRunDoesNotDelete() {
        Long id = persistAlbum(/* deletedAt = now - 200 days */);
        // flip dry-run on via @TestProfile
        job.purge();
        assertNotNull(em.find(Album.class, id)); // still there
    }
}
```

> Use Hibernate's native query to set `deleted_at` directly — going through the API would invoke soft-delete logic and not let you set an arbitrary old timestamp.

## Alerts and observability

Generate suggested alerts for the user:

- **`purge.deleted{entity="album"}`** rate suddenly zero for > 48h → job stopped running (deployment broke `@Scheduled`?).
- **`purge.deleted` rate suddenly spiking** → upstream is soft-deleting a lot more than usual; investigate why.
- **`purge.candidates` (from dry-run)** > N for > 7 days → backlog is growing faster than retention period; increase `batchSize` or shorten `retentionDays`.

## Anti-patterns to refuse

- **Deleting everything in one shot** without `LIMIT`. Locks the table; breaks reads.
- **Purging without a soft-delete pattern in place**. You're hard-deleting things that haven't been "trashed" first — users can't recover.
- **Coupling purge to the API process** in a multi-replica deployment without Quarkus's clustered scheduler enabled. N replicas all run the job at the same minute → racing deletes, wasted work. Either use `quarkus-scheduler-quartz` with database persistence, or run the purge in a dedicated cron job container.
- **Logging the deleted IDs at INFO level**. For large batches this floods logs. Log counts, not contents.
- **Putting the cutoff calculation in SQL** as `NOW() - INTERVAL '90 days'`. Makes the test non-deterministic and the migration history misleading. Compute in Java and pass as a parameter.
- **No dry-run period before enabling.** The first time you run purge in a real env, you should see "would delete N" for at least one day before flipping to real deletes.

## Post-generation

- Run with `dry-run=true` on first deploy. Confirm the count is what you expect (likely matches the volume your soft-delete has accumulated).
- Watch `purge.deleted` for the first week to ensure the backlog drains.
- Document the retention in user-facing docs (`docs/data-retention.md` or similar) — compliance requires this.
