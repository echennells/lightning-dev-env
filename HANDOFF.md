# Handoff — Lightning Dev Environment

Context for an agent picking up work in this repo. Read `README.md` for the full topology
and port map; this file covers what the project is *for*, how to test it, and the traps.

## What this is

A **Bitcoin + Lightning regtest stack for QA'ing LNbits extensions** — especially ones that
touch Taproot Assets, RFQ (sats→asset conversion), and LNURL. Everything runs locally under
`docker compose`, and the same stack runs in GitHub Actions across a version matrix.

The point is *integration* testing against real nodes and real channels — not unit tests. When
a test here pays an invoice, sats actually move across a channel between two lnd nodes.

Extensions under test live as **sibling directories**, not inside this repo:

| Extension | Location | Version | Purpose |
|---|---|---|---|
| taproot_assets | `./taproot_assets` (nested clone) | branch `tapd-v0.8.0` | asset minting, asset invoices, RFQ |
| bitcoinswitch | `../bitcoinswitch` | branch `taproot-address-support` | pay-to-switch hardware, asset support |
| laisee | `../laisee_extension` | tag `v0.7` | digital red envelopes (newest addition) |
| lnurlp / withdraw / lnurlFlip | cloned by `bootstrap-lnurl-extensions.sh` | pinned | LNURL plumbing |

`setup-lnbits-extensions.sh` copies these into the LNbits containers and registers them in
each instance's SQLite DB. Note laisee's folder (`laisee_extension`) differs from its
extension id (`laisee`) — the copy step renames it.

## Topology in one paragraph

One `bitcoind` regtest node. Two `litd` nodes (integrated lnd + tapd) named `litd-1` and
`litd-2` that share a **taproot asset channel**. One plain `lnd`. One `lnd-rfq-payer` that has
*only* a channel to litd-1, so paying a litd-2 asset invoice is forced through an RFQ route
hint. Four LNbits instances, one per node: `lnbits-1→litd-1` (5001), `lnbits-2→litd-2` (5002),
`lnbits-3→lnd` (5003), `lnbits-4→lnd-rfq-payer` (5004).

Logins: LNbits `admin` / `password123`. LiT UIs `password`. Bitcoin RPC
`http://lightning:lightning@localhost:18443`.

## Running it

```bash
./bootstrap-with-taproot-assets.sh   # full fresh stack (~30-45 min, mostly pip + restarts)
./test-suite.sh                      # 25 assertions
./destroy.sh                         # compose down -v + rm -rf data/*
```

Bootstrap is the whole world: clones extensions, generates SSL, starts containers, mines
blocks, funds nodes, opens 5 channels, mints a taproot asset, opens the asset channel, then
chains into `setup-lnbits-extensions.sh` → `bootstrap-lnurl-extensions.sh` →
`fund-lnbits-wallets.sh`. API keys land in `lnbits_keys.env` — `source` it before poking
anything with curl.

The version matrix (CI) is driven by `version-matrix.json`:

```bash
./run-matrix-tests.sh --list
./run-matrix-tests.sh --set stable
```

## How the tests are written

`test-suite.sh` is a flat bash script, ~1200 lines, no framework. Helpers are `start_test`,
`pass_test`, `fail_test`; the summary at the bottom exits non-zero on any failure. Tests are
numbered sequentially in comment banners.

The house style, worth matching:

- Talk to LNbits **from inside its own container** — `docker compose exec -T lnbits-1 curl -s
  "http://localhost:5000/..."`. Callback URLs use internal hostnames, so host-side curl breaks.
- Move money with `lncli` in the node containers: `docker compose exec -T litd-2 lncli
  --network=regtest --rpcserver=litd-2:10010 payinvoice --force "$BOLT11"`.
- Get admin keys either from `lnbits_keys.env` or by copying the DB out:
  `docker cp <container>:/app/data/database.sqlite3 /tmp/x.db && sqlite3 /tmp/x.db "SELECT adminkey FROM wallets ..."`.
- Guard every assertion so a missing prerequisite produces `fail_test` rather than a `set -e` abort.
- **Never pay an LNbits instance from its own backing node** — lnbits-1 is litd-1, so fund its
  invoices from litd-2 (or vice versa). Self-payment fails.

## Laisee — the newest thing under test (tests 21-25)

