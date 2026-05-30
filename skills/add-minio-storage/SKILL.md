---
name: add-minio-storage
description: "Add MinIO (S3-compatible) object storage to a Quarkus project — wire the quarkus-minio extension, add bucket auto-creation on startup, an ImageService that issues 30-minute presigned URLs with size/type validation, a MinioHealthCheck for /q/health/ready, and a MinioTestResource for Testcontainers-based tests. Use whenever the user wants to upload files, store images, integrate object storage, or add S3-compatible blob storage to a Quarkus app."
---

# add-minio-storage

Wire up object storage with the same conventions used by this repo's `AlbumImage` feature: bucket auto-created on startup, presigned GET URLs (30-minute TTL) for client downloads, 50 MB upload cap, validated MIME types, health-checked.

## When to invoke

- "Add file upload"
- "Add MinIO / S3 storage"
- "Implement image upload for albums"
- Implicitly: when CRUD work involves a binary asset (image, document, video).

## Inputs to collect

| Input | Default |
|---|---|
| Bucket name | derive from artifactId (e.g. `acme-files`) |
| Presigned URL TTL (minutes) | `30` |
| Max upload size (bytes) | `52428800` (50 MB) |
| Allowed MIME types | `image/jpeg, image/png, image/webp` (override if non-image) |
| Asset entity name | depends on use case (e.g. `AlbumImage`, `Document`) |

## Workflow

1. Add dependency to `pom.xml`.
2. Append MinIO config to `application.properties`.
3. Add MinIO service to `docker-compose.yml`.
4. Add `.env.example` entries.
5. Write the Java files.
6. Add a Flyway migration for the asset metadata table.
7. Run `./mvnw test -Dtest=ImageServiceTest`.

## Dependency to add

```xml
<dependency>
    <groupId>io.quarkiverse.minio</groupId>
    <artifactId>quarkus-minio</artifactId>
    <version>3.8.6</version>
</dependency>

<!-- Test -->
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>minio</artifactId>
    <scope>test</scope>
</dependency>
```

## `application.properties` additions

```properties
# MinIO
quarkus.minio.host=${MINIO_URL:http://localhost:9000}
quarkus.minio.access-key=${MINIO_ACCESS_KEY:minioadmin}
quarkus.minio.secret-key=${MINIO_SECRET_KEY:minioadmin}
quarkus.minio.secure=${MINIO_SECURE:false}

app.minio.bucket=${MINIO_BUCKET:{{bucket}}}
app.minio.presigned-url.expiry={{ttlMinutes}}
app.minio.max-file-size={{maxBytes}}
```

## `docker-compose.yml` addition

```yaml
  minio:
    image: minio/minio:RELEASE.2025-09-07T16-13-09Z
    environment:
      MINIO_ROOT_USER: ${MINIO_ACCESS_KEY:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_SECRET_KEY:-minioadmin}
    ports: ["9000:9000", "9001:9001"]
    volumes: [minio_data:/data]
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 10s
      timeout: 5s
      retries: 5
```

And update the `app` service:

```yaml
    environment:
      # ... existing entries ...
      MINIO_URL: http://minio:9000
      MINIO_ACCESS_KEY: ${MINIO_ACCESS_KEY:-minioadmin}
      MINIO_SECRET_KEY: ${MINIO_SECRET_KEY:-minioadmin}
      MINIO_SECURE: "false"
      MINIO_BUCKET: ${MINIO_BUCKET:-{{bucket}}}
    depends_on:
      postgres: { condition: service_healthy }
      minio:    { condition: service_healthy }
```

Add `minio_data:` to the `volumes:` block.

## Files to generate

### `config/MinioStartup.java`

```java
package {{packageRoot}}.config;

import io.minio.BucketExistsArgs;
import io.minio.MakeBucketArgs;
import io.minio.MinioClient;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

@ApplicationScoped
public class MinioStartup {

    private static final Logger LOG = Logger.getLogger(MinioStartup.class);

    @Inject MinioClient minioClient;

    @ConfigProperty(name = "app.minio.bucket")
    String bucket;

    void onStart(@Observes StartupEvent event) {
        try {
            boolean exists = minioClient.bucketExists(BucketExistsArgs.builder().bucket(bucket).build());
            if (!exists) {
                LOG.infof("Creating MinIO bucket: %s", bucket);
                minioClient.makeBucket(MakeBucketArgs.builder().bucket(bucket).build());
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to initialize MinIO bucket: " + bucket, e);
        }
    }
}
```

### `health/MinioHealthCheck.java`

```java
package {{packageRoot}}.health;

import io.minio.BucketExistsArgs;
import io.minio.MinioClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Readiness;

@Readiness
@ApplicationScoped
public class MinioHealthCheck implements HealthCheck {

    @Inject MinioClient minioClient;

    @ConfigProperty(name = "app.minio.bucket")
    String bucket;

    @Override
    public HealthCheckResponse call() {
        try {
            minioClient.bucketExists(BucketExistsArgs.builder().bucket(bucket).build());
            return HealthCheckResponse.up("minio");
        } catch (Exception e) {
            return HealthCheckResponse.builder().name("minio").down().withData("error", e.getMessage()).build();
        }
    }
}
```

### `service/ImageService.java`

