---
name: add-outbox-pattern
description: "Implement the transactional outbox pattern in a Quarkus + PostgreSQL project so domain events are published reliably (at-least-once) to Kafka/RabbitMQ/HTTP webhooks without dual-write inconsistency — generates an outbox_events table, an OutboxEventPublisher service that writes events inside the business transaction, a scheduled poller that publishes pending events with retry/backoff and marks them dispatched, idempotent consumer guidance, and DB constraints that make replay safe. Use whenever the user needs reliable event publishing, mentions Kafka/RabbitMQ/webhooks, \"publish event after save\", dual-write problem, eventually consistent messaging, or any cross-service notification."
---

# add-outbox-pattern

Implement the **transactional outbox pattern**: domain events are written to an `outbox_events` table inside the same DB transaction as the business write. A separate poller publishes the events to the destination (Kafka, AMQP, webhook) and marks them dispatched. Guarantees **at-least-once** delivery without distributed transactions.

This is the canonical fix for the "dual-write problem" — calling `kafka.send()` after `db.commit()` can fail in between, leaving the DB inconsistent with the outside world.

## When to invoke

- "Publish event after creating an order"
- "Reliable event publishing to Kafka"
- "Outbound webhooks with retry"
- "We have inconsistency between our DB and downstream services"

## When NOT to invoke

- Single-service app with no external event consumers — there's no event to publish.
- Hard sync/RPC integration (gRPC, HTTP call returning meaningful data) — that's a different pattern (saga, two-phase).
- Use case requires **exactly-once** semantics — outbox guarantees at-least-once; consumers must deduplicate.

## Inputs to collect

| Input | Default |
|---|---|
| Destination | Kafka (default), AMQP, HTTP webhook |
| Event types to publish | required — list each domain event with its routing key/topic |
| Poll interval | `5 seconds` |
| Batch size per poll | `100 events` |
| Max delivery attempts before parking | `10` |
| Backoff | exponential: 1s, 2s, 4s, ... 5 minutes max |

## Files to generate

### Flyway migration — `V<n>__create_outbox_events.sql`

```sql
CREATE TABLE outbox_events (
    id              BIGSERIAL    PRIMARY KEY,
    event_id        UUID         NOT NULL UNIQUE,           -- consumer dedup key
    aggregate_type  VARCHAR(64)  NOT NULL,                  -- e.g. "Album", "Order"
    aggregate_id    VARCHAR(64)  NOT NULL,                  -- e.g. "42"
    event_type      VARCHAR(128) NOT NULL,                  -- e.g. "AlbumCreated"
    routing_key     VARCHAR(256) NOT NULL,                  -- topic / queue / URL
    payload         JSONB        NOT NULL,
    headers         JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    available_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),    -- for exponential backoff
    delivery_attempts INT        NOT NULL DEFAULT 0,
    dispatched_at   TIMESTAMPTZ,                            -- NULL = pending, set = done
    last_error      TEXT,
    parked          BOOLEAN      NOT NULL DEFAULT FALSE     -- after max attempts
);

-- Poller index: pending, ready-to-send events ordered by created_at
CREATE INDEX idx_outbox_pending ON outbox_events (available_at, id)
    WHERE dispatched_at IS NULL AND parked = FALSE;

-- Dedup / lookup
CREATE INDEX idx_outbox_aggregate ON outbox_events (aggregate_type, aggregate_id);
```

> **Partial index** `WHERE dispatched_at IS NULL AND parked = FALSE` is critical — without it, the poller scans the entire table once it grows. With it, the index size stays tiny because dispatched rows are excluded.

> **`event_id UUID UNIQUE`** is the consumer-side dedup key. The poller emits this on every publish (Kafka header, AMQP property, webhook header `X-Event-Id`). Consumers store it to detect replays.

### Entity — `entity/OutboxEvent.java`

