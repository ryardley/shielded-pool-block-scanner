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
CONTRACT_PATCH="$SCRIPT_DIR/patches/contract-fast-deploy.patch"
PROXY_ADDR="0x610178dA211FEF7D417bC0e6FeD39F05609AD788"
# The wrapped native token (WETH9) address the terminal wallet expects on the
# local chain (shared-models Hardhat config). Its code being present is the
# cheap way to know the deploy actually finished: up.sh must NOT consider the
# deployment complete just because the proxy has code, or a deploy interrupted
# mid-“Setting Artifacts” silently leaves a chain the wallet can't read balances
# on (getTokenInfo throws for a code-less WETH9 and the whole public rail empties).
WETH9_ADDR="0xA7c59f010700930003b33aB25a7a0679C860f29c"

# --- timing/logging -------------------------------------------------------
LOG_NAME="up"
# shellcheck source=./_log.sh
source "$SCRIPT_DIR/_log.sh"
init_log
trap print_summary EXIT

anvil_up() { [ "$(timeout 3 cast chain-id --rpc-url "$RPC_URL" 2>/dev/null || true)" = "$CHAIN_ID" ]; }

anvil_stop() {
  [ -f "$ANVIL_PID_FILE" ] && kill "$(cat "$ANVIL_PID_FILE")" 2>/dev/null || true
  pkill -f "anvil --chain-id $CHAIN_ID" 2>/dev/null || true
  for _ in $(seq 1 10); do anvil_up || return 0; sleep 1; done
}

case "${1:-}" in
  --stop)
    anvil_stop
    log "anvil stopped"
    print_summary
    exit 0 ;;
  --fresh)
    # Stop a running anvil first: removing the state file alone does NOT reset
    # a live process, so `up.sh --fresh` previously reported success while the
    # old chain (and its incomplete deployment) kept running in memory.
    anvil_stop
    run_timed "wipe chain state" rm -f "$STATE_FILE" "$ANVIL_PID_FILE"
    log "fresh mode: chain state wiped" ;;
  *)
    log "mode: normal (use --fresh to reset, --stop to stop)" ;;
esac

# ensure installed once
if [ -d "$CONTRACT/node_modules" ] && [ -d "$TW_SRC/node_modules" ]; then
  log "deps already installed"
else
  log "deps missing; running install.sh"
  run_timed "install.sh" "$SCRIPT_DIR/install.sh"
fi

# ensure the contract fast-deploy patch is applied (idempotent). install.sh
# applies it after its git reset, but a cache installed before the patch existed
# needs it here too; a no-op when already applied.
if (cd "$CONTRACT" && git apply --check "$CONTRACT_PATCH" 2>/dev/null); then
  run_timed "apply contract patch" bash -c 'cd "$1" && git apply "$2"' _ "$CONTRACT" "$CONTRACT_PATCH"
  log "applied contract patch"
elif (cd "$CONTRACT" && git apply --reverse --check "$CONTRACT_PATCH" 2>/dev/null); then
  log "contract patch already applied"
else
  log "error: contract patch does not apply; run ./scripts/install.sh"
  exit 1
fi

if ! anvil_up; then
  if [ -f "$STATE_FILE" ]; then
    log "starting anvil (load-state)"
    anvil --chain-id "$CHAIN_ID" --code-size-limit 100000 --load-state "$STATE_FILE" >"$ANVIL_LOG" 2>&1 &
  else
    log "starting anvil (fresh state)"
    anvil --chain-id "$CHAIN_ID" --code-size-limit 100000 --state "$STATE_FILE" >"$ANVIL_LOG" 2>&1 &
  fi
  echo $! > "$ANVIL_PID_FILE"
  local_start=$(_now)
  for _ in $(seq 1 60); do anvil_up && break; sleep 1; done
  local_end=$(_now)
  if anvil_up; then
    _record "anvil startup" "$local_start" "$local_end" 0
  else
    _record "anvil startup" "$local_start" "$local_end" 1
    log "anvil failed; see $ANVIL_LOG"
    exit 1
  fi
else
  log "anvil already up"
fi
log "anvil up: $RPC_URL (chain $CHAIN_ID)"

run_timed "probe proxy code" bash -c 'cast code --rpc-url "$1" "$2" >/dev/null 2>&1 || true' _ "$RPC_URL" "$PROXY_ADDR"
code="$(cast code --rpc-url "$RPC_URL" "$PROXY_ADDR" 2>/dev/null || true)"
if [ -z "$code" ] || [ "$code" = "0x" ]; then
  log "deploying RAILGUN contracts (several minutes; do not interrupt)…"
  run_timed_in "$CONTRACT" "deploy contracts" bash -c 'npm run deploy 2>&1 | tee "$1"' _ "$DEPLOY_LOG"
  log "deployed (log: $DEPLOY_LOG)"
else
  # Proxy is up — but the deployment is only complete if the wrapped token the
  # wallet reads (WETH9) also has code. A deploy interrupted mid-artifacts leaves
  # a proxy that passes the check above and a chain the wallet shows no balance
  # on, so this must stop rather than claim success.
  weth_code="$(cast code --rpc-url "$RPC_URL" "$WETH9_ADDR" 2>/dev/null || true)"
  if [ -z "$weth_code" ] || [ "$weth_code" = "0x" ]; then
    log "error: RAILGUN deployment is incomplete — WETH9 missing at $WETH9_ADDR"
    log "error: run ./scripts/up.sh --fresh to redeploy from scratch"
    exit 1
  fi
  log "contracts already deployed at $PROXY_ADDR"
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
print_summary
