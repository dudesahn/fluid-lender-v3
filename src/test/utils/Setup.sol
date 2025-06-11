// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {FluidLenderMainnet, ERC20, SafeERC20} from "src/FluidLenderMainnet.sol"; // make sure to use SafeERC20 for USDT
import {FluidLenderFactoryMainnet} from "src/FluidLenderFactoryMainnet.sol";
import {FluidLenderFactoryL2} from "src/FluidLenderFactoryL2.sol";
import {FluidLenderFactoryPolygon} from "src/FluidLenderFactoryPolygon.sol";
import {IStrategyInterface} from "src/interfaces/IStrategyInterface.sol";
import {IStrategyFactoryInterface} from "src/interfaces/IStrategyFactoryInterface.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

// use this to simulate max utilization
interface IFluidLiquidityVault {
    function operate(
        uint256,
        int256,
        int256,
        address
    ) external returns (uint256, int256, int256);
}

contract Setup is ExtendedTest, IEvents {
    using SafeERC20 for ERC20;

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    IStrategyFactoryInterface public strategyFactory;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(6969);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    address public fluidVault;
    address public fluidStaking;
    uint24 public baseToAsset;

    // addresses of our resolvers
    address public lendingResolver;
    address public liquidityResolver;

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e18; // 1e30 for 1e18 coin == 1e18 for 1e6 coin. 1e15 = 1B USDC.
    uint256 public minFuzzAmount = 10_000;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset. This is all we should have to adjust, along with using a different network in our makefile
        asset = ERC20(tokenAddrs["USDC"]);

        // adjust asset here ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️

        if (block.chainid == 1) {
            if (address(asset) == tokenAddrs["USDC"]) {
                fluidVault = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;
                baseToAsset = 500;
            } else if (address(asset) == tokenAddrs["USDT"]) {
                fluidVault = 0x5C20B550819128074FD538Edf79791733ccEdd18;
                baseToAsset = 500;
            } else {
                // weth
                fluidVault = 0x90551c1795392094FE6D29B758EcCD233cFAa260;
            }
        } else if (block.chainid == 137) {
            if (address(asset) == tokenAddrs["USDC"]) {
                fluidVault = 0x571d456b578fDC34E26E6D636736ED7c0CDB9d89;
            } else if (address(asset) == tokenAddrs["USDT"]) {
                fluidVault = 0x6f5e34eFf43D9ab7c977512509C53840B5EfBA85;
            } else {
                // weth
                fluidVault = 0xD3154535E4D0e179583ad694859E4e876EB12d24;
            }
        } else if (block.chainid == 8453) {
            if (address(asset) == tokenAddrs["USDC"]) {
                fluidVault = 0xf42f5795D9ac7e9D757dB633D693cD548Cfd9169;
            } else {
                // weth
                fluidVault = 0x9272D6153133175175Bc276512B2336BE3931CE9;
            }
        } else if (block.chainid == 42161) {
            if (address(asset) == tokenAddrs["USDC"]) {
                fluidVault = 0x1A996cb54bb95462040408C06122D45D6Cdb6096;
            } else if (address(asset) == tokenAddrs["USDT"]) {
                fluidVault = 0x4A03F37e7d3fC243e3f99341d36f4b829BEe5E03;
            } else {
                // weth
                fluidVault = 0x45Df0656F8aDf017590009d2f1898eeca4F0a205;
            }
        }

        // Set decimals
        decimals = asset.decimals();

        // deploy our factory and strategy
        vm.startPrank(management);

        if (block.chainid == 1) {
            lendingResolver = 0xC215485C572365AE87f908ad35233EC2572A3BEC;
            liquidityResolver = 0xF82111c4354622AB12b9803cD3F6164FCE52e847;

            strategyFactory = IStrategyFactoryInterface(
                address(
                    new FluidLenderFactoryMainnet(
                        management,
                        performanceFeeRecipient,
                        keeper,
                        emergencyAdmin
                    )
                )
            );

            // Deploy strategy and set variables
            strategy = IStrategyInterface(
                strategyFactory.newFluidLender(
                    address(asset),
                    "Fluid Lender",
                    fluidVault,
                    baseToAsset
                )
            );
        } else if (block.chainid == 137) {
            lendingResolver = 0x8e72291D5e6f4AAB552cc827fB857a931Fc5CAC1;
            liquidityResolver = 0x98d900e25AAf345A4B23f454751EC5083443Fa83;

            strategyFactory = IStrategyFactoryInterface(
                address(
                    new FluidLenderFactoryPolygon(
                        management,
                        performanceFeeRecipient,
                        keeper,
                        emergencyAdmin
                    )
                )
            );

            // Deploy strategy and set variables
            strategy = IStrategyInterface(
                strategyFactory.newFluidLender(
                    address(asset),
                    "Fluid Lender",
                    fluidVault
                )
            );
        } else {
            if (block.chainid == 8453) {
                lendingResolver = 0x3aF6FBEc4a2FE517F56E402C65e3f4c3e18C1D86;
                liquidityResolver = 0x35A915336e2b3349FA94c133491b915eD3D3b0cd;
            } else {
                // arbitrum
                lendingResolver = 0xdF4d3272FfAE8036d9a2E1626Df2Db5863b4b302;
                liquidityResolver = 0x46859d33E662d4bF18eEED88f74C36256E606e44;
            }

            // L2s
            strategyFactory = IStrategyFactoryInterface(
                address(
                    new FluidLenderFactoryL2(
                        management,
                        performanceFeeRecipient,
                        keeper,
                        emergencyAdmin
                    )
                )
            );

            // Deploy strategy and set variables
            strategy = IStrategyInterface(
                strategyFactory.newFluidLender(
                    address(asset),
                    "Fluid Lender",
                    fluidVault
                )
            );
        }
        strategy.acceptManagement();
        vm.stopPrank();

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(emergencyAdmin, "emergencyAdmin");
        if (block.chainid == 1) {
            vm.label(0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33, "fluidUSDC");
            vm.label(0x5C20B550819128074FD538Edf79791733ccEdd18, "fluidUSDT");
            vm.label(0x90551c1795392094FE6D29B758EcCD233cFAa260, "fluidWETH");
            vm.label(tokenAddrs["WETH"], "WETH");
            vm.label(tokenAddrs["USDT"], "USDT");
            vm.label(tokenAddrs["USDC"], "USDC");
        } else if (block.chainid == 137) {
            vm.label(0x571d456b578fDC34E26E6D636736ED7c0CDB9d89, "fluidUSDC");
            vm.label(0x6f5e34eFf43D9ab7c977512509C53840B5EfBA85, "fluidUSDT");
            vm.label(0xD3154535E4D0e179583ad694859E4e876EB12d24, "fluidWETH");
            vm.label(tokenAddrs["WETH"], "WETH");
            vm.label(tokenAddrs["USDT"], "USDT");
            vm.label(tokenAddrs["USDC"], "USDC");
        } else if (block.chainid == 8453) {
            vm.label(0xf42f5795D9ac7e9D757dB633D693cD548Cfd9169, "fluidUSDC");
            vm.label(0x9272D6153133175175Bc276512B2336BE3931CE9, "fluidWETH");
            vm.label(tokenAddrs["WETH"], "WETH");
            vm.label(tokenAddrs["USDC"], "USDC");
        } else if (block.chainid == 42161) {
            vm.label(0x1A996cb54bb95462040408C06122D45D6Cdb6096, "fluidUSDC");
            vm.label(0x4A03F37e7d3fC243e3f99341d36f4b829BEe5E03, "fluidUSDT");
            vm.label(0x45Df0656F8aDf017590009d2f1898eeca4F0a205, "fluidWETH");
            vm.label(tokenAddrs["WETH"], "WETH");
            vm.label(tokenAddrs["USDT"], "USDT");
            vm.label(tokenAddrs["USDC"], "USDC");
        }
    }

    function causeMaxUtil(uint256 userDeposit) public returns (bool isMaxUtil) {
        // borrow all the USDC in the liquidity contract using wstETH and then see how our strategy performs
        // check usdc balance of fluid liquidity proxy (this is where our deposited funds flow)
        address liquidity = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;
        uint256 toBorrow = (asset.balanceOf(liquidity) * 995) / 1_000; // leave 50 bps so it doesn't revert

        if (
            block.chainid == 8453 &&
            fluidVault == 0xf42f5795D9ac7e9D757dB633D693cD548Cfd9169
        ) {
            address whale = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb; // morpho, wstETH, base

            IFluidLiquidityVault liquidityVault = IFluidLiquidityVault(
                0xbEC491FeF7B4f666b270F9D5E5C3f443cBf20991
            );
            ERC20 collateral_token = ERC20(
                0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452
            );

            vm.startPrank(whale);
            collateral_token.approve(
                address(liquidityVault),
                type(uint256).max
            );

            liquidityVault.operate(0, 5_000e18, int256(toBorrow), whale);
            vm.stopPrank();
            console2.log("Pushed market to max utilization");

            // check balance of liquidity contract, make sure we have less left than user deposited
            uint256 contractBalance = asset.balanceOf(liquidity);
            assertGt(userDeposit, contractBalance, "!illiquid");
            console2.log("Liquidity USDC balance:", contractBalance);
            isMaxUtil = true;
        }
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.forceApprove(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        if (block.chainid == 1) {
            tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
            tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        } else if (block.chainid == 8453) {
            tokenAddrs["WETH"] = 0x4200000000000000000000000000000000000006;
            tokenAddrs["USDC"] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        } else if (block.chainid == 42161) {
            tokenAddrs["WETH"] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            tokenAddrs["USDC"] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
            tokenAddrs["USDT"] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        } else if (block.chainid == 137) {
            tokenAddrs["WETH"] = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
            tokenAddrs["USDC"] = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
            tokenAddrs["USDT"] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
        }
    }
}
