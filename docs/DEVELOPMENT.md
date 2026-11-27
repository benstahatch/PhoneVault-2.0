# PhoneVault Development Guide

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
## Testing and Code Quality

PhoneVault uses Docker to keep the application and MySQL
running on your Linux server.

### Automatic Startup

After a server reboot, Docker automatically restarts PhoneVault
and its database, provided Docker starts normally and the
containers have not been intentionally stopped.

Your user accounts, backup history, and stored files are
preserved between restarts.

### Managing PhoneVault

From your PhoneVault project directory, use these commands:

| Command | Description |
| --- | --- |
| `python3 launch.py` | Start PhoneVault. |
| `python3 launch.py status` | Check the running containers. |
| `python3 launch.py logs` | View application logs. |
| `python3 launch.py down` | Stop PhoneVault without deleting backups or database volumes. |


> **Warning:** Avoid running `docker compose down -v` unless you
> intentionally want to remove Docker volumes. This command can
> delete the MySQL database containing your accounts and backup records.


### Updating PhoneVault

To download the latest changes and restart the application,
open your project directory and run:

```bash
git pull
python3 launch.py
```

> **Important:** If your backups are stored on an external
> drive, confirm that the drive is mounted before starting
> PhoneVault. The application does not currently detect
> missing external storage mounts automatically.

For additional storage and deployment considerations,
see [Storage Documentation](docs/STORAGE.md).

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