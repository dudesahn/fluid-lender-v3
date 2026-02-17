// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {FluidLenderFactoryMainnet} from "src/FluidLenderFactoryMainnet.sol";
import {FluidLenderFactoryBase} from "src/FluidLenderFactoryBase.sol";
import {FluidLenderFactoryArbitrum} from "src/FluidLenderFactoryArbitrum.sol";
import {FluidLenderFactoryPolygon} from "src/FluidLenderFactoryPolygon.sol";
import {IStrategyFactoryInterface} from "src/interfaces/IStrategyFactoryInterface.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/DeployFluidFactories.s.sol:DeployFluidFactories --account llc2 --rpc-url $BASE_RPC_URL -vvvvv
// use other rpcs as needed, can use the same script on all chains. ETH_RPC_URL, BASE_RPC_URL, ARBITRUM_RPC_URL, MATIC_RPC_URL
// don't need to include the optimize flag since we set it in our foundry.toml

// forge script script/DeployFluidFactories.s.sol:DeployFluidFactories --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast
// forge script script/DeployFluidFactories.s.sol:DeployFluidFactories --account llc2 --rpc-url $BASE_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast
// forge script script/DeployFluidFactories.s.sol:DeployFluidFactories --account llc2 --rpc-url $ARBITRUM_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast
// forge script script/DeployFluidFactories.s.sol:DeployFluidFactories --account llc2 --rpc-url $MATIC_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast

// verify:
// needed to manually verify, can copy-paste abi-encoded constructor args from the printed output of the deployment. this command ends with the address and contract to verify, always
// no constructor (or thus, constructor args) on this one
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "CONTRACT_ADDRESS" CONTRACT_NAME

contract DeployFluidFactories is Script {
    /// @notice Deployer to get everything setup first before transferring to SMS
    address public constant MANAGEMENT =
        0xd0002c648CCa8DeE2f2b8D70D542Ccde8ad6EC03;

    IStrategyFactoryInterface public strategyFactory;

    function run() external {
        vm.startBroadcast();

        if (block.chainid == 1) {
            strategyFactory = IStrategyFactoryInterface(
                address(
                    new FluidLenderFactoryMainnet(
                        MANAGEMENT,
                        0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7,
                        0x604e586F17cE106B64185A7a0d2c1Da5bAce711E,
                        0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69
                    )
                )
            );
        } else if (block.chainid == 137) {
            // polygon
            strategyFactory = IStrategyFactoryInterface(
                address(
                    new FluidLenderFactoryPolygon(
                        MANAGEMENT,
                        0x16388000546eDed4D476bd2A4A374B5a16125Bc1,
                        0x3A95F75f0Ea2FD60b31E7c6180C7B5fC9865492F,
                        0x54483f1592ab0aDea2757Ae0d62e6393361d4CEe
                    )
                )
            );
        } else if (block.chainid == 8453) {
            // base
            strategyFactory = IStrategyFactoryInterface(
                address(
                    new FluidLenderFactoryBase(
                        MANAGEMENT,
                        0x01fE3347316b2223961B20689C65eaeA71348e93,
                        0x46679Ba8ce6473a9E0867c52b5A50ff97579740E,
                        0x1f399808fE52d0E960CAB84b6b54d5707ab27c8a
                    )
                )
            );
        } else {
            // arbitrum
            strategyFactory = IStrategyFactoryInterface(
                address(
                    new FluidLenderFactoryArbitrum(
                        MANAGEMENT,
                        0x6346282DB8323A54E840c6C772B4399C9c655C0d,
                        0xE0D19f6b240659da8E87ABbB73446E7B4346Baee,
                        0x9aB47bE62631036CDa3a64B8322704988427F366
                    )
                )
            );
        }

        console2.log("-----------------------------");
        console2.log("factory deployed at: ", address(strategyFactory));
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}

// mainnet factory deployed at: 0x859dF6fe178Ffbf55693A7A833aaDb10C6a43861
// polygon factory deployed at: 0xF4221238052f023f2b27E402Dc86dA2D60A1bF26
// base factory deployed at: 0xc723DD5EA544069284D1384ffB654f1A93D46C81
// arbitrum factory deployed at: 0xFf70f9758F8af1C9EF7Ecd1E66e261253D4eF031
