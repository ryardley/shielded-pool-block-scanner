
# Build plan: Railgun/Armada scanner sidecar

## Goal
Build a Docker image containing a Node/TypeScript process that, for each block's pool-contract logs, emits the facts that Railgun or Armada viewing keys can derive from that block alone. It listens on a Unix socket, keeps no state between requests, and has no storage. A separate Rust service writes the facts to an event log and reconstructs all state centrally.

## Ground rules for the agent
- **The sidecar is a pure function.** The same keys and the same block always produce the same events in the same order.
- **No state:** no wallet, no database, no Merkle tree, no RPC provider, no network calls, no disk writes. Use only the crypto and ABI-parsing functions of the pinned SDK.
- **No business logic.** Don't classify transactions as sends or receives beyond what is listed below, and don't compute balances or match spends. Central projections do that.
- **Pin exact versions** of Node and every dependency, and commit the lockfile.
- **Never log** keys, decrypted note contents, amounts or memos.
- **Record findings in `DECISIONS.md`**, with file and function references into the SDK source.
- **If something in this plan proves impossible** with the SDK primitives, stop and record it. Don't work around it by adding state.

## Scope
- **Protocols:** Railgun (V2 contract events) and Armada, selected by a config profile. Armada's crypto core is byte-compatible with Railgun's. Only the contract address, chain ID and possibly the event ABI differ.
- **Tokens:** ERC-20 only. Skip NFTs.
- **Out of scope:** legacy Railgun V1 events, PPOI lookups, proving and spending.

## Events emitted

```ts
type Event =
  | { kind: "noteReceived"; id: Hex; account: string; txHash: Hex; logIndex: number;
      tree: number; position: number;            // leaf index in the commitment tree
      commitment: Hex; nullifier: Hex;            // nullifier precomputed from key + position
      blindedCommitment: Hex;                     // for PPOI lookups elsewhere
      token: Hex; amount: string; memo: string | null;
      scope: "external" | "change" | "shield" }
  | { kind: "outputSent"; id: Hex; account: string; txHash: Hex; logIndex: number;
      tree: number; position: number;
      token: Hex; amount: string; memo: string | null;
      outputType: "transfer" | "broadcasterFee"; recipient: string | null }
  | { kind: "nullifiersRevealed"; id: Hex; txHash: Hex; logIndex: number;
      tree: number; nullifiers: Hex[] }           // public; every nullifier in the block
  | { kind: "unshieldObserved"; id: Hex; txHash: Hex; logIndex: number;
      to: Hex; token: Hex; amount: string; fee: string };   // public
```

- `id = keccak256(protocol, chainId, txHash, logIndex, position or index, account or "public", kind)`. Fix and document the exact encoding.
- Order events by `(logIndex, position, account, kind)`.

## Classification per commitment and key
1. **Shield commitments.** Decrypt the shield ciphertext with the account's viewing key. If it succeeds, emit `noteReceived` with scope `shield`.
2. **Transact commitments.** First try to decrypt the annotation data with the account's key.
   - If that succeeds, the account is the sender. Read `outputType`:
     - `change`: emit `noteReceived` with scope `change`. The note is still owned and will be spent later, so the projection needs it.
     - `transfer` or `broadcasterFee`: emit `outputSent`.
     - If the account is both sender and recipient of a transfer (sending to itself), emit both `outputSent` and `noteReceived` with scope `external`. Determine how to detect this in Phase 1.
   - If it fails but the note decrypts with the key, the account is the receiver. Emit `noteReceived` with scope `external`.
   - If neither succeeds, emit nothing for this key.
3. **Nullified events.** Emit `nullifiersRevealed` for every one, regardless of keys.
4. **Unshield events.** Emit `unshieldObserved` for every one, regardless of keys.

## Phase 0: Setup
- TypeScript, strict mode, vitest, eslint. Pin Node LTS.
- Add `@railgun-community/engine` at an exact version. Add `@armada/sdk` at an exact commit only if Phase 1 shows the Armada ABI or crypto differs.
- Lay out the source: `src/core/` (pure scanning), `src/config/` (protocol profiles), `src/keys/`, `src/wire/`, `src/server/`, `test/`.

**Done when:** `npm test` passes on an empty suite.

## Phase 1: SDK investigation (no product code)
Document in `DECISIONS.md`, with file and function references:
1. The ABI and fields of the `Transact`, `Shield`, `Nullified` and `Unshield` events. How to get the tree number and start position, and from those each commitment's leaf position.
2. Receiver-side note decryption with a viewing private key: the shared key from blinded viewing keys, then AES-GCM.
3. Sender-side annotation decryption. What it contains (`outputType`, sender random). Whether the sender can also decrypt the note and recover the recipient address.
4. Shield ciphertext decryption.
5. Nullifier derivation: the formula, which key it needs, and whether that key derives from the viewing private key or comes from the shareable viewing key.
6. Blinded commitment computation as used by PPOI.
7. Parsing a shareable viewing key into the parts needed for items 2 to 6.
8. Token hash to ERC-20 address mapping, and how to detect non-ERC-20 tokens.
9. Whether Armada's contract events and ABI match Railgun V2. List any differences.
10. How to construct test notes encrypted to a test key: shield, transfer, change and broadcaster fee.

