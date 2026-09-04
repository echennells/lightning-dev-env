# Lightning Development Environment

Bitcoin + Lightning regtest stack for testing Taproot Assets, RFQ payments, and LNbits extensions. Runs locally via `docker compose` and in GitHub Actions via a version matrix.

## Topology

```
                       ┌─────────────────────────────┐
                       │          bitcoind           │
                       │    (regtest, port 18443)    │
                       └─────────────────────────────┘

  ┌───────────────────┐                             ┌───────────────────┐
  │       lnd         │◄────────── sat ────────────►│      litd-2       │
  │  (standalone,     │◄────────── sat ────────────►│  integrated lnd   │
  │   sats only)      │                             │  + tapd           │
  └───────────────────┘                             └─────────▲─────────┘
                                                              │
                                                          sat │
                                                              │
                                                    ══ asset ═╪═════╗
                                                              │     ║
                                                    ┌─────────▼─────▼───┐
                                                    │       litd-1      │
                                                    │   integrated lnd  │
                                                    │   + tapd          │
                                                    └─────────▲─────────┘
                                                              │
                                                          sat │
                                                              │
                                                    ┌─────────┴─────────┐
                                                    │   lnd-rfq-payer   │
                                                    │ (sats only, only  │
                                                    │  routes via       │
                                                    │  litd-1 → RFQ)    │
                                                    └───────────────────┘
```

Each node has a matching LNbits wallet UI as its REST client:

| LNbits | Backs | Port | Taproot assets? |
|---|---|---|---|
| lnbits-1 | litd-1 | 5001 | yes |
| lnbits-2 | litd-2 | 5002 | yes |
| lnbits-3 | lnd | 5003 | no |
| lnbits-4 | lnd-rfq-payer | 5004 | no (RFQ test payer) |

## Login

All LNbits instances use the same credentials:

- **Username:** `admin`
- **Password:** `password123`

Lightning Terminal UIs (litd-1: `https://localhost:8443`, litd-2: `https://localhost:8444`) use password-only login: `password`.

**Cookie-jar gotcha:** browsers share cookies across all `localhost` ports. To be logged into two LNbits at once, use a normal window for one and an incognito/private window for the other, or use separate browser profiles.

Bitcoin RPC: `http://lightning:lightning@localhost:18443`.

## Channels (built by `bootstrap-with-taproot-assets.sh`)

| # | Type | Opener → Peer | Capacity | Local / Remote after push |
|---|---|---|---|---|
| 1 | sat | litd-1 → lnd | 10 M sat | 5 M / 5 M |
| 2 | sat | litd-2 → lnd | 10 M sat | 5 M / 5 M |
| 3 | sat | litd-1 → litd-2 | 10 M sat | 5 M / 5 M |
| 4 | sat | lnd-rfq-payer → litd-1 | 10 M sat | 5 M / 5 M |
| 5 | **taproot asset** | litd-1 → litd-2 | 50 000 units (+ 15 000 sat push) | 35 000 / 15 000 units |

`lnd-rfq-payer` has **only** channel #4 — no direct path to litd-2 — which forces RFQ route hints to be used when paying a taproot-asset invoice.

## RFQ payment flow (sats → asset)

The canonical test: pay a taproot-asset invoice on lnbits-2 with sats from lnbits-4.

1. Create an asset invoice in lnbits-2 (`http://localhost:5002/taproot_assets/`).
2. Paste the bolt11 into lnbits-4's Pay screen (`http://localhost:5004/`).
3. The invoice's route hint directs payment `lnd-rfq-payer → litd-1 → [RFQ conversion via asset channel] → litd-2`.
4. lnbits-4 spends sats; lnbits-2 sees an asset-balance increase.

Mock price oracle is hardcoded to `100 000 asset units per BTC`.

## Laisee (red envelopes)

