#!/usr/bin/env bash
# Installs what PhoneVault needs on a fresh Linux machine, then starts it.
#
#   curl -fsSL https://raw.githubusercontent.com/benstahatch/PhoneVault-2.0/main/install.sh | bash
#
# or, on systems without curl (like Ubuntu Desktop):
#
#   wget --no-verbose --output-document=- https://raw.githubusercontent.com/benstahatch/PhoneVault-2.0/main/install.sh | bash
#
# or, inside a clone of the repository:  ./install.sh
#
# It installs only what is missing: git, curl, python3, and Docker (through the
# official get.docker.com script). Supports apt (Debian, Ubuntu, Raspberry Pi OS)
# and dnf (Fedora). Then it runs launch.py, which sets up and starts PhoneVault.
set -euo pipefail

REPO_URL="https://github.com/benstahatch/PhoneVault-2.0.git"
BRANCH="${PHONEVAULT_BRANCH:-main}"
INSTALL_DIR="${PHONEVAULT_DIR:-$HOME/PhoneVault-2.0}"
CURRENT_USER="${USER:-$(id -un)}"

say() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nError: %s\n' "$1" >&2; exit 1; }

# root can install packages directly; everyone else goes through sudo
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  command -v sudo >/dev/null || fail "sudo is needed to install packages. Install git, curl, python3, and Docker yourself, then run: python3 launch.py"
  SUDO="sudo"
fi

if command -v apt-get >/dev/null; then
  install_packages() { $SUDO apt-get update -qq && $SUDO apt-get install -y -qq "$@"; }
elif command -v dnf >/dev/null; then
  install_packages() { $SUDO dnf install -y -q "$@"; }
else
  fail "This system has neither apt nor dnf. Install git, curl, python3, and Docker yourself, then run: python3 launch.py"
fi

say "Checking git, curl, and python3"
missing=()
for tool in git curl python3; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "Installing: ${missing[*]}"
  install_packages "${missing[@]}"
else
  echo "All installed."
fi

say "Checking Docker"
if command -v docker >/dev/null; then
  echo "Docker is installed."
else
  echo "Installing Docker with the official script from get.docker.com"
  curl -fsSL https://get.docker.com | $SUDO sh
fi

# make sure the Docker service runs now and after every reboot
$SUDO systemctl enable --now docker >/dev/null 2>&1 || true

if ! docker compose version >/dev/null 2>&1; then
  echo "Installing the Docker Compose plugin"
  install_packages docker-compose-plugin
fi

# let this user run docker without sudo; the group applies fully at the next login
if [ -n "$SUDO" ] && ! id -nG "$CURRENT_USER" | grep -qw docker; then
  $SUDO usermod -aG docker "$CURRENT_USER"
  echo "Added $CURRENT_USER to the docker group."
fi

say "Getting PhoneVault"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"

if [ -f "$script_dir/launch.py" ]; then
  project_dir="$script_dir"
  echo "Using this copy: $project_dir"
elif [ -f "$INSTALL_DIR/launch.py" ]; then
  project_dir="$INSTALL_DIR"
  echo "Using the existing copy in $project_dir (run 'git pull' there to update it)"
else
  git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
  project_dir="$INSTALL_DIR"
fi

cd "$project_dir"

say "Starting PhoneVault"
# if the docker group was just added, launch.py reruns itself through sudo,
# so no logout or restart is needed
python3 launch.py
