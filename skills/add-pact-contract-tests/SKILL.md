---
name: add-pact-contract-tests
description: "Add Pact provider-side contract testing to a Quarkus REST API so consumer-defined contracts (published by frontend/mobile/microservice teams to a Pact Broker) are verified against the running API in CI — wires the pact-jvm-provider-junit5 dependency, a verifier test that boots the API with @QuarkusTest, state-handler methods that seed the DB for each interaction, and CI integration that publishes verification results back to the broker. Use only when at least one consumer is already publishing Pact contracts; otherwise prefer OpenAPI-driven testing."
---

# add-pact-contract-tests

Add **provider-side** Pact verification. This skill assumes the consumer team already publishes Pact contracts to a Pact Broker. If no contracts exist yet, this is **premature** — recommend OpenAPI-driven testing (`/add-openapi-client-gen`) and revisit when consumers exist.

## When to invoke

- "Add Pact verification"
- "Consumer team is using Pact, we need to verify"
- "Set up provider-side contract tests"

## When NOT to invoke

- No consumer publishes contracts yet → there's nothing to verify.
- Consumers only consume the generated OpenAPI SDK → contract drift is caught by `add-openapi-client-gen`'s drift check.
- Single team owns both sides → Pact's value (independence) doesn't apply; integration tests are simpler.

If the user says "let's add Pact preventively", push back. Pact has real ergonomic cost; it pays off only when the consumer↔provider boundary is real and async.

## Inputs to collect

| Input | Required |
|---|---|
| Pact Broker URL | yes, e.g. `https://broker.example.com` |
| Broker auth (token or basic) | yes |
| Provider name (as published by consumers) | yes — must match exactly |
| Consumer version selector | `mainBranch=true` + `deployedOrReleased=true` (recommended) |
| Provider version source | git short SHA or release tag |

## Dependencies

```xml
<dependency>
    <groupId>au.com.dius.pact.provider</groupId>
    <artifactId>junit5</artifactId>
    <version>4.6.14</version>
    <scope>test</scope>
</dependency>

<!-- For state handlers that need DB access -->
<dependency>
    <groupId>au.com.dius.pact.provider</groupId>
    <artifactId>junit5spring</artifactId>
    <version>4.6.14</version>
    <scope>test</scope>
    <exclusions>
        <!-- Avoid pulling Spring transitively -->
        <exclusion>
            <groupId>org.springframework</groupId>
            <artifactId>*</artifactId>
        </exclusion>
    </exclusions>
</dependency>
```

> The `junit5spring` module's `MessageStateChangeAction` is useful even without Spring on the classpath — Quarkus tests use it through `@TestExecutionListener` adapters.

## File to generate — `test/.../contract/ProviderContractTest.java`

```java
package {{packageRoot}}.contract;

import au.com.dius.pact.provider.junit5.HttpTestTarget;
import au.com.dius.pact.provider.junit5.PactVerificationContext;
import au.com.dius.pact.provider.junit5.PactVerificationInvocationContextProvider;
import au.com.dius.pact.provider.junitsupport.Provider;
import au.com.dius.pact.provider.junitsupport.State;
import au.com.dius.pact.provider.junitsupport.loader.PactBroker;
import au.com.dius.pact.provider.junitsupport.loader.SelectorBuilder;
import au.com.dius.pact.provider.junitsupport.loader.VersionSelector;
import {{packageRoot}}.entity.Album;
import {{packageRoot}}.repository.AlbumRepository;
import {{packageRoot}}.testdata.TestData;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.TestTemplate;
import org.junit.jupiter.api.extension.ExtendWith;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@QuarkusTest
@Provider("{{providerName}}")
@PactBroker(
    url = "${PACT_BROKER_URL}",
    authentication = @au.com.dius.pact.provider.junitsupport.loader.PactBrokerAuth(token = "${PACT_BROKER_TOKEN}")
)
public class ProviderContractTest {

    @Inject AlbumRepository albumRepository;

    @ConfigProperty(name = "quarkus.http.test-port")
    int httpPort;

    @BeforeEach
    void setTarget(PactVerificationContext context) {
        if (context != null) {
            context.setTarget(new HttpTestTarget("localhost", httpPort, "/"));
        }
    }

    @TestTemplate
    @ExtendWith(PactVerificationInvocationContextProvider.class)
    void verifyPact(PactVerificationContext context) {
        context.verifyInteraction();
    }

    // ───── State handlers ─────
    // The consumer-side test declares a `given(...)` for each interaction.
    // Each `given` string maps to a @State here. Pact calls the handler before
    // running the interaction, expects the DB to be in the matching state.

    @State("an album with id 1 exists")
    @Transactional
    public void anAlbumWithId1Exists() {
        if (albumRepository.findByIdOptional(1L).isEmpty()) {
            albumRepository.persist(TestData.anAlbum().withTitle("Abbey Road").build());
        }
    }

    @State("no albums exist")
    @Transactional
    public void noAlbumsExist() {
        albumRepository.deleteAll();
    }

    // Add one method per unique `given(...)` value the consumer publishes.
}

// Recommended @VersionSelector usage (verifies main + production consumers)
class PactSelectors extends SelectorBuilder {
    public PactSelectors() {
        mainBranch()
            .deployedOrReleased();
    }
}
```

