---
name: solprism-usdc
description: "Verifiable AI reasoning for USDC payments on Base. Commit reasoning hashes before spending USDC, then reveal and verify. Enforces accountability for every agent transaction."
metadata: {"openclaw": {"emoji": "🔮", "homepage": "https://github.com/basedmereum/solprism-usdc"}}
---

# SOLPRISM USDC Skill 🔮

Verifiable AI reasoning for USDC payments on Base Sepolia testnet.

**Before your agent spends USDC, prove WHY onchain.**

## Quick Start

```bash
# Set environment
export SOLPRISM_RPC="https://sepolia.base.org"
export SOLPRISM_CONTRACT="PENDING"  # Updated after deployment
export SOLPRISM_KEY="your-agent-private-key"
```

## How It Works

1. **Register** your agent onchain (one-time)
2. **Commit** a hash of your reasoning before any USDC payment
3. **Execute** the USDC transfer through the contract
4. **Reveal** the reasoning text (anyone can verify the hash matches)

## Usage with cast (Foundry)

### Register Agent
```bash
cast send $SOLPRISM_CONTRACT "registerAgent()" \
  --rpc-url $SOLPRISM_RPC --private-key $SOLPRISM_KEY
```

### Commit Reasoning
```bash
# Hash your reasoning
REASONING="Paying 50 USDC to 0x... for monthly API subscription. Invoice #123."
HASH=$(cast keccak "$REASONING")
COMMIT_ID=$(cast keccak "$(date +%s)-commit")

cast send $SOLPRISM_CONTRACT \
  "commitReasoning(bytes32,bytes32,address,uint256)" \
  $COMMIT_ID $HASH $RECIPIENT 50000000 \
  --rpc-url $SOLPRISM_RPC --private-key $SOLPRISM_KEY
```

### Execute Payment
```bash
# First approve USDC spending
cast send $USDC_ADDRESS "approve(address,uint256)" $SOLPRISM_CONTRACT 50000000 \
  --rpc-url $SOLPRISM_RPC --private-key $SOLPRISM_KEY

# Then execute
cast send $SOLPRISM_CONTRACT "executePayment(bytes32)" $COMMIT_ID \
  --rpc-url $SOLPRISM_RPC --private-key $SOLPRISM_KEY
```

### Reveal Reasoning
```bash
cast send $SOLPRISM_CONTRACT \
  "revealReasoning(bytes32,string)" \
  $COMMIT_ID "$REASONING" \
  --rpc-url $SOLPRISM_RPC --private-key $SOLPRISM_KEY
```

### Verify (anyone can do this)
```bash
cast call $SOLPRISM_CONTRACT \
  "verifyReasoning(bytes32)" $COMMIT_ID \
  --rpc-url $SOLPRISM_RPC
```

## Usage with ethers.js / viem

See the [full TypeScript examples](https://github.com/basedmereum/solprism-usdc#usage) in the repo.

## Contract Details

- **Chain**: Base Sepolia (testnet)
- **USDC**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
- **Contract**: `PENDING DEPLOYMENT`

## Why This Matters

Every USDC payment by an AI agent becomes auditable. Token holders, regulators, and users can verify *why* money was spent — not just *that* it was spent.

## Security

- Only interact with **testnet** USDC and Base Sepolia
- Never use mainnet credentials or real funds
- Private keys should be stored in environment variables, never in code

## Cross-Chain

SOLPRISM also runs on Solana mainnet + devnet. This skill is the EVM/Base adaptation for USDC-specific accountability.
