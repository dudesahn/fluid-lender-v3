// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {FluidAprOracleMainnet} from "src/periphery/FluidAprOracleMainnet.sol";
import {FluidAprOraclePolygon} from "src/periphery/FluidAprOraclePolygon.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/DeployAprOraclesUni.s.sol:DeployAprOraclesUni --account llc2 --rpc-url $ETH_RPC_URL -vvvvv
// use other rpcs as needed, can use the same script on all chains. ETH_RPC_URL, BASE_RPC_URL, ARBITRUM_RPC_URL, MATIC_RPC_URL
// don't need to include the optimize flag since we set it in our foundry.toml
// separate out these two oracles since we use the uniswap simulator with them, and otherwise we'll deploy it along with base and arbitrum too

// forge script script/DeployAprOraclesUni.s.sol:DeployAprOraclesUni --account llc2 --rpc-url $MATIC_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast
// forge script script/DeployAprOraclesUni.s.sol:DeployAprOraclesUni --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast

// need to verify the library directly, doing the flag on the script didn't work!
// forge verify-contract --rpc-url $MATIC_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "0x493B566F7A773f393735eb71B6bDDCcF5D1a8aec" UniswapV3SwapSimulator
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "0x493B566F7A773f393735eb71B6bDDCcF5D1a8aec" UniswapV3SwapSimulator
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "0xe99AA816Abd92b4F19b4eB51bE52D18cdB5bC821" FluidAprOracleMainnet

// adding the linked library flag to the script actually completely fucked it all up and didn't deploy the library...maybe when I do that it assumes it already exists?
// so in the future just do it separately

// verify:
// needed to manually verify, can copy-paste abi-encoded constructor args from the printed output of the deployment. this command ends with the address and contract to verify, always
// no constructor (or thus, constructor args) on this one
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "CONTRACT_ADDRESS" CONTRACT_NAME

contract DeployAprOraclesUni is Script {
    /// @notice Deployer
    address public constant MANAGEMENT =
        0xd0002c648CCa8DeE2f2b8D70D542Ccde8ad6EC03;

    IOracle public oracle;

    function run() external {
        vm.startBroadcast();

        if (block.chainid == 1) {
            oracle = IOracle(address(new FluidAprOracleMainnet(MANAGEMENT)));
        } else if (block.chainid == 137) {
            oracle = IOracle(address(new FluidAprOraclePolygon(MANAGEMENT)));
        }

        console2.log("-----------------------------");
        console2.log("apr oracle deployed at: %s", address(oracle));
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}

// mainnet apr oracle deployed at: 0x031EDE4CA99b9d75fC77a8b0E661C90005A7CBe2
// polygon apr oracle deployed at: 0x0cFF9Cc047DdcbB5562012e6F6a301E8DbB1Ed4D
