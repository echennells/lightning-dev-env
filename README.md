# Lightning Development Environment

Comprehensive Bitcoin Lightning Network testing environment that runs in GitHub Actions. Sets up a complete Lightning ecosystem with multiple nodes, channels, Taproot Assets, and LNbits instances for automated testing.

## Features

### Core Infrastructure
- **Bitcoin Core** in regtest mode for instant block generation
- **3 Lightning Nodes**: 2 litd nodes with Taproot Assets + 1 standard LND node
- **3 LNbits Instances**: Each connected to a different Lightning node
- **HTTPS Proxy**: Nginx-based proxy for domain spoofing and SSL termination
- **Automated Channel Management**: Multiple channel types including Taproot Asset channels

### What Gets Tested
- ✅ Bitcoin wallet creation and funding
- ✅ Lightning node initialization and synchronization
- ✅ Multi-hop Lightning channel creation and confirmation
- ✅ Cross-node Lightning payments
- ✅ Taproot Asset minting and asset channels
- ✅ LNbits instance setup with admin user creation
- ✅ LNbits wallet funding from Lightning nodes
- ✅ Inter-LNbits payments across different backend nodes
- ✅ HTTPS proxy with domain spoofing for testing production-like environments

## Architecture

```
┌─────────────┐
│  Bitcoin    │
│   Core      │
└──────┬──────┘
       │
┌──────┴──────┬──────────┬───────────┐
│             │          │           │
▼             ▼          ▼           │
litd-1        litd-2     LND         │
(Taproot)     (Taproot)  (Standard)  │
│             │          │           │
├─channel────►│          │           │
├─channel────────────────►           │
│             ├─channel──►           │
│             │          │           │
▼             ▼          ▼           │
LNbits-1      LNbits-2   LNbits-3    │
(port 5001)   (port 5002) (port 5003)│
│             │          │           │
└─────────────┴──────────┴───────────┘
         HTTPS Proxy (port 443)
```

## Services & Ports

| Service | Type | Ports | Purpose |
|---------|------|-------|---------|
| **bitcoind** | Bitcoin Core | 18443 (RPC) | Regtest blockchain |
| **litd-1** | Lightning Terminal | 10009 (gRPC), 8080 (REST) | Primary Taproot-enabled node |
| **litd-2** | Lightning Terminal | 10010 (gRPC), 8081 (REST) | Secondary Taproot-enabled node |
| **lnd** | Lightning Network Daemon | 10011 (gRPC), 8082 (REST) | Standard Lightning node |
| **lnbits-1** | LNbits | 5001 | Wallet system on litd-1 |
| **lnbits-2** | LNbits | 5002 | Wallet system on litd-2 |
| **lnbits-3** | LNbits | 5003 | Wallet system on lnd |
| **nginx** | HTTPS Proxy | 443 | SSL termination & routing |

## Lightning Channels

The workflow creates multiple channels for comprehensive testing:

1. **litd-1 → lnd**: 10M sats capacity (50/50 balanced)
2. **litd-2 → lnd**: 10M sats capacity (50/50 balanced)  
3. **litd-1 → litd-2**: 10M sats capacity (50/50 balanced)
4. **Taproot Asset Channel**: litd-1 → litd-2 with custom assets

## LNbits Configuration

Each LNbits instance is configured with:
- Admin user with generated credentials
- Invoice/read API keys for wallet operations
- 500,000 sats initial funding from Lightning nodes
- Full REST API access for payment testing

## Workflow Steps

1. **Infrastructure Setup**
   - Start Bitcoin Core and Lightning nodes
   - Wait for services to be ready

2. **Bitcoin Setup**
   - Create wallets for all nodes
   - Mine initial blocks
   - Fund each Lightning node with 10 BTC

3. **Lightning Network**
   - Open channels between all nodes
   - Mine blocks to confirm channels
   - Verify channel connectivity

4. **Taproot Assets** (Optional)
   - Mint TestCoin assets on litd-1
   - Open asset-enabled channel to litd-2
   - Test asset transfers

5. **LNbits Setup**
   - Start 3 LNbits instances
   - Configure admin users
   - Fund wallets from Lightning nodes

6. **Payment Testing**
   - Test cross-node Lightning payments
   - Test LNbits-to-LNbits transactions
   - Verify multi-hop routing

7. **HTTPS Proxy**
   - Generate SSL certificates
   - Configure Nginx for domain spoofing
   - Test HTTPS endpoints

## Usage

### Running Tests

The workflow triggers automatically on push to the repository. You can also manually trigger it from the Actions tab.

### Adding Custom Tests

Add your test steps to `.github/workflows/test-lightning-channel.yml` after the LNbits setup:

```yaml
- name: Run my custom tests
  run: |
    # Your test commands here
    curl -X POST http://localhost:5001/api/v1/payments ...
```

### Environment Variables

The workflow exports these variables for use in custom tests:

- `LNBITS1_ADMIN_KEY`, `LNBITS2_ADMIN_KEY`, `LNBITS3_ADMIN_KEY` - Admin API keys
- `LNBITS1_INVOICE_KEY`, `LNBITS2_INVOICE_KEY`, `LNBITS3_INVOICE_KEY` - Invoice/read keys
- `LITD1_PUBKEY`, `LITD2_PUBKEY`, `LND_PUBKEY` - Node public keys

## Error Handling

The workflow includes comprehensive error handling:
- Automatic failure on any payment or channel errors
- Detailed logging for debugging
- Container log output on failures
- Proper cleanup of resources

## Files

- `.github/workflows/test-lightning-channel.yml` - Main workflow definition
- `docker-compose.yml` - Service definitions for all containers
- `nginx-lnbits.conf` - Local proxy configuration
- `remote-proxy-nginx.conf` - GitHub Actions proxy configuration  
- `ssl/` - SSL certificates for HTTPS testing

## Requirements

This runs entirely in GitHub Actions - no local setup required. The workflow uses:
- Ubuntu latest runner
- Docker and Docker Compose
- Standard GitHub Actions environment

## Debugging

If the workflow fails, check:
1. The workflow logs in the Actions tab
2. Container logs (automatically shown on failure)
3. Lightning node channel states
4. LNbits wallet balances

## Based On

Inspired by [lnbits/legend-regtest-enviroment](https://github.com/lnbits/legend-regtest-enviroment) with significant enhancements for multi-node testing, Taproot Assets, and HTTPS proxy support.