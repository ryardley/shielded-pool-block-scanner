# RAILGUN local demo — walkthrough

A fully local RAILGUN demo: anvil (chain 31337) + Terminal Wallet. No public
network, no real keys, no real funds.

Everything is installed by **devenv** (see `devenv.nix` at the repo root) and
kept in `railgun-cache/` (gitignored, durable). Enter the environment first:

```sh
devenv shell    # provides node 22, anvil, cast, git + the terminal-wallet-cli command
```

## 1. Exact command sequence

```sh
# One-time install: clone+pinned commits, npm installs (cached), build TW.
# The first run downloads ~1GB of contract artifacts; after that it is cached.
./scripts/install.sh

# Each session: launch anvil + deploy contracts (fast, idempotent).
./scripts/up.sh

# Create a wallet and fund its public address (10 ETH from anvil account 0),
# then switch the wallet's network to Local Anvil so the TUI boots onto the
# local chain. The password (>= 8 chars) must match the TUI's.
TW_PASSWORD=changeme123 ./scripts/create-and-fund-wallet.sh "Wallet A"

# Stop anvil (state preserved) / reset chain state (stops anvil first):
./scripts/up.sh --stop
./scripts/up.sh --fresh
```

> **The first deploy takes several minutes** (it writes circuit artifacts
> on-chain, one tx each). `up.sh` prints progress from the deploy script and
> then **verifies the wrapped token (WETH9) is deployed** — if a deploy was
> interrupted mid-artifacts, `up.sh` refuses to continue and tells you to run
> `./scripts/up.sh --fresh`. Do not interrupt the deploy.

`install.sh` and `up.sh` never touch `railgun-cache/` except to read/write it.
The only way to delete the cache (installed deps + downloaded artifacts) is
`./scripts/purge-cache.sh`, which asks before deleting.

### Starting Terminal Wallet

```sh
terminal-wallet-cli
```

The launcher `cd`s into `railgun-cache/tw-src` so the wallet's data
(`.railgun.db`, `.railgun.artifacts`, `.zKeyChains`) is written into the
durable cache, not your current directory. It also points the app's
remote-config fetch at anvil (`REMOTE_CONFIG_RPC=http://127.0.0.1:8545`) so it
never touches a public network — the fetch fails there and the app falls back
to its baked-in defaults, which is all the local chain needs.

## 2. Terminal Wallet menu paths

The app is a keyboard-driven deck with five columns
(Private / Public / Morpho / f(x) / Utilities). The command palette is opened
with `:`; most actions also live on the clickable cards along the top.

| Action | Menu path |
| ------ | --------- |
| Open the command palette | `:` (or Ctrl-K) |
| Switch to local chain | `:` → Utilities → **Switch Network** → **Local Anvil (31337)** (or click the network card) |
| Shield ETH | `:` → Public Actions → **Shield** → pick **ETH** → amount → confirm |
| Private transfer A→B | `:` → Private Actions → **Send** → pick recipient 0zk address → amount → confirm |
| Check balances | `:` → Utilities → **Refresh Balances** (or click the sync card) |
| Create wallet B | Wallet Tools / **New / Import Wallet** |

### First boot

1. Set a local password — **the same one you used for
   `create-and-fund-wallet.sh`** (it encrypts the seed).
2. If you used the script, wallet A already exists and is on **Local Anvil
   (31337)** with its public address funded — the dashboard shows it.
3. Otherwise create wallet A (or import a mnemonic) and fund its public 0x
   address from anvil account 0, e.g.
   `cast send --unlocked --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 <addr> --value 100ether`.
4. `:` → Utilities → **Switch Network** → **Local Anvil (31337)**. The first
   switch triggers a merkletree scan from block 0.

### Shield

- Public Actions → **Shield** → select **ETH** → enter amount (e.g. 10).
- Confirm. Chain 31337 has **no POI config** (`NetworkName.Hardhat` in
  shared-models 8.2.1 has no `poi` block), so there is **no POI wait**: the
  shielded balance appears as **Spendable** immediately after the scan picks up
  the deposit.
- Note the 0.25% shield fee (25 basis points, set by the local `deploy:test`).

### Private transfer (A → B)

- Private Actions → **Send** → choose wallet B's **0zk** address as recipient
  (add it under Add / Edit Contacts or paste) → amount → review.
- In the **Transaction fee** menu choose **Self-send** (your public wallet pays
  gas). There are no broadcasters on a local chain, so the broadcaster path is
  not available — self-send is the only route.
- Confirm. Proof generation runs (see timing below), then the tx is submitted
  directly to the proxy and mined by anvil.

### Second wallet B

- Wallet Tools → **New / Import Wallet**, give it a name and a new mnemonic, or
  import an existing one. `Switch Wallet` moves between A and B.
- Wallet B needs no ETH: private 0zk→0zk transfers pay gas from wallet A's
  public address (self-signed), so B only ever holds shielded balances.

## 3. Expected timings

| Step | Time (first run) | Time (later) |
| ---- | ---------------- | ------------ |
| `./scripts/install.sh` — pulls ~1GB contract artifacts + TW deps | several minutes | seconds (cached) |
| anvil + contract deploy (`deploy:test`) — first run writes every circuit artifact on-chain, one tx each; `up.sh` re-deploys if it detects an incomplete one | ~5–10 min | seconds (`up.sh`) |
| Merkle-tree scan (chain 31337, from block 0) | seconds (local RPC) | seconds |
| **First proof generation** (shield or transfer) — downloads proving artifacts (IPFS) on demand, cached under `railgun-cache/tw-src/.railgun.artifacts` | ~1–3 min | ~10–60 s |
| Subsequent proofs | — | faster (cached) |

The artifact download only happens once; after that proofs reuse the cache in
`railgun-cache`. First-run proof generation is the main "wait".

## 4. Verifying the result

- Wallet B sees each transfer after a `Refresh Balances`; the shield fee is
  taken at shield time (0.25%), so shielded amounts are `sent × (1 − 0.0025)`.
- `./scripts/up.sh` after a restart brings the chain back from
  `railgun-cache/railgun-demo.state` with contracts and balances intact.
