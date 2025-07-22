pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "src/test/utils/Setup.sol";

import {FluidAprOracleMainnet} from "src/periphery/FluidAprOracleMainnet.sol";
import {FluidAprOraclePolygon} from "src/periphery/FluidAprOraclePolygon.sol";
import {FluidAprOracleArbitrum} from "src/periphery/FluidAprOracleArbitrum.sol";
import {FluidAprOracleBase} from "src/periphery/FluidAprOracleBase.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

contract OracleTest is Setup {
    IOracle public oracle;

    uint256 public fuzzAmount;

    function setUp() public override {
        super.setUp();
        // deploy our factory and strategy
        vm.startPrank(management);

        if (block.chainid == 1) {
            oracle = IOracle(address(new FluidAprOracleMainnet(management)));
            // set the rewards rate for our oracle
            oracle.setRewardsRate(fluidVault, extraRewardRate);
        } else if (block.chainid == 137) {
            oracle = IOracle(address(new FluidAprOraclePolygon(management)));
            // set the rewards rate for our oracle
            oracle.setRewardsRate(fluidVault, extraRewardRate);
        } else if (block.chainid == 8453) {
            // base
            oracle = IOracle(address(new FluidAprOracleBase(management)));

            // set the APR manually for our oracle
            // oracle.setUseManualRewardsApr(true);
            // oracle.setManualRewardsApr(fluidVault, manualRewardApr);

            // set the rewards rate for our oracle
            oracle.setRewardsRate(fluidVault, extraRewardRate);
        } else {
            // arbitrum
            oracle = IOracle(address(new FluidAprOracleArbitrum(management)));

            // set the APR manually for our oracle
            // oracle.setUseManualRewardsApr(true);
            // oracle.setManualRewardsApr(fluidVault, manualRewardApr);

            // set the rewards rate for our oracle
            oracle.setRewardsRate(fluidVault, extraRewardRate);
        }
        vm.stopPrank();
    }

    function test_oracle_simple_check() public {
        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        console2.log("Current APR:", currentApr);
        console2.log("Current APR (whole number):", (currentApr * 100) / 1e18);

        if (block.chainid == 1) {
            uint256 supplyApr = oracle.getSupplyRate(address(strategy), 0);
            console2.log("Current Supply APR:", supplyApr);
            console2.log(
                "Current Supply APR (whole number):",
                (supplyApr * 100) / 1e18
            );

            // WETH runs out of gas on oracle.getRewardRates
            // FluidLendingResolver::getFTokenDetails within the call gives EvmError: OutOfGas
            // likely because of WETH's fallback? that shows the following:
            // [StateChangeDuringStaticCall] EvmError: StateChangeDuringStaticCall
            // tbh I think it's likely just that it's the third time we hit the static call state change and that puts
            // us into OOG territory, because the first two calls to it don't end up running out of gas
            if (address(asset) == tokenAddrs["WETH"]) {
                vm.pauseGasMetering();
            }

            (uint256 rewardsApr, uint256 fluidApr) = oracle.getRewardRates(
                address(strategy),
                0
            );
            console2.log("Current Rewards APR:", rewardsApr);
            console2.log(
                "Current Rewards APR (whole number):",
                (rewardsApr * 100) / 1e18
            );
            console2.log("Current FLUID APR:", fluidApr);
            console2.log(
                "Current FLUID APR (whole number):",
                (fluidApr * 100) / 1e18
            );

            uint256 fluidPrice = oracle.getFluidPriceUsdc();
            console2.log("Current FLUID Price:", fluidPrice);
            console2.log("Current FLUID Price (dollars):", (fluidPrice) / 1e6);
        } else if (block.chainid == 137) {
            uint256 supplyApr = oracle.getSupplyRate(address(strategy), 0);
            console2.log("Current Supply APR:", supplyApr);
            console2.log(
                "Current Supply APR (whole number):",
                (supplyApr * 100) / 1e18
            );

            (uint256 rewardsApr, uint256 polApr) = oracle.getRewardRates(
                address(strategy),
                0
            );
            console2.log("Current Rewards APR:", rewardsApr);
            console2.log(
                "Current Rewards APR (whole number):",
                (rewardsApr * 100) / 1e18
            );
            console2.log("Current POL APR:", polApr);
            console2.log(
                "Current POL APR (whole number):",
                (polApr * 100) / 1e18
            );

            uint256 polPrice = oracle.getPolPriceUsdc();
            console2.log("Current POL Price:", polPrice);
            console2.log("Current POL Price (dollars):", (polPrice) / 1e6);
        } else {
            // L2s
            uint256 supplyApr = oracle.getSupplyRate(address(strategy), 0);
            console2.log("Current Supply APR:", supplyApr);
            console2.log(
                "Current Supply APR (whole number):",
                (supplyApr * 100) / 1e18
            );

            (uint256 rewardsApr, uint256 fluidApr) = oracle.getRewardRates(
                address(strategy),
                0
            );
            console2.log("Current Rewards APR:", rewardsApr);
            console2.log(
                "Current Rewards APR (whole number):",
                (rewardsApr * 100) / 1e18
            );
            console2.log("Current FLUID APR:", fluidApr);
            console2.log(
                "Current FLUID APR (whole number):",
                (fluidApr * 100) / 1e18
            );

            uint256 fluidPrice = oracle.getFluidPriceUsdc();
            console2.log("Current FLUID Price:", fluidPrice);
            console2.log("Current FLUID Price (dollars):", (fluidPrice) / 1e6);
        }
    }

    // NOTE: need to setup the manual merkle reward amounts on the oracles for these tests after deployment...

    function checkOracle(address _strategy, uint256 _delta) public {
        // Check set up
        // TODO: Add checks for the setup

        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        // Should be greater than 0 but likely less than 100%
        // stablecoins have bonus/rewards APR which won't be fully diluted
        // WETH can be diluted to zero since it's lending-only. above our noYieldAmount, APR might be zero
        if (
            address(asset) == tokenAddrs["WETH"] && fuzzAmount > noYieldAmount
        ) {
            assertGe(currentApr, 0, "ZERO");
        } else {
            assertGt(currentApr, 0, "ZERO");
        }

        assertLt(currentApr, 1e18, "+100%");
        console2.log("APR", currentApr);

        // TODO: Uncomment to test the apr goes up and down based on debt changes
        /**
        uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(_strategy, -int256(_delta));

        // The apr should go up if deposits go down
        assertLt(currentApr, negativeDebtChangeApr, "negative change");

        uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(_strategy, int256(_delta));

        assertGt(currentApr, positiveDebtChangeApr, "positive change");
        */

        // TODO: Uncomment if there are setter functions to test.
        /**
        vm.expectRevert("!governance");
        vm.prank(user);
        oracle.setterFunction(setterVariable);

        vm.prank(management);
        oracle.setterFunction(setterVariable);

        assertEq(oracle.setterVariable(), setterVariable);
        */
    }

    function test_oracle_fuzzy(uint256 _amount, uint16 _percentChange) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));
        fuzzAmount = _amount;

        // Deposit into strategy
        // since Fluid auto-unwraps WETH to ETH, we must deal ether to WETH in the same amount so the tokens are backed
        if (
            address(asset) == tokenAddrs["WETH"] &&
            (block.chainid == 1 ||
                block.chainid == 8453 ||
                block.chainid == 42161)
        ) {
            vm.deal(tokenAddrs["WETH"], _amount);
        }
        mintAndDepositIntoStrategy(strategy, user, _amount);

        if (_amount > noYieldAmount) {
            noBaseYield = true;
        }

        uint256 _delta = (_amount * _percentChange) / MAX_BPS;

        checkOracle(address(strategy), _delta);
    }

    // TODO: Deploy multiple strategies with different tokens as `asset` to test against the oracle.
}
