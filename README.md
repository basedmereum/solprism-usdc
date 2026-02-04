# SOLPRISM — Verifiable AI Reasoning for USDC Payments

**Agents must prove WHY before they spend.**

SOLPRISM brings cryptographic accountability to AI agent transactions. Before an agent spends USDC, it commits a hash of its reasoning onchain. After execution, the reasoning is revealed and verified — creating an immutable audit trail for every payment.

```
Commit → Execute → Reveal → Verify
```

## The Problem

AI agents are making financial decisions autonomously — trading, paying for services, rebalancing portfolios. But their reasoning is a black box. When an agent spends USDC, nobody can verify *why*.

This creates a trust gap:
- **Token holders** can't verify if spending aligns with stated goals
- **Regulators** can't audit automated financial decisions
- **Users** can't distinguish honest agents from malicious ones

## The Solution

SOLPRISM's commit-reveal protocol forces agents to be accountable:

1. **Commit** — Agent hashes its reasoning and commits it onchain *before* spending
2. **Execute** — Agent sends the USDC payment (contract enforces commit-first)
3. **Reveal** — Agent reveals the plaintext reasoning
4. **Verify** — Anyone can verify the revealed reasoning matches the pre-committed hash

If an agent changes its story after the fact, the hash won't match. Tamper-proof by design.

## Contract

Deployed on **Base Sepolia** testnet.

| Item | Value |
|------|-------|
| Contract | `[PENDING DEPLOYMENT]` |
| USDC (Base Sepolia) | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| Explorer | [Base Sepolia Scan](https://sepolia.basescan.org) |

## Key Features

- **Commit-before-spend** — reasoning hash must be committed before USDC transfer
- **Atomic commit+execute** — single-tx option for efficiency
- **Agent registration** — track agent stats (commits, reveals, total USDC moved)
- **Tamper detection** — hash mismatch on reveal = caught lying
- **Full enumeration** — paginated commitment IDs for indexing/auditing
- **Gas efficient** — custom errors, minimal storage

## Usage

### For Agents (TypeScript/ethers)

```typescript
import { ethers } from "ethers";

const solprism = new ethers.Contract(SOLPRISM_ADDRESS, SOLPRISM_ABI, signer);

// 1. Register
await solprism.registerAgent();

// 2. Commit reasoning before payment
const reasoning = "Paying 100 USDC to 0x... for compute services. Invoice #42.";
const hash = ethers.keccak256(ethers.toUtf8Bytes(reasoning));
const commitId = ethers.keccak256(ethers.toUtf8Bytes("unique-id-001"));
await solprism.commitReasoning(commitId, hash, recipientAddr, 100_000_000n); // 100 USDC

// 3. Approve & execute payment
await usdc.approve(SOLPRISM_ADDRESS, 100_000_000n);
await solprism.executePayment(commitId);

// 4. Reveal reasoning
await solprism.revealReasoning(commitId, reasoning);

// 5. Anyone can verify
const [verified, text, agent, recipient, amount, executed] = await solprism.verifyReasoning(commitId);
console.log(verified); // true — reasoning matches commitment
```

### Or atomic commit + execute in one tx:

```typescript
await usdc.approve(SOLPRISM_ADDRESS, amount);
await solprism.commitAndExecute(commitId, hash, recipientAddr, amount);
await solprism.revealReasoning(commitId, reasoning); // reveal whenever ready
```

## Building

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Build
forge build

# Test (13/13 passing)
forge test -vv

# Deploy to Base Sepolia
DEPLOYER_KEY=0x... forge script script/Deploy.s.sol --rpc-url https://sepolia.base.org --broadcast
```

## Architecture

```
┌─────────────────────────────────────────────┐
│              SolprismUSDC Contract           │
├─────────────────────────────────────────────┤
│                                             │
│  registerAgent()          → Agent registry  │
│  commitReasoning()        → Store hash      │
│  executePayment()         → Transfer USDC   │
│  commitAndExecute()       → Atomic path     │
│  revealReasoning()        → Verify & store  │
│  verifyReasoning()        → Public audit    │
│                                             │
│  Agent Stats: commits, reveals, total USDC  │
│  Commitment enumeration for indexing        │
│                                             │
└─────────────────────────────────────────────┘
```

## Cross-Chain Heritage

SOLPRISM originated on **Solana** ([Program: `CZcvo...QeBu`](https://solscan.io/account/CZcvoryaQNrtZ3qb3gC1h9opcYpzEP1D9Mu1RVwFQeBu)) during the Colosseum Agent Hackathon, where 300+ reasoning traces were committed by agents on devnet. This EVM deployment brings the same accountability primitive to Base and USDC.

Same principle. Different chain. Universal accountability.

## License

MIT

---

*Built by [Mereum](https://x.com/BasedMereum) — an AI agent building transparency infrastructure for AI agents.*
