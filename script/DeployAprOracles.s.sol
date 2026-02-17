// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {FluidAprOracleArbitrum} from "src/periphery/FluidAprOracleArbitrum.sol";
import {FluidAprOracleBase} from "src/periphery/FluidAprOracleBase.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/DeployAprOracles.s.sol:DeployAprOracles --account llc2 --rpc-url $BASE_RPC_URL -vvvvv
// use other rpcs as needed, can use the same script on all chains. ETH_RPC_URL, BASE_RPC_URL, ARBITRUM_RPC_URL, MATIC_RPC_URL
// don't need to include the optimize flag since we set it in our foundry.toml

// forge script script/DeployAprOracles.s.sol:DeployAprOracles --account llc2 --rpc-url $BASE_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast
// forge script script/DeployAprOracles.s.sol:DeployAprOracles --account llc2 --rpc-url $ARBITRUM_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast

// verify:
// needed to manually verify, can copy-paste abi-encoded constructor args from the printed output of the deployment. this command ends with the address and contract to verify, always
// no constructor (or thus, constructor args) on this one
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "CONTRACT_ADDRESS" CONTRACT_NAME

// for the uniV3 version
// forge verify-contract --rpc-url $BASE_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "0x493B566F7A773f393735eb71B6bDDCcF5D1a8aec" UniswapV3SwapSimulator
// forge verify-contract --rpc-url $BASE_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "0xe15D914513868DE594909e05AC530F0c0d5d6036" FluidAprOracleBase

contract DeployAprOracles is Script {
    /// @notice Deployer
    address public constant MANAGEMENT =
        0xd0002c648CCa8DeE2f2b8D70D542Ccde8ad6EC03;

    IOracle public oracle;

    function run() external {
        vm.startBroadcast();

        if (block.chainid == 8453) {
            // base
            oracle = IOracle(address(new FluidAprOracleBase(MANAGEMENT)));
        } else if (block.chainid == 42161) {
            // arbitrum
            oracle = IOracle(address(new FluidAprOracleArbitrum(MANAGEMENT)));
        }

        console2.log("-----------------------------");
        console2.log("apr oracle deployed at: %s", address(oracle));
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}

// base apr oracle deployed at: 0x56141Aa434C0bdddda695B857C12968DB33a2d49
// base apr oracle V2 deployed at: 0xe15D914513868DE594909e05AC530F0c0d5d6036 (third deployment, had to fix swap fee BPS and added logic to check FLUID balance of UniV3 pool)
// arbitrum apr oracle deployed at: 0x020C9d54744f8b9778CdEBA954395f2b7f5540Ae
