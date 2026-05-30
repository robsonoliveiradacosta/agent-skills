---
name: dependency-supply-chain-security
description: "Review Maven and Docker supply chain security for Quarkus APIs. Use when auditing dependencies, transitive packages, CVEs, vulnerable base images, SBOMs, license risk, dependency updates, pinned versions, plugin versions, and CI security gates."
---

# dependency-supply-chain-security

## Goal

Reduce risk from third-party code, plugins, container images, and build tooling.

## Workflow

1. Inventory Maven dependencies, plugins, Docker base images, and generated artifacts.
2. Identify direct and transitive dependencies that affect runtime, security, or licensing.
3. Check for known vulnerabilities and upgrade paths.
4. Prefer BOM-managed versions where Quarkus provides them; pin explicit versions when required.
5. Review Docker base images for freshness, size, user permissions, and vulnerability exposure.
6. Add CI checks for dependency and image scanning when available.

## Review Rules

- Do not upgrade critical dependencies without running tests.
- Avoid unused dependencies and duplicate libraries.
- Treat build plugins as supply chain risk, not just development tooling.
- Record exceptions with severity, rationale, owner, and review date.
- Generate or preserve SBOM artifacts when release policy requires them.

## Example

For a MinIO client upgrade, check Quarkus extension compatibility, transitive dependency changes, CVEs, upload tests, and container build behavior.
