#!/usr/bin/env python3
"""Launch PhoneVault on a Linux server with Docker.

The server only needs Docker (with the Compose plugin) and Python 3.8+.
Ruby, Rails, and MySQL all run inside containers.

    python3 launch.py           start PhoneVault (same as "up")
    python3 launch.py up        create .env if needed, build, and start
    python3 launch.py status    show the containers
    python3 launch.py logs      follow the Rails logs (Ctrl+C to stop)
    python3 launch.py down      stop the containers (data is kept)
"""

import grp
import json
import os
import pwd
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent
ENV_FILE = PROJECT_DIR / ".env"
ENV_EXAMPLE = PROJECT_DIR / ".env.example"

DB_CONTAINER = "phonevault2-db"
# the Rails container runs as this user id (see the Dockerfile)
APP_UID = 1000

DEFAULTS = {
    "MYSQL_DATABASE": "phonevault2",
    "MYSQL_USER": "phonevault2",
    "MYSQL_HOST_PORT": "3308",
    "PHONEVAULT_PORT": "8080",
}

# values that are filled with random secrets when missing or still the example placeholder
GENERATED_SECRETS = {
    "MYSQL_ROOT_PASSWORD": lambda: secrets.token_urlsafe(24),
    "MYSQL_PASSWORD": lambda: secrets.token_urlsafe(24),
    "SECRET_KEY_BASE": lambda: secrets.token_hex(64),
}


def main():
    # print each line right away so our messages stay in order with Docker's output
    sys.stdout.reconfigure(line_buffering=True)

    command = sys.argv[1] if len(sys.argv) > 1 else "up"
    commands = {"up": up, "status": status, "logs": logs, "down": down}

    if command not in commands:
        print(__doc__)
        sys.exit(1)

    os.chdir(PROJECT_DIR)
    check_docker()
    commands[command]()


def up():
    step("Checking .env")
    env = ensure_env_file()

    step("Preparing the backup folder")
    ensure_backup_folder(env)

    step("Starting MySQL")
    compose("up", "-d", "db")
    wait_for_healthy_database()
    grant_database_access(env)

    step("Building and starting PhoneVault (the first build can take several minutes)")
    compose("--profile", "app", "up", "-d", "--build", "app")

    port = env.get("PHONEVAULT_PORT", DEFAULTS["PHONEVAULT_PORT"])
    wait_for_app(port)

    print()
    print("PhoneVault is running:")
    print(f"  on this machine:     http://localhost:{port}")
    lan_ip = local_ip_address()
    if lan_ip:
        print(f"  from your network:   http://{lan_ip}:{port}")
    print(f"  create an account:   http://localhost:{port}/signup")
    print()
    # "python3 launch.py" only finds the script from inside the project folder
    print("To stop it, go to the PhoneVault folder first, then run launch.py down:")
    print(f"  cd {home_relative(PROJECT_DIR)}")
    print("  python3 launch.py down")


def status():
    compose("--profile", "app", "ps")


def logs():
    try:
        compose("--profile", "app", "logs", "-f", "--tail", "100", "app")
    except KeyboardInterrupt:
        pass


def down():
    step("Stopping PhoneVault (your database and backups are kept)")
    compose("--profile", "app", "down")


# --- Docker ---------------------------------------------------------------

def check_docker():
    if shutil.which("docker") is None:
        fail(
            "Docker is not installed.\n"
            "On Debian, Ubuntu, or Raspberry Pi OS you can install it with:\n"
            "  curl -fsSL https://get.docker.com | sh\n"
            "  sudo usermod -aG docker $USER\n"
            "then log out and back in, and run this script again."
        )

    if run(["docker", "compose", "version"], quiet=True).returncode != 0:
        fail(
            "The Docker Compose plugin is missing.\n"
            "Install the docker-compose-plugin package, or reinstall Docker with get.docker.com."
        )

    if run(["docker", "info"], quiet=True).returncode != 0:
        if docker_group_not_active_yet():
            # being added to the docker group only counts from your next login, but sudo
            # reads your groups fresh, so rerunning through it works without logging out
            print("You were just added to the docker group, which normally needs a new login.")
            print("Running through sudo this time instead (it may ask for your password).")
            user = pwd.getpwuid(os.getuid()).pw_name
            os.execvp("sudo", ["sudo", "-u", user, sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]])

        fail(
            "Docker is installed but this user can't talk to it.\n"
            "Either start Docker (sudo systemctl start docker) or add yourself to the docker group:\n"
            "  sudo usermod -aG docker $USER\n"
            "then log out and back in."
        )


def docker_group_not_active_yet():
    # SUDO_USER means we already reran through sudo, so don't try again
    if os.environ.get("SUDO_USER") or shutil.which("sudo") is None:
        return False
    try:
        docker_group = grp.getgrnam("docker")
    except KeyError:
        return False
    user = pwd.getpwuid(os.getuid()).pw_name
    return user in docker_group.gr_mem and docker_group.gr_gid not in os.getgroups()


def compose(*args):
    result = run(["docker", "compose", *args])
    if result.returncode != 0:
        fail(f"'docker compose {' '.join(args)}' failed (see the output above).")


def wait_for_healthy_database(timeout=180):
    print("Waiting for MySQL to be ready", end="", flush=True)
    deadline = time.time() + timeout

    while time.time() < deadline:
        result = run(
            ["docker", "inspect", "-f", "{{.State.Health.Status}}", DB_CONTAINER],
            quiet=True,
        )
        if result.stdout.strip() == "healthy":
            print(" ready.")
            return
        print(".", end="", flush=True)
        time.sleep(3)

    print()
    fail("MySQL did not become ready. Check it with:  docker compose logs db")


