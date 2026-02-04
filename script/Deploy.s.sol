// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SolprismUSDC.sol";

contract DeployScript is Script {
    function run() external {
        // Base Sepolia USDC address (Circle's official testnet USDC)
        address usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(deployerKey);

        SolprismUSDC solprism = new SolprismUSDC(usdc);
        console.log("SolprismUSDC deployed at:", address(solprism));

        vm.stopBroadcast();
    }
}
