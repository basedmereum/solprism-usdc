// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SolprismUSDC.sol";

/// @dev Mock USDC for testing (6 decimals like real USDC)
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract SolprismUSDCTest is Test {
    SolprismUSDC public solprism;
    MockUSDC public usdc;

    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");
    address public recipient = makeAddr("recipient");

    uint256 constant ONE_USDC = 1e6;

    function setUp() public {
        usdc = new MockUSDC();
        solprism = new SolprismUSDC(address(usdc));

        // Fund agent1 with 1000 USDC
        usdc.mint(agent1, 1000 * ONE_USDC);
    }

    // ──────────────── Registration ────────────────

    function test_registerAgent() public {
        vm.prank(agent1);
        solprism.registerAgent();

        (bool registered,,,,, uint256 regAt) = solprism.getAgentStats(agent1);
        assertTrue(registered);
        assertEq(regAt, block.timestamp);
        assertEq(solprism.agentCount(), 1);
    }

    function test_registerAgent_revertDouble() public {
        vm.prank(agent1);
        solprism.registerAgent();

        vm.prank(agent1);
        vm.expectRevert(SolprismUSDC.AlreadyRegistered.selector);
        solprism.registerAgent();
    }

    // ──────────────── Commit ────────────────

    function test_commitReasoning() public {
        _registerAgent(agent1);

        string memory reasoning = "Paying 100 USDC to recipient for API service rendered. Invoice #42.";
        bytes32 hash = keccak256(abi.encodePacked(reasoning));
        bytes32 commitId = keccak256("commit-1");

        vm.prank(agent1);
        solprism.commitReasoning(commitId, hash, recipient, 100 * ONE_USDC);

        (address a, bytes32 rh, address r, uint256 amt,,,,,, ) = solprism.commitments(commitId);
        assertEq(a, agent1);
        assertEq(rh, hash);
        assertEq(r, recipient);
        assertEq(amt, 100 * ONE_USDC);
        assertEq(solprism.commitmentCount(), 1);
    }

    function test_commitReasoning_revertNotRegistered() public {
        vm.prank(agent1);
        vm.expectRevert(SolprismUSDC.NotRegistered.selector);
        solprism.commitReasoning(keccak256("x"), keccak256("y"), recipient, ONE_USDC);
    }

    // ──────────────── Execute ────────────────

    function test_executePayment() public {
        _registerAgent(agent1);
        bytes32 commitId = _commitForAgent(agent1, "Paying for compute resources", 50 * ONE_USDC);

        // Approve USDC spending
        vm.prank(agent1);
        usdc.approve(address(solprism), 50 * ONE_USDC);

        // Execute
        vm.prank(agent1);
        solprism.executePayment(commitId);

        assertEq(usdc.balanceOf(recipient), 50 * ONE_USDC);
        assertEq(usdc.balanceOf(agent1), 950 * ONE_USDC);

        (,,,,,,, bool executed,,) = solprism.commitments(commitId);
        assertTrue(executed);
    }

    function test_executePayment_revertWithoutCommit() public {
        vm.prank(agent1);
        vm.expectRevert(SolprismUSDC.CommitmentNotFound.selector);
        solprism.executePayment(keccak256("nonexistent"));
    }

    // ──────────────── Reveal ────────────────

    function test_revealReasoning() public {
        _registerAgent(agent1);
        string memory reasoning = "Paying for compute resources";
        bytes32 commitId = _commitForAgent(agent1, reasoning, 50 * ONE_USDC);

        vm.prank(agent1);
        solprism.revealReasoning(commitId, reasoning);

        (bool verified, string memory revealed,,,,) = solprism.verifyReasoning(commitId);
        assertTrue(verified);
        assertEq(revealed, reasoning);
    }

    function test_revealReasoning_revertBadHash() public {
        _registerAgent(agent1);
        bytes32 commitId = _commitForAgent(agent1, "Real reasoning", 50 * ONE_USDC);

        vm.prank(agent1);
        vm.expectRevert(SolprismUSDC.HashMismatch.selector);
        solprism.revealReasoning(commitId, "Fake reasoning");
    }

    // ──────────────── Full Flow ────────────────

    function test_fullFlow_commitExecuteRevealVerify() public {
        _registerAgent(agent1);

        string memory reasoning = "Transferring 200 USDC to agent2 for data feed subscription. Monthly payment, contract #7.";
        bytes32 hash = keccak256(abi.encodePacked(reasoning));
        bytes32 commitId = keccak256("full-flow-1");

        // Step 1: Commit
        vm.prank(agent1);
        solprism.commitReasoning(commitId, hash, recipient, 200 * ONE_USDC);

        // Step 2: Execute
        vm.prank(agent1);
        usdc.approve(address(solprism), 200 * ONE_USDC);
        vm.prank(agent1);
        solprism.executePayment(commitId);

        // Step 3: Reveal
        vm.prank(agent1);
        solprism.revealReasoning(commitId, reasoning);

        // Step 4: Verify
        (bool verified, string memory rev, address ag, address rec, uint256 amt, bool exec) =
            solprism.verifyReasoning(commitId);

        assertTrue(verified);
        assertEq(rev, reasoning);
        assertEq(ag, agent1);
        assertEq(rec, recipient);
        assertEq(amt, 200 * ONE_USDC);
        assertTrue(exec);

        // Check agent stats
        (, uint64 commits, uint64 reveals, uint64 executions, uint256 totalUsdc,) =
            solprism.getAgentStats(agent1);
        assertEq(commits, 1);
        assertEq(reveals, 1);
        assertEq(executions, 1);
        assertEq(totalUsdc, 200 * ONE_USDC);
    }

    // ──────────────── Commit + Execute Atomic ────────────────

    function test_commitAndExecute() public {
        _registerAgent(agent1);

        string memory reasoning = "Atomic payment for instant settlement";
        bytes32 hash = keccak256(abi.encodePacked(reasoning));
        bytes32 commitId = keccak256("atomic-1");

        vm.prank(agent1);
        usdc.approve(address(solprism), 75 * ONE_USDC);

        vm.prank(agent1);
        solprism.commitAndExecute(commitId, hash, recipient, 75 * ONE_USDC);

        assertEq(usdc.balanceOf(recipient), 75 * ONE_USDC);

        // Can still reveal after atomic commit+execute
        vm.prank(agent1);
        solprism.revealReasoning(commitId, reasoning);

        (bool verified,,,,, ) = solprism.verifyReasoning(commitId);
        assertTrue(verified);
    }

    // ──────────────── Tamper Detection ────────────────

    function test_tamperDetection_wrongAgent() public {
        _registerAgent(agent1);
        _registerAgent(agent2);

        bytes32 commitId = _commitForAgent(agent1, "My reasoning", 10 * ONE_USDC);

        // Agent2 tries to reveal agent1's commitment
        vm.prank(agent2);
        vm.expectRevert(SolprismUSDC.NotYourCommitment.selector);
        solprism.revealReasoning(commitId, "My reasoning");
    }

    function test_tamperDetection_doubleReveal() public {
        _registerAgent(agent1);
        string memory reasoning = "One time only";
        bytes32 commitId = _commitForAgent(agent1, reasoning, 10 * ONE_USDC);

        vm.prank(agent1);
        solprism.revealReasoning(commitId, reasoning);

        vm.prank(agent1);
        vm.expectRevert(SolprismUSDC.AlreadyRevealed.selector);
        solprism.revealReasoning(commitId, reasoning);
    }

    // ──────────────── Enumeration ────────────────

    function test_getCommitmentIds() public {
        _registerAgent(agent1);
        _commitForAgent(agent1, "r1", 10 * ONE_USDC);
        _commitForAgent(agent1, "r2", 20 * ONE_USDC);
        _commitForAgent(agent1, "r3", 30 * ONE_USDC);

        bytes32[] memory ids = solprism.getCommitmentIds(0, 10);
        assertEq(ids.length, 3);

        ids = solprism.getCommitmentIds(1, 1);
        assertEq(ids.length, 1);
    }

    // ──────────────── Helpers ────────────────

    uint256 private _nonce;

    function _registerAgent(address agent) internal {
        vm.prank(agent);
        solprism.registerAgent();
    }

    function _commitForAgent(address agent, string memory reasoning, uint256 amount) internal returns (bytes32 commitId) {
        commitId = keccak256(abi.encodePacked("commit", _nonce++));
        bytes32 hash = keccak256(abi.encodePacked(reasoning));

        vm.prank(agent);
        solprism.commitReasoning(commitId, hash, recipient, amount);
    }
}
