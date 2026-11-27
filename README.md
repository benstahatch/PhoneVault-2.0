# PhoneVault

**Personal file backups, on your own hardware.**

Cloud storage services make it convenient to store and back up personal files, but they also require users to rely on infrastructure managed by third-party providers. PhoneVault offers a self-hosted alternative, allowing users to store, organize, and recover personal files on a Linux server they control.

Built with **Ruby on Rails, MySQL, and Docker**, PhoneVault provides a web interface for managing devices, uploading files, viewing backup history, and restoring backups. Each file is recorded with a SHA-256 digest, which is checked during restoration to help detect missing or corrupted data.

> **Current version:** PhoneVault supports manual, single-file backups through a web browser. Automatic device synchronization and scheduled backups are planned for future development.

**Get started:** [Installation](#quick-start-run-everything-in-docker) | [First Backup](#first-backup-test)

---

## Features

PhoneVault version 1 includes the following functionality:

- **User Accounts:** Create a local account and securely sign in with a username and password.
- **Device Management:** Register, view, and rename personal devices.
- **File Backups:** Upload files through the browser and choose where they are stored on the server.
- **Backup History:** View completed and failed backups, file information, image thumbnails, and text previews.
- **Verified Restores:** Restore files with SHA-256 and file size verification to detect missing or corrupted data.
- **Trash and Recovery:** Recover deleted files, permanently remove them, or configure retention periods with optional automatic cleanup.
- **Dashboard and Activity:** View backup summaries and security events associated with your account.
- **Access Protection:** Restrict access to each user's files and validate storage paths before accessing them.

> **Note:** PhoneVault currently supports manual file backups through a web browser. Registering a device organizes its backups but does not automatically transfer files from that device.

---

## Tech Stack

PhoneVault is built using the following technologies:

| Technology                    | Purpose                                                                      |
| ----------------------------- | ---------------------------------------------------------------------------- |
| **Ruby on Rails 8.1.4**       | Provides the application, user interface, and backup functionality.          |
| **Ruby 3.4.13**               | Programming language used by Rails.                                          |
| **MySQL 8.4**                 | Stores user accounts, registered devices, backup history, and file metadata. |
| **Docker and Docker Compose** | Run PhoneVault and its database in containers for easier deployment.         |
| **Linux**                     | Hosts the application and stores uploaded files.                             |
| **Solid Queue**               | Handles scheduled Trash cleanup when enabled.                                |
| **Tailscale (Optional)**      | Provides private remote access from other devices.                           |

### Development and Testing

PhoneVault uses **Minitest** for automated testing, **RuboCop** for Ruby code checks, and **Brakeman** for security analysis.

These tools help verify the application's functionality and identify potential issues during development.

---

# Quick Start: Run Everything in Docker

### Before You Begin

To install PhoneVault, you will need:

- A computer running **Ubuntu, Debian, Raspberry Pi OS, or Fedora Linux**.
- An internet connection to download the required software.
- A Linux user account with `sudo` permissions.
- Enough available disk space to store your backups.

You do not need to install Ruby, Rails, or MySQL manually. The installer handles the required software and starts PhoneVault using Docker.

### Install PhoneVault

Run the following command in your Linux terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/benstahatch/PhoneVault-2.0/main/install.sh | bash
```

If curl isn't installed (Ubuntu Desktop ships without it), use wget, which it does have:

```bash
wget --no-verbose --output-document=- https://raw.githubusercontent.com/benstahatch/PhoneVault-2.0/main/install.sh | bash
```

`install.sh` installs only what is missing (Git, curl, Python 3, and Docker through the official get.docker.com script), clones the repository into `~/PhoneVault-2.0`, and runs `launch.py`. It asks for your `sudo` password to install packages. You can read [install.sh](install.sh) before running it.

### Additional Installation Notes

The installer handles Docker permissions during the initial setup, so you can continue without logging out. If you later encounter a Docker permission error, signing out and back in may be necessary to activate your new group membership.

If you have already cloned PhoneVault, open the project directory and run:

```bash
./install.sh
```

If Docker, Git, and Python 3 are already installed, you can skip `install.sh`:

```bash
git clone https://github.com/benstahatch/PhoneVault-2.0.git
cd PhoneVault-2.0
python3 launch.py
```

### Open PhoneVault

Once installation is complete, PhoneVault will display the address
where the application can be accessed.

By default, PhoneVault uses port `8080`.

**If you are using a browser on the Linux server:**

```text
http://localhost:8080
```

**If you are connecting from another device on the same network:**

```text
http://SERVER_IP:8080
```

Replace `SERVER_IP` with your Linux server's local IP address.
You can find it by running:

```bash
hostname -I
```

Once the application opens, visit `/signup` to create your first
PhoneVault account.

> **Security:** Use PhoneVault on a trusted local network or through
> a private connection such as Tailscale. Do not expose port `8080`
> directly to the public internet.

**How it works:** The installer creates the necessary configuration,
prepares the backup storage, initializes MySQL, and starts PhoneVault
using Docker.

| Command                    | What it does                                       |
| -------------------------- | -------------------------------------------------- |
| `python3 launch.py`        | Set up and start PhoneVault                        |
| `python3 launch.py status` | Show the containers                                |
| `python3 launch.py logs`   | Follow the Rails logs                              |
| `python3 launch.py down`   | Stop PhoneVault; the database and backups are kept |

Both containers use `restart: unless-stopped`, so PhoneVault comes back after a reboot once Docker starts.

Backups are stored in `storage/backups/` inside the repository unless `PHONEVAULT_BACKUP_ROOT` in `.env` names another folder. The folder must be owned by user id 1000, the user Rails runs as inside the container.

The Rails container only starts with Compose's `app` profile, so the development workflow below (`docker compose up -d` starts just MySQL) is unchanged.

### First Backup Test

Once PhoneVault is running and you have created an account, you
can test the backup and restore process.

1. **Sign in** to your PhoneVault account.
2. Open **Your devices** and register a device.
3. Select **Upload** for your registered device.
4. Choose a small file, such as a picture or document.
5. Upload the file and confirm the backup completed successfully.
6. Open the device's **Backup History** to locate your file.
7. Select **Restore** to download the backed-up file.
8. Open the restored file and confirm it matches the original.

PhoneVault verifies the stored file's size and SHA-256 digest
before allowing the restore.

> **Note:** PhoneVault currently supports manual, single-file
> backups. Automatic device synchronization is not yet available.

---

### Optional: Try PhoneVault with Demo Data

PhoneVault includes optional sample data for exploring the
application without manually creating backups.

The demo includes a sample account, registered devices,
backup history, and activity records.

To create the demo account after installation, run:

```bash
docker compose exec app bin/rails phonevault:demo
```

The command generates a password and displays it in the terminal.
Use those credentials to sign in and explore PhoneVault.

To remove the demo account and its associated data, run:

```bash
docker compose exec app bin/rails phonevault:demo:reset
```

> **Note:** Demo data is not created during a normal installation.
> The reset command permanently removes the demo account and its
> associated backups.

---

## How PhoneVault Works

PhoneVault separates the web application, database, and file storage
into three main components.

```text
             Web Browser
                  |
                  v
            Ruby on Rails
                  |
          +-------+-------+
          |               |
          v               v
        MySQL        File Storage
       Metadata      Actual Files
```

- **Ruby on Rails** handles user accounts, device management, file uploads, and restores.
- **MySQL** stores information about users, devices, backup history, filenames, and SHA-256 digests.
- **File Storage** keeps the actual uploaded files on the Linux server, separate from the database.

During a backup, PhoneVault saves the file to disk and records its
metadata in MySQL. When restoring a file, the application checks its
size and SHA-256 digest before allowing the download.

This design keeps file storage separate from structured database
records while allowing users to manage everything through a single
web interface.

---

## Database Design

PhoneVault uses **MySQL 8.4** to manage user accounts,
registered devices, backup history, file metadata,
and security activity.

The database contains five main tables:

| Table             | Purpose                                                           |
| ----------------- | ----------------------------------------------------------------- |
| `users`           | Stores user accounts and retention preferences.                   |
| `devices`         | Tracks devices registered to each user.                           |
| `backup_runs`     | Records individual backup attempts and their status.              |
| `backup_files`    | Stores filenames, file sizes, SHA-256 digests, and storage paths. |
| `security_events` | Records authentication and file management activity.              |

Each user can register multiple devices, each device can
have multiple backup runs, and each backup run can contain
file records.

For the complete database schema, relationships,
constraints, and security event documentation, see
[Database Documentation](docs/DATABASE.md).

---

## Backup and Restore Documentation

For technical details about file storage, upload processing,
SHA-256 verification, and restoration safeguards, see the
[Backup and Restore Documentation](docs/BACKUP-RESTORE.md).

---

## For Developers

Interested in modifying PhoneVault or contributing to the project?

See the [Development Guide](docs/DEVELOPMENT.md) for instructions
on setting up Ruby on Rails, MySQL, and the local development environment.

---

## Backup Storage

By default, PhoneVault stores uploaded files in the
`storage/backups/` directory inside the project folder.

### Using Another Storage Location

You can store backups on another drive or directory by setting
`PHONEVAULT_BACKUP_ROOT` in your `.env` file.

For example:

```text
PHONEVAULT_BACKUP_ROOT=/mnt/phonevault-backups
```

The destination must exist and be writable by PhoneVault.
When using Docker, the application runs with user ID `1000`.

After updating `.env`, restart PhoneVault using:

```bash
python3 launch.py
```

> **Important:** Changing the storage location does not
> automatically move existing backups. If you use an external
> drive, confirm that it is mounted before uploading files.

### Trash and File Recovery

PhoneVault lets users move files to Trash, recover them,
or permanently delete them.

Users can choose to retain deleted files for **30, 60, or 90
days**, or select **Never** for no automatic expiration.

Automatic Trash cleanup is disabled by default. To enable
scheduled cleanup, set the following in `.env` and restart
PhoneVault:

```text
PHONEVAULT_TRASH_CLEANUP_ENABLED=true
```

### Protecting Your Backups

PhoneVault stores file metadata in MySQL and uploaded files on disk.

To recover PhoneVault after a server failure, keep independent backups of your **MySQL database, uploaded files, and `.env` configuration**.

A fresh Git clone alone cannot recover your existing accounts or backups.

---

## Optional: Remote Access with Tailscale

PhoneVault can be accessed from other devices on your local
network. If you want to access your backups while away from home,
you can use **Tailscale**.

Tailscale creates a private, encrypted network between your
devices, allowing you to access PhoneVault without opening
ports on your router.

### Set Up Tailscale

**1. Install Tailscale on your Linux server.**

Follow the [official Tailscale installation guide](https://tailscale.com/download/linux).

Once installed, run:

```bash
sudo tailscale up
```

Follow the instructions to authenticate your device.

**2. Find your server's Tailscale IP address.**

```bash
tailscale ip -4
```

Your address will look similar to:

```text
100.x.x.x
```

**3. Install Tailscale on your other devices.**

Install Tailscale on the laptop, phone, or computer you
want to use to access PhoneVault.

Sign in to the same Tailscale network.

**4. Open PhoneVault in your browser.**

Using your server's Tailscale IP address, navigate to:

```text
http://100.x.x.x:8080
```

Replace `100.x.x.x` with the actual address of your
Linux server.

Sign in using your regular PhoneVault account.

### Security Considerations

- Tailscale is optional. PhoneVault works on a local network without it.
- PhoneVault authentication is still required when using Tailscale.
- Do not forward port `8080` directly to the public internet.
- Keep your Linux server, Docker, and Tailscale updated.

> **Note:** These instructions assume PhoneVault is running
> through the recommended Docker installation on port `8080`.
> Developers running Rails directly on the host typically use
> port `3000`.

---

## Troubleshooting

If PhoneVault is not working as expected, use the following
table to identify common problems and possible solutions.

| Problem                           | What to Check                                                                                 |
| --------------------------------- | --------------------------------------------------------------------------------------------- |
| **Cannot open PhoneVault**        | Confirm the server is running and you are using the correct IP address and port `8080`.       |
| **Docker permission denied**      | Sign out and back in to activate your Docker group membership.                                |
| **PhoneVault fails to start**     | Check the container status and application logs using the commands below.                     |
| **File upload fails**             | Check available disk space and confirm PhoneVault can write to the selected storage location. |
| **File restore fails**            | Confirm the backup file exists and has not been modified or corrupted.                        |
| **External drive is unavailable** | Verify that the drive is connected and mounted before uploading files.                        |
| **Database connection error**     | Check that the MySQL container is running and review the application logs.                    |

### Check Application Status

From the PhoneVault project directory, run:

```bash
python3 launch.py status
```

To view application logs:

```bash
python3 launch.py logs
```

These commands can help identify startup, database,
and application errors.

> **Important:** Never share passwords, database credentials,
> or the contents of your `.env` file when requesting support.

---

## Configuration

PhoneVault automatically creates a `.env` configuration file
during installation. Most users can keep the default settings.

The following options can be customized:

| Setting                            | Default            | Description                                                          |
| ---------------------------------- | ------------------ | -------------------------------------------------------------------- |
| `PHONEVAULT_PORT`                  | `8080`             | Port used to access PhoneVault through Docker.                       |
| `PHONEVAULT_BACKUP_ROOT`           | `storage/backups/` | Directory where uploaded files are stored.                           |
| `PHONEVAULT_MAX_UPLOAD_MB`         | `10240` (10 GB)    | Maximum permitted upload size in megabytes.                          |
| `PHONEVAULT_TRASH_CLEANUP_ENABLED` | `false`            | Enables scheduled cleanup of expired Trash files when set to `true`. |

After changing your configuration, restart PhoneVault:

```bash
python3 launch.py
```

> **Important:** Keep your `.env` file private. It contains
> database credentials and application secrets. Do not commit
> it to Git or share its contents publicly.

For additional configuration details, see the
[Development Guide](docs/DEVELOPMENT.md) and
[Storage Documentation](docs/STORAGE.md).

---

## Future Development

PhoneVault currently focuses on manual file backups, verified restores,
and self-hosted storage.

Planned improvements include automatic device backups, scheduled
synchronization, additional storage options, and enhanced
monitoring and security features.

For completed milestones and planned improvements, see the
[Development Checklist](TODO.md).

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
