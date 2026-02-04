/**
 * SOLPRISM + USDC Demo — Full Verified Payment Flow on Solana Devnet
 *
 * Demonstrates:
 *   1. Agent registration on SOLPRISM
 *   2. Commit reasoning hash BEFORE payment
 *   3. Execute USDC SPL token transfer
 *   4. Reveal the reasoning onchain
 *   5. Independent verification
 *
 * Usage:
 *   npx ts-node demo.ts
 */

import { Connection, Keypair, PublicKey } from "@solana/web3.js";
import {
  createMint,
  mintTo,
  getOrCreateAssociatedTokenAccount,
} from "@solana/spl-token";
import * as fs from "fs";
import {
  executeVerifiedPayment,
  verifyPaymentReasoning,
  USDCPaymentReasoning,
} from "./usdc-reasoning";

const SOLPRISM_PROGRAM_ID = new PublicKey(
  "CZcvoryaQNrtZ3qb3gC1h9opcYpzEP1D9Mu1RVwFQeBu"
);

const SEED_AGENT = Buffer.from("agent");

function encodeString(s: string): Buffer {
  const bytes = Buffer.from(s, "utf-8");
  const buf = Buffer.alloc(4 + bytes.length);
  buf.writeUInt32LE(bytes.length, 0);
  bytes.copy(buf, 4);
  return buf;
}

function loadWallet(path: string): Keypair {
  const key = JSON.parse(fs.readFileSync(path, "utf-8"));
  return Keypair.fromSecretKey(Uint8Array.from(key));
}