[`Liongrass/laisee_extension`](https://github.com/Liongrass/laisee_extension), pinned to `v0.7`. Installed into
lnbits-1 and lnbits-2 by `setup-lnbits-extensions.sh` (repo folder is `laisee_extension`, extension id is `laisee`).
UI at `http://localhost:5001/laisee/`.

One envelope is a single LNURL that changes mode with its own state — pay once, then withdraw once:

1. Create an envelope (`POST /laisee/api/v1/laisees`, admin key) with a `min_sats`/`max_sats` range.
2. While unfunded the LNURL (`GET /laisee/api/v1/lnurl/<unique_hash>`) serves an **LNURL-pay** request.
3. The sender hits the pay callback, gets a bolt11, and pays it. The invoice listener in `tasks.py` marks the
   envelope funded and records `paid_amount` (and the comment, when `allow_comment` is set).
4. The *same* LNURL now serves an **LNURL-withdraw** for exactly `paid_amount` — the recipient scans it to claim.
5. Once claimed the envelope is spent: the withdraw callback and the LNURL both return an error.

Tests 21-24 in `test-suite.sh` drive that whole path against real channels (funded from litd-2, claimed back to
litd-2), including the double-withdraw rejection.

## Services & ports

| Service | Host port | Purpose |
|---|---|---|
| bitcoind | 18443, 29000, 29001 | regtest RPC + zmq |
| litd-1 | 8443 (LiT UI), 10009 (lnd gRPC), 8083 (lnd REST), 9735 (P2P), 10029 (tapd gRPC) | integrated lnd + tapd |
| litd-2 | 8444, 10010, 8084, 9736, 10030 | integrated lnd + tapd |
| lnd | 10011, 8085, 9737 | standalone lnd |
| lnd-rfq-payer | 10012, 8086, 9738 | RFQ payer |
| lnbits-1..4 | 5001, 5002, 5003, 5004 | LNbits web UIs |
| lnbits-https-proxy | 5443 | self-signed HTTPS front for LNURL (routes to lnbits-2) |

## Running locally

```
./bootstrap-with-taproot-assets.sh   # fresh stack
./test-suite.sh                      # 20-test smoke suite
./destroy.sh                         # tear down + wipe ./data/
```

Keys, user IDs, and access tokens for the bootstrapped wallets are written to `lnbits_keys.env` — `source lnbits_keys.env` to use them with `curl`.

## Version matrix (CI)

`.github/workflows/test-version-matrix.yml` runs `./run-matrix-tests.sh --set <name>` against each set defined in `version-matrix.json`:

- `stable` — latest released versions; builds lnd from source (`lightningnetwork/lnd` tag `v0.20.1-beta`) via `build-from-source.sh`, cached with buildx + GHA cache.
- `bleeding-edge` — stable backends + LNbits `dev` branch built from source.
- `legacy` — one major back.

To run the matrix locally:

```
./run-matrix-tests.sh --list
./run-matrix-tests.sh --set stable
```

## Building lnd (and other components) from source

Per-version-set `build_from_source` entries in `version-matrix.json` drive `build-from-source.sh`:

```json
"build_from_source": {
  "lnd": {
    "repo": "https://github.com/lightningnetwork/lnd.git",
    "branch": "v0.20.1-beta",
    "dockerfile": "Dockerfile",
    "build_args": { "checkout": "v0.20.1-beta" }
  }
}
```

The script clones, tags the image as `local-<component>:dev`, and `run-matrix-tests.sh` exports `LND_IMAGE=local-lnd:dev` (or `LNBITS_IMAGE`, `LITD_IMAGE`) so `docker-compose.yml` picks up the local build. Inside GitHub Actions, buildx uses `type=gha` cache scoped by `<component>-<branch>` so re-runs only recompile what changed.

## Key files

- `docker-compose.yml` — all service definitions
- `bootstrap-with-taproot-assets.sh` — end-to-end setup (nodes, wallets, channels, asset mint, asset channel, extensions)
- `setup-lnbits-extensions.sh` — installs taproot_assets + bitcoinswitch + laisee extensions into each LNbits DB
- `fund-lnbits-wallets.sh` — sends sats + asset funds into each LNbits wallet
- `test-suite.sh` — 25 assertions covering sat payments, asset payments, RFQ, LNURL, lnurlFlip, bitcoinswitch, laisee
- `run-matrix-tests.sh` — drives one or all version sets
- `build-from-source.sh` — per-set source builds (lnd, lnbits, litd)
- `nginx-lnbits.conf` — HTTPS front; currently proxies to lnbits-2
- `version-matrix.json` — pinned versions and optional source-build specs
- `lnbits_keys.env` — emitted at bootstrap: API keys, user IDs, JWTs, pre-seeded LNURL/flip IDs

## Debugging

- Container logs: `docker compose logs --tail=100 litd-1`
- Shell into a node: `docker compose exec litd-1 sh`
- `lncli` on litd-1: `docker compose exec litd-1 lncli --network=regtest getinfo`
- `tapcli` on litd-1: `docker compose exec litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets balance`
- `bitcoin-cli`: `docker compose exec bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getblockchaininfo`
