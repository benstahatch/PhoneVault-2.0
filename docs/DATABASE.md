# Database

The working schema is centered around these tables:

```text
USERS
  |
  | 1:N
  v
DEVICES
  |
  | 1:N
  v
BACKUP_RUNS
  |
  | 1:N
  v
BACKUP_FILES

USERS
  |
  | 1:N
  v
SECURITY_EVENTS
```

## Database Relationships

- One USER can have many DEVICES.
- One DEVICE can have many BACKUP_RUNS.
- One BACKUP_RUN can have many BACKUP_FILES.
- One USER can have many SECURITY_EVENTS.

These are one-to-many (`1:N`) relationships.

**PK = Primary Key:** uniquely identifies a row in a table.

**FK = Foreign Key:** connects a row to another table.

Example:

```text
devices.user_id -> users.id
```

## Users

Local PhoneVault accounts.

Current schema fields:

- `id` _(PK)_
- `username`
- `display_name`
- `password_digest`
- `trash_retention_days` _(30, 60, or 90; blank means Never)_
- `created_at`
- `updated_at`

## Devices

Devices registered to a user.

Current schema fields:

- `id` _(PK)_
- `user_id` _(FK -> users.id)_
- `name`
- `device_type`
- `created_at`
- `updated_at`

## Backup Runs

Individual backup attempts.

Current schema fields:

- `id` _(PK)_
- `device_id` _(FK -> devices.id)_
- `storage_root` _(saved absolute destination; blank means the default backup root)_
- `status`
- `started_at`
- `completed_at`
- `created_at`
- `updated_at`

## Backup Files

Metadata for files included in a backup.

Current schema fields:

- `id` _(PK)_
- `backup_run_id` _(FK -> backup_runs.id)_
- `original_filename`
- `storage_path`
- `size_bytes`
- `sha256`
- `deleted_at` _(set when moved to Trash; blank means active)_
- `created_at`
- `updated_at`

## Security Events

Security-related activity that can be recorded by the application.

Current schema fields:

- `id` _(PK)_
- `user_id` _(FK -> users.id, nullable)_
- `event_type`
- `ip_address`
- `subject_type`, `subject_id` _(which device, backup run, or file the event is about; nullable)_
- `details` _(a short readable summary, up to 255 characters)_
- `created_at`

Events are recorded automatically with the user (when known) and the request's IP address. Events about a device, backup run, or file also save that record as the **subject**, plus a **details** snapshot:

| Event | Recorded when | Subject | Example details |
| --- | --- | --- | --- |
| `LOGIN_SUCCESS` | A user logs in. | | |
| `LOGIN_FAILED` | A login fails. Linked to the targeted account when the username exists, otherwise saved with no user. | | |
| `LOGIN_RATE_LIMITED` | A login attempt is blocked by the rate limit (10 attempts per IP address every 3 minutes). | | |
| `LOGOUT` | A user logs out. | | |
| `ACCOUNT_CREATED` | A new account is created through signup. | | |
| `DEVICE_REGISTERED` | A device is saved successfully. | Device | `Jordan's iPhone (phone)` |
| `DEVICE_RENAMED` | A user changes the name of one of their devices. | Device | `Old Phone → Jordan's iPhone` |
| `BACKUP_SUCCESS` | An uploaded file is stored and its backup run is marked completed. | Backup file | `IMG_2041.png to Jordan's iPhone` |
| `BACKUP_FAILED` | Storing an uploaded file fails (including uploads over the size limit) and its backup run is marked failed. | Backup run | `video.mov to Jordan's iPhone (over the size limit)` |
| `FILE_RESTORED` | A file passes its size and SHA-256 checks and is sent for download. | Backup file | `IMG_2041.png from Jordan's iPhone` |
| `FILE_TRASHED` | A user moves a file to Trash. | Backup file | `IMG_2041.png from Jordan's iPhone` |
| `FILE_RECOVERED_FROM_TRASH` | A user recovers a file from Trash. | Backup file | `IMG_2041.png from Jordan's iPhone` |
| `FILE_PERMANENTLY_DELETED` | A user deletes a file from Trash, or the retention cleanup removes it. | Backup file | `IMG_2041.png from Jordan's iPhone` |
| `RESTORE_FILE_MISSING` | A restore is requested but the file is missing from storage. | Backup file | `IMG_2041.png from Jordan's iPhone` |
| `RESTORE_FILE_CORRUPTED` | A restore is requested but the file fails SHA-256 verification. | Backup file | `IMG_2041.png from Jordan's iPhone` |

The subject has no foreign key on purpose. A security log should keep every row, so deleting a device or file never deletes or blocks its events. The `subject_type`/`subject_id` pair still records what it pointed at. Details are written when the event happens, so a later rename doesn't change what an old event says. Login details never include what was typed, because people sometimes type a password into the username field.

Each user can see their own events on the **Activity** page (`/activity`, linked in the header): the latest 100, newest first, in plain words with their details and IP address. Failed sign-ins, failed backups, and failed restores are highlighted in red. Events with no user, such as failed logins for usernames that don't exist, aren't shown to anyone.

Not recorded yet:

- `AUTHORIZATION_DENIED`: requests for another user's records already return 404, but are not logged. Rails cannot tell those apart from IDs that simply don't exist without an extra lookup.



## Database Constraints and Validation

- every table has a primary key
- foreign keys maintain relationships between tables
- usernames are unique
- every device belongs to a valid user
- every backup run belongs to a valid device
- every backup file belongs to a valid backup run
- required values use NOT NULL where appropriate
- file sizes cannot be negative
- SHA-256 values are validated by the Rails model
- destructive deletes must be handled carefully so backup history is not accidentally removed

Required columns and foreign keys are defined in `db/schema.rb`.

SHA-256 format and nonnegative file sizes are enforced by Rails model validation rather than SQL CHECK constraints.