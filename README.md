# PhoneVault

PhoneVault is a self-hosted backup project built around Ruby on Rails, MySQL, Docker, and Linux.

The long-term idea is to provide a simple way for someone to run their own private backup server on their own hardware. The first version is intentionally small: get the database, application, storage, and restore pipeline working well before adding more advanced features.

---

# Current Goal — v0.1

PhoneVault v0.1 should be able to:

- [x] Run on a Linux machine.
- [x] Use a local username and password.
- [x] Register one or more personal devices.
- [x] Upload and store individual files through the browser.
- [x] Calculate a SHA-256 hash for stored files.
- [x] Store file and backup metadata in MySQL.
- [x] Track completed and failed backup attempts.
- [x] Restore individual files through the browser.
- [x] Verify stored file size and SHA-256 before downloading a restore.
- [x] Prevent users from restoring backup files that belong to another user.
- [x] Reject invalid storage paths and symlink escapes outside the backup root.

**Current scope:** PhoneVault currently performs manual, single-file browser backups. Registering a device creates an organizational record inside PhoneVault; it does not install an agent on that device or automatically copy files from it.

Automatic phone synchronization, scheduled backups, additional storage backends, and a complete production installer are future work.

---

# Tech Stack

| Component           | Current Role                                                                         |
| ------------------- | ------------------------------------------------------------------------------------ |
| Ruby 3.4.10         | Application language                                                                 |
| Ruby on Rails 8.1.4 | Web application framework                                                            |
| MySQL 8.4           | Stores users, devices, backup runs, file metadata, hashes, and other structured data |
| Docker              | Runs MySQL in development                                                            |
| Docker Compose      | Starts and configures the development database                                       |
| Linux               | Current server/development host                                                      |
| Minitest            | Automated Rails testing                                                              |
| RuboCop             | Ruby style and lint checks                                                           |
| Brakeman            | Rails security scanning                                                              |
| Tailscale           | Optional private remote access between trusted devices                               |

## Planned / Later

- Solid Queue for background backup jobs
- Storage abstraction for multiple storage backends
- MinIO / S3-compatible storage
- Restic for disaster recovery
- Prometheus and Grafana for monitoring
- Redis / Sidekiq as a later comparison experiment
- Python / PySpark only for later analytics experiments

---

# Architecture

```text
Browser / Client
      |
      v
Ruby on Rails
      |
      +---------------------+
      |                     |
      v                     v
    MySQL             Backup Storage
   metadata             actual bytes
```

MySQL stores structured data such as:

- users
- devices
- backup runs
- file metadata
- SHA-256 hashes
- timestamps
- security event records

The actual photos, videos, documents, and other uploaded files are stored separately on persistent storage.

This separation is intentional. MySQL describes the backup; backup storage contains the actual bytes.

---

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
- `created_at`
- `updated_at`

## Security Events

Security-related activity that can be recorded by the application.

Current schema fields:

- `id` _(PK)_
- `user_id` _(FK -> users.id, nullable)_
- `event_type`
- `ip_address`
- `created_at`

The model exists, but automatic event logging is still incomplete.

Possible event types include:

- `LOGIN_SUCCESS`
- `LOGIN_FAILED`
- `LOGOUT`
- `BACKUP_SUCCESS`
- `BACKUP_FAILED`
- `FILE_RESTORED`
- `AUTHORIZATION_DENIED`
- `DEVICE_REGISTERED`
- `RESTORE_FAILED`

---

# Basic Database Protocols / Constraints

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

---

# Informal Queries

Some questions PhoneVault should be able to answer:

- What devices belong to a user?
- What backups belong to a device?
- What files belong to a backup run?
- Which backup runs failed?
- How much storage is a device using?
- What security events belong to a user?
- Does a file with a specific SHA-256 hash exist?
- How many files were stored during a backup run?

---

# Backup Flow

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
      v
Save metadata in MySQL
      |
      v
Mark Backup Complete
```

PhoneVault does not use the uploaded filename as the real filesystem path. The original filename is stored as metadata while the file on disk uses a generated UUID.

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

---

# Local Development

The current developm[118;1:3uent setup is:

```text
Linux host
  |
  +-- Ruby on Rails runs directly on Linux
  |
  +-- uploaded backup files live on Linux storage
  |
  `-- Docker Compose runs MySQL
```

