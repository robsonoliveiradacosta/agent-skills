---
name: add-error-handling
description: "Replace ad-hoc error responses in a Quarkus REST API with RFC 7807 Problem Details — generates a ProblemDetail record, a base ExceptionMapper, and specific mappers for ConstraintViolationException (validation), NotFoundException, NotAuthorizedException, WebApplicationException pass-through, and a final fallback that never leaks stack traces. Use whenever the user wants consistent error responses, problem+json, RFC 7807, \"professional error handling\", or \"stop leaking exception messages\"."
---

# add-error-handling

Replace inconsistent / leaky error responses with the **RFC 7807 Problem Details** content type, plus a tight set of `ExceptionMapper`s that cover the common cases.

After this skill, every error response looks like:

```json
{
  "type": "https://example.com/problems/validation-error",
  "title": "Validation failed",
  "status": 400,
  "detail": "Request body has invalid fields",
  "instance": "/v1/albums",
  "requestId": "abc-123",
  "errors": [
    {"field": "title", "message": "must not be blank"}
  ]
}
```

with `Content-Type: application/problem+json`.

## When to invoke

- "Use Problem Details / RFC 7807"
- "Standardize error responses"
- "Add a global exception handler"
- "Stop leaking stack traces"

## Inputs to collect

| Input | Default |
|---|---|
| Problem `type` base URL | derive from artifactId or use `about:blank` (RFC 7807 default) |
| Include `requestId` in payload? | yes (assumes `RequestIdFilter` from `add-observability`; if absent, generate without it and note the gap) |

## Files to generate

### `dto/response/ProblemDetail.java`

```java
package {{packageRoot}}.dto.response;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.net.URI;
import java.util.List;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record ProblemDetail(
    URI type,
    String title,
    int status,
    String detail,
    String instance,
    String requestId,
    List<FieldError> errors
) {
    public record FieldError(String field, String message) {}

    public static final String MEDIA_TYPE = "application/problem+json";
}
```

> `@JsonInclude(NON_NULL)` keeps the wire format clean — extension fields are only present when they have content.

### `exception/ProblemBuilder.java`

```java
package {{packageRoot}}.exception;

import {{packageRoot}}.dto.response.ProblemDetail;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;

import java.net.URI;
import java.util.List;

public final class ProblemBuilder {

    private static final String TYPE_BASE = "{{typeBase}}";

    private ProblemBuilder() {}

    public static Response build(int status, String title, String detail,
                                  UriInfo uriInfo, ContainerRequestContext ctx,
                                  List<ProblemDetail.FieldError> errors) {
        ProblemDetail body = new ProblemDetail(
            URI.create(TYPE_BASE + "/" + slug(title)),
            title,
            status,
            detail,
            uriInfo == null ? null : uriInfo.getPath(),
            ctx == null ? null : (String) ctx.getProperty("requestId"),
            errors
        );
        return Response.status(status)
            .type(ProblemDetail.MEDIA_TYPE)
            .entity(body)
            .build();
    }

    private static String slug(String title) {
        return title.toLowerCase().replaceAll("[^a-z0-9]+", "-").replaceAll("(^-|-$)", "");
    }
}
```

### `exception/ValidationExceptionMapper.java`

```java
package {{packageRoot}}.exception;

import {{packageRoot}}.dto.response.ProblemDetail;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.ConstraintViolationException;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;

import java.util.List;

@Provider
public class ValidationExceptionMapper implements ExceptionMapper<ConstraintViolationException> {

    @Context UriInfo uriInfo;
    @Context ContainerRequestContext ctx;

    @Override
    public Response toResponse(ConstraintViolationException ex) {
        List<ProblemDetail.FieldError> errors = ex.getConstraintViolations().stream()
            .map(this::toField).toList();
        return ProblemBuilder.build(400, "Validation failed", "Request body has invalid fields",
                                     uriInfo, ctx, errors);
    }

    private ProblemDetail.FieldError toField(ConstraintViolation<?> v) {
        String path = v.getPropertyPath().toString();
        // Strip "methodName.argumentName." prefix that Hibernate Validator emits
        int dot = path.indexOf('.');
        String field = dot >= 0 ? path.substring(dot + 1) : path;
        return new ProblemDetail.FieldError(field, v.getMessage());
    }
}
```

### `exception/NotFoundExceptionMapper.java`

```java
package {{packageRoot}}.exception;

import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;

@Provider
public class NotFoundExceptionMapper implements ExceptionMapper<NotFoundException> {

    @Context UriInfo uriInfo;
    @Context ContainerRequestContext ctx;

    @Override
    public Response toResponse(NotFoundException ex) {
        return ProblemBuilder.build(404, "Resource not found", ex.getMessage(), uriInfo, ctx, null);
    }
}
```

### `exception/NotAuthorizedExceptionMapper.java`

Replace the simple version generated by `bootstrap-quarkus-rest`:

```java
package {{packageRoot}}.exception;

import jakarta.ws.rs.NotAuthorizedException;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;

@Provider
public class NotAuthorizedExceptionMapper implements ExceptionMapper<NotAuthorizedException> {

    @Context UriInfo uriInfo;
    @Context ContainerRequestContext ctx;

    @Override
    public Response toResponse(NotAuthorizedException ex) {
        return ProblemBuilder.build(401, "Unauthorized", "Authentication is required", uriInfo, ctx, null);
    }
}
```