> **State handlers run before each interaction**. Make them idempotent — Pact may call the same state multiple times per run.

## How to write state handlers correctly

State strings are arbitrary — coordinate with consumers. Patterns that work:

- `"a {resource} with id {id} exists"` — straightforward seed.
- `"no {resources} exist"` — clean slate.
- `"a {resource} with name {name} exists"` — parameterized state. Use `@State("...")` with parameters from `@StateValue`.

```java
@State("a user with username #username exists")
@Transactional
public void aUserExists(java.util.Map<String, Object> params) {
    String username = (String) params.get("username");
    if (userRepository.findByUsername(username).isEmpty()) {
        userRepository.persist(TestData.aUser().withUsername(username).build());
    }
}
```

## `application.properties` additions

```properties
# Random port for tests — Pact will read quarkus.http.test-port
%test.quarkus.http.test-port=0
```

## CI integration

```yaml
  contract-verify:
    needs: [build-and-test]
    runs-on: ubuntu-latest
    services:
      postgres: { /* same as build-and-test */ }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '21', cache: maven }

      - name: Run provider verification
        env:
          PACT_BROKER_URL:   ${{ secrets.PACT_BROKER_URL }}
          PACT_BROKER_TOKEN: ${{ secrets.PACT_BROKER_TOKEN }}
          pact.provider.version: ${{ github.sha }}
          pact.verifier.publishResults: 'true'   # publish ✓/✗ back to broker
          pact.provider.branch: ${{ github.ref_name }}
        run: ./mvnw -B test -Dtest=ProviderContractTest
```

> `pact.verifier.publishResults=true` is critical — without it the broker doesn't know whether `mainBranch=true` consumers are safe to deploy. Only set this on push to `main` / release branches, **not** on PRs (PR runs may verify against partial code).

## Coordinating with consumers

Document in `CLAUDE.md` (or a dedicated `docs/pact.md`):

1. **State names are a contract**. Consumer changes to state strings = provider must add a matching `@State`. Coordinate via review of the consumer's pact files.
2. **Pact failures block consumer deploys** via `can-i-deploy` checks. Do not delete or rename states without coordinating.
3. **New endpoints don't require new states** — only new interactions do.

## Anti-patterns to refuse

- **Using Pact as schema validation.** That's what OpenAPI does. Pact validates **behavior**, not just shape.
- **`pact.verifier.publishResults=true` on PR branches.** Pollutes the broker; defeats `can-i-deploy`.
- **State handlers calling the service layer** with side effects beyond the state setup (e.g. WebSocket broadcasts). Use the repository directly to avoid noise.
- **Mocking external dependencies inside the verifier test.** Provider verification runs against the real wire. If you mock the DB, you're not testing the provider — you're testing your mock.
- **One huge state handler per resource.** Each `given(...)` from the consumer maps to ONE specific state. Don't over-factor.

## Post-generation

- Tell the user the **first run** will likely fail with "no pacts found" if the consumer hasn't published yet. That's a configuration question, not a test failure.
- Set `PACT_BROKER_URL` and `PACT_BROKER_TOKEN` as GitHub secrets.
- Run `./mvnw test -Dtest=ProviderContractTest` locally with the broker URL exported.
- If the project already has `add-test-data-builders`, the state handlers above will work; otherwise the user needs to hand-craft entities or run that skill first.

---

## Strategic considerations & governance

## Goal

Ensure the API described by OpenAPI is the API clients actually receive.

## Workflow

1. Identify public endpoints, DTOs, status codes, authentication rules, and examples.
2. Verify OpenAPI metadata includes request bodies, response schemas, and error responses.
3. Add REST tests that assert real payload shapes for representative endpoints.
4. Compare contract changes against previous behavior when compatibility matters.
5. Keep README examples synchronized with executable behavior.

## Contract Rules

- Every public endpoint should have documented success and common error responses.
- Examples must be valid JSON and match DTO validation rules.
- Required and optional fields must match runtime validation.
- Security requirements in OpenAPI must match actual annotations and filters.
- Contract tests should catch accidental field renames, status changes, and missing errors.

## Testing Examples

- Assert `POST /v1/auth/login` returns the documented token response.
- Assert invalid album creation returns the documented validation error shape.
- Assert protected writes advertise and enforce bearer authentication.

## Review Checklist

OpenAPI, DTOs, REST Assured tests, README examples, and exception mappers all describe the same API.
