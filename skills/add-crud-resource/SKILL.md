---
name: add-crud-resource
description: "Generate a full CRUD slice for a new domain entity in a Quarkus + Panache project — Entity, Repository, Service (@Transactional), JAX-RS Resource with @RolesAllowed and OpenAPI annotations, request/response DTOs, Flyway migration, plus REST Assured and Mockito tests. Use whenever the user asks to add a new resource, endpoint, entity, or \"CRUD for X\" to a Quarkus project that follows this repo's layered architecture."
---

# add-crud-resource

Generate a complete CRUD slice in **one pass** so the new endpoint compiles, has tests, and follows the project's conventions. No half-built scaffolding — every layer is created together.

## When to invoke

- "Add a CRUD for `Genre`"
- "Crie um novo recurso `Customer`"
- "Implement endpoints for entity X"

## Inputs to collect

| Input | Notes |
|---|---|
| Entity name | PascalCase singular, e.g. `Genre` |
| Field list | `name:String:required`, `priority:Integer:optional`, `code:String:unique` |
| Resource base path | derive from plural lowercase (`/v1/genres`) — confirm with user |
| Read roles / write roles | default: read `USER,ADMIN`, write `ADMIN` only |
| Relationships? | Optional `@ManyToOne` / `@ManyToMany` to existing entities |

Ask in **one** consolidated message. Don't go field-by-field.

## Workflow