### `exception/WebApplicationExceptionMapper.java`

Pass-through for JAX-RS's own subclasses that arrive with a meaningful status:

```java
package {{packageRoot}}.exception;

import jakarta.annotation.Priority;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;

@Provider
@Priority(5000) // lower priority than the specific mappers above
public class WebApplicationExceptionMapper implements ExceptionMapper<WebApplicationException> {

    @Context UriInfo uriInfo;
    @Context ContainerRequestContext ctx;

    @Override
    public Response toResponse(WebApplicationException ex) {
        int status = ex.getResponse().getStatus();
        String title = Response.Status.fromStatusCode(status) != null
                ? Response.Status.fromStatusCode(status).getReasonPhrase()
                : "Error";
        return ProblemBuilder.build(status, title, ex.getMessage(), uriInfo, ctx, null);
    }
}
```

### `exception/FallbackExceptionMapper.java`

```java
package {{packageRoot}}.exception;

import jakarta.annotation.Priority;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import org.jboss.logging.Logger;

@Provider
@Priority(9000) // last resort
public class FallbackExceptionMapper implements ExceptionMapper<Throwable> {

    private static final Logger LOG = Logger.getLogger(FallbackExceptionMapper.class);

    @Context UriInfo uriInfo;
    @Context ContainerRequestContext ctx;

    @Override
    public Response toResponse(Throwable ex) {
        // Log with the full stack trace internally...
        LOG.errorf(ex, "Unhandled exception at %s", uriInfo == null ? "?" : uriInfo.getPath());
        // ...but never expose it to the caller.
        return ProblemBuilder.build(500, "Internal Server Error",
                "An unexpected error occurred", uriInfo, ctx, null);
    }
}
```

> **Critical**: `detail` is generic. Stack traces, SQL errors, and class names must **never** be in the response body.

## OpenAPI integration

Add a global response shape so Swagger UI shows error contracts:

```java
// resource/AlbumResource.java (annotation only — no code change)
@APIResponse(
    responseCode = "default",
    description = "Error",
    content = @Content(
        mediaType = "application/problem+json",
        schema = @Schema(implementation = ProblemDetail.class)
    )
)
```

> Encourage the user to apply this once on each resource class. The skill doesn't auto-add it because it must coexist with method-specific `@APIResponse`s.

## Tests to add

A small integration test that hits a validation-failing endpoint and asserts the problem+json shape:

```java
@Test
void validationError_returnsProblemDetail() {
    given()
        .auth().oauth2(TestTokenHelper.adminToken())
        .contentType("application/json")
        .body("""
            {"title":"","year":1969,"artistIds":[]}
        """)
    .when().post("/v1/albums")
    .then()
        .statusCode(400)
        .contentType("application/problem+json")
        .body("title", equalTo("Validation failed"))
        .body("errors.field", hasItem("title"));
}
```

## Anti-patterns to refuse

- **Returning `ex.getMessage()` as `detail`** for arbitrary exceptions. Internal messages may contain SQL fragments, secrets, or class names. Use a generic phrase for `5xx` and only echo the message for **known** safe exceptions (`NotFoundException`, validation).
- **Replacing JAX-RS's own `WebApplicationException` propagation** with try/catch in services. Services throw, mappers translate.
- **Different content types per endpoint**. Always `application/problem+json` for errors.
- **Logging at WARN for client errors**. 4xx are caller's fault, not yours. Reserve WARN/ERROR for 5xx.

## Post-generation

- Tell the user to re-run resource tests — the response content-type assertion may need updating from `application/json` to `application/problem+json` for error cases.
- Suggest documenting the problem `type` URIs publicly so clients can branch on stable identifiers.

---

## Strategic considerations & governance

## Goal

Make failures predictable for clients and useful for operators without leaking internals.

## Workflow

1. Define a stable error DTO with fields such as `code`, `message`, `details`, `path`, `timestamp`, and optional `correlationId`.
2. Map validation, authentication, authorization, not found, conflict, unsupported media type, rate limit, and unexpected errors explicitly.
3. Keep domain exceptions meaningful and transport-neutral; map them at the resource boundary.
4. Log unexpected errors with correlation context, but return safe client messages.
5. Document error responses in OpenAPI and cover them with resource tests.

## HTTP Policy

- Use `400` for malformed or invalid client input.
- Use `401` for missing or invalid authentication.
- Use `403` for authenticated users without permission.
- Use `404` for missing resources.
- Use `409` for unique constraint or state conflicts.
- Use `413` for oversized uploads.
- Use `429` for rate limiting.
- Use `500` only for unhandled server failures.

## Testing Checklist

- REST tests assert status code, stable error code, and response shape.
- Validation tests cover field-level details.
- Unexpected exception tests verify safe output and server-side logging.

## Example

For duplicate artist names, throw a domain conflict such as `DuplicateArtistException` from the service and map it to `409` with code `ARTIST_ALREADY_EXISTS`.
