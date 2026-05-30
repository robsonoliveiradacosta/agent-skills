---
name: secrets-config-management
description: "Manage secrets and runtime configuration for Quarkus REST APIs. Use when reviewing application.properties, profiles, environment variables, JWT keys, database credentials, MinIO secrets, CORS origins, local .env files, production overrides, secret rotation, and accidental secret exposure."
---

# secrets-config-management

## Goal

Keep local development convenient while making production secrets explicit, externalized, and rotatable.

## Workflow

1. Inventory sensitive values: DB password, MinIO keys, JWT private key, external API tokens, CORS origins, and admin seed credentials.
2. Separate local defaults from production-required configuration.
3. Use environment variables or secret stores for production; do not commit real secrets.
4. Ensure `.env` files with real values are ignored and examples contain placeholders only.
5. Document rotation steps for JWT keys, database passwords, MinIO keys, and external credentials.
6. Verify logs and error responses do not expose config values.

## Rules

- Do not bake production keys into Docker images.
- Treat JWT private keys and presigned URLs as secrets.
- Prefer fail-fast startup for missing required production configuration.
- Keep `%dev`, `%test`, and `%prod` differences intentional and documented.
- Keep CORS origins narrow outside local development.

## Example

For JWT, commit only local sample keys if explicitly acceptable for development, never production keys, and document how production provides `privateKey.pem` and `publicKey.pem`.
