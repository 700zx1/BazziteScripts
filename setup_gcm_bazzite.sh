#!/usr/bin/env bash
# Installs Git Credential Manager (user-mode) and configures Git to use
# the 'manager' helper with the Secret Service credential store on Bazzite.
# Verbose output is enabled.

set -euxo pipefail
set -x

# --- Settings ---
GCM_VERSION="2.6.1"
GCM_TGZ="gcm-linux_amd64.${GCM_VERSION}.tar.gz"
GCM_URL="https://github.com/git-ecosystem/git-credential-manager/releases/download/v${GCM_VERSION}/${GCM_TGZ}"
INSTALL_DIR="${HOME}/.local/share/gcm"
BIN_DIR="${HOME}/.local/bin"
GCM_BIN="${INSTALL_DIR}/git-credential-manager"
SYMLINK="${BIN_DIR}/git-credential-manager"
# ---------------

# Pre-flight
command -v git >/dev/null
mkdir -p "${INSTALL_DIR}" "${BIN_DIR}"

# Download to a temp file (safer), then extract
TMP_TGZ="$(mktemp)"
trap 'rm -f "${TMP_TGZ}"' EXIT
curl -fL --retry 3 --retry-delay 1 -o "${TMP_TGZ}" "${GCM_URL}"
tar -xzf "${TMP_TGZ}" -C "${INSTALL_DIR}"

# Ensure the binary exists and is executable
test -x "${GCM_BIN}"

# Put it on PATH via a stable symlink
ln -sf "${GCM_BIN}" "${SYMLINK}"

# Ensure ~/.local/bin is on PATH now and later
export PATH="${BIN_DIR}:$PATH"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
grep -Fq "${PATH_LINE}" "${HOME}/.bashrc" 2>/dev/null || echo "${PATH_LINE}" >> "${HOME}/.bashrc"
grep -Fq "${PATH_LINE}" "${HOME}/.zshrc"  2>/dev/null || echo "${PATH_LINE}" >> "${HOME}/.zshrc"

# Configure Git to use GCM helper and Secret Service store
git config --global --replace-all credential.helper manager
git config --global --replace-all credential.credentialStore secretservice

# Run GCM configure (sets up auth flow)
"${GCM_BIN}" configure

# Show final state
git config --global --get-all credential.helper
git config --global --get credential.credentialStore
echo "GCM installed at: ${GCM_BIN}"
echo "Symlink on PATH:  ${SYMLINK}"
echo "Done. First 'git push' over HTTPS will open a browser for login."
echo "If you see store errors, ensure a Secret Service daemon (e.g., gnome-keyring or KeePassXC with Secret Service) is running."
echo "If you ever need to switch stores: git config --global --replace-all credential.credentialStore secretservice   # recommended
# or: cache | gpg | plaintext | none
"
