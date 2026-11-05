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
CONTRACT_PATCH="$SCRIPT_DIR/patches/contract-fast-deploy.patch"

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
  # reset --hard, not checkout: a previously-applied patch leaves the working
  # tree dirty, and `git checkout <commit>` then refuses to move. The cache is
  # disposable, so a hard reset is the correct way to get a pristine tree for
  # the patch step below.
  run_timed "reset $name" git -C "$dir" reset --hard --quiet "$commit"
  log "$name pinned to $(git -C "$dir" log -1 --format='%h %s')"
}

clone_pin "$TW_URL" "$TW_SRC" "$TW_COMMIT"
clone_pin "$CONTRACT_URL" "$CONTRACT" "$CONTRACT_COMMIT"

# --- Terminal Wallet patch (chain id 31337 + menu entry + balance fallback) ---
PATCH_APPLIED=0
if (cd "$TW_SRC" && git apply --check "$TW_PATCH" 2>/dev/null); then
  run_timed "apply TW patch" bash -c 'cd "$1" && git apply "$2"' _ "$TW_SRC" "$TW_PATCH"
  PATCH_APPLIED=1
  log "applied TW patch"
elif (cd "$TW_SRC" && git apply --reverse --check "$TW_PATCH" 2>/dev/null); then
  log "TW patch already applied"
else
  echo "error: TW patch does not apply" >&2; exit 1
fi

# --- Contract patch: fast + verbose artifact loading -------------------------
# `clone_pin` resets the contract repo, so re-apply here. Keeps all 91
# setVerificationKey txs but drops ethers' 4s receipt polling to ~100ms (anvil
# automines instantly) and prints per-artifact progress.
if (cd "$CONTRACT" && git apply --check "$CONTRACT_PATCH" 2>/dev/null); then
  run_timed "apply contract patch" bash -c 'cd "$1" && git apply "$2"' _ "$CONTRACT" "$CONTRACT_PATCH"
  log "applied contract patch"
elif (cd "$CONTRACT" && git apply --reverse --check "$CONTRACT_PATCH" 2>/dev/null); then
  log "contract patch already applied"
else
  echo "error: contract patch does not apply" >&2; exit 1
fi

# --- SDK patch: disable POI on local-only chains ----------------------------
# patch-package patches applied by `npm install`'s postinstall. Stage the repo
# copy into tw-src/patches/ so it survives purge + reinstall.
TW_SDK_PATCH="$SCRIPT_DIR/patches/@railgun-community+wallet+11.2.0.patch"
if [ -f "$TW_SDK_PATCH" ]; then
  mkdir -p "$TW_SRC/patches"
  cp "$TW_SDK_PATCH" "$TW_SRC/patches/"
  log "staged SDK patch $(basename "$TW_SDK_PATCH")"
else
  log "warn: SDK patch missing at $TW_SDK_PATCH"
fi

# --- build TW ---------------------------------------------------------------
# npm install only when deps are missing; the build runs when deps are missing
# OR the patch changed (a patch edit leaves dist/ stale, and a stale dist would
# run the old logic while src/ carries the new).
if [ ! -d "$TW_SRC/node_modules" ]; then
  log "installing Terminal Wallet deps (cached)"
  run_timed_in "$TW_SRC" "TW npm install" npm install --legacy-peer-deps
fi
if [ "$PATCH_APPLIED" = 1 ] || [ ! -f "$TW_SRC/dist/main.js" ]; then
  log "building Terminal Wallet"
  run_timed_in "$TW_SRC" "TW build" npm run build
else
  log "terminal-wallet: already built"
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
