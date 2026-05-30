---
name: add-api-versioning
description: "Establish an explicit URL-path-based API versioning strategy for a Quarkus REST API — moves existing endpoints to a versioned base path (already /v1 in this repo), introduces a Resource-per-version convention, generates a DeprecationFilter that adds RFC 8594 Sunset and Deprecation headers when an endpoint is marked @Deprecated(since=\"v1\", sunset=\"2026-12-01\"), splits OpenAPI documentation per version, and writes a docs/api-versioning.md policy with deprecation lifecycle and SemVer mapping. Use whenever the user asks for API versioning, \"how do I add v2\", deprecation strategy, breaking change roadmap, or wants to introduce a new version of an existing endpoint without breaking current consumers."
---

# add-api-versioning

Make the API version explicit so future breaking changes don't strand consumers. This skill is **policy + scaffolding** — it doesn't add new functionality, it sets the rules of the road.

## When to invoke

- "How do I version this API?"
- "I need a v2 of this endpoint"
- "Deprecate an old endpoint"
- "Plan for breaking changes"

## Strategies compared

| Strategy | Pros | Cons |
|---|---|---|
| **URL path** (`/v1/`, `/v2/`) ← this skill | Visible, explicit, easy to route at gateway, cacheable, browser-friendly | Two paths in OpenAPI; URL pollution |
| **Accept header** (`Accept: application/vnd.example.v2+json`) | Clean URLs; "REST purist" | Invisible in browser/curl; hard to debug; cache key complexity |
| **Query param** (`?version=2`) | Easy to default | Easy to forget; doesn't survive bookmarks; mixed semantics |

This skill uses **URL path**. It's the strategy almost every major API (Stripe, GitHub, Twilio) uses for good reason: visibility and tooling-friendliness. If the user insists on header-based versioning, push back once; if they hold, switch the scaffold to a `ContainerRequestFilter` that routes based on `Accept`. Most teams come around.

## Inputs to collect

| Input | Default |
|---|---|
| Current version (already in URL) | `v1` (detected from existing `@Path("/v1/...")`) |
| Target new version | required when introducing — e.g. `v2` |
| Deprecation policy | recommend **6-month minimum** between deprecation and sunset |
| SemVer mapping | recommend **path version bump = MAJOR bump** in `mp.openapi.extensions.smallrye.info.version` |

## What this skill produces

1. A `docs/api-versioning.md` document the team can reference (and link from CLAUDE.md).
2. A `@Deprecated` annotation pattern + `DeprecationFilter` that emits RFC 8594 headers.
3. A package convention for v2: `resource.v2.AlbumResource` extends or replaces `resource.AlbumResource` (which becomes `resource.v1.*`).
4. OpenAPI split: separate operation tags per version so Swagger UI is navigable.

## Files to generate

### `docs/api-versioning.md`

```markdown
# API Versioning Policy

## Versioning scheme

- The API uses **URL path versioning**: `https://api.example.com/api/v{N}/...`.
- `N` is a monotonically-increasing integer. We do **not** ship `v1.1`, `v1.2` — there are only major versions in the URL.
- Each released version remains supported for **at least 12 months** from the date its successor is released, unless announced otherwise.

## When to bump the version

Bump from `v{N}` to `v{N+1}` for any **breaking change**, as defined by the `api-contract-reviewer` agent:

- Removing an endpoint, field, parameter, or status code from the contract.
- Renaming any of the above.
- Narrowing an enum.
- Changing a field's type.
- Tightening validation that previously accepted values.
- Changing a default value clients depended on.

Non-breaking changes are released **into the existing version**:

- Adding endpoints, optional fields, optional parameters.
- Adding new enum values (subject to forward-compatibility note).
- Loosening validation.

## Deprecation lifecycle

1. **Announce** — open a public deprecation issue / changelog entry. Annotate the endpoint with `@Deprecated(since = "v{N}", sunset = "YYYY-MM-DD")`.
2. **Headers** — from the announcement, the API emits `Deprecation: true` and `Sunset: <date>` headers on every response from the deprecated endpoint.
3. **Sunset** — after the sunset date, the endpoint may be removed in a release. The new version (`v{N+1}`) has been generally available for at least 6 months by this point.

## Versioning maps to SemVer

The `info.version` in OpenAPI follows SemVer:

- `1.x.y` = path-version `v1`. MINOR for new endpoints, PATCH for bugfixes.
- `2.x.y` = path-version `v2`. The path bump implies a SemVer MAJOR bump.

