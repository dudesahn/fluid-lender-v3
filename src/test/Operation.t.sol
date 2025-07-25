// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    // note that this test only considers base yield (underlying lending and in-kind rewards APR)
    function test_operation_fuzzy(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

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
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // we may not generate yield if the deposit is too large (crush borrow APR to 0), or very tiny (base yield not
        //  1 whole wei of interest earned yet)
        if (_amount > noYieldAmount || _amount < 1e5) {
            noBaseYield = true;
        }

        // turn off health check if no yield since we may lose 1-2 wei from rounding
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        if (noBaseYield) {
            assertGe(profit, 0, "!profit");
            assertLe(loss, 2, "!loss");
        } else {
            assertGt(profit, 0, "!profit");
            assertEq(loss, 0, "!loss");
        }

        // skip time to unlock any profit we've earned
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // check that we can withdraw our full balance that we just deposited
        uint256 totalVaultDeposits = strategy.valueOfVault();
        uint256 maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            address(strategy)
        );

        // check balance of fluid liquidity proxy (this is where our deposited funds flow)
        // WETH converted to ether on chains where it's native
        uint256 proxyBalance;
        if (
            address(asset) == tokenAddrs["WETH"] &&
            (block.chainid == 1 ||
                block.chainid == 8453 ||
                block.chainid == 42161)
        ) {
            proxyBalance = fluidLiquidityProxy.balance;
        } else {
            proxyBalance = asset.balanceOf(fluidLiquidityProxy);
        }

        assertGe(
            proxyBalance,
            totalVaultDeposits,
            "deposits missing from proxy"
        );

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (totalVaultDeposits > maxRedeemForVault) {
            // as long as user holds strategy shares, we still need to redeem more
            uint256 daysToExpand;
            while (strategy.balanceOf(user) > 0) {
                // our strategy should accurately report how much we can redeem in one go
                uint256 toRedeem = strategy.maxRedeem(user);

                // if we can redeem more than the strategy holds, just redeem what we hold!
                if (toRedeem > strategy.balanceOf(user)) {
                    toRedeem = strategy.balanceOf(user);
                }

                // prank and redeem
                vm.prank(user);
                strategy.redeem(toRedeem, user, user);

                // skip a day for expansion
                skip(1 days);
                daysToExpand += 1;
            }
            console2.log("Number of days to expand:", daysToExpand);
        } else {
            assertGe(
                maxRedeemForVault,
                totalVaultDeposits,
                "can't redeem our full balance"
            );
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        if (noBaseYield) {
            assertGe(
                asset.balanceOf(user) + 2, // up to 2 wei loss for 4626 rounding
                balanceBefore + _amount,
                "!final balance"
            );
        } else {
            assertGe(
                asset.balanceOf(user),
                balanceBefore + _amount,
                "!final balance"
            );
        }
    }

    function test_operation_fixed() public {
        // use ~$1M
        uint256 _amount = 1_000_000 * 10 ** asset.decimals();
        if (address(asset) == tokenAddrs["WETH"]) {
            _amount = 275 * (10 ** asset.decimals());
        }

        // set min amounts to sell
        if (block.chainid == 42161) {
            vm.prank(management);
            strategy.setMinFluidToSell(100e18);
        } else {
            vm.prank(management);
            strategy.setMinAmountToSell(100e18);
        }

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

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log(
            "Profit from basic report:",
            profit / 10 ** asset.decimals(),
            "* token decimals"
        );
        uint256 apr = (profit * 365 * 86400 * 1e18) /
            (_amount * strategy.profitMaxUnlockTime());
        console2.log("Estimated APR percentage (divide by 1e18):", apr);
        console2.log(
            "Estimated APR percentage (whole number):",
            (apr * 100) / 1e18
        );

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // log what our maxRedeem is
        uint256 maxRedeem = strategy.maxRedeem(user);
        console2.log("Max Redeem for user:", maxRedeem);

        // airdrop some FLUID or WPOL to our strategy to simulate the merkle claim and to test selling rewards
        // only do this if we have merkle rewards
        if (extraRewardRate > 0 || manualRewardApr > 0) {
            simulateMerkleClaim();
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profitTwo, uint256 lossTwo) = strategy.report();
        console2.log(
            "Profit from report after merkle claim:",
            profitTwo / 10 ** asset.decimals(),
            "* token decimals"
        );
        apr =
            (profitTwo * 365 * 86400 * 1e18) /
            (_amount * strategy.profitMaxUnlockTime());
        console2.log("Estimated APR percentage (divide by 1e18):", apr);
        console2.log(
            "Estimated APR percentage (whole number):",
            (apr * 100) / 1e18
        );

        // Check return Values
        assertGt(profitTwo, 0, "!profit");
        assertEq(lossTwo, 0, "!loss");

        // our profits should be higher with the merkle claim, assuming we have extra rewards
        if (extraRewardRate > 0 || manualRewardApr > 0) {
            assertGt(profitTwo, profit, "!profitTwo");
        }

        ////

        // switch to using the auction for strategies with merkle rewards on mainnet
        if ((extraRewardRate > 0 || manualRewardApr > 0)) {
            // claim rewards to the strategy
            simulateMerkleClaim();

            // auction time
            vm.startPrank(management);
            vm.expectRevert("!auction");
            strategy.setUseAuction(true);
            strategy.setAuction(address(auction));
            strategy.setUseAuction(true);
            vm.stopPrank();

            // simulate our auction process
            uint256 simulatedProfit = _amount / 200; // 0.5% profit
            simulateAuction(simulatedProfit);

            // Report profit
            vm.prank(keeper);
            (uint256 profitThree, uint256 lossThree) = strategy.report();
            console2.log(
                "Profit from auction report:",
                profitThree / 10 ** asset.decimals(),
                "* token decimals"
            );
            assertGt(profitThree, 0, "!profit");
            assertEq(lossThree, 0, "!loss");

            // simulate merkle claim, manually sell atomically
            assertEq(strategy.balanceOfRewards(), 0, "!rewards");
            simulateMerkleClaim();
            vm.startPrank(management);
            strategy.setUseAuction(false);
            assertEq(strategy.balanceOfAsset(), 0, "!asset");
            assertGt(strategy.balanceOfRewards(), 0, "!rewards");
            uint256 vaultBefore = strategy.balanceOfVault();
            strategy.manualRewardSell();
            uint256 vaultAfter = strategy.balanceOfVault();
            assertEq(strategy.balanceOfRewards(), 0, "!rewards");
            assertEq(strategy.balanceOfAsset(), 0, "!asset");
            assertGt(vaultAfter, vaultBefore, "!vault");
            // also do other setters (uniV3 fees)
            if (block.chainid == 1) {
                strategy.setUniV3Fees(100, 100);
            } else if (block.chainid == 137 || block.chainid == 42161) {
                strategy.setUniV3Fees(100);
            }
            vm.stopPrank();
        }

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // airdrop some asset to the strategy to test our reverts
        airdrop(asset, address(strategy), 1_000e18);
        address vault = strategy.vault();
        vm.startPrank(management);
        vm.expectRevert("cannot kick");
        strategy.kickAuction(address(asset));
        vm.expectRevert("cannot kick");
        strategy.kickAuction(vault);
        vm.stopPrank();

        // hit some more reverts deploying evil auctions
        address rewardToken;
        if (block.chainid == 137) {
            rewardToken = strategy.WPOL();
        } else {
            rewardToken = strategy.FLUID();
        }
        setUpAuction(rewardToken, address(strategy), address(strategy));
        vm.expectRevert("wrong want");
        vm.prank(management);
        strategy.setAuction(address(auction));
        setUpAuction(rewardToken, address(asset), user);
        vm.expectRevert("wrong receiver");
        vm.prank(management);
        strategy.setAuction(address(auction));

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // since our lender is default profitable, doing max 10_000 will revert w/ health check
        //  (more than 100% total profit). so do 9950 to give some buffer for the interest earned.
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, 9_950));

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

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // confirm that our strategy is empty
        assertEq(asset.balanceOf(address(strategy)), 0, "!empty");

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // confirm that we have our airdrop amount in our strategy loose
        assertEq(asset.balanceOf(address(strategy)), toAirdrop, "!airdrop");

        // if we don't have base yield, we will still have profit, but it might lose a few wei compared to the airdrop
        if (_amount > noYieldAmount) {
            noBaseYield = true;
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        if (noBaseYield) {
            assertGe(profit + 2, toAirdrop, "!profit");
            assertEq(loss, 0, "!loss");
        } else {
            assertGe(profit, toAirdrop, "!profit");
            assertEq(loss, 0, "!loss");
        }

        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // check that we can withdraw our full balance that we just deposited
        uint256 totalVaultDeposits = strategy.valueOfVault();
        uint256 maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            address(strategy)
        );

        // check balance of fluid liquidity proxy (this is where our deposited funds flow)
        // WETH converted to ether on chains where it's native
        uint256 proxyBalance;
        if (
            address(asset) == tokenAddrs["WETH"] &&
            (block.chainid == 1 ||
                block.chainid == 8453 ||
                block.chainid == 42161)
        ) {
            proxyBalance = fluidLiquidityProxy.balance;
        } else {
            proxyBalance = asset.balanceOf(fluidLiquidityProxy);
        }

        assertGe(
            proxyBalance,
            totalVaultDeposits,
            "deposits missing from proxy"
        );

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (totalVaultDeposits > maxRedeemForVault) {
            // as long as user holds strategy shares, we still need to redeem more
            uint256 daysToExpand;
            while (strategy.balanceOf(user) > 0) {
                // our strategy should accurately report how much we can redeem in one go
                uint256 toRedeem = strategy.maxRedeem(user);

                // if we can redeem more than the strategy holds, just redeem what we hold!
                if (toRedeem > strategy.balanceOf(user)) {
                    toRedeem = strategy.balanceOf(user);
                }

                // prank and redeem
                vm.prank(user);
                strategy.redeem(toRedeem, user, user);

                // skip a day for expansion
                skip(1 days);
                daysToExpand += 1;
            }
            console2.log("Number of days to expand:", daysToExpand);
        } else {
            assertGe(
                maxRedeemForVault,
                totalVaultDeposits,
                "can't redeem our full balance"
            );
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        if (noBaseYield) {
            assertGe(
                asset.balanceOf(user) + 2, // up to 2 wei loss for 4626 rounding
                balanceBefore + _amount,
                "!final balance"
            );
        } else {
            assertGe(
                asset.balanceOf(user),
                balanceBefore + _amount,
                "!final balance"
            );
        }
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // since our lender is default profitable, doing max 10_000 will revert w/ health check
        //  (more than 100% total profit). so do 9950 to give some buffer for the interest earned.
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, 9_950));

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

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

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // if we don't have base yield, we will still have profit, but it might lose a few wei compared to the airdrop
        if (_amount > noYieldAmount) {
            noBaseYield = true;
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        if (noBaseYield) {
            assertGe(profit + 2, toAirdrop, "!profit");
            assertEq(loss, 0, "!loss");
        } else {
            assertGe(profit, toAirdrop, "!profit");
            assertEq(loss, 0, "!loss");
        }

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // check that we can withdraw our full balance that we just deposited
        uint256 totalVaultDeposits = strategy.valueOfVault();
        uint256 maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            address(strategy)
        );

        // check balance of fluid liquidity proxy (this is where our deposited funds flow)
        // WETH converted to ether on chains where it's native
        uint256 proxyBalance;
        if (
            address(asset) == tokenAddrs["WETH"] &&
            (block.chainid == 1 ||
                block.chainid == 8453 ||
                block.chainid == 42161)
        ) {
            proxyBalance = fluidLiquidityProxy.balance;
        } else {
            proxyBalance = asset.balanceOf(fluidLiquidityProxy);
        }

        assertGe(
            proxyBalance,
            totalVaultDeposits,
            "deposits missing from proxy"
        );

        // pull this out since we use it in two while loops
        uint256 toRedeem;
        uint256 daysToExpand;

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (totalVaultDeposits > maxRedeemForVault) {
            // as long as user holds strategy shares, we still need to redeem more
            while (strategy.balanceOf(user) > 0) {
                // our strategy should accurately report how much we can redeem in one go
                toRedeem = strategy.maxRedeem(user);

                // if we can redeem more than the strategy holds, just redeem what we hold!
                if (toRedeem > strategy.balanceOf(user)) {
                    toRedeem = strategy.balanceOf(user);
                }

                // prank and redeem
                vm.prank(user);
                strategy.redeem(toRedeem, user, user);

                // skip a day for expansion
                skip(1 days);
                daysToExpand += 1;
            }
            console2.log("Number of days to expand:", daysToExpand);
        } else {
            assertGe(
                maxRedeemForVault,
                totalVaultDeposits,
                "can't redeem our full balance"
            );
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        if (noBaseYield) {
            assertGe(
                asset.balanceOf(user) + 2, // up to 2 wei loss for 4626 rounding
                balanceBefore + _amount,
                "!final balance"
            );
        } else {
            assertGe(
                asset.balanceOf(user),
                balanceBefore + _amount,
                "!final balance"
            );
        }

        // check that we are tracking our deposits correctly
        totalVaultDeposits = strategy.valueOfVault();
        daysToExpand = 0;

        // check that we can withdraw our full staked balance that we just deposited
        maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            address(strategy)
        );

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (totalVaultDeposits > maxRedeemForVault) {
            // as long as performanceFeeRecipient holds strategy shares, we still need to redeem more
            while (strategy.balanceOf(performanceFeeRecipient) > 0) {
                // our strategy should accurately report how much we can redeem in one go
                toRedeem = strategy.maxRedeem(performanceFeeRecipient);

                // if we can redeem more than the strategy holds, just redeem what we hold!
                if (toRedeem > strategy.balanceOf(performanceFeeRecipient)) {
                    toRedeem = strategy.balanceOf(performanceFeeRecipient);
                }

                // prank and redeem
                vm.prank(performanceFeeRecipient);
                strategy.redeem(
                    toRedeem,
                    performanceFeeRecipient,
                    performanceFeeRecipient
                );

                // skip a day for expansion
                skip(1 days);
                daysToExpand += 1;
            }
            console2.log("Number of days to expand:", daysToExpand);
        } else {
            assertGe(
                maxRedeemForVault,
                totalVaultDeposits,
                "can't redeem our full balance"
            );
            // Withdraw all funds
            vm.prank(performanceFeeRecipient);
            strategy.redeem(
                expectedShares,
                performanceFeeRecipient,
                performanceFeeRecipient
            );
        }

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

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

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // turn off health check if no yield since we may lose 1-2 wei from rounding
        if (_amount > noYieldAmount) {
            noBaseYield = true;
        }
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // check that we can withdraw our full balance that we just deposited
        uint256 totalVaultDeposits = strategy.valueOfVault();
        uint256 maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            address(strategy)
        );

        // check balance of fluid liquidity proxy (this is where our deposited funds flow)
        // WETH converted to ether on chains where it's native
        uint256 proxyBalance;
        if (
            address(asset) == tokenAddrs["WETH"] &&
            (block.chainid == 1 ||
                block.chainid == 8453 ||
                block.chainid == 42161)
        ) {
            proxyBalance = fluidLiquidityProxy.balance;
        } else {
            proxyBalance = asset.balanceOf(fluidLiquidityProxy);
        }

        assertGe(
            proxyBalance,
            totalVaultDeposits,
            "deposits missing from proxy"
        );

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (totalVaultDeposits > maxRedeemForVault) {
            // as long as user holds strategy shares, we still need to redeem more
            uint256 daysToExpand;
            while (strategy.balanceOf(user) > 0) {
                // our strategy should accurately report how much we can redeem in one go
                uint256 toRedeem = strategy.maxRedeem(user);

                // if we can redeem more than the strategy holds, just redeem what we hold!
                if (toRedeem > strategy.balanceOf(user)) {
                    toRedeem = strategy.balanceOf(user);
                }

                // prank and redeem
                vm.prank(user);
                strategy.redeem(toRedeem, user, user);

                // skip a day for expansion
                skip(1 days);
                daysToExpand += 1;
            }
            console2.log("Number of days to expand:", daysToExpand);
        } else {
            assertGe(
                maxRedeemForVault,
                totalVaultDeposits,
                "can't redeem our full balance"
            );
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }
}
