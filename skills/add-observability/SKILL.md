---
name: add-observability
description: "Wire production observability into a Quarkus project — Micrometer metrics with Prometheus scrape endpoint, OpenTelemetry distributed tracing (OTLP exporter), structured JSON console logs, and a JAX-RS filter that propagates an X-Request-Id correlation header through MDC and OpenTelemetry context. Use whenever the user asks for metrics, monitoring, tracing, structured logs, observability, \"instrument the API\", or wants to integrate with Prometheus/Grafana/Tempo/Jaeger."
---

# add-observability

Add the three pillars of observability — metrics, traces, logs — wired together by a correlation ID so a single request can be followed across stdout, traces, and metric labels.

## When to invoke

- "Add metrics / Prometheus"
- "Add tracing / OpenTelemetry"
- "Instrument the API"
- "Make logs structured"
- "Add request correlation ID"

## What this skill produces

- `GET /q/metrics` Prometheus scrape endpoint with JVM, HTTP, DB pool, and Hibernate stats.
- All outbound spans exported via OTLP to whatever collector the user runs (Tempo, Jaeger, Honeycomb, Datadog OTLP, …).
- Console logs in JSON with `traceId`, `spanId`, `requestId`, level, thread, and timestamp ready for Loki/ELK.
- An `X-Request-Id` header echoed on every response — propagated to MDC and to OTel baggage so downstream services see the same id.

## Inputs to collect

| Input | Default |
|---|---|
| OTLP collector endpoint | `http://localhost:4317` (gRPC) |
| Service name (in traces/metrics) | derive from `quarkus.application.name` |
| Enable in dev mode? | yes |

## Dependencies to add

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-micrometer-registry-prometheus</artifactId>
</dependency>
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-opentelemetry</artifactId>
</dependency>
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-logging-json</artifactId>
</dependency>
```

> Quarkus exposes `/q/metrics` automatically once `quarkus-micrometer-registry-prometheus` is on the classpath. No code wiring needed.

## `application.properties` additions

```properties
# Micrometer / Prometheus
quarkus.micrometer.export.prometheus.enabled=true
quarkus.micrometer.binder.http-server.enabled=true
quarkus.micrometer.binder.http-client.enabled=true
quarkus.micrometer.binder.jvm=true

# Hibernate metrics
quarkus.hibernate-orm.metrics.enabled=true
quarkus.datasource.metrics.enabled=true
quarkus.datasource.jdbc.enable-metrics=true

