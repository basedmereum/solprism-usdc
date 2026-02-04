/**
 * SOLPRISM + USDC Integration — Verifiable Reasoning for USDC Payments on Solana
 *
 * This module wraps the SOLPRISM SDK to provide a complete
 * commit-execute-reveal-verify flow for USDC SPL token transfers.
 *
 * Flow:
 *   1. Agent commits reasoning hash to SOLPRISM program
 *   2. Agent executes USDC SPL token transfer
 *   3. Agent reveals the reasoning text
 *   4. Anyone can verify the reasoning matches the pre-commitment
 *
 * Every USDC payment gets an immutable, tamper-proof audit trail onchain.
 */

import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  sendAndConfirmTransaction,
  LAMPORTS_PER_SOL,
} from "@solana/web3.js";
import {
  getOrCreateAssociatedTokenAccount,
  createTransferInstruction,
  TOKEN_PROGRAM_ID,
  getAssociatedTokenAddress,
  getAccount,
} from "@solana/spl-token";
import { createHash } from "crypto";

// ─── SOLPRISM Program Constants ──────────────────────────────────────────

const SOLPRISM_PROGRAM_ID = new PublicKey(
  "CZcvoryaQNrtZ3qb3gC1h9opcYpzEP1D9Mu1RVwFQeBu"
);

const DISCRIMINATORS = {
  registerAgent: Buffer.from([135, 157, 66, 195, 2, 113, 175, 30]),
  commitReasoning: Buffer.from([163, 80, 25, 135, 94, 49, 218, 44]),
  revealReasoning: Buffer.from([76, 215, 6, 241, 209, 207, 84, 96]),
};

const SEED_AGENT = Buffer.from("agent");
const SEED_COMMITMENT = Buffer.from("commitment");

// ─── Types ───────────────────────────────────────────────────────────────

export interface USDCPaymentReasoning {
  /** Why is this payment being made? */
  reason: string;
  /** Recipient address */
  recipient: string;
  /** Amount in USDC (human-readable, e.g., 100.50) */
  amount: number;
  /** Payment category (e.g., "service", "subscription", "rebalance") */
  category: string;
  /** Agent's confidence in this decision (0-100) */
  confidence: number;
  /** ISO timestamp of when the decision was made */
  decidedAt: string;
  /** Optional: additional context or invoice reference */
  context?: string;
}

export interface VerifiedPayment {
  /** SOLPRISM commitment signature */
  commitSignature: string;
  /** USDC transfer signature */
  transferSignature: string;
  /** SOLPRISM reveal signature */
  revealSignature: string;
  /** Commitment PDA address */
  commitmentAddress: string;
  /** The reasoning that was committed */
  reasoning: USDCPaymentReasoning;
  /** Hash of the reasoning (stored onchain) */
  reasoningHash: string;
  /** Whether the full flow completed successfully */
  verified: boolean;
}

// ─── Helpers ─────────────────────────────────────────────────────────────

function deriveAgentPDA(authority: PublicKey): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [SEED_AGENT, authority.toBuffer()],
    SOLPRISM_PROGRAM_ID
  );
}

function deriveCommitmentPDA(
  agentProfile: PublicKey,
  nonce: number
): [PublicKey, number] {
  const nonceBuf = Buffer.alloc(8);
  nonceBuf.writeBigUInt64LE(BigInt(nonce));
  return PublicKey.findProgramAddressSync(
    [SEED_COMMITMENT, agentProfile.toBuffer(), nonceBuf],
    SOLPRISM_PROGRAM_ID
  );
}

function encodeString(s: string): Buffer {
  const bytes = Buffer.from(s, "utf-8");
  const buf = Buffer.alloc(4 + bytes.length);
  buf.writeUInt32LE(bytes.length, 0);
  bytes.copy(buf, 4);
  return buf;
}

function encodeU64(n: number | bigint): Buffer {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64LE(BigInt(n));
  return buf;
}