```java
package {{packageRoot}}.entity;

import com.fasterxml.jackson.databind.JsonNode;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "outbox_events")
public class OutboxEvent extends PanacheEntityBase {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "event_id",       nullable = false, unique = true) private UUID eventId;
    @Column(name = "aggregate_type", nullable = false, length = 64)   private String aggregateType;
    @Column(name = "aggregate_id",   nullable = false, length = 64)   private String aggregateId;
    @Column(name = "event_type",     nullable = false, length = 128)  private String eventType;
    @Column(name = "routing_key",    nullable = false, length = 256)  private String routingKey;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(nullable = false, columnDefinition = "jsonb")
    private JsonNode payload;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(nullable = false, columnDefinition = "jsonb")
    private JsonNode headers;

    @Column(name = "created_at",        nullable = false) private OffsetDateTime createdAt;
    @Column(name = "available_at",      nullable = false) private OffsetDateTime availableAt;
    @Column(name = "delivery_attempts", nullable = false) private int deliveryAttempts;
    @Column(name = "dispatched_at")                       private OffsetDateTime dispatchedAt;
    @Column(name = "last_error", columnDefinition = "text") private String lastError;
    @Column(nullable = false) private boolean parked;

    // Getters / setters omitted for brevity ...
}
```

### Publisher — `service/OutboxEventPublisher.java`

The **only** thing services call. It writes to the outbox in the **current** transaction.

```java
package {{packageRoot}}.service;

import {{packageRoot}}.entity.OutboxEvent;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

/**
 * Records an outbound event in the same transaction as the business write.
 *
 * <p><b>Critical contract:</b> Call this method <em>only</em> inside a {@code @Transactional}
 * service method. The event is persisted atomically with the business state — if the transaction
 * rolls back, the event is never published. The poller does the actual publishing later.
 */
@ApplicationScoped
public class OutboxEventPublisher {

    @Inject EntityManager em;
    @Inject ObjectMapper mapper;

    /** Record an event for later publishing. NOT @Transactional — must run inside caller's tx. */
    public void publish(String aggregateType, String aggregateId,
                         String eventType, String routingKey,
                         Object payload) {
        publish(aggregateType, aggregateId, eventType, routingKey, payload, Map.of());
    }

    public void publish(String aggregateType, String aggregateId,
                         String eventType, String routingKey,
                         Object payload, Map<String, String> headers) {
        OutboxEvent e = new OutboxEvent();
        e.setEventId(UUID.randomUUID());
        e.setAggregateType(aggregateType);
        e.setAggregateId(aggregateId);
        e.setEventType(eventType);
        e.setRoutingKey(routingKey);
        e.setPayload((JsonNode) mapper.valueToTree(payload));
        e.setHeaders((JsonNode) mapper.valueToTree(headers));
        e.setCreatedAt(OffsetDateTime.now());
        e.setAvailableAt(OffsetDateTime.now());

        em.persist(e);
    }
}
```

### How services use it

```java
@ApplicationScoped
public class AlbumService {

    @Inject AlbumRepository       albumRepository;
    @Inject OutboxEventPublisher  outbox;

    @Transactional
    public AlbumResponse create(AlbumRequest req) {
        Album album = new Album(req.title(), req.year());
        albumRepository.persist(album);

        // The event row is persisted in THIS transaction. Atomic with the album.
        outbox.publish(
            "Album",
            album.getId().toString(),
            "AlbumCreated",
            "albums.events.created",   // Kafka topic or AMQP routing key
            AlbumResponse.from(album)
        );

        return AlbumResponse.from(album);
    }
}
```

> The pattern is simple precisely because the magic is elsewhere: the poller publishes; the service just records intent.

### Poller — `scheduler/OutboxPollerJob.java`

