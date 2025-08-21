#!/usr/bin/env bash
set -euo pipefail

DEFAULT_BOX_NAME="dev-fedora"
DEFAULT_IMAGE="registry.fedoraproject.org/fedora:40"

# Interactive prompts (press Enter for defaults)
if [ -z "${BOX_NAME-}" ]; then
  read -rp "Enter Distrobox name [${DEFAULT_BOX_NAME}]: " BOX_NAME
  BOX_NAME="${BOX_NAME:-$DEFAULT_BOX_NAME}"
fi
if [ -z "${IMAGE-}" ]; then
  read -rp "Enter Distrobox base image [${DEFAULT_IMAGE}]: " IMAGE
  IMAGE="${IMAGE:-$DEFAULT_IMAGE}"
fi

need_cmd() { command -v "$1" >/dev/null 2>&1; }

echo "==> Checking for distrobox..."
if ! need_cmd distrobox; then
  echo "ERROR: 'distrobox' not installed. On Bazzite: sudo rpm-ostree install distrobox && reboot"; exit 1
fi

if ! need_cmd podman && ! need_cmd docker; then
  echo "WARNING: no podman/docker detected; distrobox may fail to create the container."
fi

echo "==> Ensuring Distrobox '${BOX_NAME}' exists (image: ${IMAGE})..."
if ! distrobox list | awk 'NR>1 {print $1}' | grep -qx "${BOX_NAME}"; then
  # auto-pull, no prompt
  podman image exists "${IMAGE}" || podman pull "${IMAGE}" || docker pull "${IMAGE}" || true
  distrobox create -n "${BOX_NAME}" -i "${IMAGE}" --additional-flags "--device=/dev/kvm"
else
  echo "   ...box already exists; reusing."
fi

echo "==> Entering box and provisioning VS Code + libsecret..."
distrobox enter "${BOX_NAME}" -- bash -lc '
  set -euo pipefail

  echo "   -> DNF update + base deps..."
  sudo dnf -y update || true
  sudo dnf -y install \
    git-credential-libsecret libsecret gnome-keyring dbus-daemon which \
    ca-certificates curl gnupg2

  echo "   -> Add VS Code yum repo (if missing) and install..."
  if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    cat <<'"'"'REPO'"'"' | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
  fi
  sudo dnf -y check-update || true
  sudo dnf -y install code

  echo "   -> Configure Git to use libsecret..."
  git config --global --unset-all credential.helper || true
  git config --global credential.helper libsecret

  echo "   -> Add keyring bootstrap to shell rc (for VS Code terminal sessions)..."
  # pick rc file
  SHELL_RC=""
  if [ -n "${ZSH_VERSION-}" ]; then SHELL_RC="$HOME/.zshrc"; fi
  if [ -n "${BASH_VERSION-}" ]; then SHELL_RC="$HOME/.bashrc"; fi
  if [ -z "$SHELL_RC" ]; then SHELL_RC="$HOME/.bashrc"; fi

  # define marker BEFORE use; also use default in grep to satisfy nounset
  BOOTSTRAP_MARK="Distrobox Git + libsecret bootstrap"
  if ! grep -q "${BOOTSTRAP_MARK:-Distrobox Git + libsecret bootstrap}" "$SHELL_RC" 2>/dev/null; then
    cat <<'"'"'RCBLOCK'"'"' >> "$SHELL_RC"

# ---- Distrobox Git + libsecret bootstrap ----
# Start a user D-Bus if none exists (needed for Secret Service in containers)
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && command -v dbus-launch >/dev/null 2>&1; then
  eval "$(dbus-launch --sh-syntax)"  >/dev/null 2>&1
fi
# Start gnome-keyring (Secret Service) if not already running
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if ! pgrep -u "$USER" gnome-keyring-d >/dev/null 2>&1; then
    eval "$(gnome-keyring-daemon --start)" >/dev/null 2>&1
    export SSH_AUTH_SOCK
  fi
fi
# ---- end bootstrap ----
RCBLOCK
  fi

  echo "   -> Export VS Code back to the host menu (safe if already exported)..."
  if command -v distrobox-export >/dev/null 2>&1; then
    distrobox-export --app code || true
  fi

  echo "   -> Quick smoke test hints:"
  echo "      - Open a NEW terminal in VS Code or re-enter the box so the bootstrap loads."
  echo "      - Run: git fetch (first time will prompt and store via Secret Service)."
'

echo "==> All done.

Launch:
  distrobox enter ${BOX_NAME} -- code
If Git in VS Code terminal still complains:
  exec \$SHELL -l
"
