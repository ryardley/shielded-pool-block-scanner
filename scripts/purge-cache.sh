#!/usr/bin/env bash
# THE ONLY destructive command: deletes the durable railgun-cache.
# Everything else in this repo leaves railgun-cache alone.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT_DIR/railgun-cache"
[ -d "$CACHE" ] || { echo "no cache at $CACHE"; exit 0; }
du -sh "$CACHE"
read -r -p "Delete railgun-cache? This removes installed node_modules + artifacts. [y/N] " a
[ "$a" = "y" ] || [ "$a" = "Y" ] || { echo "aborted"; exit 1; }
rm -rf "$CACHE"
echo "deleted $CACHE"
