#!/usr/bin/env bash
# Download the Windsurf Language Server binary for the current architecture.
# Usage: ./download-ls.sh
# The binary is saved to ./windsurf/ and mounted into the container.
set -euo pipefail

EXAFUNCTION_API='https://api.github.com/repos/Exafunction/codeium/releases/latest'
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/windsurf"

log() { echo -e "[1;34m===>[0m $*"; }
err() { echo -e "[1;31m!!![0m  $*" >&2; }

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  ASSET='language_server_linux_x64' ;;
  aarch64|arm64) ASSET='language_server_linux_arm' ;;
  *) err "Unsupported arch: $arch"; exit 1 ;;
esac

mkdir -p "$OUT_DIR"
target="$OUT_DIR/$ASSET"

if [ -x "$target" ]; then
  log "Binary already exists: $target"
  log "Delete it first if you want to re-download."
  ls -lh "$target"
  exit 0
fi

log "Architecture: $arch -> $ASSET"
log "Fetching latest Exafunction/codeium release..."

if command -v jq >/dev/null 2>&1; then
  url="$(curl -fsSL "$EXAFUNCTION_API" | jq -r     --arg asset "$ASSET" '.assets[] | select(.name == $asset) | .browser_download_url')"
else
  url="$(curl -fsSL "$EXAFUNCTION_API" |     grep -oE "https://[^"]+/${ASSET}" | head -1)"
fi

if [ -z "$url" ]; then
  err "Could not find asset '$ASSET' in latest release."
  err "Visit https://github.com/Exafunction/codeium/releases and download manually."
  exit 1
fi

log "Downloading: $url"
curl -fL --progress-bar -o "$target" "$url"
chmod +x "$target"

size="$(du -h "$target" | cut -f1)"
log "Done! Saved to: $target ($size)"
log "Now run: docker compose up -d"
