# ShibaPepe Smart Contracts

## Overview
ShibaPepe ($SHPE) is a meme token on Base Network with ICO and staking functionality.

## Links
- Website: https://shibapepe.com
- Whitepaper: [whitepaper.pdf](./docs/whitepaper.pdf)
- Contact: info@shibapepe.com

## Contracts

### SHPEToken.sol
- ERC-20 Token
- Total Supply: 1 Trillion (1,000,000,000,000)
- Owner-only burn function

### ShibaPepeICO.sol
- 10-stage presale with progressive pricing
- Payment: ETH, USDC, USDT
- 5-tier affiliate system (5% - 50%)
- Chainlink price feed integration

### ShibaPepeStaking.sol
- Plan 0: Flexible (15% APY, no lock)
- Plan 1: 6-month Lock (80% APY)

## Security Features
- ReentrancyGuard on all user functions
- SafeERC20 for token transfers
- Pausable for emergency stops
- Chainlink price feed with staleness check (1 hour)

## License
MIT
