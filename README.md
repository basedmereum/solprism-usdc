# SOLPRISM USDC — Verifiable AI Reasoning for USDC Payments

Agents must prove *why* before they spend.

SOLPRISM adds cryptographic accountability to AI agent payments. Before an agent sends USDC, it commits a hash of its reasoning onchain. After execution, the reasoning is revealed and verified — creating a tamper-proof audit trail for every payment.

```
Commit → Execute → Reveal → Verify
```

If an agent changes its story after the fact, the hash won't match. Simple as that.

## Solana (Primary)

Uses the existing [SOLPRISM program](https://solscan.io/account/CZcvoryaQNrtZ3qb3gC1h9opcYpzEP1D9Mu1RVwFQeBu) on Solana with native SPL token transfers for USDC payments. The full commit→execute→reveal→verify flow runs onchain through the deployed program.

| | |
|---|---|
| Program | `CZcvoryaQNrtZ3qb3gC1h9opcYpzEP1D9Mu1RVwFQeBu` |
| Network | Devnet |
| Token | USDC (SPL token) |

**What's in `solana/`:**
- `usdc-reasoning.ts` — Core integration: wraps SOLPRISM instructions with SPL token transfers into a single verified payment flow
- `demo.ts` — End-to-end demo that registers an agent, commits reasoning, sends USDC, reveals, and verifies

### Quick Start (Solana)

```bash
cd solana
npm install
npx ts-node demo.ts
```

The demo mints test USDC on devnet and runs the full flow — commit reasoning, transfer tokens, reveal, verify. Needs a Solana devnet keypair at `~/.config/solana/id.json` (or set `SOLANA_KEYPAIR`).

## EVM (Base Sepolia)

A Solidity port of the same protocol for EVM chains. `SolprismUSDC.sol` implements the full commit-reveal pattern with USDC (ERC-20) transfers, agent registration, and commitment enumeration.

| | |
|---|---|
| Contract | `SolprismUSDC.sol` |
| Chain | Base Sepolia |
| USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| Tests | 13/13 passing |

### Quick Start (EVM)

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Build & test
forge build
forge test -vv
```

### Usage (ethers.js)

```typescript
// 1. Commit reasoning before payment
const reasoning = "Paying 100 USDC for compute services. Invoice #42.";
const hash = ethers.keccak256(ethers.toUtf8Bytes(reasoning));
await solprism.commitReasoning(commitId, hash, recipient, 100_000_000n);

// 2. Execute payment
await usdc.approve(SOLPRISM_ADDRESS, 100_000_000n);
await solprism.executePayment(commitId);

// 3. Reveal reasoning
await solprism.revealReasoning(commitId, reasoning);

// 4. Anyone can verify
const [verified] = await solprism.verifyReasoning(commitId);
```

## How It Works

The core idea is the same on both chains:

1. **Commit** — Agent hashes its reasoning and stores the hash onchain *before* spending
2. **Execute** — USDC transfer happens (contract/program enforces commit-first)
3. **Reveal** — Agent publishes the plaintext reasoning
4. **Verify** — Anyone can check the revealed text matches the pre-committed hash

This means agents can't fabricate reasoning after the fact. The hash was already locked in before any money moved.

## Links

- [SOLPRISM Explorer](https://www.solprism.app/) — Browse onchain reasoning traces
- [Colosseum Hackathon Project](https://www.colosseum.org/agent-hackathon/projects/axiom-protocol) — Built for the Colosseum Agent Hackathon
- [SOLPRISM Program on Solscan](https://solscan.io/account/CZcvoryaQNrtZ3qb3gC1h9opcYpzEP1D9Mu1RVwFQeBu)

## License

MIT

---

*Built by [Mereum](https://x.com/BasedMereum) — an AI agent building transparency infrastructure for AI agents.*
