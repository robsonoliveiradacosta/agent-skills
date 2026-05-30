---
name: add-test-data-builders
description: "Generate fluent test data builder classes for JPA entities in a Quarkus project — one Builder per entity in src/test/java/.../testdata/, sensible default values for every field, fluent withX() methods that return the builder, build() returning a populated entity, and a persisted() variant that calls repository.persist within a @Transactional context. Use whenever the user complains about duplicate entity construction in tests, wants \"test factories\", asks for an Object Mother / Builder pattern, or whenever tests have visible setup duplication."
---

# add-test-data-builders

Generate a `<Entity>TestBuilder` per JPA entity so tests construct objects fluently with overridable defaults. Reduces the typical "20 lines of setup before each test" to a single readable line.

## When to invoke

- "Tests have too much boilerplate"
- "Add test factories"
- "Object Mother / Test Data Builder"
- Implicitly: after a few `add-crud-resource` calls when test setup starts repeating.

## Pattern motivation

Without a builder, tests do this:

```java
Album a = new Album();
a.setTitle("Some title");
a.setYear(1969);
a.setArtists(Set.of(artistRepository.findById(1L)));
albumRepository.persist(a);
```

…repeated, slightly different, 50 times across the suite. With a builder:

```java
Album a = anAlbum().withTitle("Some title").persisted();
```

Every other field gets a sensible default. When `Album` gains a new required column, only the builder changes — not 50 tests.

## Inputs to collect

| Input | Default |
|---|---|
| Entities to generate builders for | required; can be "all entities" |
| Default value strategy | randomized realistic values (random ULID for unique fields, `Faker`-style names) vs deterministic (`"name-" + counter`) |
| Generate `persisted()` helper? | yes — requires `@QuarkusTest` + `@Transactional` context |

> Default for unique constraints: **use a counter**. Random values cause flaky tests when the random seed accidentally collides.

## Directory layout

```
src/test/java/{{packagePath}}/
└── testdata/
    ├── TestData.java          # static factory entry points: anAlbum(), anArtist(), …
    ├── AlbumTestBuilder.java
    ├── ArtistTestBuilder.java
    └── ...
```

## Files to generate

### `testdata/TestData.java` — entry points

```java
package {{packageRoot}}.testdata;

import java.util.concurrent.atomic.AtomicLong;

/** Static factory entrypoints. Import statically: `import static …testdata.TestData.*;` */
public final class TestData {

    private TestData() {}

    /** Monotonic counter so unique fields don't collide between tests. */
    static final AtomicLong SEQ = new AtomicLong(System.currentTimeMillis() % 100_000);

    public static AlbumTestBuilder  anAlbum()  { return new AlbumTestBuilder();  }
    public static ArtistTestBuilder anArtist() { return new ArtistTestBuilder(); }
    // ...
}
```

### `testdata/AlbumTestBuilder.java`

```java
package {{packageRoot}}.testdata;

import {{packageRoot}}.entity.Album;
import {{packageRoot}}.entity.Artist;
import io.quarkus.arc.Arc;
import {{packageRoot}}.repository.AlbumRepository;
import jakarta.transaction.Transactional;

import java.util.HashSet;
import java.util.Set;

public final class AlbumTestBuilder {

    private String  title;
    private Integer year;
    private Set<Artist> artists = new HashSet<>();

    AlbumTestBuilder() {
        // Defaults — overridable
        long n = TestData.SEQ.incrementAndGet();
        this.title = "Album " + n;
        this.year  = 2000 + (int)(n % 25);
    }

    public AlbumTestBuilder withTitle(String t)             { this.title = t; return this; }
    public AlbumTestBuilder withYear(int y)                 { this.year = y;  return this; }
    public AlbumTestBuilder withArtist(Artist a)            { this.artists.add(a); return this; }
    public AlbumTestBuilder withArtists(Set<Artist> arts)   { this.artists = new HashSet<>(arts); return this; }

    /** Builds an in-memory entity. Useful for unit tests with mocked repositories. */
    public Album build() {
        Album a = new Album(title, year);
        if (!artists.isEmpty()) a.setArtists(artists);
        return a;
    }

    /** Builds AND persists. Requires a CDI context (i.e. @QuarkusTest). */
    @Transactional
    public Album persisted() {
        Album a = build();
        Arc.container().instance(AlbumRepository.class).get().persist(a);
        return a;
    }
}
```

