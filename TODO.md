# PhoneVault Development Checklist

This document tracks completed development milestones, planned improvements,
and features being considered for future versions of PhoneVault.

## Database Design

- [x] Finalize the working database schema.
- [x] Identify primary keys and foreign keys.
- [x] Create the EER diagram.
- [x] Define integrity constraints.
- [x] Test the schema in MySQL.
- [x] Document the database design.
- [x] Add realistic sample data where it is useful for demos/testing.

## Development Environment and Setup

- [x] Run MySQL through Docker Compose.
- [x] Connect Rails to MySQL.
- [x] Document required host/runtime dependencies.
- [x] Track required packages such as MySQL client headers and libvips.
- [x] Keep secrets and local configuration out of Git.
- [x] Document the current manual setup process.
- [x] Add `PHONEVAULT_BACKUP_ROOT` to `.env.example`.
- [x] Test setup from a completely fresh Linux clone.
- [x] Test setup on another Linux machine.
- [x] Fix any README commands that fail during a fresh setup.

## Authentication and Security

- [x] Add local username/password authentication.
- [x] Store passwords as secure hashes.
- [x] Add login and logout.
- [x] Protect authenticated pages by default.
- [x] Prevent users from accessing devices/backups they do not own.
- [x] Validate storage paths and reject traversal and symlink escapes.
- [x] Create private backup files.
- [x] Run Brakeman security scanning in CI.
- [x] Add login rate limiting.
- [x] Add automatic security-event logging.
- [x] Show each user their own activity, with warnings highlighted.
- [x] Limit the size of stored uploads with `PHONEVAULT_MAX_UPLOAD_MB`.
- [ ] Reject oversized upload requests before Rails receives the whole body.
- [ ] Decide whether to log `AUTHORIZATION_DENIED` for requests to records the user does not own.
- [x] Record which device, backup run, or file a security event is about.
- [ ] Research 2FA.
- [ ] Research recovery codes.
- [ ] Research device API tokens.

## Device Management

- [x] Add device registration.
- [x] Associate devices with users.
- [x] Display registered devices.
- [x] Add navigation to device backups and uploads.
- [x] Allow devices to be renamed.
- [ ] Eventually expose device/client API credentials if automatic clients are added.

## Backup System

- [x] Accept a file upload through the browser.
- [x] Create backup run records.
- [x] Add persistent local file storage.
- [x] Store file metadata in MySQL.
- [x] Calculate SHA-256 hashes while storing files.
- [x] Record file sizes.
- [x] Associate backup files with backup runs.
- [x] Track successful and failed backup runs.
- [x] Use readable device folders and safe filenames.
- [x] Let users choose any writable server folder for a backup.
- [x] Use partial files before publishing a completed backup.
- [x] Prevent existing completed backup files from being overwritten.
- [x] Move deleted backups to Trash, with recovery and permanent deletion.
- [x] Add per-user Trash retention with an opt-in scheduled cleanup.

## Restore System

- [x] Display backup history.
- [x] Restore individual backup files through the browser.
- [x] Scope restore requests through the current user's device and backup run.
- [x] Verify restored files using file size and SHA-256.
- [x] Handle missing stored files.
- [x] Handle corrupted stored files.
- [x] Improve backup-history presentation and file details.
- [x] Verify the complete browser backup -> restore workflow from a fresh installation.

## Storage Configuration and Dashboard

- [x] Support `PHONEVAULT_BACKUP_ROOT`.
- [x] Store backup bytes separately from MySQL metadata.
- [x] Document local, `/srv`, and `/mnt` storage choices.
- [x] Explain the difference between another directory and another physical disk.
- [ ] Decide on the recommended permanent Linux storage directory.
- [ ] Detect/report unavailable storage.
- [ ] Detect a missing external mount and refuse uploads instead of falling back to the system disk.
- [ ] Improve errors when an external disk is disconnected.
- [ ] Research startup ordering when an external disk mounts after boot.
- [ ] Display total, used, and available disk capacity.
- [x] Display PhoneVault storage usage.
- [x] Display the number of stored backup files.
- [ ] Build the storage dashboard.
- [x] Support Docker host bind mounts when Rails becomes part of the supported container deployment.

## Testing and Reliability

- [x] Add Minitest tests.
- [x] Test database models and relationships.
- [x] Test password authentication.
- [x] Test authorization/ownership.
- [x] Test file uploads.
- [x] Test backup creation.
- [x] Test file restoration.
- [x] Test SHA-256 verification.
- [x] Test size verification.
- [x] Test failed backup scenarios.
- [x] Test path traversal protection.
- [x] Test symlink escape protection.
- [x] Test partial- and completed-file collision protection.
- [x] Test private file permissions.

## Linux Deployment and Remote Access

- [x] Document the Linux setup procedure.
- [x] Run PhoneVault on a dedicated Linux machine.
- [x] Add optional Tailscale access.
- [x] Verify PhoneVault through Tailscale.
- [x] Keep MySQL bound locally rather than exposing it directly to the public internet.
- [x] Decide on the permanent deployment method.
- [x] Add automatic startup after Linux reboot.
- [x] Verify MySQL readiness before Rails depends on it.
- [x] Evaluate Docker restart policies.
- [x] Evaluate systemd where appropriate (not needed; Docker restart policies cover it).
- [x] Test a full reboot and confirm PhoneVault returns with the correct storage.
- [x] Test access from another laptop.
- [x] Test browser access from a phone.
- [x] Keep Tailscale optional.

## Disaster Recovery

- [x] Document that one server or disk can still fail.
- [x] Explain the benefit of separating backup bytes onto another physical disk.
- [ ] Research Restic for PhoneVault disaster recovery.
- [ ] Research another independent/off-site backup copy.
- [ ] Document how to rebuild PhoneVault from a MySQL backup plus the backup bytes after losing the server.

## Documentation and Due Diligence

- [x] Document installation.
- [x] Document backup and restore.
- [x] Document the database.
- [x] Document local database binding.
- [x] Document storage safeguards.
- [x] Document troubleshooting.
- [ ] Verify every setup command on a fresh Linux machine.
- [ ] Continue cleaning old development files/scripts.
- [x] Document the final production deployment method.

## V3 — Background Jobs

- [x] Introduce Solid Queue (it runs the daily Trash retention cleanup).
- [ ] Move appropriate backup processing out of the web request.
- [ ] Compare background-job behavior with the current synchronous flow.
- [ ] Later experiment with Redis / Sidekiq for comparison.

## V3 — Storage Backends

- [ ] Create a storage abstraction.
- [ ] Keep local filesystem storage as the simple default.
- [ ] Add optional MinIO / S3-compatible storage.
- [ ] Keep advanced storage optional.

## V3 — Disaster Recovery and Monitoring

- [ ] Research Prometheus metrics.
- [ ] Add Grafana when useful operational metrics exist.
- [ ] Keep monitoring optional for the basic PhoneVault install.

## Future Clients

- [ ] Design a PhoneVault API for client uploads.
- [ ] Research a Linux backup client/agent.
- [ ] Research Android background uploads.
- [ ] Research iOS background uploads.
- [ ] Research automatic synchronization.
- [ ] Keep manual browser uploads supported.

## Future Research

- [ ] File deduplication.
- [ ] Encryption improvements.
- [ ] WebDAV.
- [ ] CalDAV.
- [ ] CardDAV.
- [ ] Security-event analytics.
- [ ] Large synthetic backup datasets.
- [ ] PySpark experiments only if the project reaches a scale where they are useful.
- [ ] Duress-mode concepts as research only.