async function main() {
  console.log("═══════════════════════════════════════════════════════════");
  console.log("  SOLPRISM × USDC — Verifiable AI Reasoning for Payments  ");
  console.log("═══════════════════════════════════════════════════════════\n");

  // ─── Setup ─────────────────────────────────────────────────────────

  const connection = new Connection(
    "https://api.devnet.solana.com",
    "confirmed"
  );

  // Use existing funded devnet wallet
  const walletPath = process.env.WALLET_PATH || `${process.env.HOME}/.config/solana/axiom-devnet.json`;
  const agentWallet = loadWallet(walletPath);
  const recipientWallet = Keypair.generate();

  console.log(`🤖 Agent:     ${agentWallet.publicKey.toBase58()}`);
  console.log(`📬 Recipient: ${recipientWallet.publicKey.toBase58()}`);

  const balance = await connection.getBalance(agentWallet.publicKey);
  console.log(`💰 Balance:   ${balance / 1e9} SOL`);

  // Create mock USDC mint (6 decimals like real USDC)
  console.log(`\n🪙 Creating test USDC mint...`);
  const usdcMint = await createMint(
    connection,
    agentWallet,
    agentWallet.publicKey, // mint authority
    null, // freeze authority
    6 // decimals (same as USDC)
  );
  console.log(`   Mint: ${usdcMint.toBase58()}`);

  // Mint test USDC to agent
  const agentATA = await getOrCreateAssociatedTokenAccount(
    connection,
    agentWallet,
    usdcMint,
    agentWallet.publicKey
  );

  await mintTo(
    connection,
    agentWallet,
    usdcMint,
    agentATA.address,
    agentWallet.publicKey,
    1000_000_000 // 1000 USDC
  );
  console.log(`   Minted 1,000 USDC to agent`);

  // ─── Register Agent on SOLPRISM (if not already) ────────────────────

  const [agentProfile] = PublicKey.findProgramAddressSync(
    [SEED_AGENT, agentWallet.publicKey.toBuffer()],
    SOLPRISM_PROGRAM_ID
  );

  const { Transaction, SystemProgram, sendAndConfirmTransaction } =
    await import("@solana/web3.js");

  const existingAgent = await connection.getAccountInfo(agentProfile);
  if (!existingAgent) {
    console.log(`\n📝 Registering agent on SOLPRISM...`);
    const registerIx = {
      keys: [
        { pubkey: agentProfile, isSigner: false, isWritable: true },
        { pubkey: agentWallet.publicKey, isSigner: true, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId: SOLPRISM_PROGRAM_ID,
      data: Buffer.concat([
        Buffer.from([135, 157, 66, 195, 2, 113, 175, 30]),
        encodeString("USDC-Demo-Agent"),
      ]),
    };

    const registerTx = new Transaction().add(registerIx);
    const registerSig = await sendAndConfirmTransaction(
      connection,
      registerTx,
      [agentWallet],
      { commitment: "confirmed" }
    );
    console.log(`   ✅ Registered: ${registerSig}`);
  } else {
    console.log(`\n📝 Agent already registered on SOLPRISM ✅`);
    // Read current nonce from agent profile for commitment
    const data = Buffer.from(existingAgent.data);
    // total_commitments is at offset 8 (disc) + 32 (authority) + name_len + 4
    // We'll read it after the variable-length name
    const nameLen = data.readUInt32LE(40);
    const totalCommitments = Number(data.readBigUInt64LE(44 + nameLen));
    console.log(`   Total commitments so far: ${totalCommitments}`);
  }

  // ─── Execute Verified USDC Payment ─────────────────────────────────

  const reasoning: USDCPaymentReasoning = {
    reason:
      "Paying for monthly data feed subscription from OracleService. Price data covers SOL/USDC, ETH/USDC, BTC/USDC pairs with 1-second resolution. Cost-benefit: 50 USDC/month saves approximately 2 hours of manual price collection per day. Service uptime verified at 99.97% over past 30 days.",
    recipient: recipientWallet.publicKey.toBase58(),
    amount: 50,
    category: "subscription",
    confidence: 92,
    decidedAt: new Date().toISOString(),
    context: "Invoice #2026-02-001, auto-renewal enabled",
  };

  // Get the current nonce from agent profile
  const agentData = await connection.getAccountInfo(agentProfile);
  let nonce = 0;
  if (agentData && agentData.data) {
    const d = Buffer.from(agentData.data);
    const nameLen = d.readUInt32LE(40);
    nonce = Number(d.readBigUInt64LE(44 + nameLen));
  }
  console.log(`   Using nonce: ${nonce}`);

  const result = await executeVerifiedPayment(
    connection,
    agentWallet,
    usdcMint,
    reasoning,
    nonce
  );

  // ─── Independent Verification ──────────────────────────────────────

  console.log(`\n═══════════════════════════════════════════════════════════`);
  console.log(`  Independent Verification (anyone can do this)           `);
  console.log(`═══════════════════════════════════════════════════════════\n`);

  const verification = await verifyPaymentReasoning(
    connection,
    result.commitmentAddress,
    reasoning
  );

  console.log(`Result: ${verification.message}`);

  // ─── Tamper Detection Demo ─────────────────────────────────────────

  console.log(`\n═══════════════════════════════════════════════════════════`);
  console.log(`  Tamper Detection (try to lie about reasoning)           `);
  console.log(`═══════════════════════════════════════════════════════════\n`);

  const tamperedReasoning: USDCPaymentReasoning = {
    ...reasoning,
    reason: "Paying for critical security audit", // Changed!
    amount: 500, // Changed!
  };

  const tamperCheck = await verifyPaymentReasoning(
    connection,
    result.commitmentAddress,
    tamperedReasoning
  );

  console.log(`Tampered result: ${tamperCheck.message}`);

  // ─── Summary ───────────────────────────────────────────────────────

  console.log(`\n═══════════════════════════════════════════════════════════`);
  console.log(`  SOLPRISM × USDC Demo Complete                           `);
  console.log(`═══════════════════════════════════════════════════════════`);
  console.log(`\n  Program:    ${SOLPRISM_PROGRAM_ID.toBase58()}`);
  console.log(`  Commitment: ${result.commitmentAddress}`);
  console.log(`  Hash:       ${result.reasoningHash}`);
  console.log(`  Verified:   ${result.verified ? "✅ YES" : "❌ NO"}`);
  console.log(`\n  Explorer:   https://solscan.io/tx/${result.commitSignature}?cluster=devnet`);
  console.log(`  SOLPRISM:   https://www.solprism.app/`);
  console.log(`\n  Every USDC payment is now accountable. 🔮\n`);
}

main().catch(console.error);