The current Compose setup starts the database. Rails itself is still started from the Linux host.

This is a development setup, not a finished always-on production deployment.

> **Storage safety:** Self-hosting gives you control over your backups, but control is not the same as redundancy. Any computer or drive can fail, be reformatted, become corrupted, be stolen, or be damaged. Keep another independent copy of important data.

---

## 1. Prerequisites

| Component                        | Installation and purpose                                | Documentation                                                                                                           |
| -------------------------------- | ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Git                              | Clone the repository.                                   | [Install Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)                                            |
| Ruby 3.4.10                      | Runs the Rails application and matches `.ruby-version`. | [Ruby installation](https://www.ruby-lang.org/en/documentation/installation/) / [rbenv](https://github.com/rbenv/rbenv) |
| Bundler                          | Installs the Ruby gems in `Gemfile.lock`.               | [Bundler](https://bundler.io/)                                                                                          |
| Rails application gems           | Installed with `bundle install`.                        | [Rails installation guide](https://guides.rubyonrails.org/install_ruby_on_rails.html)                                   |
| Docker Engine                    | Runs the MySQL container.                               | [Docker Engine](https://docs.docker.com/engine/install/)                                                                |
| Docker Compose                   | Starts and manages the development database service.    | [Docker Compose](https://docs.docker.com/compose/)                                                                      |
| MySQL client development headers | Needed to compile the `mysql2` gem.                     | [mysql2](https://github.com/brianmario/mysql2)                                                                          |
| Build tools                      | Needed for Ruby and native gems.                        | [ruby-build dependencies](https://github.com/rbenv/ruby-build/wiki)                                                     |
| libvips                          | Required by image-processing dependencies.              | [libvips](https://www.libvips.org/install.html)                                                                         |
| Tailscale                        | Optional private remote access.                         | [Tailscale](https://tailscale.com/download/linux)                                                                       |

Python, PySpark, Node.js, Redis, MinIO, Restic, Prometheus, and Grafana are not required for the current browser-based setup.

---

## 2. Install Linux packages

On Ubuntu/Debian, the development dependencies include:

```bash
sudo apt-get update
sudo apt-get install -y git curl ca-certificates build-essential autoconf \
  libssl-dev libyaml-dev zlib1g-dev libreadline-dev libffi-dev \
  libgmp-dev rustc pkg-config default-libmysqlclient-dev libvips-dev
```

Other Linux distributions should use equivalent packages from their own package manager.

---

## 3. Install Docker Engine and Compose

Follow Docker's official installation instructions for your Linux distribution.

After Docker is installed, verify it:

```bash
sudo systemctl enable --now docker
sudo docker run --rm hello-world
sudo docker compose version
```

If your account is configured to use Docker without `sudo`, the same project commands can be run without it.

---

## 4. Clone PhoneVault

```bash
git clone https://github.com/benstahatch/PhoneVault-2.0.git
cd PhoneVault-2.0
```

---

## 5. Install Ruby and Bundler

Make sure the Ruby version matches `.ruby-version`.

If you use rbenv:

```bash
rbenv install -s "$(cat .ruby-version)"
ruby --version
```

Then install Bundler and the project gems:

```bash
gem install bundler
bundle install
```

Confirm Rails is available:

```bash
bin/rails --version
```

Do not use `sudo` for Ruby, Bundler, or Rails commands when using a user-level Ruby installation such as rbenv.

---

## 6. Configure the application

Create your local environment file:

```bash
cp .env.example .env
chmod 600 .env
```

Edit `.env` and configure the database values.

| Setting                  | Typical development value | Purpose                                           |
| ------------------------ | ------------------------- | ------------------------------------------------- |
| `MYSQL_ROOT_PASSWORD`    | Replace the example value | MySQL administrator password                      |
| `MYSQL_DATABASE`         | `phonevault2`             | Main PhoneVault development database              |
| `MYSQL_USER`             | `phonevault2`             | MySQL account used by Rails                       |
| `MYSQL_PASSWORD`         | Replace the example value | Password for the Rails database account           |
| `MYSQL_HOST_PORT`        | `3308`                    | Host port mapped to MySQL container port `3306`   |
| `DB_HOST`                | `127.0.0.1` when used     | Database host for Rails                           |
| `PHONEVAULT_BACKUP_ROOT` | Optional                  | Absolute path where backup bytes should be stored |

Keep `.env` private. Do not commit real passwords or credentials.

---

# Backup Storage Configuration

PhoneVault already supports an environment-configurable storage root through:

```text
PHONEVAULT_BACKUP_ROOT
```

If it is not set, normal development storage defaults to:

```text
storage/backups/
```

inside the PhoneVault repository.

Tests use their own temporary storage under:

```text
tmp/storage/backups/
```

You can point PhoneVault at another Linux directory without changing Ruby source code.

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

# Docker Storage: Current and Future

## Current setup

Rails currently runs directly on Linux.

MySQL runs in Docker.

Therefore:

```text
PHONEVAULT_BACKUP_ROOT=/mnt/phonevault-backups
```

currently refers directly to that Linux host path.

No Docker bind mount is required for Rails because Rails is not currently running inside a container.

## Future containerized Rails setup

If Rails becomes part of the supported Docker Compose deployment, the desired storage setup is:

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

This is future work. The current development Compose setup should not be described as if it already provides this bind mount.

---

# Start MySQL

From the PhoneVault repository:

```bash
docker compose up -d db
```

Check the service:

```bash
docker compose ps
```

If needed, inspect the database logs:

```bash
docker compose logs --tail=100 db
```

Then prepare the Rails database:

```bash
bin/rails db:prepare
```

The main development mapping is:

```text
127.0.0.1:3308 -> MySQL container:3306
```

This keeps MySQL available to the local PhoneVault host without exposing it directly on every network interface.

---

# Start PhoneVault

## Local-only access

```bash
bin/rails server -b 127.0.0.1
```

Open:

```text
http://127.0.0.1:3000
```

## LAN or Tailscale access

```bash
bin/rails server -b 0.0.0.0
```

`0.0.0.0` tells Rails to listen on the machine's available IPv4 network interfaces.

Use the server's real LAN or Tailscale address in the browser.

---

# First Backup Test

After Rails is running:

1. Sign up or sign in.
2. Open **Your devices**.
3. Register a device.
4. Select **Upload** for that device.
5. Upload a small test file.
6. Confirm the backup is listed as completed.
7. Open the backup history.
8. Select **Restore**.
9. Compare the restored file with the original.

On Linux:

```bash
sha256sum /path/to/original-file /path/to/restored-file
```

The hashes should match.

---

# Optional Tailscale Access

Tailscale is optional.

PhoneVault should still work through localhost or a trusted LAN without it.

Tailscale is useful when the PhoneVault Linux server stays at home and you want to reach it privately from another laptop or phone.

```text
Mac / laptop / phone
        |
        | private Tailscale network
        v
Linux PhoneVault server
        |
        +-- SSH :22
        `-- Rails :3000
```

## 1. Install Tailscale on the Linux server

Follow Tailscale's Linux installation instructions.

After installation:

```bash
sudo tailscale up
```

Complete the authentication step.

Then check the server's Tailscale address and connection status:

```bash
tailscale ip -4
tailscale status
```

A Tailscale IPv4 address normally looks similar to:

```text
100.x.x.x
```

---

## 2. Install Tailscale on the client

Install Tailscale on the Mac, laptop, or phone that should connect to PhoneVault.

Sign into the same Tailscale network and enable the connection.

---

## 3. Start Rails for remote access

On the Linux PhoneVault server:

```bash
bin/rails server -b 0.0.0.0
```

Then open:

```text
http://100.x.x.x:3000
```

using the server's actual Tailscale address from:

```bash
tailscale ip -4
```

PhoneVault authentication is still required. Tailscale does not replace the PhoneVault username/password system.

---

## Tailscale and public exposure

Binding Rails to:

```text
0.0.0.0
```

means Rails listens on more than localhost.

For the current project, use trusted LAN/Tailscale access and appropriate firewall rules.

Do not port-forward the Rails development server directly to the public internet.

A future public deployment should use a proper production server/reverse proxy and TLS.

---

# Manual Startup vs Automatic Startup

## Currently supported

PhoneVault is currently started manually.

| Stage          | Command or action                               | Ready when                                           |
| -------------- | ----------------------------------------------- | ---------------------------------------------------- |
| Database       | `docker compose up -d db`                       | The MySQL container is running and ready             |
| Rails database | `bin/rails db:prepare`                          | The command completes without error                  |
| Application    | `bin/rails server -b 127.0.0.1` or `-b 0.0.0.0` | Rails reports that it is listening on port `3000`    |
| Browser        | Open the matching Linux/LAN/Tailscale address   | Login, device registration, upload, and restore work |

Manual startup is useful during development because logs remain visible and services are easy to restart.

## Planned permanent deployment

A permanent PhoneVault server should eventually recover automatically after a reboot.

```text
machine boots
     |
     v
backup disk mounts
     |
     v
Docker / MySQL starts
     |
     v
database becomes ready
     |
     v
Rails starts
     |
     v
PhoneVault becomes available
```

Possible approaches include:

- Docker restart policies
- Docker Compose startup
- systemd

The final deployment method has not been chosen yet.

The configured backup storage should be verified before PhoneVault begins accepting uploads.

---

# Storage and Persistence

| Data                               | Current location                               | What must be preserved                                  |
| ---------------------------------- | ---------------------------------------------- | ------------------------------------------------------- |
| Accounts, devices, backup metadata | MySQL Docker volume                            | A consistent MySQL backup                               |
| Uploaded backup bytes              | `storage/backups/` or `PHONEVAULT_BACKUP_ROOT` | The complete backup directory tree                      |
| Local configuration                | `.env`                                         | A secure copy of configuration and database credentials |

A usable server recovery needs both:

```text
MySQL metadata
      +
backup bytes
```

A Git clone by itself does not restore either.

---

# Stop and Restart

Stop Rails with:

```text
Ctrl+C
```

Stop the database container:

```bash
docker compose down
```

Start MySQL again:

```bash
docker compose up -d db
```

Normal `docker compose down` keeps the named MySQL volume.

Do not use:

```bash
docker compose down -v
```

unless you intentionally want to remove Docker volumes.

---

# Testing

Run the Rails test suite:

```bash
bin/rails test
```

Run Ruby style checks:

```bash
bin/rubocop
```

Run the Rails security scanner:

```bash
bin/brakeman --no-pager
```

PhoneVault currently includes tests for:

- models and relationships
- authentication behavior
- device ownership
- uploads
- backup runs
- restore responses
- missing stored files
- corrupted stored files
- SHA-256 verification
- size verification
- invalid storage paths
- path traversal
- symlink escape protection
- storage collisions
- private storage permissions

---

# Recording Setup Failures

When a setup command fails, record:

- the exact command
- the exact error message
- what you expected to happen
- whether Docker/MySQL/Rails was running
- relevant container state

Useful commands:

```bash
docker compose ps
docker compose logs --tail=100 db
```

Do not include passwords or secrets when sharing logs.

A useful rule for the project is:

```text
README command fails
        |
        v
fix the machine
        |
        v
fix the README too
```

---

# Troubleshooting

| Problem                                         | What to check                                                                                   |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Wrong Ruby version                              | Run `ruby --version` and `rbenv version` inside the repository                                  |
| `mysql2` fails to compile                       | Confirm build tools and MySQL client development headers are installed                          |
| libvips cannot be loaded                        | Confirm `libvips` / `libvips-dev` is installed                                                  |
| Docker permission denied                        | Use `sudo docker` or configure Docker access for your user                                      |
| MySQL connection refused                        | Check `docker compose ps`, logs, and `MYSQL_HOST_PORT`                                          |
| MySQL access denied after editing `.env`        | Existing MySQL volumes keep their old accounts/passwords; changing `.env` does not rewrite them |
| Test database missing or denied                 | Check the database initialization script and test database grants                               |
| Upload fails                                    | Check Rails logs, free disk space, and write permissions on the backup root                     |
| Restore says missing or corrupted               | Confirm the correct backup root/disk is available and the stored bytes were not changed         |
| Browser cannot connect                          | Confirm Rails is running and the binding/address matches localhost, LAN, or Tailscale use       |
| External drive path exists but drive is missing | Use `findmnt` and `lsblk` before uploading more files                                           |

---

# Configuration

| Variable                 | Example/default               | Purpose                                   |
| ------------------------ | ----------------------------- | ----------------------------------------- |
| `MYSQL_ROOT_PASSWORD`    | Replace the example value     | MySQL administrator password              |
| `MYSQL_DATABASE`         | `phonevault2`                 | Main development database                 |
| `MYSQL_USER`             | `phonevault2`                 | MySQL application account                 |
| `MYSQL_PASSWORD`         | Replace the example value     | Application account password              |
| `MYSQL_HOST_PORT`        | `3308`                        | Host port mapped to container port `3306` |
| `DB_HOST`                | `127.0.0.1` when used         | Rails database host                       |
| `PHONEVAULT_BACKUP_ROOT` | `storage/backups/` when unset | Optional absolute path for backup storage |

---

# ToDo

The long-term setup goal is:

```text
git clone
    |
    v
configure .env
    |
    v
choose backup location
    |
    v
start PhoneVault
    |
    v
PhoneVault works
```

Advanced storage, remote access, and monitoring should add capability without making the basic setup unnecessarily complicated.

## Database Design

- [x] Finalize the working database schema.
- [x] Identify primary keys and foreign keys.
- [x] Create the EER diagram.
- [x] Define integrity constraints.
- [x] Test the schema in MySQL.
- [x] Document the database design.
- [ ] Add realistic sample data where it is useful for demos/testing.

## Development Environment and Setup

- [x] Run MySQL through Docker Compose.
- [x] Connect Rails to MySQL.
- [x] Document required host/runtime dependencies.
- [x] Track required packages such as MySQL client headers and libvips.
- [x] Keep secrets and local configuration out of Git.
- [x] Document the current manual setup process.
- [ ] Add `PHONEVAULT_BACKUP_ROOT` to `.env.example`.
- [ ] Test setup from a completely fresh Linux clone.
- [ ] Test setup on another Linux machine.
- [ ] Fix any README commands that fail during a fresh setup.
- [ ] Finalize the supported permanent deployment method.

## Authentication and Security

- [x] Add local username/password authentication.
- [x] Store passwords as secure hashes.
- [x] Add login and logout.
- [x] Protect authenticated pages by default.
- [x] Prevent users from accessing devices/backups they do not own.
- [x] Verify file size and SHA-256 before restore.
- [x] Validate internal storage paths.
- [x] Reject symlink escapes outside the backup root.
- [x] Prevent partial/final backup file collisions from overwriting existing data.
- [x] Create private backup files.
- [x] Run Brakeman security scanning in CI.
- [ ] Add login rate limiting.
- [ ] Add automatic security-event logging.
- [ ] Research 2FA.
- [ ] Research recovery codes.
- [ ] Research device API tokens.

## Device Management

- [x] Add device registration.
- [x] Associate devices with users.
- [x] Display registered devices.
- [x] Add navigation to device backups and uploads.
- [ ] Allow devices to be renamed.
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
- [x] Use server-generated UUID storage filenames.
- [x] Use partial files before publishing a completed backup.
- [x] Prevent existing completed backup files from being overwritten.
- [ ] Verify the complete backup workflow from a fresh Linux installation.

## Restore System

- [x] Display backup history.
- [x] Restore individual backup files through the browser.
- [x] Scope restore requests through the current user's device and backup run.
- [x] Verify restored files using file size and SHA-256.
- [x] Handle missing stored files.
- [x] Handle corrupted stored files.
- [x] Reject path traversal and symlink escapes.
- [ ] Improve backup-history presentation and file details.
- [ ] Verify the complete browser backup -> restore workflow from a fresh installation.

## Storage Configuration and Dashboard

- [x] Support `PHONEVAULT_BACKUP_ROOT`.
- [x] Store backup bytes separately from MySQL metadata.
- [x] Document local, `/srv`, and `/mnt` storage choices.
- [x] Explain the difference between another directory and another physical disk.
- [ ] Add `PHONEVAULT_BACKUP_ROOT` to the example environment file.
- [ ] Decide on the recommended permanent Linux storage directory.
- [ ] Detect/report unavailable storage.
- [ ] Detect when an expected external mount is missing.
- [ ] Prevent accidental system-disk fallback when the external mount is missing.
- [ ] Improve errors when an external disk is disconnected.
- [ ] Research startup ordering when an external disk mounts after boot.
- [ ] Display total disk capacity.
- [ ] Display used/available disk capacity.
- [ ] Display PhoneVault storage usage.
- [ ] Display the number of stored backup files.
- [ ] Build the storage dashboard.
- [ ] Support Docker host bind mounts when Rails becomes part of the supported container deployment.

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
- [x] Test partial-file collision protection.
- [x] Test completed-file collision protection.
- [x] Test private file permissions.
- [ ] Follow the README from a clean environment and record failed commands/errors.
- [ ] Test project/setup scripts from a fresh clone.

## Linux Deployment and Remote Access

- [x] Document the Linux setup procedure.
- [x] Run PhoneVault on a dedicated Linux machine.
- [x] Add optional Tailscale access.
- [x] Verify PhoneVault through Tailscale.
- [x] Keep MySQL bound locally rather than exposing it directly to the public internet.
- [ ] Validate the full documented procedure on a clean Linux installation.
- [ ] Decide on the permanent deployment method.
- [ ] Add automatic startup after Linux reboot.
- [ ] Verify MySQL readiness before Rails depends on it.
- [ ] Verify the configured backup disk is mounted before uploads are accepted.
- [ ] Evaluate Docker restart policies.
- [ ] Evaluate systemd where appropriate.
- [ ] Test a full reboot and confirm PhoneVault returns with the correct storage.
- [ ] Test access from another laptop.
- [ ] Test browser access from a phone.
- [ ] Keep Tailscale optional.

## Disaster Recovery

- [x] Document that one server or disk can still fail.
- [x] Explain the benefit of separating backup bytes onto another physical disk.
- [ ] Document a full recovery procedure for MySQL metadata plus backup bytes.
- [ ] Research Restic for PhoneVault disaster recovery.
- [ ] Research another independent/off-site backup copy.
- [ ] Later evaluate MinIO / S3-compatible storage.
- [ ] Document how to rebuild PhoneVault after losing the application server.

## Documentation and Due Diligence

- [x] Document installation.
- [x] Document backup and restore.
- [x] Document the database.
- [x] Document local database binding.
- [x] Document storage safeguards.
- [x] Document troubleshooting.
- [ ] Verify every setup command on a fresh Linux machine.
- [ ] Continue cleaning old development files/scripts.
- [ ] Document the final production deployment method when it is chosen.

## V3 — Background Jobs

- [ ] Introduce Solid Queue.
- [ ] Move appropriate backup processing out of the web request.
- [ ] Compare background-job behavior with the current synchronous flow.
- [ ] Later experiment with Redis / Sidekiq for comparison.

## V3 — Storage Backends

- [ ] Create a storage abstraction.
- [ ] Keep local filesystem storage as the simple default.
- [ ] Add optional MinIO / S3-compatible storage.
- [ ] Keep advanced storage optional.

## V3 — Disaster Recovery and Monitoring

- [ ] Research Restic integration.
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

- [ ] 2FA.
- [ ] Recovery codes.
- [ ] Device API tokens.
- [ ] File deduplication.
- [ ] Encryption improvements.
- [ ] WebDAV.
- [ ] CalDAV.
- [ ] CardDAV.
- [ ] Security-event analytics.
- [ ] Large synthetic backup datasets.
- [ ] PySpark experiments only if the project reaches a scale where they are useful.
- [ ] Duress-mode concepts as research only.

---

# Project Philosophy

PhoneVault should remain understandable and self-hostable.

The basic path should stay simple:

```text
git clone
   |
   v
configure
   |
   v
start
   |
   v
backup
   |
   v
restore
```

More advanced infrastructure should add capability without making the beginner setup unnecessarily complicated.