```java
package {{packageRoot}}.scheduler;

import {{packageRoot}}.entity.OutboxEvent;
import io.micrometer.core.instrument.MeterRegistry;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;

@ApplicationScoped
public class OutboxPollerJob {

    private static final Logger LOG = Logger.getLogger(OutboxPollerJob.class);

    @Inject EntityManager em;
    @Inject OutboxTransport transport;     // Kafka, AMQP, or HTTP — see below
    @Inject MeterRegistry registry;

    @ConfigProperty(name = "app.outbox.batch-size",   defaultValue = "100") int batchSize;
    @ConfigProperty(name = "app.outbox.max-attempts", defaultValue = "10")  int maxAttempts;

    @Scheduled(every = "{{pollInterval}}s", identity = "outbox-poller", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    public void poll() {
        List<OutboxEvent> batch = fetchPending();
        for (OutboxEvent event : batch) {
            tryDeliver(event);
        }
    }

    /**
     * SELECT ... FOR UPDATE SKIP LOCKED → safe with multiple replicas.
     * Each replica grabs a different batch; no double-send.
     */
    @Transactional
    public List<OutboxEvent> fetchPending() {
        return em.createQuery("""
                FROM OutboxEvent
                WHERE dispatchedAt IS NULL
                  AND parked = false
                  AND availableAt <= :now
                ORDER BY id ASC
                """, OutboxEvent.class)
            .setParameter("now", OffsetDateTime.now())
            .setMaxResults(batchSize)
            .setLockMode(jakarta.persistence.LockModeType.PESSIMISTIC_WRITE)
            .setHint("jakarta.persistence.lock.timeout", -2)  // SKIP LOCKED on PG
            .getResultList();
    }

    @Transactional
    public void tryDeliver(OutboxEvent event) {
        try {
            transport.send(event);
            event.setDispatchedAt(OffsetDateTime.now());
            event.setLastError(null);
            registry.counter("outbox.dispatched", "type", event.getEventType()).increment();
        } catch (Exception e) {
            event.setDeliveryAttempts(event.getDeliveryAttempts() + 1);
            event.setLastError(truncate(e.toString(), 1000));
            if (event.getDeliveryAttempts() >= maxAttempts) {
                event.setParked(true);
                registry.counter("outbox.parked", "type", event.getEventType()).increment();
                LOG.errorf("Outbox event parked after %d attempts: %s", maxAttempts, event.getEventId());
            } else {
                // Exponential backoff: 1s, 2s, 4s, ..., max 5 minutes
                long delaySec = Math.min(300L, (long) Math.pow(2, event.getDeliveryAttempts()));
                event.setAvailableAt(OffsetDateTime.now().plus(Duration.ofSeconds(delaySec)));
                registry.counter("outbox.retried", "type", event.getEventType()).increment();
            }
        }
        em.merge(event);
    }

    private static String truncate(String s, int n) { return s.length() <= n ? s : s.substring(0, n); }
}
```

> **`SKIP LOCKED`**: critical for multi-instance deployments. Without it, every replica fetches the same batch and the first to commit wins; the rest waste cycles. `setHint("jakarta.persistence.lock.timeout", -2)` is the JPA hint that maps to `FOR UPDATE SKIP LOCKED` on PostgreSQL.

> **`concurrentExecution = SKIP`**: if a poll run takes longer than the interval, the next scheduled run skips rather than piling up.

### Transport interface — `service/OutboxTransport.java`

```java
package {{packageRoot}}.service;

import {{packageRoot}}.entity.OutboxEvent;

public interface OutboxTransport {
    /** Deliver the event. Throw on any failure — the poller handles retry. */
    void send(OutboxEvent event) throws Exception;
}
```

Implementations — generate the one the user picks:

#### Kafka — `service/KafkaOutboxTransport.java`

```java
package {{packageRoot}}.service;

import io.smallrye.reactive.messaging.kafka.api.OutgoingKafkaRecordMetadata;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;
import org.eclipse.microprofile.reactive.messaging.Message;
import org.apache.kafka.common.header.internals.RecordHeader;
import org.apache.kafka.common.header.internals.RecordHeaders;

@ApplicationScoped
public class KafkaOutboxTransport implements OutboxTransport {

    @Inject @Channel("outbox-events") Emitter<String> emitter;

    @Override
    public void send({{packageRoot}}.entity.OutboxEvent event) throws Exception {
        var headers = new RecordHeaders();
        headers.add(new RecordHeader("event-id",   event.getEventId().toString().getBytes()));
        headers.add(new RecordHeader("event-type", event.getEventType().getBytes()));

        emitter.send(Message.of(event.getPayload().toString())
            .addMetadata(OutgoingKafkaRecordMetadata.builder()
                .withTopic(event.getRoutingKey())
                .withKey(event.getAggregateId())
                .withHeaders(headers)
                .build()))
            .toCompletableFuture().get();   // synchronous: throw on failure
    }
}
```

Requires `quarkus-messaging-kafka` and config:

```properties
mp.messaging.outgoing.outbox-events.connector=smallrye-kafka
mp.messaging.outgoing.outbox-events.value.serializer=org.apache.kafka.common.serialization.StringSerializer
```

#### HTTP webhook — `service/WebhookOutboxTransport.java`

