# Lightning Dev Environment for GitHub Actions

Automated Bitcoin + Lightning Network testing environment that runs in GitHub Actions for testing LNbits plugins.

## What It Does

When you push code, GitHub Actions automatically:
1. Starts Bitcoin Core in regtest mode
2. Starts two LND nodes 
3. Creates and funds wallets
4. Opens a Lightning channel between the nodes
5. Tests Lightning payments work
6. Starts LNbits connected to the Lightning backend

## The Setup

- **Bitcoin Core**: Regtest node for instant block mining
- **LND-1**: Primary Lightning node (connected to LNbits)
- **LND-2**: Secondary Lightning node for testing payments
- **Channel**: 0.1 BTC capacity, balanced 50/50
- **LNbits**: Connected to LND-1 via REST API

## How to Use

1. Fork this repo
2. Add your LNbits plugin tests to the workflow
3. Push code and watch it test automatically

The workflow file is `.github/workflows/test-lightning-channel.yml`

## Services & Ports

| Service | Purpose | Port |
|---------|---------|------|
| Bitcoin | Regtest blockchain | 18443 |
| LND-1 | Primary Lightning node | 10009 (gRPC), 8080 (REST) |
| LND-2 | Secondary Lightning node | 10010 (gRPC), 8081 (REST) |
| LNbits | Lightning wallet system | 5000 |

## Workflow Status

The workflow verifies:
- ✅ Both Lightning nodes sync with Bitcoin
- ✅ Wallets get funded (10 BTC each)
- ✅ Channel opens successfully
- ✅ Payments route between nodes
- ✅ LNbits connects and sees the balance

## Based On

Inspired by [lnbits/legend-regtest-enviroment](https://github.com/lnbits/legend-regtest-enviroment)