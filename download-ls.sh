#!/usr/bin/env bash
set -euo pipefail

API_URL='https://api.github.com/repos/Exafunction/codeium/releases/latest'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/windsurf"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  ASSET=language_server_linux_x64 ;;
  aarch64|arm64) ASSET=language_server_linux_arm ;;
  *) echo "!!! Unsupported arch: $arch" >&2; exit 1 ;;
esac

mkdir -p "$OUT_DIR"
target="$OUT_DIR/$ASSET"

if [ -x "$target" ]; then
  echo "===> Binary already exists: $target"
  echo "===> Delete it first if you want to re-download."
  ls -lh "$target"
  exit 0
fi

echo "===> Architecture: $arch -> $ASSET"
echo "===> Fetching latest Exafunction/codeium release..."

TMPFILE="$(mktemp)"
curl -fsSL "$API_URL" > "$TMPFILE"

# Try jq first, fall back to python3, then to simple grep+sed
if command -v jq >/dev/null 2>&1; then
  url="$(jq -r --arg a "$ASSET" '.assets[] | select(.name == $a) | .browser_download_url' < "$TMPFILE")"
elif command -v python3 >/dev/null 2>&1; then
  url="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(next((a['browser_download_url'] for a in d.get('assets',[]) if a['name']=='$ASSET'),''))" < "$TMPFILE")"
else
  # Simple sed extraction
  url="$(sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*'"$ASSET"'[^"]*\)".*/\1/p' "$TMPFILE" | head -1)"
fi

rm -f "$TMPFILE"

if [ -z "$url" ]; then
  echo "!!! Could not find asset $ASSET in latest release." >&2
  echo "!!! Visit https://github.com/Exafunction/codeium/releases and download manually." >&2
  exit 1
fi

echo "===> Downloading: $url"
curl -fL --progress-bar -o "$target" "$url"
chmod +x "$target"

size="$(du -h "$target" | cut -f1)"
echo "===> Done! Saved to: $target ($size)"
echo "===> Now run: docker compose up -d"