```java
package {{packageRoot}}.service;

import io.minio.*;
import io.minio.http.Method;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.NotFoundException;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.io.InputStream;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.Set;
import java.util.concurrent.TimeUnit;

@ApplicationScoped
public class ImageService {

    private static final Set<String> ALLOWED_TYPES = Set.of({{allowedMimes}});

    @Inject MinioClient minioClient;

    @ConfigProperty(name = "app.minio.bucket")        String bucket;
    @ConfigProperty(name = "app.minio.presigned-url.expiry") int expiryMinutes;
    @ConfigProperty(name = "app.minio.max-file-size") long maxFileSize;

    /** Returns the object key. */
    public String upload(InputStream data, long size, String contentType, String originalFilename) throws Exception {
        if (size <= 0 || size > maxFileSize) {
            throw new BadRequestException("File size out of range");
        }
        if (!ALLOWED_TYPES.contains(contentType)) {
            throw new BadRequestException("Unsupported content type: " + contentType);
        }

        String hash = sha256(originalFilename + System.nanoTime());
        String key = LocalDate.now() + "/" + hash + extensionFor(contentType);

        minioClient.putObject(PutObjectArgs.builder()
            .bucket(bucket).object(key)
            .stream(data, size, -1)
            .contentType(contentType)
            .build());

        return key;
    }

    public String presignedUrl(String key) {
        try {
            ensureExists(key);
            return minioClient.getPresignedObjectUrl(GetPresignedObjectUrlArgs.builder()
                .bucket(bucket).object(key)
                .method(Method.GET)
                .expiry(expiryMinutes, TimeUnit.MINUTES)
                .build());
        } catch (Exception e) {
            throw new RuntimeException("Failed to presign", e);
        }
    }

    public void delete(String key) {
        try {
            ensureExists(key);
            minioClient.removeObject(RemoveObjectArgs.builder().bucket(bucket).object(key).build());
        } catch (Exception e) {
            throw new RuntimeException("Failed to delete object", e);
        }
    }

    private void ensureExists(String key) throws Exception {
        try {
            minioClient.statObject(StatObjectArgs.builder().bucket(bucket).object(key).build());
        } catch (Exception e) {
            throw new NotFoundException("Object not found: " + key);
        }
    }

    private static String sha256(String input) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(input.getBytes());
            return HexFormat.of().formatHex(digest);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static String extensionFor(String mime) {
        return switch (mime) {
            case "image/jpeg" -> ".jpg";
            case "image/png"  -> ".png";
            case "image/webp" -> ".webp";
            default           -> "";
        };
    }
}
```

> The substitution `{{allowedMimes}}` becomes e.g. `"image/jpeg", "image/png", "image/webp"`.

### `test/.../common/MinioTestResource.java`

```java
package {{packageRoot}}.common;

import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import org.testcontainers.containers.MinIOContainer;

import java.util.Map;

public class MinioTestResource implements QuarkusTestResourceLifecycleManager {

    private final MinIOContainer minio =
        new MinIOContainer("minio/minio:RELEASE.2025-09-07T16-13-09Z")
            .withUserName("minioadmin")
            .withPassword("minioadmin");

    @Override
    public Map<String, String> start() {
        minio.start();
        return Map.of(
            "quarkus.minio.host", minio.getS3URL(),
            "quarkus.minio.access-key", "minioadmin",
            "quarkus.minio.secret-key", "minioadmin"
        );
    }

    @Override
    public void stop() {
        minio.stop();
    }
}
```

### Flyway migration — `V<n>__create_<asset>_table.sql`

For an `AlbumImage`-like asset:

```sql
CREATE TABLE {{asset}}s (
    id           BIGSERIAL    PRIMARY KEY,
    object_key   VARCHAR(255) NOT NULL UNIQUE,
    content_type VARCHAR(50)  NOT NULL,
    size_bytes   BIGINT       NOT NULL,
    uploaded_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_{{asset}}s_object_key ON {{asset}}s (object_key);
```

If the asset belongs to a parent entity, add a `parent_id BIGINT NOT NULL REFERENCES parents(id) ON DELETE CASCADE` column instead of (or alongside) the standalone PK.

## Anti-patterns to refuse

- Returning the MinIO URL directly to the client. Always use **presigned URLs** so the client doesn't see the bucket internals and the TTL gives security a kill switch.
- Storing the binary in PostgreSQL. The DB stores metadata + key only.
- Skipping `ALLOWED_TYPES`. Always validate MIME — never trust the client.
- Hardcoding the bucket name. Always `@ConfigProperty(name = "app.minio.bucket")`.

## Post-generation

- Confirm `MinioStartup` ran on first boot (check logs).
- Visit http://localhost:9001 (minioadmin / minioadmin) to inspect the bucket.
- Re-run health: `curl localhost:8080/q/health/ready` should show `minio: UP`.

---

## Strategic considerations & governance

## Goal

Add reliable media storage without coupling API responses to raw storage internals.

## Workflow

1. Define upload limits: allowed MIME types, extensions, maximum size, ownership, and replacement rules.
2. Configure MinIO through environment variables: `MINIO_URL`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, `MINIO_SECURE`, and `MINIO_BUCKET`.
3. Create a service that validates the multipart file before storage.
4. Generate stable object names using a collision-resistant strategy, such as a hash or UUID plus date partition.
5. Persist metadata in an entity when files belong to domain objects.
6. Return response DTOs with object metadata and presigned URLs when clients need direct access.
7. Add cleanup behavior for delete and replacement flows.

## Design Rules

- Do not trust client-provided filenames for object keys.
- Validate MIME type and file size before upload.
- Keep bucket creation/startup checks in config or startup components, not resource methods.
- Keep storage exceptions mapped to user-safe API errors.
- Avoid exposing MinIO credentials or internal object paths.

## Testing Checklist

- Unit tests cover validation and object key generation.
- Resource tests cover upload success, invalid type, oversized file, missing parent entity, and delete behavior.
- Integration tests use Testcontainers or a test MinIO resource when storage behavior matters.

## Example

For album covers, store metadata in `AlbumImage`, upload through `ImageResource`, write storage logic in `ImageService`, and return `ImageUploadResponse` or `ImageUrlResponse`.
