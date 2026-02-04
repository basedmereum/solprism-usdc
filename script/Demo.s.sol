// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SolprismUSDC.sol";

/// @notice Demo script: register an agent, commit reasoning, and reveal.
///         Run after deploying SolprismUSDC.
contract DemoScript is Script {
    function run() external {
        address solprismAddr = vm.envAddress("SOLPRISM_ADDRESS");
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");

        SolprismUSDC solprism = SolprismUSDC(solprismAddr);

        vm.startBroadcast(deployerKey);

        // 1. Register as an agent
        solprism.registerAgent();
        console.log("Agent registered");

        // 2. Commit reasoning for a USDC payment
        string memory reasoning = "Paying 10 USDC for API access to data feed service. Invoice #001. Service verified operational at 2026-02-04T06:30:00Z. Cost-benefit analysis: 10 USDC/month for real-time price data saves 2h manual collection per day.";
        bytes32 reasoningHash = keccak256(abi.encodePacked(reasoning));
        bytes32 commitId = keccak256(abi.encodePacked("demo-commit-001", block.timestamp));
        address recipient = address(0xdead);

        solprism.commitReasoning(commitId, reasoningHash, recipient, 10e6);
        console.log("Reasoning committed");
        console.logBytes32(commitId);

        // 3. Reveal reasoning
        solprism.revealReasoning(commitId, reasoning);
        console.log("Reasoning revealed");

        // 4. Verify
        (bool verified, string memory rev,,,,) = solprism.verifyReasoning(commitId);
        console.log("Verified:", verified);
        console.log("Reasoning:", rev);

        vm.stopBroadcast();
    }
}