```java
package {{packageRoot}}.service;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.client.Client;
import jakarta.ws.rs.client.ClientBuilder;
import jakarta.ws.rs.client.Entity;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.util.HexFormat;
import java.util.concurrent.TimeUnit;

@ApplicationScoped
public class WebhookOutboxTransport implements OutboxTransport {

    private final Client client = ClientBuilder.newBuilder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build();

    @Override
    public void send({{packageRoot}}.entity.OutboxEvent event) throws Exception {
        String body = event.getPayload().toString();
        String signature = sign(body, "{{webhookSecret}}");

        try (Response resp = client.target(event.getRoutingKey())
            .request(MediaType.APPLICATION_JSON)
            .header("X-Event-Id",  event.getEventId().toString())
            .header("X-Event-Type", event.getEventType())
            .header("X-Signature", signature)
            .post(Entity.json(body))) {

            if (resp.getStatus() >= 200 && resp.getStatus() < 300) return;
            throw new RuntimeException("HTTP " + resp.getStatus() + " from " + event.getRoutingKey());
        }
    }

    private static String sign(String body, String secret) throws Exception {
        Mac hmac = Mac.getInstance("HmacSHA256");
        hmac.init(new SecretKeySpec(secret.getBytes(), "HmacSHA256"));
        return "sha256=" + HexFormat.of().formatHex(hmac.doFinal(body.getBytes()));
    }
}
```

> HMAC signing is essential for webhooks — consumers verify the signature to know the call came from us, not an attacker who learned the URL.

### `application.properties`

```properties
app.outbox.batch-size=100
app.outbox.max-attempts=10
app.outbox.poll-interval-seconds={{pollInterval}}

# Tests: disable poller so test data doesn't trigger real sends
%test.quarkus.scheduler.enabled=false
```

## Operational: monitor parked events

Parked events (= max attempts exceeded) are silent failures **unless** alerted on. Generate a metric and a recommendation:

```promql
# Alert: any parked events in the last hour
increase(outbox_parked_total[1h]) > 0
```

Operators must triage parked events — either fix the consumer and bulk-retry (`UPDATE outbox_events SET parked = false, delivery_attempts = 0, available_at = NOW() WHERE id = X`) or accept the loss and document it.

## Tests

```java
@QuarkusTest
@QuarkusTestResource(PostgresResource.class)
class OutboxTest {

    @Inject AlbumService service;
    @Inject EntityManager em;

    @Test
    @TestTransaction
    void createAlbum_recordsOutboxEvent() {
        service.create(new AlbumRequest("X", 2024, List.of()));

        Long count = em.createQuery(
            "SELECT count(o) FROM OutboxEvent o WHERE o.eventType = 'AlbumCreated'", Long.class)
            .getSingleResult();
        assertEquals(1, count);
    }

    @Test
    @TestTransaction
    void rollback_doesNotRecordOutboxEvent() {
        // Force the transaction to roll back AFTER outbox publish
        assertThrows(RuntimeException.class, () -> service.createAndFail());
        Long count = em.createQuery("SELECT count(o) FROM OutboxEvent o", Long.class).getSingleResult();
        assertEquals(0, count);
    }
}
```

The second test is the **canonical proof** that the pattern works: if business state rolls back, the event isn't dispatched.

## Consumer guidance (out of scope but mention)

Tell the user: **consumers must be idempotent**. The outbox guarantees at-least-once, never exactly-once. Consumer-side:

- Store the `event-id` (UUID) of every processed event.
- On receive, check if `event-id` was already processed; if yes, ack and skip.
- TTL the dedup store at least 2x the producer's max-delay window.

## Anti-patterns to refuse

- **Publishing inside the same DB transaction without an outbox table.** Some Kafka transactional producers seem to work… until they don't. The transactional outbox is the most robust pattern.
- **Skipping `SKIP LOCKED`** in the poller. With multiple replicas, you get double-sends.
- **Auto-purging dispatched events too aggressively.** Keep them for at least 7 days for audit / replay. Use a separate purge job (analogous to `add-purge-job`).
- **Polling every 100ms.** PostgreSQL becomes the bottleneck; the partial index isn't enough. 1-5 second poll interval is fine — events buffer briefly, no consumer cares.
- **One outbox table per aggregate.** Resist. One table with `aggregate_type` discriminator is enough for typical scale (millions of events/day). Sharding comes later if ever.
- **Returning HTTP success from the producer endpoint before the event is in the outbox.** The whole point is atomicity — if the outbox insert fails, the response should fail too.

## Post-generation

- Verify in the running app: create an album, then `SELECT * FROM outbox_events ORDER BY id DESC LIMIT 1` shows the event with `dispatched_at` populated within ~5 seconds.
- Add metrics dashboards: `outbox_dispatched_total` and `outbox_parked_total`.
- Document consumer dedup requirements in API docs or a `docs/events.md` file.
