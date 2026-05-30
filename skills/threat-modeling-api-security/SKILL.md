---
name: threat-modeling-api-security
description: "Perform threat modeling for Quarkus REST APIs using OWASP API Top 10 and STRIDE-style thinking. Use when designing or reviewing authentication, authorization, uploads, external integrations, JWT, rate limits, data exposure, privilege escalation, and abuse cases before implementation or release."
---

# threat-modeling-api-security

## Goal

Find realistic abuse paths early enough that the API design, tests, and controls can still change cheaply.

## Workflow

1. Map assets: users, roles, JWTs, images, database records, MinIO objects, external APIs, and admin operations.
2. Map trust boundaries: client to API, API to database, API to MinIO, API to external services, scheduler to services.
3. Identify threats across spoofing, tampering, repudiation, information disclosure, denial of service, and privilege escalation.
4. Tie each threat to a control: validation, RBAC, ownership checks, rate limits, safe errors, audit logs, timeouts, or tests.
5. Record residual risk and required follow-up before implementation or release.

## Review Checklist

- Authenticated users cannot act as admins or mutate resources they do not own.
- Tokens, presigned URLs, keys, and credentials cannot leak through logs, errors, or DTOs.
- Uploads validate size, MIME type, object name, and storage path.
- External integrations have timeout, retry, and data validation boundaries.
- Rate limits and abuse cases are considered for login, upload, and sync.

## Example

For image uploads, model threats for oversized files, disguised MIME types, path-like filenames, presigned URL leakage, unauthorized replacement, and orphaned MinIO objects.
