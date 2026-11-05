# Shielded Pool Block Scanner

A fully local RAILGUN demo: anvil (chain 31337) + Terminal Wallet. No public
network, no real keys, no real funds. All tools come from devenv; everything
heavy lives in `railgun-cache/` (gitignored, durable, never deleted by scripts).

## Commands

```sh
devenv shell                # enter env: node 22, anvil, cast, git + terminal-wallet-cli command
./scripts/install.sh        # one-time install (~1GB first run, cached after)
./scripts/up.sh             # start anvil + deploy contracts (fast)
terminal-wallet-cli         # run the wallet
```

`up.sh --stop` stops anvil, `up.sh --fresh` resets chain state. The only way to
delete `railgun-cache/` (installed deps + artifacts) is `./scripts/purge-cache.sh`.

## In the wallet

1. First boot: set a local password, create wallet A.
2. Utilities → **Switch Network** → **Local Anvil (31337)**.
3. **Shield:** Public Actions → Shield → ETH → amount. No POI wait on 31337.
4. **Send A→B:** create wallet B (Wallet Tools → New / Import), then
   Private Actions → Send → B's 0zk address → amount → fee: **Self-send**.
5. **Balances:** Utilities → Refresh Balances.

See `scripts/DEMO.md` for the full walkthrough and timings.