Multiple path versions coexist in the same JVM; the OpenAPI spec is split per version.

## Co-existence rules

While `v1` and `v2` are both supported:

- They MUST share the same JWT, the same authentication, the same rate limits.
- They SHOULD share entities and the database schema — duplicate persistence is a tarpit.
- They MAY share services (recommended: v2 resource calls service, service stays version-agnostic; the v2 resource maps to v2 DTOs).
```

### `security/Deprecated.java` (annotation)

```java
package {{packageRoot}}.security;

import jakarta.ws.rs.NameBinding;
import java.lang.annotation.*;

@NameBinding
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE, ElementType.METHOD})
public @interface Deprecated {
    /** Version where this endpoint was deprecated, e.g. "v1". */
    String since();

    /** ISO 8601 date when this endpoint may be removed, e.g. "2026-12-01". */
    String sunset();

    /** Optional link to migration documentation. */
    String link() default "";
}
```

> Reusing the JDK's `@java.lang.Deprecated` is tempting but it's a marker, not a runtime annotation we can read in a filter. A custom one with the metadata we actually need is clearer.

### `security/DeprecationFilter.java`

```java
package {{packageRoot}}.security;

import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.container.ResourceInfo;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.ext.Provider;

import java.lang.reflect.Method;

@Provider
public class DeprecationFilter implements ContainerResponseFilter {

    @Context ResourceInfo resourceInfo;

    @Override
    public void filter(ContainerRequestContext req, ContainerResponseContext resp) {
        Method method = resourceInfo.getResourceMethod();
        if (method == null) return;

        Deprecated d = method.getAnnotation(Deprecated.class);
        if (d == null && resourceInfo.getResourceClass() != null) {
            d = resourceInfo.getResourceClass().getAnnotation(Deprecated.class);
        }
        if (d == null) return;

        // RFC 8594 — Sunset HTTP header
        resp.getHeaders().putSingle("Deprecation", "true");
        resp.getHeaders().putSingle("Sunset", d.sunset());
        if (!d.link().isBlank()) {
            resp.getHeaders().putSingle("Link",
                "<" + d.link() + ">; rel=\"deprecation\"; type=\"text/html\"");
        }
    }
}
```

> RFC 8594 specifies `Sunset` as an HTTP-date. The `IETF Deprecation Header draft` adds `Deprecation: true` (now widely adopted). Together they're the standard.

### Package convention for v2

```
src/main/java/{{packagePath}}/
└── resource/
    ├── v1/                              # rename existing resources here
    │   └── AlbumResource.java           # @Path("/v1/albums")
    └── v2/                              # new version lives here
        └── AlbumResource.java           # @Path("/v2/albums")
```

A v2 resource example showing the "service-version-agnostic" pattern:

```java
package {{packageRoot}}.resource.v2;

import {{packageRoot}}.dto.v2.request.AlbumRequestV2;
import {{packageRoot}}.dto.v2.response.AlbumResponseV2;
import {{packageRoot}}.service.AlbumService;
// ... (other imports)

@Path("/v2/albums")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@Tag(name = "Albums (v2)")
public class AlbumResource {

    @Inject AlbumService service;   // service is shared across versions

    @POST
    @RolesAllowed("ADMIN")
    @Operation(summary = "Create an album (v2)")
    public Response create(@Valid AlbumRequestV2 request) {
        // v2 DTO has different fields; map to the version-agnostic service input
        AlbumRequest internal = AlbumRequestV2.toInternal(request);
        return Response.status(201)
                .entity(AlbumResponseV2.from(service.create(internal)))
                .build();
    }
}
```

> **Key principle**: the **service** layer is version-agnostic. Each version has its own DTOs that map to/from a stable internal representation. Without this, two versions duplicate business logic and drift.

### Deprecate the v1 endpoint

```java
package {{packageRoot}}.resource.v1;

import {{packageRoot}}.security.Deprecated;

