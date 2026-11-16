# PhoneVault

PhoneVault is a self-hosted backup project built around Ruby on Rails, MySQL, Docker, and Linux.

The long-term idea is to provide a simple way for someone to run their own private backup server on their own hardware. The first version is intentionally small: get the database, application, storage, and restore pipeline working well before adding more advanced features.

---

# Version 1

PhoneVault version 1 can:

- [x] Run on a Linux machine, either fully in Docker or with Rails on the host.
- [x] Use a local username and password.
- [x] Register, list, and rename personal devices.
- [x] Upload and store individual files through the browser, into a default or chosen server folder.
- [x] Calculate a SHA-256 hash for stored files.
- [x] Store file and backup metadata in MySQL.
- [x] Track completed and failed backup attempts.
- [x] Show backup history with image thumbnails and text previews.
- [x] Restore individual files through the browser.
- [x] Verify stored file size and SHA-256 before downloading a restore.
- [x] Move files to Trash, recover them, or delete them permanently.
- [x] Let each user choose how long Trash keeps files, with an opt-in scheduled cleanup.
- [x] Show a dashboard summary and each user's own security activity.
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
| Solid Queue         | Runs the daily Trash retention cleanup job                                           |
| Minitest            | Automated Rails testing                                                              |
| RuboCop             | Ruby style and lint checks                                                           |
| Brakeman            | Rails security scanning                                                              |
| Tailscale           | Optional private remote access between trusted devices                               |

