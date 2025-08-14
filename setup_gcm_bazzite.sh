#!/usr/bin/env bash
set -Eeuo pipefail

# -------- settings --------
GCM_VERSION="2.6.1"
GCM_TGZ="gcm-linux_amd64.${GCM_VERSION}.tar.gz"
GCM_URL="https://github.com/git-ecosystem/git-credential-manager/releases/download/v${GCM_VERSION}/${GCM_TGZ}"
INSTALL_DIR="${HOME}/.local/share/gcm"
BIN_DIR="${HOME}/.local/bin"
GCM_BIN="${INSTALL_DIR}/git-credential-manager"
SYMLINK="${BIN_DIR}/git-credential-manager"
# --------------------------

die() { echo "Error: $*" >&2; exit 1; }

# prerequisites
command -v git >/dev/null || die "git not found in PATH."
[ "$(uname -m)" = "x86_64" ] || die "This script targets x86_64. Download the right archive for your arch."

mkdir -p "${INSTALL_DIR}" "${BIN_DIR}"

# download to a temp file, then extract atomically
TMP_TGZ="$(mktemp)"
cleanup() { rm -f "${TMP_TGZ}"; }
trap cleanup EXIT

echo "Downloading GCM ${GCM_VERSION}..."
curl -fL --retry 3 --retry-delay 1 -o "${TMP_TGZ}" "${GCM_URL}" || die "Failed to download ${GCM_URL}"

echo "Extracting to ${INSTALL_DIR}..."
tar -xzf "${TMP_TGZ}" -C "${INSTALL_DIR}" || die "Failed to extract archive"
[ -x "${GCM_BIN}" ] || die "GCM binary not found after extract: ${GCM_BIN}"

echo "Creating symlink ${SYMLINK}..."
ln -sf "${GCM_BIN}" "${SYMLINK}"

# ensure ~/.local/bin is in PATH for this session
export PATH="${BIN_DIR}:$PATH"

# persist PATH for future shells (bash + zsh if present)
ensure_path_line='export PATH="$HOME/.local/bin:$PATH"'
if [ -f "${HOME}/.bashrc" ] && ! grep -Fq "${ensure_path_line}" "${HOME}/.bashrc"; then
  echo "${ensure_path_line}" >> "${HOME}/.bashrc"
fi
if [ -f "${HOME}/.zshrc" ] && ! grep -Fq "${ensure_path_line}" "${HOME}/.zshrc"; then
  echo "${ensure_path_line}" >> "${HOME}/.zshrc"
fi

# configure git to use GCM (separate commands, with clear errors)
echo "Configuring Git to use GCM..."
git config --global credential.helper manager || die "Failed to set Git credential.helper"

echo "Running 'git-credential-manager configure'..."
if "${GCM_BIN}" configure; then
  echo "✅ GCM installed and configured successfully."
  echo "   You may need to open a new shell for PATH changes to take effect."
else
  echo "⚠️  GCM installed, but 'configure' failed."
  echo "   Try running it manually for more details:"
  echo "     ${GCM_BIN} configure"
  exit 1
fi
