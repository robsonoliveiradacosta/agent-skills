---
name: flaky-test-triage
description: "Diagnose and fix intermittent tests in Quarkus API projects. Use when tests pass and fail unpredictably due to shared data, test order, clocks, async work, WebSocket timing, Testcontainers startup, fixed ports, race conditions, external services, or cleanup gaps."
---

# flaky-test-triage

## Goal

Turn intermittent failures into reproducible causes and stable tests.

## Workflow

1. Capture failure logs, test name, seed data, environment, timing, and recent changes.
2. Re-run the smallest failing scope repeatedly before changing code.
3. Check common causes: shared mutable data, missing cleanup, fixed ports, current time, async waits, container readiness, network calls, and test order.
4. Replace sleeps with explicit waits or deterministic synchronization.
5. Isolate data by test, clean state, or unique identifiers.
6. Add a regression assertion for the root cause when practical.

## Anti-Patterns

- Increasing timeouts without understanding the cause.
- Retrying tests in CI as the only fix.
- Depending on test method order.
- Calling real external services from tests.
- Sharing state through static mutable fields.

## Example

If a WebSocket notification test sometimes misses the message, subscribe and wait for connection acknowledgement before triggering the album creation event.