/**
 * Hash a USDC payment reasoning into a 32-byte commitment.
 * Uses SHA-256 of the canonical JSON representation.
 */
export function hashReasoning(reasoning: USDCPaymentReasoning): Buffer {
  const canonical = JSON.stringify({
    reason: reasoning.reason,
    recipient: reasoning.recipient,
    amount: reasoning.amount,
    category: reasoning.category,
    confidence: reasoning.confidence,
    decidedAt: reasoning.decidedAt,
    context: reasoning.context || "",
  });
  return createHash("sha256").update(canonical).digest();
}

// ─── Core: Verified USDC Payment ─────────────────────────────────────────

/**
 * Execute a USDC payment with verifiable reasoning.
 *
 * This is the main entry point. It:
 *   1. Commits the reasoning hash to SOLPRISM onchain
 *   2. Transfers USDC SPL tokens to the recipient
 *   3. Reveals the reasoning text onchain
 *
 * After this, anyone can call `verifyPaymentReasoning()` to confirm
 * the reasoning matches the pre-committed hash.
 *
 * @param connection - Solana RPC connection
 * @param agentWallet - The agent's keypair (payer + authority)
 * @param usdcMint - USDC SPL token mint address
 * @param reasoning - The structured reasoning for this payment
 * @param nonce - The agent's current commitment nonce
 * @returns VerifiedPayment with all signatures and verification status
 */
