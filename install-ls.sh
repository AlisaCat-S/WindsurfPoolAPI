#!/usr/bin/env bash
# Install / update the Windsurf language server binary.
#
# Usage:
#   ./install-ls.sh                        # install latest from Exafunction/codeium
#   ./install-ls.sh /path/to/local.bin     # install a local file
#   ./install-ls.sh --url <direct-url>     # install from a custom URL
#
# Default location: /opt/windsurf/language_server_linux_x64
# Override with LS_INSTALL_PATH env var.
set -euo pipefail

TARGET="${LS_INSTALL_PATH:-/opt/windsurf/language_server_linux_x64}"
EXAFUNCTION_API='https://api.github.com/repos/Exafunction/codeium/releases/latest'

log() { echo -e "\033[1;34m==>\033[0m $*"; }
err() { echo -e "\033[1;31m!!\033[0m  $*" >&2; }

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  ASSET='language_server_linux_x64' ;;
  aarch64|arm64) ASSET='language_server_linux_arm' ;;
  *) err "Unsupported arch: $arch"; exit 1 ;;
esac

mkdir -p "$(dirname "$TARGET")"

if [[ $# -gt 0 && "$1" != "--url" && -f "$1" ]]; then
  log "Installing from local file: $1"
  cp -f "$1" "$TARGET"
elif [[ $# -ge 2 && "$1" == "--url" ]]; then
  url="$2"
  log "Downloading from: $url"
  curl -fL --progress-bar -o "$TARGET" "$url"
else
  log "Fetching latest Exafunction/codeium release tag..."
  if command -v jq >/dev/null 2>&1; then
    url="$(curl -fsSL "$EXAFUNCTION_API" | jq -r \
      --arg asset "$ASSET" '.assets[] | select(.name == $asset) | .browser_download_url')"
  else
    url="$(curl -fsSL "$EXAFUNCTION_API" | \
      grep -oE "https://[^\"]+/${ASSET}" | head -1)"
  fi
  if [[ -z "$url" ]]; then
    err "Could not find asset '$ASSET' in latest release."
    err "Visit https://github.com/Exafunction/codeium/releases and download manually."
    exit 1
  fi
  log "Downloading: $url"
  curl -fL --progress-bar -o "$TARGET" "$url"
fi

chmod +x "$TARGET"
size="$(du -h "$TARGET" | cut -f1)"
sha="$(sha256sum "$TARGET" | cut -c1-16)"
log "Installed: $TARGET ($size, sha256:$sha...)"
log "Verify: $TARGET --help | head -5"