Write a throwaway spike that proves items 2, 3, 5 and 6 on hand-built notes.

**Done when:** the spike decrypts a note, tells sender from receiver, and produces a nullifier and blinded commitment matching the engine's own wallet for the same note.

## Phase 2: Core function
```ts
scanBlock(profile: ProtocolProfile, keys: Map<AccountId, ViewingKeys>, block: BlockLogs): Event[]
```
- Pure and synchronous where the SDK allows, with no I/O.
- Ignores logs from other contracts and unknown event types. Throws a typed error on malformed logs from the pool contract.
- Applies the classification rules above and returns events in the defined order.

## Phase 3: Fixtures and tests
Generate synthetic logs with the SDK's own encryption, using three test keys (A, B, C). Cover:
1. A shield to A: `noteReceived` with scope `shield`.
2. A transfers to B with change and a broadcaster fee:
   - for A: `outputSent` (transfer), `outputSent` (broadcaster fee), and `noteReceived` (change);
   - for B: `noteReceived` (external).
3. A sends to itself.
4. Two outputs to B in one transaction: distinct IDs.
5. A note encrypted to an unknown key: no account events.
6. A non-ERC-20 note: skipped.
7. `Nullified` and `Unshield` logs: public events emitted with no keys loaded.
8. Malformed pool log: typed error. Logs from other contracts: ignored.
9. Determinism: the same input gives byte-identical output.
10. **Cross-check against the engine's wallet.** For fixture keys, nullifiers and blinded commitments must equal what the engine's wallet computes for the same notes.

Also capture one real mainnet block with Railgun `Transact` and `Nullified` logs. It must parse, emit only the public events with unrelated keys, and those events must match the on-chain data.

## Phase 4: Keys and config
- **Keys:** `loadKeys(path)` reads `{ "account_id": "<shareable viewing key>" }` at startup and fails with the offending account ID, never the key. This function is the only key source, so it can later be swapped for a KMS-based version.
- **Profiles:** `{ protocol: "railgun" | "armada", chainId, poolAddress }`, from a config file. The sidecar serves exactly one profile per process.

## Phase 5: Wire protocol and socket server
- A Unix socket at `SOCKET_PATH` with mode 0600. Remove any stale socket at startup, and clean up on SIGTERM.
- Each frame is a u32 big-endian length followed by UTF-8 JSON, up to 16 MiB. Reject larger declared lengths before allocating.
- One request at a time per connection, and requests processed one at a time globally.

```ts
type Request =
  | { type: "scan"; block: { number: number; hash: Hex; parentHash: Hex; logs: Log[] };
      accounts?: string[] }               // optional subset, for backfilling one account
  | { type: "health" };

type Response =
  | { type: "scan"; blockNumber: number; blockHash: Hex; events: Event[] }
  | { type: "health"; ok: true; protocol: string; chainId: number; accounts: number }
  | { type: "error"; message: string };
```

- `accounts` restricts which keys are tried. Public events are always emitted.
- An empty `events` array is a valid response.

**Done when:** tests cover a round trip, a frame split across writes, two frames in one write, an oversized frame, invalid JSON, an unknown request type, an unknown account in `accounts`, and a client disconnecting mid-frame.

## Phase 6: Logging hygiene
- Structured JSON logs to stdout: startup (profile and account count), each scan (block number, event counts by kind, duration) and errors.
- Add a test that captures all logs over the fixture scans and asserts that no key material, amounts, memos or recipients appear.

## Phase 7: Docker image
- Multi-stage build. The runtime stage holds only production dependencies and compiled JS, and runs as a non-root user with a fixed, documented UID.
- Configuration through `SOCKET_PATH`, `KEYS_PATH` and `PROFILE_PATH`.
- Document the run command: `--network none --read-only`, the socket directory as a volume, and the keys and profile as read-only mounts.

## Phase 8: End-to-end check
- Write `scripts/client.ts` that sends fixture blocks over the socket and diffs the responses against the expected events.
- Run the container with fixture keys and confirm the client's diff is empty.
- Measure scan time per block with 1, 100 and 1,000 keys, and record it in `DECISIONS.md`.

## Deliverables
- Source, tests, fixtures, Dockerfile.
- `README.md` covering how to run it, the socket protocol, event definitions, the keys and profile formats, and security notes.
- `DECISIONS.md` covering SDK functions used, the classification method, the ID encoding, Armada differences and performance numbers.

---

The main risk is in Phase 1, items 3 and 5. If sender-side annotation decryption or nullifier derivation from a shareable viewing key doesn't work as assumed, the agent will stop and record it, and the event model will need adjusting before Phase 2.
