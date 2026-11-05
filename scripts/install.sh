#!/usr/bin/env bash
# One-time install. Everything stays inside <repo>/railgun-cache (durable,
# gitignored). Idempotent + cached: safe to run any time, from `devenv shell`.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE="$ROOT_DIR/railgun-cache"
NPM_CACHE="$CACHE/npm-cache"
TW_SRC="$CACHE/tw-src"
CONTRACT="$CACHE/contract"
CONTRACT_URL="https://github.com/Railgun-Privacy/contract"
CONTRACT_COMMIT="36bcf5ed7cf94bfafb6e1a303e1832c769c16780"
TW_URL="https://github.com/Terminal-Wallet/terminal-wallet-cli"
TW_COMMIT="503d322dda11da81b47178bbd514dc258825a2bc"
TW_PATCH="$SCRIPT_DIR/terminal-wallet-localnet.patch"

# --- timing/logging -------------------------------------------------------
LOG_NAME="install"
# shellcheck source=./_log.sh
source "$SCRIPT_DIR/_log.sh"
init_log
trap print_summary EXIT

export npm_config_cache="$NPM_CACHE"
run_timed "cache dirs" mkdir -p "$CACHE" "$NPM_CACHE"

# --- clone/pin (only if missing) -------------------------------------------
clone_pin() {
  local url="$1" dir="$2" commit="$3" name
  name="$(basename "$dir")"
  if [ ! -d "$dir/.git" ]; then
    run_timed "clone $name" git clone --quiet "$url" "$dir"
  else
    log "SKIP clone $name: already cloned"
  fi
  run_timed "fetch $name" git -C "$dir" fetch --quiet origin
  run_timed "checkout $name" git -C "$dir" checkout --quiet "$commit"
  log "$name pinned to $(git -C "$dir" log -1 --format='%h %s')"
}

clone_pin "$TW_URL" "$TW_SRC" "$TW_COMMIT"
clone_pin "$CONTRACT_URL" "$CONTRACT" "$CONTRACT_COMMIT"

# --- Terminal Wallet patch (chain id 31337 + menu entry) --------------------
if (cd "$TW_SRC" && git apply --check "$TW_PATCH" 2>/dev/null); then
  run_timed "apply TW patch" bash -c 'cd "$1" && git apply "$2"' _ "$TW_SRC" "$TW_PATCH"
  log "applied TW patch"
elif (cd "$TW_SRC" && git apply --reverse --check "$TW_PATCH" 2>/dev/null); then
  log "TW patch already applied"
else
  echo "error: TW patch does not apply" >&2; exit 1
fi

# --- build TW once ----------------------------------------------------------
if [ -d "$TW_SRC/node_modules" ] && [ -f "$TW_SRC/dist/main.js" ]; then
  log "terminal-wallet: already built"
else
  log "installing + building Terminal Wallet (cached)"
  run_timed_in "$TW_SRC" "TW npm install" npm install --legacy-peer-deps
  run_timed_in "$TW_SRC" "TW build" npm run build
fi

# --- contract deps once (large, cached) -------------------------------------
if [ -d "$CONTRACT/node_modules" ]; then
  log "contracts: already installed"
else
  log "installing contracts (~1GB first time, then cached)"
  run_timed_in "$CONTRACT" "contracts npm install" npm install
fi

log "done. now run: ./scripts/up.sh"
print_summary