A digital red envelope: **one stateful LNURL** that serves LNURL-pay while unfunded, flips to
LNURL-withdraw for exactly the amount paid in once funded, then goes dead once claimed. Same
QR throughout — the protocol underneath changes. Upstream is
[`Liongrass/laisee_extension`](https://github.com/Liongrass/laisee_extension); `v0.7` is
current HEAD of `origin/master` (June 2026, nothing newer).

Installed on lnbits-1 and lnbits-2. UI at `http://localhost:5001/laisee/`.

Driving it programmatically (this is exactly what tests 21-24 do — see
`scratchpad/laisee-demo.sh` for a runnable version):

```bash
POST /laisee/api/v1/laisees            # admin key → {id, unique_hash, k1, lnurl}
GET  /laisee/api/v1/lnurl/<hash>       # unfunded → {"tag":"payRequest", minSendable, maxSendable}
GET  /laisee/api/v1/lnurl/pay-cb/<hash>?amount=<MSAT>&comment=<txt>   # → {"pr": bolt11}
# ...pay that bolt11 from a different node...
GET  /laisee/api/v1/lnurl/<hash>       # funded → {"tag":"withdrawRequest", k1, min==max}
GET  /laisee/api/v1/lnurl/withdraw-cb/<hash>?k1=<k1>&pr=<bolt11>      # → {"status":"OK"}
```

Two easy mistakes: the pay callback takes **millisats** while `min_sats`/`max_sats` are in
**sats**; and the claim invoice must equal `paid_amount` within 1 sat or it's rejected.

The interesting property to keep testing is the **withdraw-once invariant** — the extension
claims the envelope with a conditional `UPDATE ... WHERE is_withdrawn = FALSE` *before*
touching Lightning. Test 24 covers the sequential replay case; test 25 fires six concurrent
claims and asserts exactly one wins.

## Security audit notes (2026-08)

Adversarial run against the live stack confirmed five issues in laisee, none caught by
the semgrep report in `../laisee_extension/static_analysis_semgrep_1/`:

1. **Multi-funder over-collection** — `pay-cb` mints a fresh invoice on every call while
   unfunded; all minted invoices stay payable even after funding (Lightning can't recall
   them). Extra payments credit the owner's wallet silently; envelope only acknowledges
   the first. Verified: two invoices minted, both paid after funding, wallet +200,
   envelope `paid_amount=100`.
2. **Invoice key leaks claim credential** — list/detail endpoints accept the invoice key
   and return `unique_hash`+`k1` (the bearer withdraw link). Verified drain with invoice
   key only. NOTE: unclear how anyone would obtain the read-only invoice key in practice —
   owner has to share it; no escalation path found from invoice key to admin key, and no
   unauthenticated leaks. Severity depends on whether you treat the invoice key as shared.
3. **Wallet ownership bypass** — `CreateLaiseeData.wallet` used verbatim; accepted foreign
   wallet IDs (403'd the creator afterward, proving the bypass). Funded sats became a
   phantom credit.
4. **HTTP 500 on bad invoice** — unguarded `decode_bolt11(pr)`.
5. **±1 sat claim tolerance admits over-claims** — only LNbits core's `max_sat` caught it.

Checked and NOT vulnerable: concurrent double-withdraw (6-way race → 1 winner, now test 25),
k1 rejection, replay-after-spend, negative/zero/over-max amounts, revert-on-failure.

**All five issues are fixed** in the local `../laisee_extension` checkout (branch
`security-fixes-audit-2026-09`) and deployed into the running containers; every fix was
re-attacked live after patching. Finding #3's drain was later executed end-to-end on a
single-instance multi-user setup (attacker-bound envelope paid out of a victim wallet's
balance). Full write-up in `../laisee_extension/SECURITY_AUDIT.md`; fixes submitted upstream
as [Liongrass/laisee_extension#3](https://github.com/Liongrass/laisee_extension/pull/3).

## Known traps

**The `taproot_assets` branch pin is broken.** `bootstrap-with-taproot-assets.sh` defaults to
`TAPROOT_ASSETS_VERSION=cleanup-and-race-fixes`, which no longer exists upstream — a clean
bootstrap dies immediately on `git checkout`. `version-matrix.json` says `main`; the local
checkout is `tapd-v0.8.0`. Override until this is resolved:

```bash
TAPROOT_ASSETS_VERSION=tapd-v0.8.0 ./bootstrap-with-taproot-assets.sh
```

**Never edit a shell script while it's executing.** Bash reads scripts incrementally, so an
edit mid-run corrupts execution and throws a bogus syntax error. Make edits between runs.

**A wiped `bitcoin-data` volume silently poisons everything.** If `bitcoind` is recreated
without its volume, the chain resets to height 0 while the lnd nodes still hold state from the
old chain — they crash-loop with confusing errors. Check
`bitcoin-cli getblockchaininfo | jq .blocks`; if it's 0 but `./data/` has node state, you need
a full `./destroy.sh && ./bootstrap-with-taproot-assets.sh`.

**Bootstrap is slow and looks hung.** Most of the wall time is `pip install` inside containers
plus fixed `sleep 25` restart waits, repeated per LNbits instance. Confirm progress by checking
the log's mtime rather than assuming it's stuck.

**Browser cookie jar.** All LNbits share `localhost`, so you can only be logged into one port
at a time per browser profile. Use incognito for the second.

## Repo state

On `main`, with **uncommitted** changes across `README.md`, `test-suite.sh`,
`setup-lnbits-extensions.sh`, `bootstrap-with-taproot-assets.sh`, `run-matrix-tests.sh`,
`version-matrix.json`, `build-from-source.sh`, `docker-compose.yml`, and the CI workflow.
The laisee integration is part of that uncommitted set. Nothing has been committed or pushed.

Last full run: **25/25 passing**.

## Debugging

```bash
docker compose logs --tail=100 litd-1
docker compose exec litd-1 lncli --network=regtest getinfo
docker compose exec litd-1 tapcli --network=regtest --rpcserver=localhost:10009 \
  --tlscertpath=/root/.lnd/tls.cert \
  --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets balance
docker compose exec bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getblockchaininfo
```
