# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

# PhoneVault

PhoneVault is a self-hosted backup project built around Ruby on Rails, MySQL, Docker, and Linux.

The long term idea is to provide a simple way for anyone to run their own private backup server on their own hardware. The first version is intentionally small: get the database, application, storage, and restore pipeline working well before adding more unique features.
---------------------------------------------------------------------------

## Current Goal for September

PhoneVault v0.1 should be able to:

- [x]- run on a Linux machine.
- use a local username and password.
- register one or more personal devices.
- upload and store files such as notes and pictures.
- calculate a SHA-256 hash for stored files.
- store file and backup metadata in MySQL.
- track backup runs.
- restore files.
- verify that restored files match the originals.

---------------------------------------------------------------------------
# Tech Stack

*Core (v0.1):*
- Ruby
- Ruby on Rails
- Python
- MySQL
- Docker
- Docker Compose
- Linux
- Minitest

*Planned:*

- Tailscale (remote access)
- Python + PySpark (analytics, Future Work tier)

---------------------------------------------------------------------------
# Architecture

Browser

  ⬇

Ruby on Rails 

  ⬇    ⬇
     
MySQL  File Storage

MySQL is used for structured data such as the users, devices, backup history, file metadata, hashes, timestamps, and security events.

The actual photos, videos, documents, and other files are stored separately on persistent storage.
---------------------------------------------------------------------------
# Database
The working schema is centered around these tables:

USERS

  ⬇ 1:N (one-to-many)

DEVICES

  ⬇ 1:N

BACKUP_RUNS

  ⬇ 1:N

BACKUP_FILES

USERS

  ⬇ 1:N

SECURITY_EVENTS

## Database Relationships

- One USER can have many DEVICES
- One DEVICE can have many BACKUP_RUNS
- One BACKUP_RUN can have many BACKUP_FILES
- One USER can have many SECURITY_EVENTS

These are one-to-many (`1:N`) relationships.

** PK = Primary Key:**
uniquely identifies a row in a table.

** FK = Foreign Key:** connects a row to another table.

Examples: `devices.user_id` references `users.id`.
--------------------------------------------------------------------------


# Users

*Local PhoneVault accounts.*
Possible fields:

- `id`            *(PK)*
- `username`
- `display_name`
- `password_digest`
- `created_at`
- `updated_at`


# Devices

Devices that are registered to a user.

Possible fields:

- `id`             *(PK)*
- `user_id`        *(FK) ➡ users.id*
- `name`
- `device_type`
- `created_at`
- `updated_at`

# Backup Runs

Individual backup attempts.

Possible fields:

- `id`            *(PK)*
- `device_id`     *(FK) ➡ devices.id*
- `status`
- `started_at`
- `completed_at`
- `created_at`
- `updated_at`


# Backup Files
*Metadata for files included in a backup:*

*Potential fields:*

- `id`             *(PK)*
- `backup_run_id`  *(FK) ➡ backup_runs.id*
- `original_filename`
- `storage_path`
- `size_bytes`
- `sha256`
- `created_at`
- `updated_at`


# Security Events

Security related activity recorded by the application.

Possible fields:

- `id`           *(PK)*
- `user_id`      *(FK) ➡ users.id, nullable*
- `event_type`
- `ip_address`
- `created_at`

Possible events:

`LOGIN_SUCCESS`
`LOGIN_FAILED`
`LOGOUT`
`BACKUP_SUCCESS`
`BACKUP_FAILED`
`FILE_RESTORED`
`AUTHORIZATION_DENIED`
`DEVICE_REGISTERED`
`RESTORE_FAILED`


# Basic Database Protocols / Constraints

