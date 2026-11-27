# Backup and Restore

This document explains how PhoneVault stores uploaded files,
records backup information, and verifies files during restoration.

## Backup Flow

```text
Select Device
      |
      v
Create Backup Run
      |
      v
Upload File
      |
      v
Generate server-controlled storage path
      |
      v
Stream file to storage
      |
      +--> calculate SHA-256
      |
      +--> count size in bytes
      |
      +--> stop and delete the partial file if over the upload size limit
      |
      v
Save metadata in MySQL
      |
      v
Mark Backup Complete
```

## Choosing a save folder

**Save path** on the upload form accepts any existing server folder PhoneVault can write to, and starts at your default folder (`<backup root>/users/<your id>`). **Browse folders** picks a directory without clearing the chosen file, and **Test path** checks write access.

Files are stored as `<Device>-Backups/<filename>` inside that folder, such as `Benji-Backups/photo.jpeg`. Unsafe characters are sanitized, and a repeated name gets a numbered suffix such as `photo (2).jpeg` instead of overwriting the earlier backup.

Each backup run remembers its folder, so keep that path available when moving the server. In Docker, choose a mounted container path (the default is `/rails/storage/backups`); additional host folders need a volume mount and write permission for UID 1000.

## Upload size limit

PhoneVault refuses to store uploads larger than `PHONEVAULT_MAX_UPLOAD_MB` megabytes (10 GB when unset). The value must be a positive whole number; anything else makes uploads fail instead of silently allowing any size.

```text
PHONEVAULT_MAX_UPLOAD_MB=2048
```

The limit protects the backup disk, but Rails has already received the whole upload into a temporary file before PhoneVault checks it. Stopping oversized requests earlier needs a web server or reverse proxy limit.

---

# Restore Flow

```text
Choose Backup
      |
      v
Find file through the logged-in user's device
      |
      v
Validate storage path
      |
      v
Check real filesystem location
      |
      v
Verify size
      |
      v
Verify SHA-256
      |
      v
Download restored file
```

PhoneVault refuses a normal restore if the stored file is missing, corrupted, outside the configured backup root, or resolves outside the root through a symlink.