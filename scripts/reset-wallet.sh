#!/usr/bin/env bash
# Reset the terminal-wallet runtime state — keychain, encrypted seed (engine
# db), config and logs — WITHOUT touching the large cached downloads
# (node_modules, dist, .railgun.artifacts, npm-cache, contract deps).
# Safe to run any time, from `devenv shell`. Your mnemonic is lost (it was only
# ever shown once); re-create a wallet with scripts/tw-create-wallet.sh.
#
#   ./scripts/reset-wallet.sh                    # wallet data only
#   ./scripts/reset-wallet.sh --with-artifacts   # also delete proving artifacts
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TW_SRC="$ROOT_DIR/railgun-cache/tw-src"

if pgrep -f 'dist/main.js' >/dev/null 2>&1; then
  echo "terminal wallet is running — quit it first, then retry." >&2
  exit 1
fi

[ -d "$TW_SRC" ] || { echo "no terminal wallet at $TW_SRC (run ./scripts/install.sh)"; exit 0; }

du -sh "$TW_SRC/.railgun.db" "$TW_SRC/.zKeyChains" 2>/dev/null || true
read -r -p "Delete wallet data (keychain + encrypted seed + config + logs)? [y/N] " a
[ "$a" = "y" ] || [ "$a" = "Y" ] || { echo "aborted"; exit 1; }

rm -rf "$TW_SRC/.railgun.db" "$TW_SRC/.zKeyChains" "$TW_SRC/twallet.config.json"
rm -f "$TW_SRC"/*.log
echo "deleted wallet data (downloads kept)"

if [ "${1:-}" = "--with-artifacts" ]; then
  du -sh "$TW_SRC/.railgun.artifacts" 2>/dev/null || true
  read -r -p "Also delete proving artifacts (.railgun.artifacts)? They re-download on demand. [y/N] " a
  [ "$a" = "y" ] || [ "$a" = "Y" ] || { echo "artifacts kept"; exit 0; }
  rm -rf "$TW_SRC/.railgun.artifacts"
  echo "deleted proving artifacts"
fi