Planned additions are listed in the [ToDo](#todo).

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

---

# Quick Start: Run Everything in Docker

On a fresh Debian, Ubuntu, Raspberry Pi OS, or Fedora machine, one command installs everything and starts PhoneVault:

```bash
curl -fsSL https://raw.githubusercontent.com/benstahatch/PhoneVault-2.0/main/install.sh | bash
```

If curl isn't installed (Ubuntu Desktop ships without it), use wget, which it does have:

```bash
wget --no-verbose --output-document=- https://raw.githubusercontent.com/benstahatch/PhoneVault-2.0/main/install.sh | bash
```

`install.sh` installs only what is missing (Git, curl, Python 3, and Docker through the official get.docker.com script), clones the repository into `~/PhoneVault-2.0`, and runs `launch.py`. It asks for your `sudo` password to install packages. You can read [install.sh](install.sh) before running it.

No logout or restart is needed. Installing Docker adds you to the `docker` group, which normally only applies at your next login, so until then `launch.py` reruns itself through `sudo` (as you, not as root).

If you already cloned the repository, run `./install.sh` from inside it. To install from a branch instead of `main`, set `PHONEVAULT_BRANCH`, for example `wget --no-verbose --output-document=- https://raw.githubusercontent.com/benstahatch/PhoneVault-2.0/docker-launcher/install.sh | PHONEVAULT_BRANCH=docker-launcher bash`.

If Docker, Git, and Python 3 are already installed, you can skip `install.sh`:

```bash
git clone https://github.com/benstahatch/PhoneVault-2.0.git
cd PhoneVault-2.0
python3 launch.py
```

Ruby, Rails, and MySQL all run in containers. `launch.py` creates `.env` with random passwords and a Rails secret, creates the backup folder, starts MySQL, waits for it to be ready, then builds and starts Rails. When it finishes it prints the address to open, by default `http://<server>:8080`. Open `/signup` to create the first account.

| Command | What it does |
| --- | --- |
| `python3 launch.py` | Set up and start PhoneVault |
| `python3 launch.py status` | Show the containers |
| `python3 launch.py logs` | Follow the Rails logs |
| `python3 launch.py down` | Stop PhoneVault; the database and backups are kept |

Both containers use `restart: unless-stopped`, so PhoneVault comes back after a reboot once Docker starts.

Backups are stored in `storage/backups/` inside the repository unless `PHONEVAULT_BACKUP_ROOT` in `.env` names another folder. The folder must be owned by user id 1000, the user Rails runs as inside the container.

The Rails container only starts with Compose's `app` profile, so the development workflow below (`docker compose up -d` starts just MySQL) is unchanged.

## Demo Data

To show PhoneVault without starting from an empty account, create a `demo` account with three devices and a few weeks of backups, including one failed run. The files are real (small photos, contacts, a calendar, notes), so Restore works on them. It also gets a matching Activity history, including one failed sign-in so the warning highlight shows.

```bash
docker compose exec app bin/rails phonevault:demo         # with launch.py
bin/rails phonevault:demo                                 # Rails on the host
```

It prints a random password once. Set `DEMO_PASSWORD` to choose it instead, for example `docker compose exec -e DEMO_PASSWORD=your-password app bin/rails phonevault:demo`. Delete the account, its backups, its stored files, and its activity with `bin/rails phonevault:demo:reset` (or `docker compose exec app bin/rails phonevault:demo:reset`).

The demo account is not part of `db/seeds.rb` on purpose: seeds run automatically when a new database is created, which would give every install a demo login.

---

# Local Development

The current development setup is:

```text
Linux host
  |
  +-- Ruby on Rails runs directly on Linux
  |
  +-- uploaded backup files live on Linux storage
  |
  `-- Docker Compose runs MySQL
```

In this development setup, Compose starts only the database and Rails is started from the Linux host. To run Rails in Docker too, see [Quick Start: Run Everything in Docker](#quick-start-run-everything-in-docker).

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

Edit `.env` and set the values listed under [Configuration](#configuration).

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

# Docker Storage: Current and Future

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

Start Rails with `-b 0.0.0.0` as in [LAN or Tailscale access](#lan-or-tailscale-access), then open `http://100.x.x.x:3000` using the address from `tailscale ip -4`.

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

# Deployment Method

The supported way to run PhoneVault permanently is **Docker Compose through `launch.py`**, as in the [Docker quick start](#quick-start-run-everything-in-docker). Running Rails directly on the host is for development only.

## How it comes back after a reboot

```text
machine boots
     |
     v
Docker starts (enabled at boot by the Docker install)
     |
     v
MySQL container starts           restart: unless-stopped
     |
     v
MySQL healthcheck passes
     |
     v
Rails container starts           depends_on: db (service_healthy)
     |
     v
PhoneVault is available on port 8080
```

| Piece | What handles it |
| --- | --- |
| Starting at boot | Docker's own service, plus `restart: unless-stopped` on both containers |
| Waiting for the database | The MySQL healthcheck and `depends_on: condition: service_healthy` |
| Secrets and settings | `.env`, created once by `launch.py` with random passwords |
| Updating | `git pull`, then `python3 launch.py` (it rebuilds the image) |
| Stopping on purpose | `python3 launch.py down`; containers stopped this way stay stopped after a reboot |

This was verified with a full reboot of the Raspberry Pi server: PhoneVault came back on its own with the same accounts and backups, and was reachable from another laptop and a phone.

**systemd** was evaluated and is not needed. Docker already starts at boot through its own systemd service, and the restart policies bring the containers back, so a separate PhoneVault unit would only duplicate that.

**Not handled yet:** waiting for an external backup disk to mount. If the disk is missing at boot, PhoneVault starts anyway. See [Missing external disks](#missing-external-disks).

## Development startup

When working on the code, start the pieces by hand so logs stay visible: [Start MySQL](#start-mysql), then [Start PhoneVault](#start-phonevault).

---

# Storage and Persistence

| Data                               | Current location                               | What must be preserved                                  |
| ---------------------------------- | ---------------------------------------------- | ------------------------------------------------------- |
| Accounts, devices, backup metadata | MySQL Docker volume                            | A consistent MySQL backup                               |
| Uploaded backup bytes              | Default storage root and any selected save folders | Every backup directory tree used by the app |
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

| Variable | Example/default | Purpose |
| --- | --- | --- |
| `MYSQL_ROOT_PASSWORD` | Replace the example value | MySQL administrator password |
| `MYSQL_DATABASE` | `phonevault2` | Main development database |
| `MYSQL_USER` | `phonevault2` | MySQL application account |
| `MYSQL_PASSWORD` | Replace the example value | Application account password |
| `MYSQL_HOST_PORT` | `3308` | Host port mapped to container port `3306` |
| `DB_HOST` | `127.0.0.1` when used | Rails database host |
| `PHONEVAULT_BACKUP_ROOT` | `storage/backups/` when unset | Optional absolute path for backup storage |
| `PHONEVAULT_MAX_UPLOAD_MB` | `10240` (10 GB) when unset | Optional upload size limit in whole megabytes |
| `PHONEVAULT_TRASH_CLEANUP_ENABLED` | `false` | Set to `true` to let the scheduled job permanently delete expired Trash |
| `PHONEVAULT_PORT` | `8080` when unset | Port the Docker app is served on |
| `SECRET_KEY_BASE` | Generated by `launch.py` | Rails secret used in production (Docker) |

---

# ToDo

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
