---
name: backup-restore-disaster-recovery
description: "Plan backup, restore, rollback, and disaster recovery for Quarkus APIs using PostgreSQL and MinIO. Use when defining RPO, RTO, database backups, object storage backups, restore drills, migration rollback, release recovery, data-loss scenarios, and operational recovery checklists."
---

# backup-restore-disaster-recovery

## Goal

Ensure critical data can be recovered, not merely backed up.

## Workflow

1. Define RPO and RTO for PostgreSQL data, MinIO objects, and configuration.
2. Inventory what must be backed up: database, object buckets, JWT keys, environment config, migration history, and release artifacts.
3. Define backup frequency, retention, encryption, access control, and storage location.
4. Create restore drills that verify application health and data correctness after restore.
5. Plan recovery from failed migrations, bad deployments, object loss, and credential compromise.
6. Record manual steps, owners, and validation commands.

## Recovery Rules

- A backup is not valid until a restore has been tested.
- Keep database and object storage recovery points consistent when records reference objects.
- Document when rollback is impossible after destructive migrations.
- Protect backup credentials as production secrets.
- Include post-restore checks for `/q/health`, login, key endpoints, and object access.

## Example

For album images, restore must validate both `album_images` metadata in PostgreSQL and referenced objects in the MinIO bucket.