export async function executeVerifiedPayment(
  connection: Connection,
  agentWallet: Keypair,
  usdcMint: PublicKey,
  reasoning: USDCPaymentReasoning,
  nonce: number
): Promise<VerifiedPayment> {
  const recipient = new PublicKey(reasoning.recipient);
  const amountLamports = Math.round(reasoning.amount * 1_000_000); // USDC has 6 decimals

  console.log(`\n🔮 SOLPRISM Verified USDC Payment`);
  console.log(`   Amount: ${reasoning.amount} USDC`);
  console.log(`   Recipient: ${reasoning.recipient}`);
  console.log(`   Reason: ${reasoning.reason}`);
  console.log(`   Confidence: ${reasoning.confidence}%`);

  // ─── Step 1: Commit reasoning hash to SOLPRISM ───────────────────

  console.log(`\n📝 Step 1: Committing reasoning hash...`);

  const reasoningHash = hashReasoning(reasoning);
  const [agentProfile] = deriveAgentPDA(agentWallet.publicKey);
  const [commitmentPDA] = deriveCommitmentPDA(agentProfile, nonce);

  const commitIx = {
    keys: [
      { pubkey: commitmentPDA, isSigner: false, isWritable: true },
      { pubkey: agentProfile, isSigner: false, isWritable: true },
      { pubkey: agentWallet.publicKey, isSigner: true, isWritable: true },
      {
        pubkey: new PublicKey("11111111111111111111111111111111"),
        isSigner: false,
        isWritable: false,
      },
    ],
    programId: SOLPRISM_PROGRAM_ID,
    data: Buffer.concat([
      DISCRIMINATORS.commitReasoning,
      reasoningHash, // [u8; 32]
      encodeString(reasoning.category), // action_type
      Buffer.from([reasoning.confidence]), // confidence u8
      encodeU64(nonce), // nonce u64
    ]),
  };

  const commitTx = new Transaction().add(commitIx);
  const commitSig = await sendAndConfirmTransaction(
    connection,
    commitTx,
    [agentWallet],
    { commitment: "confirmed" }
  );

  console.log(`   ✅ Committed: ${commitSig}`);
  console.log(`   📍 Commitment PDA: ${commitmentPDA.toBase58()}`);

  // ─── Step 2: Execute USDC transfer ───────────────────────────────

  console.log(`\n💸 Step 2: Transferring ${reasoning.amount} USDC...`);

  // Get or create token accounts
  const senderATA = await getOrCreateAssociatedTokenAccount(
    connection,
    agentWallet,
    usdcMint,
    agentWallet.publicKey
  );

  const recipientATA = await getOrCreateAssociatedTokenAccount(
    connection,
    agentWallet,
    usdcMint,
    recipient
  );

  const transferIx = createTransferInstruction(
    senderATA.address,
    recipientATA.address,
    agentWallet.publicKey,
    amountLamports
  );

  const transferTx = new Transaction().add(transferIx);
  const transferSig = await sendAndConfirmTransaction(
    connection,
    transferTx,
    [agentWallet],
    { commitment: "confirmed" }
  );

  console.log(`   ✅ Transferred: ${transferSig}`);

  // ─── Step 3: Reveal reasoning ────────────────────────────────────

  console.log(`\n🔓 Step 3: Revealing reasoning...`);

  // Store reasoning reference as a URI (in production: IPFS/Arweave)
  // For demo, we use the reasoning hash as a compact reference
  // The full reasoning can be looked up off-chain using this hash
  const reasoningUri = `solprism://usdc/${reasoningHash.toString("hex")}`;

  const revealIx = {
    keys: [
      { pubkey: commitmentPDA, isSigner: false, isWritable: true },
      { pubkey: agentProfile, isSigner: false, isWritable: true },
      { pubkey: agentWallet.publicKey, isSigner: true, isWritable: false },
    ],
    programId: SOLPRISM_PROGRAM_ID,
    data: Buffer.concat([
      DISCRIMINATORS.revealReasoning,
      encodeString(reasoningUri),
    ]),
  };

  const revealTx = new Transaction().add(revealIx);
  const revealSig = await sendAndConfirmTransaction(
    connection,
    revealTx,
    [agentWallet],
    { commitment: "confirmed" }
  );

  console.log(`   ✅ Revealed: ${revealSig}`);

  // ─── Step 4: Verify ──────────────────────────────────────────────

  console.log(`\n🔍 Step 4: Verifying...`);

  const commitmentAccount = await connection.getAccountInfo(commitmentPDA);
  let verified = false;

  if (commitmentAccount && commitmentAccount.data) {
    // Read the stored hash from the commitment account (offset 8+32+32 = 72)
    const storedHash = commitmentAccount.data.slice(72, 104);
    verified = Buffer.compare(reasoningHash, storedHash) === 0;
  }

  console.log(
    verified
      ? `   ✅ VERIFIED — reasoning matches onchain commitment`
      : `   ❌ MISMATCH — reasoning does not match`
  );

  console.log(`\n📋 Summary:`);
  console.log(`   Commit:   ${commitSig}`);
  console.log(`   Transfer: ${transferSig}`);
  console.log(`   Reveal:   ${revealSig}`);
  console.log(`   Verified: ${verified}`);

  return {
    commitSignature: commitSig,
    transferSignature: transferSig,
    revealSignature: revealSig,
    commitmentAddress: commitmentPDA.toBase58(),
    reasoning,
    reasoningHash: reasoningHash.toString("hex"),
    verified,
  };
}

/**
 * Verify an existing payment's reasoning against its onchain commitment.
 * Anyone can call this — it's a read-only verification.
 */
export async function verifyPaymentReasoning(
  connection: Connection,
  commitmentAddress: string,
  reasoning: USDCPaymentReasoning
): Promise<{ verified: boolean; message: string }> {
  const commitPDA = new PublicKey(commitmentAddress);
  const account = await connection.getAccountInfo(commitPDA);

  if (!account || !account.data) {
    return {
      verified: false,
      message: "Commitment account not found onchain",
    };
  }

  const storedHash = account.data.slice(72, 104);
  const computedHash = hashReasoning(reasoning);
  const verified = Buffer.compare(computedHash, storedHash) === 0;

  return {
    verified,
    message: verified
      ? "✅ Reasoning matches the onchain commitment — this payment is verified"
      : "❌ Hash mismatch — the provided reasoning does not match what was committed",
  };
}