@Path("/v1/albums")
@Deprecated(since = "v1", sunset = "2027-05-15", link = "https://docs.example.com/migrating-to-v2-albums")
@Tag(name = "Albums (v1, deprecated)")
public class AlbumResource {
    // existing v1 implementation stays untouched
}
```

> The migration date should be **at least 12 months** from the day v2 ships, per the policy.

### OpenAPI tagging

In `application.properties`:

```properties
mp.openapi.extensions.smallrye.info.version=2.0.0
# Tag descriptions visible in Swagger UI
mp.openapi.extensions.smallrye.tags."Albums (v1, deprecated)".description=v1 endpoints scheduled for sunset on 2027-05-15.
mp.openapi.extensions.smallrye.tags."Albums (v2)".description=Current.
```

Generated Swagger UI groups operations under each tag, so consumers immediately see what's current vs deprecated.

## Mapping DTOs between versions

Place mapping helpers in the **v2 DTO** (not in a shared utility):

```java
package {{packageRoot}}.dto.v2.request;

public record AlbumRequestV2(String name, Integer year, List<Long> artistIds, Map<String, String> tags) {
    public static AlbumRequest toInternal(AlbumRequestV2 v2) {
        // v2 renamed "title" → "name"; preserve internal naming
        return new AlbumRequest(v2.name(), v2.year(), v2.artistIds());
        // tags are v2-only; for now, ignored or written to album.metadata.tags
    }
}
```

> Don't add `toV2(...)` to the v1 DTO — that creates a coupling from old to new. Always forward-only mapping at the new boundary.

## Tests

A small test that proves the deprecation headers fire:

```java
@Test
void v1Endpoint_emitsDeprecationAndSunsetHeaders() {
    given().auth().oauth2(TestTokenHelper.userToken())
    .when().get("/v1/albums")
    .then()
        .statusCode(200)
        .header("Deprecation", "true")
        .header("Sunset", equalTo("2027-05-15"));
}

@Test
void v2Endpoint_doesNotEmitDeprecation() {
    given().auth().oauth2(TestTokenHelper.userToken())
    .when().get("/v2/albums")
    .then()
        .statusCode(200)
        .header("Deprecation", nullValue())
        .header("Sunset", nullValue());
}
```

## Anti-patterns to refuse

- **Versioning via "?v=2" query parameter** without a strong reason. Caching, bookmarks, and routing all suffer.
- **Multiple minor versions in the URL** (`/v1.2/`). The URL version is binary: either it's compatible or it's not. Compatibility lives in OpenAPI MINOR/PATCH.
- **Removing a deprecated endpoint without the Sunset window**. Clients that haven't migrated break with zero warning.
- **Duplicating the service layer per version**. Bug fixes happen once, in the service; the v1 and v2 resources just shape the wire format.
- **Versioning everything at once when only one resource has a breaking change.** Bump only the affected paths; other resources stay on their current version.
- **Bumping the path version for non-breaking additions**. New optional fields = same version, MINOR OpenAPI bump.

## Post-generation

- Tell the user that the **first** sunset doesn't need to be aggressive — 12+ months is fine. The headers exist to give consumers warning, not pressure.
- Add a CI check that fails if a `@Deprecated` endpoint's `sunset` date has passed but the endpoint still exists. Quick script:
  ```bash
  grep -rn "@Deprecated.*sunset" src/main/java/ \
      | awk -F'sunset = "' '{print $2}' | cut -d'"' -f1 \
      | while read date; do
          if [[ "$date" < "$(date -I)" ]]; then
              echo "::error::Sunset date $date has passed"
              exit 1
          fi
        done
  ```
- Encourage pairing with `api-contract-reviewer` — that agent catches breaking changes; this skill gives you the version-bump mechanism to handle them.

---

## Strategic considerations & governance

## Goal

Change REST APIs without surprising existing clients.

## Workflow

1. Identify whether the change is additive, behavior-changing, or breaking.
2. Keep existing `/v1` contracts stable unless a breaking change is explicitly approved.
3. Prefer additive DTO fields, optional request fields, and new endpoints over changing existing meanings.
4. Deprecate before removal; document replacement endpoints and timelines.
5. Add tests that preserve old behavior while covering new behavior.
6. Update OpenAPI and README examples when public contracts change.

## Compatibility Rules

- Safe: adding optional response fields, adding optional request fields, adding new endpoints, adding new enum values only when clients tolerate them.
- Risky: changing validation, pagination defaults, sort semantics, status codes, or error shapes.
- Breaking: renaming fields, removing fields, changing required fields, changing IDs, changing auth requirements, or changing response types.

## Review Checklist

- Existing clients can still parse responses.
- Error status and error body shape remain stable.
- Pagination, sorting, and filters retain previous defaults.
- OpenAPI examples reflect the active version.

## Example

If album responses need `releaseDate`, add it as an optional response field in `v1`. Do not replace an existing `year` field unless a new API version is introduced.