def grant_database_access(env):
    # MySQL's own setup scripts only run when its data volume is first created,
    # so grant access here too. That covers databases set up by older versions.
    database = env["MYSQL_DATABASE"]
    user = env["MYSQL_USER"]
    sql = (
        f"GRANT ALL PRIVILEGES ON `{database}`.* TO '{user}'@'%';\n"
        f"GRANT ALL PRIVILEGES ON `{database}\\_%`.* TO '{user}'@'%';\n"
    )

    # the root password is read inside the container, so it never appears on this machine's command line
    result = run(
        ["docker", "compose", "exec", "-T", "db", "sh", "-c", 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" 2>&1'],
        input_text=sql,
        quiet=True,
    )
    if result.returncode != 0:
        fail("Could not grant database access:\n" + result.stdout)


def wait_for_app(port, timeout=300):
    print("Waiting for PhoneVault to answer", end="", flush=True)
    url = f"http://127.0.0.1:{port}/up"
    deadline = time.time() + timeout

    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                if response.status == 200:
                    print(" ready.")
                    return
        except (urllib.error.URLError, ConnectionError, OSError):
            pass
        print(".", end="", flush=True)
        time.sleep(3)

    print()
    run(["docker", "compose", "--profile", "app", "logs", "--tail", "50", "app"])
    fail("PhoneVault did not start. The last log lines are above.")


# --- .env -----------------------------------------------------------------

def ensure_env_file():
    if not ENV_FILE.exists():
        shutil.copyfile(ENV_EXAMPLE, ENV_FILE)
        print("Created .env from .env.example")

    lines = ENV_FILE.read_text().splitlines()
    env = parse_env(lines)
    database_exists = database_volume_exists()
    changes = {}

    for key, value in DEFAULTS.items():
        if not env.get(key):
            changes[key] = value

    for key, generate in GENERATED_SECRETS.items():
        value = env.get(key, "")
        needs_value = not value or "change_me" in value

        # an existing database already uses its passwords, so changing them would lock Rails out
        if needs_value and key.startswith("MYSQL_") and database_exists and value:
            print(f"Warning: {key} still looks like the example value, but the database already uses it. Leaving it.")
            continue

        if needs_value:
            changes[key] = generate()

    if changes:
        write_env(lines, changes)
        env.update(changes)
        # only the names are printed; secret values stay in .env
        print("Set in .env: " + ", ".join(sorted(changes)))
    else:
        print(".env is complete")

    ENV_FILE.chmod(0o600)
    return env


def parse_env(lines):
    env = {}
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip("'\"")
    return env


def write_env(lines, changes):
    remaining = dict(changes)
    updated = []

    for line in lines:
        key = line.split("=", 1)[0].strip() if "=" in line and not line.lstrip().startswith("#") else None
        if key in remaining:
            updated.append(f"{key}={remaining.pop(key)}")
        else:
            updated.append(line)

    if remaining:
        updated.append("")
        updated.append("# Added by launch.py")
        updated.extend(f"{key}={value}" for key, value in remaining.items())

    ENV_FILE.write_text("\n".join(updated) + "\n")


def database_volume_exists():
    result = run(["docker", "compose", "config", "--format", "json"], quiet=True)
    if result.returncode != 0:
        return False
    project = json.loads(result.stdout).get("name", "")
    return run(["docker", "volume", "inspect", f"{project}_mysql_data"], quiet=True).returncode == 0


# --- backup folder ----------------------------------------------------------

def ensure_backup_folder(env):
    folder = Path(env.get("PHONEVAULT_BACKUP_ROOT") or PROJECT_DIR / "storage" / "backups").expanduser()
    if not folder.is_absolute():
        folder = PROJECT_DIR / folder

    try:
        folder.mkdir(parents=True, exist_ok=True)
    except PermissionError:
        fail(f"Can't create {folder}. Create it yourself with:\n  sudo mkdir -p {folder} && sudo chown {APP_UID}:{APP_UID} {folder}")

    owner = folder.stat().st_uid
    if owner == APP_UID:
        print(f"Backups will be stored in {folder}")
    elif os.geteuid() == 0:
        os.chown(folder, APP_UID, APP_UID)
        print(f"Backups will be stored in {folder} (owner set to user id {APP_UID})")
    else:
        fail(
            f"{folder} must be owned by user id {APP_UID}, the user PhoneVault runs as inside Docker.\n"
            f"Fix it with:\n  sudo chown {APP_UID}:{APP_UID} {folder}"
        )


# --- helpers ----------------------------------------------------------------

def run(command, quiet=False, input_text=None):
    return subprocess.run(
        command,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE if quiet else None,
        stderr=subprocess.STDOUT if quiet else None,
    )


def local_ip_address():
    # connecting a UDP socket picks the outgoing network interface without sending anything
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("10.255.255.255", 1))
            return probe.getsockname()[0]
    except OSError:
        return None


def home_relative(path):
    # "~" means "your home folder", so the default install shows ~/PhoneVault-2.0 for every user
    try:
        return "~/" + str(path.relative_to(Path.home()))
    except ValueError:
        return str(path)


def step(message):
    print(f"\n==> {message}")


def fail(message):
    print(f"\nError: {message}", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
