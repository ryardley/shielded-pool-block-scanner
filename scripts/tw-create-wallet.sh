#!/usr/bin/env bash
# Headless wallet generation for the local RAILGUN demo. Creates a fresh wallet
# (or imports one via TW_MNEMONIC) in the terminal-wallet keychain and prints
# its public 0x + 0zk addresses and the mnemonic.
#
#   TW_PASSWORD=changeme123 ./scripts/tw-create-wallet.sh "Wallet A"
#   TW_PASSWORD=changeme123 TW_MNEMONIC="..." ./scripts/tw-create-wallet.sh "Wallet B"
#
# The password (>= 8 chars) encrypts the seed and must match the password used
# when opening the terminal wallet TUI. The mnemonic is printed once and never
# stored in plaintext — back it up.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TW_SRC="$ROOT_DIR/railgun-cache/tw-src"

[ -d "$TW_SRC/node_modules" ] && [ -f "$TW_SRC/dist/main.js" ] || {
  echo "terminal wallet not installed — run ./scripts/install.sh first" >&2
  exit 1
}
[ -n "${TW_PASSWORD:-}" ] || {
  echo "TW_PASSWORD is required (min 8 chars)" >&2
  exit 1
}

cd "$TW_SRC"
export REMOTE_CONFIG_RPC="${REMOTE_CONFIG_RPC:-http://127.0.0.1:8545}"
exec node "$SCRIPT_DIR/tw-create-wallet.js" "$@"
