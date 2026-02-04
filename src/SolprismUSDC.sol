// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SOLPRISM — Verifiable AI Reasoning for USDC Payments
/// @notice Agents must commit cryptographic proof of their reasoning BEFORE spending USDC.
///         Commit → Execute → Reveal → Verify
/// @dev Ported from SOLPRISM on Solana (CZcvoryaQNrtZ3qb3gC1h9opcYpzEP1D9Mu1RVwFQeBu)
///      to bring verifiable AI accountability to EVM + USDC.

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract SolprismUSDC {
    // ──────────────────────────── Types ────────────────────────────

    struct Agent {
        bool registered;
        uint64 commitCount;
        uint64 revealCount;
        uint64 executedCount;
        uint256 totalUsdcMoved;
        uint256 registeredAt;
    }

    struct Commitment {
        address agent;
        bytes32 reasoningHash;   // keccak256(reasoning_text)
        address recipient;
        uint256 amount;          // USDC amount (6 decimals)
        uint256 committedAt;
        uint256 executedAt;
        uint256 revealedAt;
        bool executed;
        bool revealed;
        string reasoning;        // populated on reveal
    }

    // ──────────────────────────── State ────────────────────────────

    IERC20 public immutable usdc;

    mapping(address => Agent) public agents;
    mapping(bytes32 => Commitment) public commitments;

    address[] public agentList;
    bytes32[] public commitmentIds;

    // ──────────────────────────── Events ───────────────────────────

    event AgentRegistered(address indexed agent, uint256 timestamp);
    event ReasoningCommitted(
        bytes32 indexed commitId,
        address indexed agent,
        bytes32 reasoningHash,
        address recipient,
        uint256 amount
    );
    event PaymentExecuted(
        bytes32 indexed commitId,
        address indexed agent,
        address indexed recipient,
        uint256 amount
    );
    event ReasoningRevealed(
        bytes32 indexed commitId,
        address indexed agent,
        string reasoning
    );

    // ──────────────────────────── Errors ───────────────────────────

    error AlreadyRegistered();
    error NotRegistered();
    error CommitmentExists();
    error CommitmentNotFound();
    error NotYourCommitment();
    error AlreadyExecuted();
    error AlreadyRevealed();
    error NotExecutedYet();
    error HashMismatch();
    error TransferFailed();

    // ──────────────────────────── Constructor ──────────────────────

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    // ──────────────────────────── Agent Registration ──────────────

    function registerAgent() external {
        if (agents[msg.sender].registered) revert AlreadyRegistered();

        agents[msg.sender] = Agent({
            registered: true,
            commitCount: 0,
            revealCount: 0,
            executedCount: 0,
            totalUsdcMoved: 0,
            registeredAt: block.timestamp
        });

        agentList.push(msg.sender);
        emit AgentRegistered(msg.sender, block.timestamp);
    }

    // ──────────────────────── Step 1: Commit ──────────────────────
    /// @notice Agent commits a hash of their reasoning BEFORE executing a USDC payment.
    /// @param commitId Unique identifier for this commitment (agent-generated)
    /// @param reasoningHash keccak256 hash of the reasoning text
    /// @param recipient Who will receive the USDC
    /// @param amount How much USDC (6 decimals) will be sent

    function commitReasoning(
        bytes32 commitId,
        bytes32 reasoningHash,
        address recipient,
        uint256 amount
    ) external {
        if (!agents[msg.sender].registered) revert NotRegistered();
        if (commitments[commitId].agent != address(0)) revert CommitmentExists();

        commitments[commitId] = Commitment({
            agent: msg.sender,
            reasoningHash: reasoningHash,
            recipient: recipient,
            amount: amount,
            committedAt: block.timestamp,
            executedAt: 0,
            revealedAt: 0,
            executed: false,
            revealed: false,
            reasoning: ""
        });

        commitmentIds.push(commitId);
        agents[msg.sender].commitCount++;

        emit ReasoningCommitted(commitId, msg.sender, reasoningHash, recipient, amount);
    }

    // ──────────────────────── Step 2: Execute ─────────────────────
    /// @notice Execute the USDC payment. Reasoning must be committed first.
    /// @dev Agent must have approved this contract to spend their USDC.

    function executePayment(bytes32 commitId) external {
        Commitment storage c = commitments[commitId];
        if (c.agent == address(0)) revert CommitmentNotFound();
        if (c.agent != msg.sender) revert NotYourCommitment();
        if (c.executed) revert AlreadyExecuted();

        c.executed = true;
        c.executedAt = block.timestamp;

        agents[msg.sender].executedCount++;
        agents[msg.sender].totalUsdcMoved += c.amount;

        bool ok = usdc.transferFrom(msg.sender, c.recipient, c.amount);
        if (!ok) revert TransferFailed();

        emit PaymentExecuted(commitId, msg.sender, c.recipient, c.amount);
    }

    // ────────────────── Step 2b: Commit + Execute Atomic ──────────
    /// @notice Commit reasoning and execute payment in a single transaction.
    /// @dev For agents that want atomic commit+pay in one tx.

    function commitAndExecute(
        bytes32 commitId,
        bytes32 reasoningHash,
        address recipient,
        uint256 amount
    ) external {
        if (!agents[msg.sender].registered) revert NotRegistered();
        if (commitments[commitId].agent != address(0)) revert CommitmentExists();

        commitments[commitId] = Commitment({
            agent: msg.sender,
            reasoningHash: reasoningHash,
            recipient: recipient,
            amount: amount,
            committedAt: block.timestamp,
            executedAt: block.timestamp,
            revealedAt: 0,
            executed: true,
            revealed: false,
            reasoning: ""
        });

        commitmentIds.push(commitId);

        Agent storage a = agents[msg.sender];
        a.commitCount++;
        a.executedCount++;
        a.totalUsdcMoved += amount;

        bool ok = usdc.transferFrom(msg.sender, recipient, amount);
        if (!ok) revert TransferFailed();

        emit ReasoningCommitted(commitId, msg.sender, reasoningHash, recipient, amount);
        emit PaymentExecuted(commitId, msg.sender, recipient, amount);
    }

    // ──────────────────────── Step 3: Reveal ──────────────────────
    /// @notice Reveal the reasoning text. Hash must match the committed hash.

    function revealReasoning(bytes32 commitId, string calldata reasoning) external {
        Commitment storage c = commitments[commitId];
        if (c.agent == address(0)) revert CommitmentNotFound();
        if (c.agent != msg.sender) revert NotYourCommitment();
        if (c.revealed) revert AlreadyRevealed();
        if (keccak256(abi.encodePacked(reasoning)) != c.reasoningHash) revert HashMismatch();

        c.revealed = true;
        c.revealedAt = block.timestamp;
        c.reasoning = reasoning;

        agents[msg.sender].revealCount++;
        emit ReasoningRevealed(commitId, msg.sender, reasoning);
    }

    // ──────────────────────── Verification ────────────────────────

    /// @notice Verify a commitment's reasoning integrity.
    /// @return verified True if reasoning has been revealed and hash matches
    /// @return reasoning The revealed reasoning text (empty if not yet revealed)

    function verifyReasoning(bytes32 commitId) external view returns (
        bool verified,
        string memory reasoning,
        address agent,
        address recipient,
        uint256 amount,
        bool executed
    ) {
        Commitment storage c = commitments[commitId];
        return (
            c.revealed && keccak256(abi.encodePacked(c.reasoning)) == c.reasoningHash,
            c.reasoning,
            c.agent,
            c.recipient,
            c.amount,
            c.executed
        );
    }

    /// @notice Get agent stats for reputation/accountability scoring.

    function getAgentStats(address agent) external view returns (
        bool registered,
        uint64 commits,
        uint64 reveals,
        uint64 executions,
        uint256 totalUsdc,
        uint256 registeredAt
    ) {
        Agent storage a = agents[agent];
        return (a.registered, a.commitCount, a.revealCount, a.executedCount, a.totalUsdcMoved, a.registeredAt);
    }

    /// @notice Get total number of registered agents.
    function agentCount() external view returns (uint256) {
        return agentList.length;
    }

    /// @notice Get total number of commitments.
    function commitmentCount() external view returns (uint256) {
        return commitmentIds.length;
    }

    /// @notice Get a page of commitment IDs for enumeration.
    function getCommitmentIds(uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        uint256 len = commitmentIds.length;
        if (offset >= len) return new bytes32[](0);
        uint256 end = offset + limit;
        if (end > len) end = len;
        bytes32[] memory ids = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            ids[i - offset] = commitmentIds[i];
        }
        return ids;
    }
}
