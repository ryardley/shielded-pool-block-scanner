#!/usr/bin/env bash
# Create a terminal-wallet wallet on the local chain and fund its public
# address from anvil account 0, so it can be shielded immediately.
#
#   TW_PASSWORD=changeme123 ./scripts/create-and-fund-wallet.sh "Wallet A"
#   TW_PASSWORD=changeme123 ./scripts/create-and-fund-wallet.sh "Wallet A" 50
#
# The password (>= 8 chars) must match the one used in the terminal wallet TUI.
# Amount defaults to 10 ETH.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPC_URL="http://127.0.0.1:8545"
FUNDER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
NAME="${1:-}"
AMOUNT="${2:-10}"

[ -n "$NAME" ] || { echo "usage: $0 <wallet-name> [amount-eth]" >&2; exit 1; }

output="$("$SCRIPT_DIR/tw-create-wallet.sh" "$NAME")"
addr="$(printf '%s\n' "$output" | sed -n 's/^public:  *//p')"
[ -n "$addr" ] || { echo "could not read public address from tw-create-wallet" >&2; exit 1; }

printf '%s\n' "$output"

echo "funding $addr with ${AMOUNT} ETH from $FUNDER…"
cast send --unlocked --rpc-url "$RPC_URL" --from "$FUNDER" "$addr" --value "${AMOUNT}ether"
echo "balance: $(cast balance --ether --rpc-url "$RPC_URL" "$addr") ETH"
echo
echo "wallet is on Local Anvil (31337). Run terminal-wallet-cli, enter your"
echo "password, then Shield ETH from Public Actions to start the demo."
