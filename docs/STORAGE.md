# PhoneVault Storage Configuration

PhoneVault already supports an environment-configurable storage root through:

```text
PHONEVAULT_BACKUP_ROOT
```

If it is not set, normal development storage defaults to:

```text
storage/backups/
```

inside the PhoneVault repository. Set `PHONEVAULT_BACKUP_ROOT` to use another Linux directory instead.

Tests use their own temporary storage under:

```text
tmp/storage/backups/
```

## Automatic Trash retention

PhoneVault schedules a daily Solid Queue job at 3:00 a.m. The job is disabled
by default. Each user selects **Never**, 30, 60, or 90 days in Trash →
Retention Settings. Never is the initial setting. Expiration is calculated
from each backup's `deleted_at` timestamp. Set this value in `.env` to allow
the scheduled job to remove expired files:

```text
PHONEVAULT_TRASH_CLEANUP_ENABLED=true
```

Restart the production app after changing the environment. To disable automatic deletion, set
`PHONEVAULT_TRASH_CLEANUP_ENABLED=false` (or remove it) and restart.

When server-level cleanup is disabled, users can still save their preference,
but PhoneVault will show that no automatic deletion will occur. The Trash page
shows each file's days remaining and exact expiration date. When cleanup is
enabled, choosing a period first lists the files it would make eligible, and
the change must be confirmed.

Preview the eligible files without changing anything:

```bash
DRY_RUN=true bin/rails phonevault:trash:cleanup
```

Run cleanup manually by setting the enable flag to `true` for the command:

```bash
PHONEVAULT_TRASH_CLEANUP_ENABLED=true bin/rails phonevault:trash:cleanup
```

The job uses each backup run's configured server storage root and the same
path, symlink, size, and SHA-256 checks as manual permanent deletion. Failed
deletions remain in Trash and are logged for review.

## Storage Choices

| Choice                   | Example                   | Best Use                                      | Important Tradeoff                                                                |
| ------------------------ | ------------------------- | --------------------------------------------- | --------------------------------------------------------------------------------- |
| Repository-local storage | `storage/backups/`        | Development and testing                       | Application and backups can share the same physical drive                         |
| Service directory        | `/srv/phonevault/backups` | Permanent local server storage                | Still only safer from disk failure if it is backed by a different disk/filesystem |
| Mounted external drive   | `/mnt/phonevault-backups` | Separating backup bytes from the system drive | The drive must actually be mounted there and available before uploads begin       |

Example:

```text
PHONEVAULT_BACKUP_ROOT=/mnt/phonevault-backups
```

Changing the backup root changes where PhoneVault looks for backup bytes. It does **not** move files that were already stored somewhere else.

---

## Internal drive versus external drive

### Same physical disk

```text
Linux system disk
|-- PhoneVault application
|-- MySQL data
`-- backup bytes
```

This is simple, but all three share the same physical failure risk.

A disk failure, filesystem corruption, accidental formatting, OS reinstall, theft, or physical damage can affect the entire machine.

### Separate physical disk

```text
Linux system disk
|-- PhoneVault application
`-- MySQL

External HDD / SSD
`-- /mnt/phonevault-backups
    `-- backup bytes
```

This reduces the chance that one disk failure destroys both the application and the backup bytes.

It is still not complete disaster recovery. A second independent copy is recommended for important data.

---

## What `/mnt` means

`/mnt` is a conventional Linux location for mounted filesystems.

This path:

```text
/mnt/phonevault-backups
```

only represents another physical disk if another filesystem is actually mounted there.

Creating the directory by itself does not move data onto another drive.

Use Linux tools to check what backs a path:

```bash
findmnt --target /mnt/phonevault-backups
lsblk -o NAME,PKNAME,SIZE,FSTYPE,MOUNTPOINTS
```

Replace the example path with your configured location.

---

## Storage permissions

The Linux user running Rails must be able to create directories and files inside the configured backup root.

PhoneVault's storage service currently creates new storage directories and backup files with restrictive permissions where supported:

| Item               | Requested permissions |
| ------------------ | --------------------- |
| Backup directories | `0700`                |
| Backup files       | `0600`                |

Do not make the backup directory world-writable just to work around permission problems.

Do not run Rails as root simply to bypass filesystem permissions.

---

## Missing external disks

PhoneVault does not yet verify that a specific physical disk is mounted before accepting uploads.

This still needs to be solved:

```text
expected:
external drive mounted at /mnt/phonevault-backups

after reboot:
drive fails to mount
        |
        v
/mnt/phonevault-backups may exist on the system disk
```

A future storage check should detect this and refuse to silently write to the wrong filesystem.

---

# Docker Storage

When Rails runs on the host, `PHONEVAULT_BACKUP_ROOT` is simply a host path and no bind mount is needed.

## Containerized Rails setup

When Rails runs in Docker (`python3 launch.py`, or `docker compose --profile app up -d`), the storage setup is:

```text
Linux host
/mnt/phonevault-backups
        |
        | Docker bind mount
        v
Rails container
/rails/storage/backups
        |
        v
BackupStorage
```

The host path decides where the bytes physically live.

The container path gives Rails a stable internal location.

In Docker, `PHONEVAULT_BACKUP_ROOT` in `.env` names the host folder; Compose mounts it at `/rails/storage/backups` and tells Rails to use that path.