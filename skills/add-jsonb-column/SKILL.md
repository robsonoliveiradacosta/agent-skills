---
name: add-jsonb-column
description: "Add a PostgreSQL JSONB column to a JPA entity in a Quarkus + Hibernate project — Flyway migration with JSONB column and GIN index, Hibernate 6.4+ @JdbcTypeCode(SqlTypes.JSON) mapping to a typed POJO/record (no string nu), repository finder methods using JSONB operators (->>, @>) with proper parameter binding, and a sample request DTO with @Valid nested validation. Use whenever the user mentions JSONB, JSON column, flexible attributes, metadata bag, semi-structured fields, \"store dynamic settings\", or wants to query keys inside a JSON payload."
---

# add-jsonb-column

Add a typed JSONB column to a JPA entity — properly indexed for key lookups, mapped to a Java record (not a String), and queryable via Panache.

## When to invoke

- "Add a JSONB / JSON column"
- "Store flexible metadata"
- "Query inside a JSON payload"

## Why typed mapping matters

The default Hibernate JSON mapping returns `Object` or `String`. Both are foot-guns:

- `String` requires Jackson plumbing in every service method.
- `Object` (`Map<String, Object>`) loses type safety; you typo `"isPublik"` and it compiles.

Hibernate 6.4+'s `@JdbcTypeCode(SqlTypes.JSON)` deserializes directly into a record/POJO, with Jackson under the hood. **Always** use the typed form.

## Inputs to collect

| Input | Default |
|---|---|
| Entity to extend | required, e.g. `Album` |
| New column name | snake_case of the field name |
| Shape of the JSON value | required — Java record or class with known fields (can have optional fields) |
| Query patterns needed | list — e.g. "by `metadata.featured = true`", "where `tags` contains `X`" |
| Index strategy | `GIN` for key/value queries (default), `BTREE on (col->>'key')` for single-key sort, none for write-mostly |

## Files to generate

### Flyway migration — `V<n>__add_metadata_to_albums.sql`

```sql
ALTER TABLE albums ADD COLUMN metadata JSONB;

-- Default value AFTER add (avoids rewriting all existing rows during ADD COLUMN with default)
UPDATE albums SET metadata = '{}'::jsonb WHERE metadata IS NULL;
ALTER TABLE albums ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;
ALTER TABLE albums ALTER COLUMN metadata SET NOT NULL;

-- GIN index: fast for ?, @>, ?| operators (key existence, contains)
CREATE INDEX idx_albums_metadata ON albums USING GIN (metadata jsonb_path_ops);
```

> **`jsonb_path_ops`** vs default `jsonb_ops`: `jsonb_path_ops` is **smaller and faster** for the `@>` (contains) operator — the most common query pattern. Use it unless you also need `?` (key exists) on the same index, in which case use `jsonb_ops`.

### Value type — `entity/AlbumMetadata.java`

```java
package {{packageRoot}}.entity;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.util.List;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record AlbumMetadata(
    Boolean featured,
    String  isrc,
    List<String> tags,
    Stats stats
) {
    public record Stats(Long playCount, Long likeCount) {}

    public static AlbumMetadata empty() {
        return new AlbumMetadata(null, null, List.of(), null);
    }
}
```

> `@JsonInclude(NON_NULL)` keeps the stored JSON small — absent fields don't get a `null` entry.

### Entity change

```java
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "albums")
public class Album extends AuditableEntity {

    // ... existing fields ...

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(nullable = false, columnDefinition = "jsonb")
    private AlbumMetadata metadata = AlbumMetadata.empty();

    public AlbumMetadata getMetadata() { return metadata; }
    public void setMetadata(AlbumMetadata metadata) {
        this.metadata = metadata == null ? AlbumMetadata.empty() : metadata;
    }
}
```

> The defensive setter prevents `null` from sneaking past the `NOT NULL` constraint. The DB default also catches it on direct SQL writes.

### Repository — JSONB queries

```java
import io.quarkus.panache.common.Page;

@ApplicationScoped
public class AlbumRepository implements PanacheRepositoryBase<Album, Long> {

    /** Find all albums marked "featured":true in the metadata JSON. */
    public List<Album> findFeatured(Page page) {
        return find("metadata @> ?1::jsonb",
                    "{\"featured\":true}")
               .page(page).list();
    }

    /** Find albums whose tags array contains a given tag. */
    public List<Album> findByTag(String tag, Page page) {
        // Uses the JSONB `@>` containment operator; index can support this.
        String pattern = "{\"tags\":[\"" + tag.replace("\"", "\\\"") + "\"]}";
        return find("metadata @> ?1::jsonb", pattern).page(page).list();
    }

    /** Sort by a JSONB-derived field (uses BTREE expression index for speed). */
    public List<Album> findOrderedByPlayCount(Page page) {
        return find("FROM Album a ORDER BY (a.metadata->'stats'->>'playCount')::bigint DESC NULLS LAST")
               .page(page).list();
    }
}
```

