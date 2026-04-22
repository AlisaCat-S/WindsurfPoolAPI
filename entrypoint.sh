#!/bin/sh
set -e

# Ensure runtime state files exist.
# When docker-compose bind-mounts a file that doesn't exist on the host,
# Docker creates a root-owned directory instead — this script fixes that.
for f in accounts.json stats.json runtime-config.json proxy-config.json model-access.json; do
  target="/app/$f"
  # If Docker created a directory instead of a file, remove it first
  if [ -d "$target" ]; then
    rm -rf "$target"
  fi
  if [ ! -f "$target" ]; then
    echo '{}' > "$target"
  fi
done

mkdir -p /app/logs 2>/dev/null || true

exec node src/index.js "$@"