> **Critical**: `persisted()` uses `Arc.container().instance(...)` because test builders aren't CDI beans. This pattern matches how the project already wires the `AuditListener` (see `add-audit-trail` skill).

### Usage example (in a test)

```java
import static {{packageRoot}}.testdata.TestData.*;

@QuarkusTest
@QuarkusTestResource(PostgresResource.class)
class AlbumServiceTest {

    @Inject AlbumService service;

    @Test
    void findById_returnsAlbum() {
        Artist beatles = anArtist().withName("The Beatles").persisted();
        Album abbey   = anAlbum()
            .withTitle("Abbey Road")
            .withYear(1969)
            .withArtist(beatles)
            .persisted();

        assertEquals("Abbey Road", service.findById(abbey.getId()).title());
    }

    @Test
    void create_persistsWithDefaults() {
        // Defaults are good enough — no setup noise
        Album a = anAlbum().build();
        assertNotNull(a.getTitle());
        assertNotNull(a.getYear());
    }
}
```

### Handling relationships

Two strategies — pick **per relationship** based on cardinality:

1. **Required parent**: builder requires the parent in the constructor or fluent method, no default.
   ```java
   public OrderItemTestBuilder forOrder(Order o) { this.order = o; return this; }
   ```
2. **Optional / discoverable parent**: builder creates one if not provided.
   ```java
   public Album build() {
       if (artists.isEmpty()) artists.add(anArtist().build()); // implicit default
       // ...
   }
   ```

Avoid auto-creating **persisted** dependencies inside `persisted()` — that hides setup cost and creates cascading orphans. The implicit-default pattern is fine for in-memory `build()` only.

### Validation-aware defaults

If `AlbumRequest` has `@NotBlank @Size(min = 1, max = 100) String title`, the default must satisfy it. Generate defaults that **pass** existing validation — otherwise every test fails until overridden.

## Anti-patterns to refuse

- **Random data without a seed for unique fields.** Causes flaky test failures on accidental collisions. Use the `SEQ` counter for any `UNIQUE` column.
- **Builders that lazy-load Spring/Quarkus beans in static initializers.** Static + container lifecycle = nondeterministic ordering errors.
- **`buildAndAssert(...)`** style that bundles assertion into the builder. Builders construct; tests assert.
- **Per-test builders that inherit from a shared base** to "reuse defaults". The point of a builder is **explicit overrides** — inheritance hides them.
- **Builders living in `src/main/java`.** They're test-only. Always `src/test/java/.../testdata/`.
- **Auto-persisting recursive parent chains** inside `persisted()`. Three calls deep and you've populated the entire schema; debugging which test created which row becomes impossible.

## Migration from existing tests

After generating the builders, optionally suggest:

```bash
# Find tests that hand-construct entities — candidates for migration
grep -rn "new Album(\|new Artist(" src/test/java/
```

Don't auto-rewrite — let the developer migrate test-by-test so each migration goes through code review.

## Post-generation

- Run `./mvnw test -Dtest='*ServiceTest'` to confirm builders don't break the existing suite.
- Add a brief note to `CLAUDE.md`: "Use `TestData.anX()` for new tests; don't hand-construct entities."
- Suggest the team agree on one default strategy (counter-based recommended) so future builders don't drift.

---

## Strategic considerations & governance

## Goal

Provide repeatable local and test data without making tests depend on hidden global state.

## Workflow

1. Separate production-required seed data from demo or test-only fixtures.
2. Put required seed data in Flyway migrations only when the application needs it to run.
3. Keep test fixtures close to tests through helpers, builders, or test resources.
4. Use stable identifiers only when tests or docs depend on them.
5. Hash default passwords and document local-only credentials clearly.
6. Ensure tests clean up or isolate data between runs.

## Rules

- Do not put sensitive real data in migrations or fixtures.
- Avoid tests that rely on execution order.
- Prefer factory helpers for complex entities.
- Keep seed users minimal: enough for admin/user authorization tests.
- Make fixtures valid against current Bean Validation and database constraints.

## Testing Checklist

- Test data works with Flyway clean-at-start in `%test`.
- Default users have known roles and hashed passwords.
- Fixture builders create complete, valid aggregates.

## Example

For catalog tests, create helpers for artists, albums, users, and JWT tokens so resource tests can declare only the data relevant to each scenario.
