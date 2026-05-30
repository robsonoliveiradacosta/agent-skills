---
name: add-mutation-testing
description: "Add Pitest (PIT) mutation testing to a Quarkus + Maven project to measure how well existing tests detect actual bugs — wires the pitest-maven plugin targeting service/repository packages, uses incremental analysis with history file to skip unchanged code, sets per-class mutator strength, configures CI to compare mutation score vs baseline and fail PRs that drop it, and surfaces surviving mutants as actionable findings. Use when the user asks about mutation testing, Pitest, \"are my tests actually good\", \"we have 90% coverage but bugs slip through\", or wants to measure test quality not just quantity."
---

# add-mutation-testing

Add **Pitest** (mutation testing) so the suite isn't graded on "did the line execute" but on "did a test fail when I changed the code". A line covered by an assertion-free test gives 100% line coverage and 0% mutation score — and that gap is exactly what this skill exposes.

## When to invoke

- "Add mutation testing"
- "Our coverage is 90% but bugs still slip through"
- "Audit test quality"
- "Set up Pitest"

## What this skill produces

- `target/pit-reports/<timestamp>/index.html` — surviving mutants per class.
- A **mutation score** (% of mutants killed) per package.
- A `pitest-history` file so subsequent runs only re-mutate changed classes.
- CI integration that fails PRs which drop the mutation score below the threshold.

## Inputs to collect

| Input | Default |
|---|---|
| Target packages | `{{packageRoot}}.service.*`, `{{packageRoot}}.repository.*` |
| Mutators | `STRONGER` (recommended) or `DEFAULTS` |
| Minimum mutation score | `60%` (start) → ratchet up over time |
| Run on every PR or nightly? | nightly (PR-time can be slow on large codebases) |
| Incremental? | yes — use `historyFile` |

> Mutation testing is **CPU-intensive**: it recompiles and re-runs the test suite for each mutant. Targeting only `service/`+`repository/` keeps it tractable.

## `pom.xml` plugin block

```xml
<plugin>
    <groupId>org.pitest</groupId>
    <artifactId>pitest-maven</artifactId>
    <version>1.17.1</version>
    <dependencies>
        <dependency>
            <groupId>org.pitest</groupId>
            <artifactId>pitest-junit5-plugin</artifactId>
            <version>1.2.1</version>
        </dependency>
    </dependencies>
    <configuration>
        <targetClasses>
            <param>{{packageRoot}}.service.*</param>
            <param>{{packageRoot}}.repository.*</param>
        </targetClasses>
        <targetTests>
            <param>{{packageRoot}}.service.*</param>
            <param>{{packageRoot}}.repository.*</param>
        </targetTests>

        <mutators><mutator>STRONGER</mutator></mutators>

        <!-- Skip classes that are mostly delegation / glue -->
        <excludedClasses>
            <param>{{packageRoot}}.service.*Notification*</param>
        </excludedClasses>

        <!-- Don't try to mutate methods Mockito/Quarkus generates -->
        <avoidCallsTo>
            <avoidCallsTo>org.jboss.logging</avoidCallsTo>
            <avoidCallsTo>io.quarkus.logging</avoidCallsTo>
            <avoidCallsTo>java.util.logging</avoidCallsTo>
            <avoidCallsTo>org.slf4j</avoidCallsTo>
        </avoidCallsTo>

        <outputFormats>
            <param>HTML</param>
            <param>XML</param>
        </outputFormats>

        <!-- Incremental analysis: skip unchanged classes -->
        <historyInputFile>${project.basedir}/.pitest/history.bin</historyInputFile>
        <historyOutputFile>${project.basedir}/.pitest/history.bin</historyOutputFile>

        <!-- Enforce minimum -->
        <mutationThreshold>{{mutationThreshold}}</mutationThreshold>
        <coverageThreshold>{{lineCovThreshold}}</coverageThreshold>

        <!-- Pitest's own test execution timeout multiplier -->
        <timeoutFactor>2.0</timeoutFactor>
        <timeoutConstant>5000</timeoutConstant>

        <!-- Parallelism -->
        <threads>4</threads>

        <!-- JUnit 5 -->
        <testPlugin>junit5</testPlugin>
    </configuration>
</plugin>
```

> Why `STRONGER` mutators: `DEFAULTS` is the original Pitest set, balanced for speed. `STRONGER` adds `NULL_RETURNS`, `EMPTY_RETURNS`, `PRIMITIVE_RETURNS`, `TRUE_RETURNS`, `FALSE_RETURNS` — these catch the "test only asserts the type" failure mode that's most common in CRUD codebases.

## `.gitignore`

```
# Pitest reports rotate each run; only the history file is worth tracking
target/pit-reports/
```

The history file (`.pitest/history.bin`) IS worth committing — it accelerates subsequent runs by an order of magnitude.

## Run locally

```bash
./mvnw test-compile org.pitest:pitest-maven:mutationCoverage
```

Open `target/pit-reports/<latest>/index.html`. Each class shows:

- **Killed mutants** (good — tests caught the change).
- **Surviving mutants** (bad — tests didn't notice).
- **No coverage** (your test never executes this line — fix by adding **any** test).
- **Timeouts** / **memory errors** (mutations introduced infinite loops; usually safe to ignore).

## What a "surviving mutant" looks like in practice

Pitest report shows:

```
src/main/java/com/quarkus/service/AlbumService.java:46

  if (size > 100) {        ←  SURVIVED:  changed condition from >  to >=
    size = 100;
  }
```

Translation: there's no test that calls `findAll(page, 100, ...)` and checks the boundary. The mutant `size > 100` → `size >= 100` would silently change behavior for `size = 100` (clamping it down to 100, which is a no-op… but only by accident). Add a boundary test.

## CI integration

Add a separate job to `.github/workflows/ci.yml`. Don't put mutation testing in the critical path — it's slow.

```yaml
  mutation-testing:
    if: github.event_name == 'push' || github.event_name == 'schedule'
    runs-on: ubuntu-latest
    services:
      postgres: { /* same as build-and-test */ }
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }   # need history for diff

      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '21', cache: maven }

      # Restore pitest history for incremental analysis
      - uses: actions/cache@v4
        with:
          path: .pitest/history.bin
          key: pitest-history-${{ runner.os }}-${{ hashFiles('src/main/**') }}
          restore-keys: pitest-history-${{ runner.os }}-

      - run: ./mvnw -B verify
      - run: ./mvnw -B test-compile org.pitest:pitest-maven:mutationCoverage

      - name: Upload Pitest report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: pitest-report
          path: target/pit-reports/
```

Also add a **scheduled** run weekly so the score is tracked across time:

```yaml
on:
  schedule:
    - cron: '0 5 * * 1'   # Mondays 05:00 UTC
```

## PR-time mode (faster — only changed classes)

For per-PR feedback, use the **scmMutationCoverage** goal which only mutates classes modified vs the base branch:

```bash
./mvnw -B test-compile org.pitest:pitest-maven:scmMutationCoverage \
  -DanalyseLastCommit=true
```

This typically completes in seconds for small PRs. Add it as a PR-time job alongside the full nightly run.

## Threshold strategy

Mutation thresholds are different from line coverage — **don't** start at 80%:

1. **Day 1**: run Pitest, note the baseline (often surprising — many "well-tested" codebases score 30-50%).
2. **First threshold**: `baseline - 5%`. Allow some headroom for fluctuation.
3. **Ratchet**: each PR can only raise the threshold, never lower it (enforce via the agent `test-quality-reviewer` or a CI check).
4. **Target**: 75% on `service/` is professional; 85% is excellent.

## Interpreting low scores per mutator type

| Mutator | Survives when... | Likely fix |
|---|---|---|
| `CONDITIONALS_BOUNDARY` (> vs >=) | Tests don't cover boundary conditions | Add boundary test cases |
| `MATH` (+ vs -) | No assertion on the computed value | Assert exact value, not just "not null" |
| `NEGATE_CONDITIONALS` (if vs if-not) | Tests only exercise the happy path | Add a negative-path test |
| `VOID_METHOD_CALLS` | Side-effecting method tested without `verify(...)` | Add Mockito verify |
| `EMPTY_RETURNS` / `NULL_RETURNS` | Returned value not asserted | Assert content, not presence |
| `INCREMENTS` (i++ vs i--) | Loop counter not asserted | Verify total iterations |

## Anti-patterns to refuse

- **Setting `mutationThreshold=0`** so it never fails. Pointless — remove the plugin instead.
- **Mutating DTOs / entities / config classes.** No logic = no value. Always scope to `service` + `repository`.
- **Running on every PR with `STRONGER` and `<threads>1</threads>`.** Builds will take 20+ minutes. Either go nightly or use `scmMutationCoverage` for PR-time.
- **Silencing surviving mutants** by adding `excludedMethods` instead of fixing tests. Use exclusions only for genuinely untestable code (e.g. `equals` / `hashCode` autogen).
- **Mixing Pitest with `org.pitest.testapi.TestPluginFactory`** custom hacks before trying `STRONGER` mutators first. Almost always overkill.

## Post-generation

- Run `./mvnw test-compile org.pitest:pitest-maven:mutationCoverage` once, even if it takes 10 minutes — establish the baseline before configuring CI.
- Open the report and walk the user through 2-3 surviving mutants. The "oh, that one was real" moment sells the rest.
- Suggest pairing with `test-quality-reviewer` agent which flags the **kinds** of weak tests Pitest tends to expose.

---

## Strategic considerations & governance

## Goal

Use mutation testing to reveal tests that execute code but do not prove behavior.

## Workflow

1. Target service and domain logic first; avoid starting with resource glue or generated code.
2. Configure PIT or the project's chosen mutation tool for focused packages.
3. Run mutation tests on a small scope before broadening.
4. Review survived mutants and classify them as weak assertion, missing branch, equivalent mutant, or low-value target.
5. Improve tests by asserting outcomes and side effects, not implementation details.
6. Set pragmatic gates only after the suite is stable.

## Review Rules

- Prioritize business rules, validation, authorization decisions, and mapping logic.
- Do not chase equivalent mutants indefinitely; document exclusions when justified.
- Mutation score is a signal, not the goal. Better tests are the goal.
- Keep mutation runs out of the fastest PR gate unless runtime is acceptable.

## Example

If changing an album year validation from `>= 1900` to `> 1900` survives, add a boundary test for year `1900` and the first valid year.