> **Critical**: every dynamic value is bound as `?1` — never string-concatenated. For the tag finder, the tag value is embedded in a JSON template, so escape any quote. For untrusted input, validate against an allowlist or use parameter binding with `jsonb_build_object`.

### When the JSON shape is truly dynamic

Sometimes the user really does want "arbitrary JSON". In that case use `JsonNode`:

```java
import com.fasterxml.jackson.databind.JsonNode;

@JdbcTypeCode(SqlTypes.JSON)
@Column(nullable = false, columnDefinition = "jsonb")
private JsonNode metadata;
```

Push back though — most "dynamic" cases turn out to have 3-5 known fields plus an optional extension bag. Define the known fields as a record with an extra `Map<String, JsonNode> extensions` for the bag.

### Request DTO with nested validation

```java
public record AlbumRequest(
    @NotBlank @Size(max = 200) String title,
    @NotNull @Min(1900) Integer year,
    @Valid AlbumMetadata metadata
) {}
```

`@Valid` on the nested record activates Hibernate Validator constraints inside `AlbumMetadata` (add `@NotNull`/`@Size` to its fields if needed). Without `@Valid`, nested validations are silently skipped.

### Resource

No change beyond using the new request DTO — the existing `@Valid AlbumRequest` is enough.

## Tests

```java
@Test
@QuarkusTestResource(PostgresResource.class)
void findFeatured_returnsOnlyFeaturedAlbums() {
    given().auth().oauth2(TestTokenHelper.adminToken())
        .contentType("application/json")
        .body("""
            {
              "title":"A", "year":2024,
              "metadata":{"featured":true,"tags":["rock"]}
            }
        """)
    .when().post("/v1/albums").then().statusCode(201);

    given().auth().oauth2(TestTokenHelper.adminToken())
        .contentType("application/json")
        .body("""
            {
              "title":"B", "year":2024,
              "metadata":{"featured":false,"tags":["jazz"]}
            }
        """)
    .when().post("/v1/albums").then().statusCode(201);

    given().auth().oauth2(TestTokenHelper.userToken())
        .queryParam("featured", true)
    .when().get("/v1/albums")
    .then().body("content.size()", equalTo(1))
           .body("content[0].title", equalTo("A"));
}
```

## Performance notes

- **GIN index size**: GIN on JSONB is roughly 30-50% the size of the JSONB column data. Plan disk accordingly.
- **`->>'key'`** returns text; `->'key'` returns JSONB. For sorting/comparing numeric keys: `(col->>'key')::bigint`. Index expressions: `CREATE INDEX ON albums ((metadata->>'isrc'));`.
- **Don't store huge blobs** in JSONB. Files (>~1 MB) belong in object storage (`add-minio-storage`); the JSONB column should hold *metadata about* the file, not the file itself.
- **Avoid `SELECT *` on tables with multi-MB JSONB columns** — every list query pulls the full payload. Use a projection or split into a separate table.

## Anti-patterns to refuse

- **Mapping JSONB to `String`** and doing `objectMapper.readValue(...)` in every service method. The Hibernate type registry exists for this; use it.
- **Storing structured relational data in JSONB** because "it's flexible". Foreign keys, JOINs, and constraints all break. JSONB is for genuinely semi-structured data, not lazy schema design.
- **No index on a frequently-queried JSONB column.** A sequential scan over JSONB is brutal at scale.
- **Skipping `@Valid`** on the nested DTO. Validation annotations on `AlbumMetadata` fields are silently ignored.
- **Mutating the returned `JsonNode`** in service code. The instance is shared with Hibernate's session; mutations bypass dirty checking. Create a copy if you must change it.

## Post-generation

- Run the migration; verify `metadata` defaults to `{}` on existing rows.
- Add a `?featured=true` query param example to OpenAPI docs.
- Tell the user to monitor index size with `pg_size_pretty(pg_relation_size('idx_albums_metadata'))` — JSONB indexes can grow surprisingly.
