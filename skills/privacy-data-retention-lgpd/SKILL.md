---
name: privacy-data-retention-lgpd
description: "Review privacy, data retention, and LGPD-oriented concerns for Quarkus REST APIs. Use when identifying personal data, minimizing DTOs, avoiding PII in logs, designing deletion or anonymization, retention periods, audit data, user records, tokens, backups, and compliance-sensitive API behavior."
---

# privacy-data-retention-lgpd

## Goal

Minimize personal data exposure and make retention behavior intentional.

## Workflow

1. Identify personal, sensitive, credential, token, audit, and operational data.
2. Minimize fields in request DTOs, response DTOs, logs, metrics, and error responses.
3. Define retention and deletion behavior for users, auth records, uploaded objects, audit logs, and backups.
4. Decide when data should be deleted, anonymized, retained for legal/audit reasons, or excluded from logs.
5. Ensure API examples and seed data do not contain real personal data.
6. Review backup and restore plans for retained personal data.

## Review Rules

- Do not log passwords, tokens, private keys, full authorization headers, or unnecessary personal data.
- Keep response DTOs smaller than entities.
- Treat audit and backup retention as part of privacy design.
- Document any data that cannot be deleted immediately due to referential integrity or legal retention.
- Prefer fake data in tests, docs, and seeds.

## Example

For `User`, expose username and role only when needed; never expose password hash, token internals, or operational secrets in API responses.