1. Detect the Java package root by reading the existing `entity/` directory.
2. Read the **next** Flyway migration number (use the `add-flyway-migration` skill's numbering rule).
3. Write the 8 files listed below.
4. Run `./mvnw test -Dtest=<NewResource>Test` to prove the slice compiles and tests pass.
5. Report changes with file paths.

## Files to generate

For an entity called `Genre` with fields `name:String:required:unique`, `priority:Integer:optional`, the output is:

### 1. Entity — `entity/Genre.java`

```java
package {{packageRoot}}.entity;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;

@Entity
@Table(name = "genres")
public class Genre extends PanacheEntityBase {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String name;

    @Column
    private Integer priority;

    public Genre() {}

    public Genre(String name, Integer priority) {
        this.name = name;
        this.priority = priority;
    }

    public Long getId() { return id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public Integer getPriority() { return priority; }
    public void setPriority(Integer priority) { this.priority = priority; }
}
```

> Use `PanacheEntityBase` (not `PanacheEntity`) so the project owns the `id` column — matches the existing entities in this repo.

### 2. Repository — `repository/GenreRepository.java`

```java
package {{packageRoot}}.repository;

import {{packageRoot}}.entity.Genre;
import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class GenreRepository implements PanacheRepositoryBase<Genre, Long> {

    public boolean existsByName(String name) {
        return count("name = ?1", name) > 0;
    }
}
```

> Add only domain-specific lookup methods. Standard finders come from `PanacheRepositoryBase`.

### 3. Request DTO — `dto/request/GenreRequest.java`

```java
package {{packageRoot}}.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record GenreRequest(
    @NotBlank @Size(max = 100) String name,
    Integer priority
) {}
```

### 4. Response DTO — `dto/response/GenreResponse.java`

```java
package {{packageRoot}}.dto.response;

import {{packageRoot}}.entity.Genre;

public record GenreResponse(Long id, String name, Integer priority) {

    public static GenreResponse from(Genre g) {
        return new GenreResponse(g.getId(), g.getName(), g.getPriority());
    }
}
```

### 5. Service — `service/GenreService.java`

```java
package {{packageRoot}}.service;

import {{packageRoot}}.dto.request.GenreRequest;
import {{packageRoot}}.dto.response.GenreResponse;
import {{packageRoot}}.entity.Genre;
import {{packageRoot}}.repository.GenreRepository;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.WebApplicationException;

import java.util.List;

@ApplicationScoped
public class GenreService {

    @Inject GenreRepository repository;

    public List<GenreResponse> findAll() {
        return repository.listAll().stream().map(GenreResponse::from).toList();
    }

    public GenreResponse findById(Long id) {
        Genre g = repository.findByIdOptional(id)
            .orElseThrow(() -> new NotFoundException("Genre not found with id: " + id));
        return GenreResponse.from(g);
    }

    @Transactional
    public GenreResponse create(GenreRequest request) {
        if (repository.existsByName(request.name())) {
            throw new WebApplicationException("Genre name already exists", 409);
        }
        Genre g = new Genre(request.name(), request.priority());
        repository.persist(g);
        return GenreResponse.from(g);
    }

    @Transactional
    public GenreResponse update(Long id, GenreRequest request) {
        Genre g = repository.findByIdOptional(id)
            .orElseThrow(() -> new NotFoundException("Genre not found with id: " + id));
        g.setName(request.name());
        g.setPriority(request.priority());
        return GenreResponse.from(g);
    }

    @Transactional
    public void delete(Long id) {
        Genre g = repository.findByIdOptional(id)
            .orElseThrow(() -> new NotFoundException("Genre not found with id: " + id));
        repository.delete(g);
    }
}
```

> Services **always** throw `NotFoundException` / `WebApplicationException` — never return null. The exception mapper translates them to HTTP responses.

### 6. Resource — `resource/GenreResource.java`

```java
package {{packageRoot}}.resource;

import {{packageRoot}}.dto.request.GenreRequest;
import {{packageRoot}}.dto.response.GenreResponse;
import {{packageRoot}}.service.GenreService;
import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.validation.Valid;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

import java.util.List;

@Path("/v1/genres")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@Tag(name = "Genres")
public class GenreResource {

    @Inject GenreService service;

    @GET
    @RolesAllowed({"USER", "ADMIN"})
    @Operation(summary = "List all genres")
    public List<GenreResponse> list() {
        return service.findAll();
    }

    @GET @Path("/{id}")
    @RolesAllowed({"USER", "ADMIN"})
    @Operation(summary = "Get genre by ID")
    public GenreResponse get(@PathParam("id") Long id) {
        return service.findById(id);
    }

    @POST
    @RolesAllowed("ADMIN")
    @Operation(summary = "Create a new genre")
    public Response create(@Valid GenreRequest request) {
        return Response.status(Response.Status.CREATED).entity(service.create(request)).build();
    }

    @PUT @Path("/{id}")
    @RolesAllowed("ADMIN")
    @Operation(summary = "Update an existing genre")
    public GenreResponse update(@PathParam("id") Long id, @Valid GenreRequest request) {
        return service.update(id, request);
    }

    @DELETE @Path("/{id}")
    @RolesAllowed("ADMIN")
    @Operation(summary = "Delete a genre")
    public Response delete(@PathParam("id") Long id) {
        service.delete(id);
        return Response.noContent().build();
    }
}
```

> **Critical**: every method has an explicit `@RolesAllowed`. `quarkus.security.jaxrs.deny-unannotated-endpoints=false` in this project means an unannotated method would be public.

### 7. Migration — `src/main/resources/db/migration/V<next>__create_genres_table.sql`

```sql
CREATE TABLE genres (
    id         BIGSERIAL PRIMARY KEY,
    name       VARCHAR(100) NOT NULL UNIQUE,
    priority   INTEGER
);

CREATE INDEX idx_genres_name ON genres (name);
```

### 8. Tests

`test/.../service/GenreServiceTest.java` — service-level test with `@InjectMock` for the repository:

```java
package {{packageRoot}}.service;

import {{packageRoot}}.dto.request.GenreRequest;
import {{packageRoot}}.entity.Genre;
import {{packageRoot}}.repository.GenreRepository;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import jakarta.ws.rs.NotFoundException;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@QuarkusTest
class GenreServiceTest {

    @Inject GenreService service;
    @InjectMock GenreRepository repository;

    @Test
    void findById_returnsResponseWhenFound() {
        Genre g = new Genre("Rock", 1);
        when(repository.findByIdOptional(1L)).thenReturn(Optional.of(g));
        assertEquals("Rock", service.findById(1L).name());
    }

    @Test
    void findById_throwsWhenMissing() {
        when(repository.findByIdOptional(any())).thenReturn(Optional.empty());
        assertThrows(NotFoundException.class, () -> service.findById(99L));
    }

    @Test
    void create_persists() {
        when(repository.existsByName("Jazz")).thenReturn(false);
        service.create(new GenreRequest("Jazz", 2));
        verify(repository).persist(any(Genre.class));
    }
}
```

`test/.../resource/GenreResourceTest.java` — REST Assured end-to-end:

```java
package {{packageRoot}}.resource;

import {{packageRoot}}.common.PostgresResource;
import {{packageRoot}}.util.TestTokenHelper;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;

@QuarkusTest
@QuarkusTestResource(PostgresResource.class)
class GenreResourceTest {

    @Test
    void list_requiresAuth() {
        given().when().get("/v1/genres").then().statusCode(401);
    }

    @Test
    void create_asUser_is403() {
        given()
            .auth().oauth2(TestTokenHelper.userToken())
            .contentType("application/json")
            .body("""
                {"name":"Rock","priority":1}
            """)
        .when().post("/v1/genres")
        .then().statusCode(403);
    }

    @Test
    void crud_happyPath() {
        Integer id = given()
            .auth().oauth2(TestTokenHelper.adminToken())
            .contentType("application/json")
            .body("""
                {"name":"Rock","priority":1}
            """)
        .when().post("/v1/genres")
        .then().statusCode(201).extract().path("id");

        given()
            .auth().oauth2(TestTokenHelper.userToken())
        .when().get("/v1/genres/" + id)
        .then().statusCode(200).body("name", equalTo("Rock"));
    }
}
```

> Resource tests assume `TestTokenHelper` exists (created by `add-jwt-auth`) and `PostgresResource` exists (created by `add-testcontainers-resource`). If either is missing, instruct the user to run those skills first instead of fabricating tokens.

## Conventions to enforce (do not deviate)

- Constructor or field `@Inject` — match the rest of the codebase (this project uses field injection).
- DTOs are `record` types. Mapping helpers live as a static `from(Entity)` on the response DTO.
- Validation lives on the **request DTO**, not the entity.
- Pagination: only add it when the user lists pagination as a requirement. Otherwise `findAll()` returns the full list (matches `ArtistResource` in this repo). For paginated endpoints, follow the `AlbumResource` pattern with `page`, `size`, `sort` query params and a `PageResponse<T>` response.
- For relationships, generate junction tables in the same migration (mirroring `V3__create_album_artist_junction.sql`), not separate.

## Post-generation

Tell the user:
- The new migration number used.
- The new endpoints (`GET /v1/genres`, `POST /v1/genres`, …).
- That `./mvnw test -Dtest=GenreServiceTest,GenreResourceTest` should pass.

---

## Strategic considerations & governance

## Goal

Add one coherent domain feature without leaking concerns across layers. Follow the local naming style: `*Resource`, `*Service`, `*Repository`, `*Request`, `*Response`, and singular entity names.

## Workflow

1. Model the aggregate: fields, constraints, relationships, uniqueness rules, lifecycle, and delete behavior.
2. Create the next Flyway migration in `src/main/resources/db/migration` using `V<number>__description.sql`.
3. Add the JPA entity in `entity`; use explicit table/column names and Bean Validation where useful.
4. Add a Panache repository for query composition, pagination, sorting, and relationship lookups.
5. Add request DTOs for writes and response DTOs for reads. Keep API contracts separate from entities.
6. Implement service methods for create, read, update, delete, filtering, and mapping.
7. Add a REST resource under `/v1/<plural-resource>` with clear status codes.
8. Add tests before considering the module complete.

## Design Rules

- Keep transaction boundaries in services unless the existing neighboring code does otherwise.
- Validate IDs and relationship existence before persistence changes.
- Use pagination response types for list endpoints when results can grow.
- Return stable response shapes; do not expose lazy entities directly.
- Keep error handling consistent with existing exception mappers and response DTOs.

## Testing Checklist

- Service tests cover business rules, validation paths, and missing references.
- Resource tests cover happy paths, invalid input, not found, authorization, pagination, and sorting.
- Migration changes are exercised by Quarkus tests or Testcontainers-backed integration tests.

## Example

For a `Genre` module, create `Genre`, `GenreRepository`, `GenreService`, `GenreResource`, `GenreRequest`, `GenreResponse`, `V11__create_genres_table.sql`, and tests such as `GenreServiceTest` and `GenreResourceTest`.