- every table has a primary key
- foreign keys are used to maintain relationships between tables
- usernames are unique
- every device belongs to a valid user
- every backup run belongs to a valid device
- every backup file belongs to a valid backup run
- required values use NOT NULL
- file sizes cannot be negative
- destructive deletes need to be handled carefully so related backup records aren`t accidentally wiped out.


*The exact constraints are subject to change as the schema is tested.*


# Informal Queries

*Some questions PhoneVault database should be able to answer*

- What devices belong to a user?
- What backups belong to a device?
- What files belong to a backup run?
- Which backup runs failed?
- How much storage is a device using?
- What security events belong to a user?
- Does a file with a specific SHA-256 hash exist?
- How many files were stored during a backup run?

*--------------------------------------------------------------------------*

# Backup Flow


Select Device
     ➡ 
Create Backup Run
     ➡
Upload File
     ➡ 
Calculate SHA-256
     ➡ 
Store File
     ➡ 
Save Metadata
     ➡ 
Mark Backup Complete


# Restore Flow


Choose Backup
     ➡ 
Find File Metadata
     ➡
Locate Stored File
     ➡ 
Restore File
     ➡ 
Verify SHA-256


# Local Development

The project currently uses Docker Compose for the database environment.

Typical commands:

```bash
docker compose up -d
docker compose ps
docker compose logs
docker compose down
```

*Note* The local MySQL container may be mapped like this during development:

127.0.0.1:3307 ➡ MySQL container:3306

The host port CAN change, but MySQL still listens on 3306 inside the container.

# Configuration

Local configuration belongs in `.env`.

The repository contains an `.env.example` file that shows the variables needed to run PhoneVault without exposing any real credentials. After cloning the repository, rename `.env.example` to `.env` and replace the current placeholder values with your own credentials. 

*Note:* Never push your `.env`, passwords, credentials, or other sensitive data to GitHub.


# ToDo 

## Database Design

- [x] Finalize the database schema
- [x] Identify primary keys and foreign keys
- [x] create the EER diagram
- [x] define integrity constraints
- [ ] add realistic sample data
- [x] test the schema in MySQL
- [x] Document database design

## Development Environment & Automation

- [ ] Finalize the Docker development environment
- [ ] Document required host/runtime dependencies
- [ ] Track required system packages such as `libvips`
- [ ] Track required Ruby gems and why they are needed
- [ ] Move host/runtime dependencies into Docker where practical
- [ ] Update `.env.example`
- [x] Verify secrets and local config are ignored by Git
- [ ] Plan the automated setup process
- [ ] Write and test initial setup scripts
- [ ] Use Ruby, Python, or shell scripts where appropriate for automation
- [ ] Automate environment and Docker setup where practical
- [ ] Test setup scripts from a fresh clone
- [ ] Document anything that stilljjk requires manual setup
- [ ] Test setup on a second Linux machine

## Rails Foundation

- [x] Create the Rails application
- [x] Connect Rails to MySQL
- [x] Replace temporary SQL setup with Rails migrations as needed
- [x] Create the initial Rails models
- [x] add model relationships
- [x] verify Rails can read & write database records

## Authentication

- [x] add local user authentication
- [x] Store passwords as secure hashes
- [x] Add login and logout
- [x] Protect authenticated pages by default
- [ ] Prevent users from accessing data they do not own
- [ ] add login rate limiting
- [ ] add security event logging
- [ ] Research other useful security events to log

## Vault / Data Isolation 
- [ ] Design the `Vault` model
- [ ] Design `VaultMembership`
- [ ] Separate user identity from storage ownership
- [ ] Create a default vault for new users
- [ ] Allow users to create multiple isolated vaults
- [ ] Scope devices, backups, and files to a vault
- [ ] Add authorization checks between users and vaults
- [ ] Design shared vault support for users

## Linux Agent and Permissions
- [ ] Research privileged full-system backup mode
- [ ] Define approved default backup paths
- [ ] Define excluded virtual and system paths
- [ ] Design symbolic link handling
- [ ] Design removable storage support
- [ ] Decide where PhoneVault agent configuration should live
- [ ] Decide where PhoneVault temporary/cache data should live
- [ ] Design an allowlist-based backup source policy
- [ ] Build the first Linux backup agent/script

## Device Management
- [ ] Add device registration
- [x] Associate devices w/ users at the model/database level
- [ ] Revisit device ownership when the Vault layer is introduced
- [ ] Display registered devices
- [ ] Allow devices to be renamed


## Backup System
- [ ] Accept a file upload through the web UI
- [x] Create and test backup run records
- [ ] Add persistent file storage
- [x] Store file metadata in MySQL
- [x] Calculate SHA-256 hashes
- [x] Associate uploaded files with backup runs
- [ ] Track successful and failed backups


## Restore System
- [ ] Display available backups
- [ ] Locate stored files using database metadata
- [ ] restore individual files
- [ ] verify restored files using SHA-256
- [ ] handle missing or corrupted files
- [ ] test the complete backup -> restore pipeline


## Testing & Reliability

- [ ] add *Minitest* tests
- [ ] test database models and relationships
- [ ] test authentication
- [ ] test authorization
- [ ] test file uploads
- [ ] test backup creation
- [ ] test file restoration
- [ ] test SHA-256 verification
- [ ] test failed backup scenarios
- [ ] Test project/setup scripts from a fresh clone


## Linux Deployment and Remote Access

- [ ] Document clean setup on Linux
- [x] test PhoneVault on a dedicated Linux machine
- [ ] test persistent storage after container restarts
- [x] add Tailscale setup for trusted remote access
- [x] verify PhoneVault works through Tailscale
- [x] avoid exposing MySQL directly to public Internet
- [x] Evaluate Raspberry Pi deployment


## Documentation & Due Diligence

- [x] Keep the README synchronized with the actual state of the project
- [ ] document installation
- [ ] document backup & restore
- [x] document the database
- [x] document security decisions
- [ ] document troubleshooting
- [ ] remove unused development files & scripts
- [x] verify no passwords or private data are committed

## Future Work

- [ ] 2FA
- [ ] Recovery codes
- [ ] Device API tokens
- [ ] command line backup client
- [ ] automatic backup synchronization
- [ ] encryption improvements
- [ ] file deduplication research
- [ ] additional storage backends
- [ ] security event analytics
- [ ] generate large synthetic backup datasets with Python
- [ ] experiment with PySpark for a large scale backup analytics
- [ ] analyze storage growth & duplicate files
- [ ] research duress mode concepts
- [ ] research WEBDDAV support for remote file access
- [ ] research CalDAV support for calendar backup & sync
- [ ] research CardDAV support for contact backup & sync
 



