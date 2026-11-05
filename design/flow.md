# Scan flow and actix-web integration

## Pages

| Step | File | Route |
|------|------|-------|
| 1. Viewing key + start date | `scan.html` | `GET /` |
| 2. Scan progress | `scanning.html` | `GET /scan/{id}` |
| 3. Transaction table | `transactions.html` | `GET /scan/{id}/transactions` |

## Routes

| Method | Route | Behaviour |
|--------|-------|-----------|
| GET  | `/` | Render the form. |
| POST | `/scan` | Form fields: `viewing_key`, `chain`, `start_date` (YYYY-MM-DD, UTC). Validate. On error, re-render `scan.html` with status 422 and the error banner visible (do not echo the key back). On success, resolve start date to block, create the job, respond `303 See Other` to `/scan/{id}`. |
| GET  | `/scan/{id}` | Render progress page with current values filled in (works without JS via `<noscript>` refresh). |
| GET  | `/scan/{id}/status` | JSON, polled once per second. |
| POST | `/scan/{id}/cancel` | Cancel the job, `303` to `/`. |
| GET  | `/scan/{id}/transactions` | Render the table. If the job is still running, `303` to `/scan/{id}`. |
| GET  | `/scan/{id}/export.csv` | Same rows as the table, one column per `LedgerTx` field. |

Status JSON:

```json
{
  "state": "running",          // running | done | failed | cancelled
  "phase": "decrypt",          // commitments | decrypt | ppoi | ledger
  "from_block": 24136000,
  "to_block": 26354112,
  "scanned_block": 25012000,
  "found": 4,
  "error": null
}
```

```rust
#[derive(Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ScanState { Running, Done, Failed, Cancelled }

#[derive(Serialize)]
pub struct ScanStatus {
    pub state: ScanState,
    pub phase: &'static str,
    pub from_block: u64,
    pub to_block: u64,
    pub scanned_block: u64,
    pub found: usize,
    pub error: Option<String>,
}
```

## Mapping `LedgerTx` to the table

Each tx renders two `<tr>`: a summary row (`data-tx`) and a hidden detail row (`data-detail`). The filter JS reads the `data-*` attributes on the summary row.

| Column / attribute | Source |
|---|---|
| `data-kind` | `TxKind` variant name (`Receive`, `Send`, `Shield`, `Unshield`, `Fee`, `SelfTransfer`) |
| `data-status` | `TxStatus` variant name (`Confirmed`, `Pending`, `PpoiPending`) |
| `data-asset` | `asset` |
| `data-search` | `txid` + `memo`, lowercased |
| Kind badge class | `kind-{{ kind | lower }}` |
| Status class | `status-{{ status | lower }}` |
| Time | `timestamp.format("%Y-%m-%d %H:%M:%S")` |
| Amount | Sign prefix and class (`amt-pos` / `amt-neg` / `amt-zero`) from `amount.signum()`. Use `−` (U+2212) for negatives. Format precision per asset server-side. |
| Fee | `fee` or `—` |
| Block | `block`, thousands-separated |
| Transaction link | Explorer base URL per `ChainId` + `txid` |
| Detail row | `id`, `protocol`, `chain`, full `txid`, `memo` |

Summary cards (counts, net per asset) are computed server-side over the full ledger.

Askama is a reasonable fit for the templates: compile-time checked, and the `kind-*` / `status-*` classes map directly from enum `Display` impls. Use the `|lower` filter or implement a `css_class()` method on each enum.

## Tailwind in production

The pages load the Tailwind Play CDN for previewing. Replace it with a built stylesheet:

1. Download the Tailwind standalone CLI binary (no Node required).
2. Move the `@layer components { ... }` block from `transactions.html` into `input.css`.
3. Set `content` to your template directory, e.g. `templates/**/*.html`.
4. Build `static/app.css`, serve with `actix-files`, and replace the `<script src="https://cdn.tailwindcss.com">` and `<style type="text/tailwindcss">` tags with `<link rel="stylesheet" href="/static/app.css">`.

## Handling the viewing key

- Accept it only in the POST body. Never put it in a URL or query string.
- Exclude it from request logging and tracing spans.
- Use an unguessable scan id (UUIDv4 or 128-bit random). Anyone with `/scan/{id}/transactions` can read the history, so either bind the id to a session cookie or expire results.
- Decide on retention explicitly (in-memory for the job's lifetime vs persisted) and state it on the form.
