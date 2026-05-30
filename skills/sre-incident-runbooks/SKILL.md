---
name: sre-incident-runbooks
description: "Create SRE incident runbooks for Quarkus REST APIs and supporting services. Use when documenting response steps for API outage, PostgreSQL unavailable, MinIO failures, JWT/key issues, failed migrations, high latency, external API failures, elevated errors, and post-incident follow-up."
---

# sre-incident-runbooks

## Goal

Make incident response repeatable, fast, and less dependent on tribal knowledge.

## Workflow

1. Define the incident trigger, customer impact, severity, and immediate safety checks.
2. List diagnostics: health endpoints, logs, metrics, Docker Compose status, database checks, MinIO checks, and recent deploys.
3. Provide mitigation steps before root-cause investigation.
4. Include rollback or failover steps when applicable.
5. Add verification steps that prove recovery.
6. Add post-incident tasks: timeline, root cause, corrective actions, and follow-up owners.

## Runbook Template

- Symptoms and alerts.
- Impact and severity.
- First checks.
- Mitigation.
- Deep diagnostics.
- Recovery verification.
- Escalation contacts or owners.
- Post-incident actions.

## Example

For PostgreSQL unavailable, check `/q/health/ready`, container or service status, connection pool errors, recent migrations, disk space, credentials, and whether rollback or restore is required.
