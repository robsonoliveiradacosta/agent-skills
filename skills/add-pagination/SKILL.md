---
name: add-pagination
description: "Convert a non-paginated Quarkus REST resource into a paginated listing endpoint following this repo's PageResponse<T> + Panache Page/Sort pattern — adds page/size/sort/filter query parameters with caps and validation, wires repository.findWithFilters + countWithFilters, and refactors the resource and service to return PageResponse<T>. Use whenever the user asks to paginate, sort, filter, \"add page params\", or wants list endpoints to scale beyond a few thousand rows."
---

# add-pagination

Convert a `GET /v1/<resource>` endpoint that returns `List<Response>` into one that returns `PageResponse<Response>`, following the exact pattern in `AlbumResource` / `AlbumService` / `AlbumRepository`.

## When to invoke

- "Paginate the albums endpoint"
- "Add page/size/sort to X"
- "Returns too many rows, need pagination"

## Inputs to collect

| Input | Default |
|---|---|
| Resource to paginate | required, e.g. `Genre` |
| Default page size | `20` |
| Max page size cap | `100` |
| Allowed sort fields | required — explicit allowlist, e.g. `["name", "createdAt"]` |
| Filter fields | optional, with their query-param names and types |
| Default sort | required — `<field>:asc` |

> **Critical**: never accept arbitrary user-controlled column names into `ORDER BY`. Always validate against an allowlist.

## Files to generate / modify

### `dto/response/PageResponse.java` (if not already present)

```java
package {{packageRoot}}.dto.response;

import java.util.List;

public record PageResponse<T>(
    List<T> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean first,
    boolean last
) {
    public static <T> PageResponse<T> of(List<T> content, int page, int size, long totalElements) {
        int totalPages = size == 0 ? 0 : (int) Math.ceil((double) totalElements / size);
        return new PageResponse<>(
            content, page, size, totalElements, totalPages,
            page == 0,
            page >= totalPages - 1 || content.isEmpty()
        );
    }
}
```

### Repository — add pagination-aware queries

```java
import io.quarkus.panache.common.Page;
import io.quarkus.panache.common.Sort;

import java.util.List;

@ApplicationScoped
public class GenreRepository implements PanacheRepositoryBase<Genre, Long> {

    public List<Genre> findWithFilters(Page page, Sort sort, String nameFilter) {
        if (nameFilter == null || nameFilter.isBlank()) {
            return findAll(sort).page(page).list();
        }
        return find("LOWER(name) LIKE LOWER(?1)", sort, "%" + nameFilter + "%").page(page).list();
    }

    public long countWithFilters(String nameFilter) {
        if (nameFilter == null || nameFilter.isBlank()) {
            return count();
        }
        return count("LOWER(name) LIKE LOWER(?1)", "%" + nameFilter + "%");
    }
}
```

> **SQL injection safety**: filter values are bound as `?1` parameters; only column names appear in the literal SQL string and they come from compile-time code. Don't accept user input into the query string itself.

### Service — return `PageResponse<T>`

```java
public PageResponse<GenreResponse> findAll(int page, int size, String sortParam, String nameFilter) {
    int capped = clampSize(size);
    int safePage = Math.max(page, 0);
    Sort sort = parseSort(sortParam);

    Page pageReq = Page.of(safePage, capped);
    List<Genre> rows = repository.findWithFilters(pageReq, sort, nameFilter);
    long total = repository.countWithFilters(nameFilter);

    List<GenreResponse> content = rows.stream().map(GenreResponse::from).toList();
    return PageResponse.of(content, safePage, capped, total);
}

private static int clampSize(int size) {
    if (size > 100) return 100;
    if (size <= 0)  return 20;
    return size;
}

private Sort parseSort(String sortParam) {
    if (sortParam == null || sortParam.isBlank()) return Sort.by("name").ascending();
    String[] parts = sortParam.split(":");
    String field     = parts[0].trim();
    String direction = parts.length > 1 ? parts[1].trim().toLowerCase() : "asc";

    // CRITICAL: allowlist check
    if (!ALLOWED_SORT_FIELDS.contains(field)) field = "name";
    return "desc".equals(direction) ? Sort.by(field).descending() : Sort.by(field).ascending();
}

private static final Set<String> ALLOWED_SORT_FIELDS = Set.of("name", "createdAt");
```

### Resource — new query params

```java
@GET
@RolesAllowed({"USER", "ADMIN"})
@Operation(summary = "List genres (paginated)")
public PageResponse<GenreResponse> list(
    @Parameter(description = "Page number (0-based)")  @QueryParam("page")   @DefaultValue("0")  int page,
    @Parameter(description = "Page size (max 100)")    @QueryParam("size")   @DefaultValue("20") int size,
    @Parameter(description = "Sort, e.g. name:asc")    @QueryParam("sort")                       String sort,
    @Parameter(description = "Filter by name (LIKE)")  @QueryParam("name")                       String name
) {
    return service.findAll(page, size, sort, name);
}
```

## Tests to update / add

```java
@Test
void list_paginates() {
    // seed 25 rows via repository
    given()
        .auth().oauth2(TestTokenHelper.userToken())
        .queryParam("page", 0)
        .queryParam("size", 10)
    .when().get("/v1/genres")
    .then()
        .statusCode(200)
        .body("content.size()", equalTo(10))
        .body("totalElements", equalTo(25))
        .body("totalPages", equalTo(3))
        .body("first", equalTo(true))
        .body("last", equalTo(false));
}

@Test
void list_rejectsUnknownSortField() {
    given()
        .auth().oauth2(TestTokenHelper.userToken())
        .queryParam("sort", "secretInternalField:asc")
    .when().get("/v1/genres")
    .then()
        .statusCode(200); // falls back to default — does NOT return 500 or leak DB error
}

@Test
void list_clampsSize() {
    given()
        .auth().oauth2(TestTokenHelper.userToken())
        .queryParam("size", 9999)
    .when().get("/v1/genres")
    .then()
        .statusCode(200)
        .body("size", equalTo(100));
}
```

## Conventions to enforce

- **Page numbers are 0-based**. Match `Page.of(...)`.
- **Default size 20, max 100**. Hard cap server-side — never trust the client.
- **Sort allowlist is mandatory**. Unknown fields silently fall back to default, never 500.
- **Filters are nullable / optional**. Never make filter params `@NotNull` — that defeats the purpose.
- **Count query mirrors the filter query**. If you change one, change the other. They're two halves of the same operation.

## Anti-patterns to refuse

- **Returning the raw `Page` object** from Panache. Always wrap in `PageResponse<T>` so the contract is stable.
- **Offset pagination on tables that will exceed ~100k rows where the user expects deep pages**. For "load all in chunks" use cases, recommend cursor / keyset pagination instead — push back and discuss with the user.
- **`COUNT(*)` on every list request without an index supporting the filter.** For very large tables, suggest approximate counts (`pg_class.reltuples`) when exact counts aren't required.
- **String concatenation in the `ORDER BY`** — even with an allowlist, prefer Panache `Sort.by(field)` which builds the SQL safely.

## Post-generation

- Tell the user the new endpoint signature.
- Run the new test set.
- Suggest adding an index on each `ALLOWED_SORT_FIELDS` entry if missing. Generate a Flyway migration via `/add-flyway-migration` if needed.
