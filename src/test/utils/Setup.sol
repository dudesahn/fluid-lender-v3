// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {FluidLenderMainnet, ERC20, SafeERC20, Auction} from "src/FluidLenderMainnet.sol";
import {FluidLenderFactoryMainnet} from "src/FluidLenderFactoryMainnet.sol";
import {FluidLenderFactoryBase} from "src/FluidLenderFactoryBase.sol";
import {FluidLenderFactoryArbitrum} from "src/FluidLenderFactoryArbitrum.sol";
import {FluidLenderFactoryPolygon} from "src/FluidLenderFactoryPolygon.sol";
import {IStrategyInterface} from "src/interfaces/IStrategyInterface.sol";
import {IStrategyFactoryInterface} from "src/interfaces/IStrategyFactoryInterface.sol";
import {AuctionFactory} from "@periphery/Auctions/AuctionFactory.sol";

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

contract Setup is Test, IEvents {
    using SafeERC20 for ERC20;

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    IStrategyFactoryInterface public strategyFactory;

    mapping(string => address) public tokenAddrs;

    // auction to be used by our strategy
    Auction public auction;
    AuctionFactory public auctionFactory =
        AuctionFactory(0xCfA510188884F199fcC6e750764FAAbE6e56ec40); // same address on all chains

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    address public fluidVault;
    address public fluidStaking;
    address public fluidDex; // address of our FLUID-WETH DEXes on L2s

    // addresses of our resolvers and chainlink calcs, used with our apr oracles
    address public lendingResolver;
    address public liquidityResolver;
    address public dexResolver;
    address public chainlinkCalcs;
    address public constant fluidLiquidityProxy =
        0x52Aa899454998Be5b000Ad077a46Bbe360F4e497; // same on all chains

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    // do these based on the decimals
    uint256 public maxFuzzAmount; // 1e30 for 1e18 coin == 1e18 for 1e6 coin. 1e15 = 1B USDC.
    uint256 public minFuzzAmount;
    uint256 public ORACLE_FUZZ_MIN;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    // state vars to use in case we have very low or zero yield; some of our assumptions break
    bool public noBaseYield;
    bool public lowBaseYield;
    uint256 public noYieldAmount; // amount above which we dilute lending yields to zero
    uint256 public extraRewardRate; // rate for FLUID or WPOL rewards (tokens per second)
    uint256 public manualRewardApr; // manual reward apr for base and arbitrum
    address public merkleRewardToken; // token we receive from our merkle claim (WPOL on Polgyon, FLUID everywhere else)

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset. This is all we should have to adjust, along with using a different network in our makefile
        asset = ERC20(tokenAddrs["USDC"]);

        // consider adding GHO to test auctions with too (atomic swaps not as simple on this, liq on balancer)

        // setup our fuzz amounts
        maxFuzzAmount = 1e12 * (10 ** asset.decimals());
        minFuzzAmount = (10 ** asset.decimals()) / 100;

        // set ~$1B as no yield amount
        // EURC hits it lower than other assets since no one wants to borrow :(
        if (address(asset) == tokenAddrs["WETH"]) {
            // mainnet has better yields so can tolerate more dilution
            if (block.chainid == 1) {
                noYieldAmount = 250_000 * (10 ** asset.decimals());
            } else if (block.chainid == 137) {
                // smaller size as L2s with similarly poor yield on polygon
                noYieldAmount = 15_000 * (10 ** asset.decimals());
            } else {
                noYieldAmount = 25_000 * (10 ** asset.decimals());
            }
        } else if (address(asset) == tokenAddrs["EURC"]) {
            noYieldAmount = 1e8 * (10 ** asset.decimals());
        } else {
            noYieldAmount = 1e9 * (10 ** asset.decimals());
        }

        // adjust asset here ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️ ⬆️️️️️️️️️️

        if (block.chainid == 1) {
            if (address(asset) == tokenAddrs["USDC"]) {
                fluidVault = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;
                extraRewardRate = 38580246913580246;
            } else if (address(asset) == tokenAddrs["USDT"]) {
                fluidVault = 0x5C20B550819128074FD538Edf79791733ccEdd18;
                extraRewardRate = 38580246913580246;
            } else {
                // weth
                fluidVault = 0x90551c1795392094FE6D29B758EcCD233cFAa260;
            }
        } else if (block.chainid == 137) {
            if (address(asset) == tokenAddrs["USDC"]) {
                fluidVault = 0x571d456b578fDC34E26E6D636736ED7c0CDB9d89;
                extraRewardRate = 173611111111111111;
            } else if (address(asset) == tokenAddrs["USDT"]) {
                fluidVault = 0x6f5e34eFf43D9ab7c977512509C53840B5EfBA85;
                extraRewardRate = 173611111111111111;
            } else {
                // weth
                fluidVault = 0xD3154535E4D0e179583ad694859E4e876EB12d24;
            }
        } else if (block.chainid == 8453) {
            if (address(asset) == tokenAddrs["USDC"]) {
                fluidVault = 0xf42f5795D9ac7e9D757dB633D693cD548Cfd9169;
                manualRewardApr = 450 * 10 ** 14;
                extraRewardRate = 4243827160493827;
            } else if (address(asset) == tokenAddrs["EURC"]) {
                fluidVault = 0x1943FA26360f038230442525Cf1B9125b5DCB401;
                manualRewardApr = 664 * 10 ** 14;
                extraRewardRate = 964506172839506;
            } else {
                // weth
                fluidVault = 0x9272D6153133175175Bc276512B2336BE3931CE9;
            }
        } else if (block.chainid == 42161) {
            if (address(asset) == tokenAddrs["USDC"]) {
                fluidVault = 0x1A996cb54bb95462040408C06122D45D6Cdb6096;
                manualRewardApr = 415 * 10 ** 14;
                extraRewardRate = 6172839506111111;
            } else if (address(asset) == tokenAddrs["USDT"]) {
                fluidVault = 0x4A03F37e7d3fC243e3f99341d36f4b829BEe5E03;
                manualRewardApr = 621 * 10 ** 14;
                extraRewardRate = 6172839506111111;
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
            merkleRewardToken = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;

            // can't use zero addresses
            vm.expectRevert("ZERO_ADDRESS");
            new FluidLenderFactoryMainnet(
                address(0),
                performanceFeeRecipient,
                keeper,
                emergencyAdmin
            );
            vm.expectRevert("ZERO_ADDRESS");
            new FluidLenderFactoryMainnet(
                management,
                address(0),
                keeper,
                emergencyAdmin
            );
            vm.expectRevert("ZERO_ADDRESS");
            new FluidLenderFactoryMainnet(
                management,
                performanceFeeRecipient,
                keeper,
                address(0)
            );

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
                    fluidVault
                )
            );
        } else if (block.chainid == 137) {
            lendingResolver = 0x8e72291D5e6f4AAB552cc827fB857a931Fc5CAC1;
            liquidityResolver = 0x98d900e25AAf345A4B23f454751EC5083443Fa83;
            merkleRewardToken = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

            // can't use zero addresses
            vm.expectRevert("ZERO_ADDRESS");
            new FluidLenderFactoryPolygon(
                address(0),
                performanceFeeRecipient,
                keeper,
                emergencyAdmin
            );
            vm.expectRevert("ZERO_ADDRESS");
            new FluidLenderFactoryPolygon(
                management,
                address(0),
                keeper,
                emergencyAdmin
            );
            vm.expectRevert("ZERO_ADDRESS");
            new FluidLenderFactoryPolygon(
                management,
                performanceFeeRecipient,
                keeper,
                address(0)
            );

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
            // L2s
            if (block.chainid == 8453) {
                lendingResolver = 0x3aF6FBEc4a2FE517F56E402C65e3f4c3e18C1D86;
                liquidityResolver = 0x35A915336e2b3349FA94c133491b915eD3D3b0cd;
                dexResolver = 0xa3B18522827491f10Fc777d00E69B3669Bf8c1f8;
                chainlinkCalcs = 0x20e1F95cd5CD6954f16B7455a4C8fA1aDb99eb4D;
                fluidDex = 0xdE632C3a214D5f14C1d8ddF0b92F8BCd188fee45;

                // can't use zero addresses
                vm.expectRevert("ZERO_ADDRESS");
                new FluidLenderFactoryBase(
                    address(0),
                    performanceFeeRecipient,
                    keeper,
                    emergencyAdmin
                );
                vm.expectRevert("ZERO_ADDRESS");
                new FluidLenderFactoryBase(
                    management,
                    address(0),
                    keeper,
                    emergencyAdmin
                );
                vm.expectRevert("ZERO_ADDRESS");
                new FluidLenderFactoryBase(
                    management,
                    performanceFeeRecipient,
                    keeper,
                    address(0)
                );

                strategyFactory = IStrategyFactoryInterface(
                    address(
                        new FluidLenderFactoryBase(
                            management,
                            performanceFeeRecipient,
                            keeper,
                            emergencyAdmin
                        )
                    )
                );
            } else {
                // arbitrum
                lendingResolver = 0xdF4d3272FfAE8036d9a2E1626Df2Db5863b4b302;
                liquidityResolver = 0x46859d33E662d4bF18eEED88f74C36256E606e44;
                dexResolver = 0x87B7E70D8F1FAcD3d154AF8559D632481724508E;
                chainlinkCalcs = 0x9d032763693D4eF989b630de2eCA8750BDe88219;
                fluidDex = 0x2886a01a0645390872a9eb99dAe1283664b0c524;

                // can't use zero addresses
                vm.expectRevert("ZERO_ADDRESS");
                new FluidLenderFactoryArbitrum(
                    address(0),
                    performanceFeeRecipient,
                    keeper,
                    emergencyAdmin
                );
                vm.expectRevert("ZERO_ADDRESS");
                new FluidLenderFactoryArbitrum(
                    management,
                    address(0),
                    keeper,
                    emergencyAdmin
                );
                vm.expectRevert("ZERO_ADDRESS");
                new FluidLenderFactoryArbitrum(
                    management,
                    performanceFeeRecipient,
                    keeper,
                    address(0)
                );

                strategyFactory = IStrategyFactoryInterface(
                    address(
                        new FluidLenderFactoryArbitrum(
                            management,
                            performanceFeeRecipient,
                            keeper,
                            emergencyAdmin
                        )
                    )
                );
            }
            // same on base and arbitrum
            merkleRewardToken = 0x61E030A56D33e8260FdD81f03B162A79Fe3449Cd;

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

        // check that deposits are closed
        vm.startPrank(management);
        assertEq(strategy.availableDepositLimit(user), 0, "!deposit");
        strategy.setAllowed(user, true);
        assertGt(strategy.availableDepositLimit(user), 0, "!deposit");
        strategy.setAllowed(user, false);

        // turn on open deposits
        strategy.setOpenDeposits(true);
        vm.stopPrank();

        // setup our auction with our rewards token to sell
        if (block.chainid == 137) {
            setUpAuction(strategy.WPOL(), address(asset), address(strategy));
        } else {
            setUpAuction(strategy.FLUID(), address(asset), address(strategy));
        }

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
            vm.label(0x1943FA26360f038230442525Cf1B9125b5DCB401, "fluidEURC");
            vm.label(tokenAddrs["WETH"], "WETH");
            vm.label(tokenAddrs["USDC"], "USDC");
            vm.label(tokenAddrs["EURC"], "EURC");
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
        uint256 toBorrow = (asset.balanceOf(fluidLiquidityProxy) * 9950) /
            10_000; // leave 50 bps so it doesn't revert

        if (block.chainid == 8453 && address(asset) == tokenAddrs["USDC"]) {
            address whale = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb; // morpho, wstETH, base

            IFluidLiquidityVault liquidityVault = IFluidLiquidityVault(
                0xbEC491FeF7B4f666b270F9D5E5C3f443cBf20991 // wstETH-USDC
            );
            ERC20 collateral_token = ERC20(
                0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452 // wstETH
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
            uint256 contractBalance = asset.balanceOf(fluidLiquidityProxy);
            assertGt(userDeposit, contractBalance, "!illiquid");
            console2.log(
                "Fluid Liquidity Proxy USDC balance:",
                contractBalance
            );
            isMaxUtil = true;
        }

        if (block.chainid == 42161 && address(asset) == tokenAddrs["USDC"]) {
            address whale = 0x513c7E3a9c69cA3e22550eF58AC1C0088e918FFf; // aave, wstETH, arbitrum

            IFluidLiquidityVault liquidityVault = IFluidLiquidityVault(
                0xA0F83Fc5885cEBc0420ce7C7b139Adc80c4F4D91 // wstETH-USDC
            );
            ERC20 collateral_token = ERC20(
                0x5979D7b546E38E414F7E9822514be443A4800529 // wstETH
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
            uint256 contractBalance = asset.balanceOf(fluidLiquidityProxy);
            assertGt(userDeposit, contractBalance, "!illiquid");
            console2.log(
                "Fluid Liquidity Proxy USDC balance:",
                contractBalance
            );
            isMaxUtil = true;
        }
        // skip polygon and mainnet because there's not enough immediately borrowable stables in the major markets to push to max util
    }

    function setUpAuction(
        address _token,
        address _want,
        address _receiver
    ) public {
        // deploy auction for the strategy
        auction = Auction(
            auctionFactory.createNewAuction(_want, _receiver, management)
        );

        // enable reward token on our auction
        vm.prank(management);
        auction.enable(_token);
    }

    function simulateAuction(uint256 _profitAmount) public {
        // cache our rewards token
        address rewardsToken;
        if (block.chainid == 137) {
            rewardsToken = strategy.WPOL();
        } else {
            rewardsToken = strategy.FLUID();
        }

        // kick the auction
        vm.prank(keeper);
        strategy.kickAuction(rewardsToken);

        // check for reward token balance in auction
        uint256 rewardBalance = ERC20(rewardsToken).balanceOf(address(auction));
        uint256 strategyBalance = ERC20(rewardsToken).balanceOf(
            address(auction)
        );
        console2.log(
            "Reward token sitting in our strategy",
            strategyBalance / 1e18,
            "* 1e18"
        );

        // if we have reward tokens, sweep it out, and send back our designated profitAmount
        if (rewardBalance > 0) {
            console2.log(
                "Reward token sitting in our auction",
                rewardBalance / 1e18,
                "* 1e18"
            );

            vm.prank(address(auction));
            ERC20(rewardsToken).transfer(user, rewardBalance);
            airdrop(asset, address(strategy), _profitAmount);
            rewardBalance = ERC20(rewardsToken).balanceOf(address(auction));
        }

        // confirm that we swept everything out
        assertEq(rewardBalance, 0, "!rewardBalance");
    }

    function simulateMerkleClaim() public {
        // aim for roughly 5% APR on $1M, so ~$1300 from rewards in 10 days
        if (block.chainid == 137) {
            deal(merkleRewardToken, address(strategy), 5_000e18);
        } else {
            deal(merkleRewardToken, address(strategy), 200e18);
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
    ) public view {
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
        // if doing on arbitrum, let's deal with increasing total supply
        if (block.chainid == 42161) {
            // use the last argument to increase the totalSupply for burning WETH on arbitrum
            deal(address(_asset), _to, balanceBefore + _amount, true);
        } else {
            deal(address(_asset), _to, balanceBefore + _amount);
        }
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
            tokenAddrs["EURC"] = 0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42;
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
