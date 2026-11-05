# Shielded Pool Block Scanner

A fully local RAILGUN demo: anvil (chain 31337) + Terminal Wallet. No public
network, no real keys, no real funds. All tools come from devenv; everything
heavy lives in `railgun-cache/` (gitignored, durable, never deleted by scripts).

## Commands

```sh
devenv shell                # enter env: node 22, anvil, cast, git + terminal-wallet-cli command
./scripts/install.sh        # one-time install (~1GB first run, cached after)
./scripts/up.sh             # start anvil + deploy contracts (fast)
TW_PASSWORD=changeme123 ./scripts/create-and-fund-wallet.sh "Wallet A"   # create + fund 10 ETH
terminal-wallet-cli         # run the wallet
```

`up.sh --stop` stops anvil, `up.sh --fresh` stops anvil and resets chain state
(so an interrupted deploy can be redone). The only way to delete `railgun-cache/`
(installed deps + artifacts) is `./scripts/purge-cache.sh`.

> The first deploy (`up.sh --fresh`) takes **several minutes** while it writes
> circuit artifacts on-chain. Do not interrupt it — `up.sh` verifies the wrapped
> token (WETH9) is actually deployed and refuses to treat a partial deploy as
> done.

`create-and-fund-wallet.sh` creates the wallet, funds its public address from
anvil account 0, and sets the wallet's network to **Local Anvil (31337)**, so the
TUI opens straight onto the local chain.

## In the wallet

1. First boot: set a local password (the one you used for `create-and-fund-wallet.sh`).
2. **Shield:** open the palette with `:` → Public Actions → Shield → ETH → amount. No POI wait on 31337.
3. **Send A→B:** create wallet B (Wallet Tools → New / Import), then
   `:` → Private Actions → Send → B's 0zk address → amount → fee: **Self-send**.
4. **Balances:** `:` → Utilities → Refresh Balances, or click the sync card.

See `scripts/DEMO.md` for the full walkthrough and timings.
