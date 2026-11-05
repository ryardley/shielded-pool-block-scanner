#!/usr/bin/env bash
# Launch anvil (chain 31337) + deploy the RAILGUN contracts. Fast + cached.
# Run from `devenv shell`.
#
#   ./scripts/up.sh            start anvil + deploy (if not already deployed)
#   ./scripts/up.sh --fresh    wipe chain state, fresh anvil, deploy
#   ./scripts/up.sh --stop     stop anvil
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE="$ROOT_DIR/railgun-cache"
CHAIN_ID=31337
RPC_URL="http://127.0.0.1:8545"
STATE_FILE="$CACHE/railgun-demo.state"
ANVIL_LOG="$CACHE/anvil.log"
ANVIL_PID_FILE="$CACHE/anvil.pid"
DEPLOY_LOG="$CACHE/deploy.log"
CONTRACT="$CACHE/contract"
TW_SRC="$CACHE/tw-src"
PROXY_ADDR="0x610178dA211FEF7D417bC0e6FeD39F05609AD788"

anvil_up() { [ "$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null || true)" = "$CHAIN_ID" ]; }

case "${1:-}" in
  --stop)
    [ -f "$ANVIL_PID_FILE" ] && kill "$(cat "$ANVIL_PID_FILE")" 2>/dev/null || true
    pkill -f "anvil --chain-id $CHAIN_ID" 2>/dev/null || true
    echo "anvil stopped"; exit 0 ;;
  --fresh) rm -f "$STATE_FILE" "$ANVIL_PID_FILE" ;;
esac

# ensure installed once
[ -d "$CONTRACT/node_modules" ] && [ -d "$TW_SRC/node_modules" ] || "$SCRIPT_DIR/install.sh"

if ! anvil_up; then
  if [ -f "$STATE_FILE" ]; then
    anvil --chain-id "$CHAIN_ID" --code-size-limit 100000 --load-state "$STATE_FILE" >"$ANVIL_LOG" 2>&1 &
  else
    anvil --chain-id "$CHAIN_ID" --code-size-limit 100000 --state "$STATE_FILE" >"$ANVIL_LOG" 2>&1 &
  fi
  echo $! > "$ANVIL_PID_FILE"
  for _ in $(seq 1 60); do anvil_up && break; sleep 1; done
  anvil_up || { echo "anvil failed; see $ANVIL_LOG" >&2; exit 1; }
fi
echo "anvil up: $RPC_URL (chain $CHAIN_ID)"

code="$(cast code --rpc-url "$RPC_URL" "$PROXY_ADDR" 2>/dev/null || true)"
if [ -z "$code" ] || [ "$code" = "0x" ]; then
  echo "deploying RAILGUN contracts…"
  (cd "$CONTRACT" && npm run deploy) >"$DEPLOY_LOG" 2>&1
  echo "deployed (log: $DEPLOY_LOG)"
else
  echo "contracts already deployed at $PROXY_ADDR"
fi

cat <<EOF

RAILGUN local chain ready: $RPC_URL (chain $CHAIN_ID)
  proxy: $PROXY_ADDR

Run the wallet (a command, installed once):
  terminal-wallet-cli

  Then: Utilities -> Switch Network -> "Local Anvil (31337)"
        Public Actions -> Shield -> ETH        (no POI wait on 31337)
        Private Actions -> Send -> 0zk recipient -> Self-send fee
EOF
