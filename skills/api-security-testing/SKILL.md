---
name: api-security-testing
description: "Design security-focused tests for professional REST APIs. Use when testing JWT, RBAC, authorization bypass, token tampering, rate limiting, input validation, injection risk, upload safety, sensitive data exposure, CORS behavior, and OWASP API Top 10 controls."
---

# api-security-testing

## Goal

Prove that the API rejects unauthorized, malformed, abusive, and malicious requests.

## Workflow

1. Map endpoints by role: public, authenticated user, admin, internal, or scheduled.
2. Test missing, expired, malformed, tampered, and wrong-role JWTs.
3. Test object-level authorization when users can access only their own resources.
4. Exercise validation boundaries: long strings, nulls, unexpected enum values, path traversal, SQL-like input, and malformed JSON.
5. Test upload safety: MIME type, extension, file size, object key generation, and presigned URL leakage.
6. Verify rate limits and generic auth errors where configured.

## Required Cases

- `401` without token for protected endpoints.
- `403` with valid token but insufficient role.
- Rejected tampered JWT signature or claims.
- No sensitive data in errors, logs, or response DTOs.
- Admin-only mutations blocked for regular users.

## Example

For image upload, test anonymous `401`, user `403` if admin-only, oversized file `413`, invalid MIME `400`, path-like filename ignored, and no MinIO credentials in any response.
