---
name: transaction-boundary-design
description: "Design transaction boundaries for Quarkus services using Hibernate ORM and Panache. Use when deciding @Transactional placement, rollback behavior, consistency, long-running operations, remote calls, file storage, event publication, retries, and service method atomicity."
---

# transaction-boundary-design

## Goal

Keep data changes atomic without making transactions long, leaky, or coupled to unreliable remote work.

## Workflow

1. Define the invariant that must be committed atomically.
2. Put `@Transactional` on service methods that perform coordinated writes.
3. Keep resource methods thin and avoid transaction logic in REST classes.
4. Do validation and existence checks before mutations when possible.
5. Avoid remote HTTP calls, MinIO uploads, and slow IO inside database transactions unless consistency requires a compensating design.
6. Define rollback behavior for domain exceptions, persistence errors, and external failures.

## Design Rules

- Read-only methods usually do not need a write transaction.
- Keep transaction scope small and explicit.
- Publish WebSocket or integration events after persistence succeeds when possible.
- For multi-resource work such as DB plus object storage, document compensation or cleanup behavior.
- Test rollback for the failure paths that matter.

## Example

For image upload metadata, avoid holding a database transaction while streaming a large file to MinIO. Persist metadata only after storage succeeds, or add cleanup for orphaned objects if the database write fails.