# OpenTelemetry
quarkus.otel.service.name=${quarkus.application.name}
quarkus.otel.exporter.otlp.endpoint=${OTEL_EXPORTER_OTLP_ENDPOINT:http://localhost:4317}
quarkus.otel.exporter.otlp.traces.protocol=grpc

# Disable OTel completely in tests so unit tests don't try to reach a collector
%test.quarkus.otel.sdk.disabled=true

# Structured logs in prod, plain text in dev for readability
%prod.quarkus.log.console.json=true
%dev.quarkus.log.console.json=false
quarkus.log.console.json.additional-field."service.name".value=${quarkus.application.name}
```

## Files to generate

### `security/RequestIdFilter.java`

```java
package {{packageRoot}}.security;

import io.opentelemetry.api.baggage.Baggage;
import io.opentelemetry.context.Scope;
import jakarta.annotation.Priority;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.ext.Provider;
import org.jboss.logging.MDC;

import java.util.UUID;

@Provider
@Priority(Priorities.AUTHENTICATION - 100)
public class RequestIdFilter implements ContainerRequestFilter, ContainerResponseFilter {

    public static final String HEADER = "X-Request-Id";
    public static final String MDC_KEY = "requestId";

    @Override
    public void filter(ContainerRequestContext ctx) {
        String id = ctx.getHeaderString(HEADER);
        if (id == null || id.isBlank()) {
            id = UUID.randomUUID().toString();
        }
        MDC.put(MDC_KEY, id);
        ctx.setProperty(MDC_KEY, id);
        // Make the id visible to OTel baggage so downstream calls carry it.
        Scope ignored = Baggage.current().toBuilder().put(MDC_KEY, id).build().makeCurrent();
    }

    @Override
    public void filter(ContainerRequestContext req, ContainerResponseContext resp) {
        Object id = req.getProperty(MDC_KEY);
        if (id != null) {
            resp.getHeaders().putSingle(HEADER, id);
        }
        MDC.remove(MDC_KEY);
    }
}
```

> Priority is `AUTHENTICATION - 100` so the request id is bound to MDC **before** any auth/rate-limit filter logs, and every subsequent log line in the request carries it.

### Optional — domain metrics example

If the user wants custom metrics, show how. For example, inside `AlbumService`:

```java
import io.micrometer.core.instrument.MeterRegistry;

@Inject MeterRegistry registry;

@Transactional
public AlbumResponse create(AlbumRequest request) {
    // ...
    registry.counter("albums.created", "type", album.getArtistType().name()).increment();
    return AlbumResponse.from(album);
}
```

> **Cardinality discipline**: never use unbounded values (user ids, free-text) as tag values. Stick to enums and small fixed sets.

## docker-compose additions (optional, for local development)

If the user develops locally and wants a complete stack, suggest adding to `docker-compose.yml`:

```yaml
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.118.0
    command: ["--config=/etc/otel/config.yaml"]
    volumes:
      - ./otel-config.yaml:/etc/otel/config.yaml
    ports: ["4317:4317"]

  prometheus:
    image: prom/prometheus:v3.1.0
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports: ["9090:9090"]

  grafana:
    image: grafana/grafana:11.4.0
    ports: ["3001:3000"]
    environment:
      GF_AUTH_ANONYMOUS_ENABLED: "true"
      GF_AUTH_ANONYMOUS_ORG_ROLE: Admin
```

> Only generate these if the user asked. Mention they need a `prometheus.yml` with `scrape_configs` pointing at `app:8080/q/metrics`, and an `otel-config.yaml` with a logging or `otlp` exporter.

## Anti-patterns to refuse

- **Logging request bodies at INFO**. PII / secrets leak. Sample carefully, redact, and use DEBUG.
- **High-cardinality tags** (user id, full URL with path params). Cardinality explosions kill Prometheus.
- **`@WithSpan` everywhere**. OTel already auto-instruments JAX-RS, REST Client, JDBC, Hibernate, Kafka, etc. Adding manual spans on plain methods is mostly noise.
- **Sampling at 100% in production**. Default to head-based sampling at 10% with parent-respecting policy, or use tail sampling at the collector.
- **Stripping the correlation id in tests**. Tests should still propagate it so reproductions are deterministic.

## Post-generation

- Tell the user the new endpoints: `/q/metrics` (Prometheus format).
- Show one curl that proves correlation id round-trips:
  ```bash
  curl -i -H "X-Request-Id: abc-123" http://localhost:8080/v1/albums
  # Response includes: X-Request-Id: abc-123
  ```
- Remind them to set `OTEL_EXPORTER_OTLP_ENDPOINT` for non-localhost collectors.
- If no collector is running locally, OTel will log warnings every export interval. Either run a collector or set `quarkus.otel.sdk.disabled=true` per-profile.

---

## Strategic considerations & governance

## Goal

Make production behavior diagnosable without exposing secrets or overwhelming logs.

## Workflow

1. Add or preserve a correlation ID for every request and include it in logs and error responses when practical.
2. Log request outcomes at useful boundaries: authentication, mutations, external calls, sync jobs, uploads, and unexpected errors.
3. Use structured fields where available: method, path, status, duration, user ID, role, correlation ID, external service, and entity ID.
4. Add metrics or counters for high-value operations and failure modes.
5. Keep health checks dependency-focused and troubleshooting docs current.

## Logging Rules

- Never log passwords, tokens, private keys, presigned URLs, or raw uploaded file contents.
- Use `INFO` for business-relevant lifecycle events, `WARN` for recoverable unusual conditions, and `ERROR` for failures requiring attention.
- Include enough context to debug, but not full request bodies by default.
- Keep noisy SQL/debug logs disabled in production.

## Testing Checklist

- Filters preserve or generate correlation IDs.
- Error responses can be matched to server logs.
- External call failures include service name and safe context.

## Example

For regional sync, log sync start, external API outcome, created/updated/skipped counts, failures, duration, and correlation ID.
