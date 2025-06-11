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
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // skip time to unlock any profit we've earned
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // check that we are tracking our deposits correctly
        uint256 stakedBalance = strategy.balanceOfStake();
        uint256 strategyVaultBalance = strategy.balanceOfVault() +
            stakedBalance;
        assertEq(strategyVaultBalance, stakedBalance, "!staked");

        // check that we can withdraw our full staked balance that we just deposited
        uint256 maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            fluidStaking
        );
        // check balance of fluid liquidity proxy (this is where our deposited funds flow)
        uint256 proxyBalance = asset.balanceOf(
            0x52Aa899454998Be5b000Ad077a46Bbe360F4e497
        );

        assertGe(proxyBalance, stakedBalance, "deposits missing from proxy");

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (stakedBalance > maxRedeemForVault) {
            // as long as user holds strategy shares, we still need to redeem more
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
            }
        } else {
            assertGe(
                maxRedeemForVault,
                stakedBalance,
                "can't redeem our staked balance"
            );
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_operation_fixed() public {
        uint256 _amount = 1_000_000 * 10 ** asset.decimals();

        // Deposit into strategy
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
        uint256 apr = (100 * profit * 365 * 86400) /
            (_amount * strategy.profitMaxUnlockTime());
        console2.log("Estimated APR whole percentage:", apr);

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

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
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // confirm that our strategy is empty
        assertEq(asset.balanceOf(address(strategy)), 0, "!empty");

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // confirm that we have our airdrop amount in our strategy loose
        assertEq(asset.balanceOf(address(strategy)), toAirdrop, "!airdrop");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // check that we are tracking our deposits correctly
        uint256 stakedBalance = strategy.balanceOfStake();
        uint256 strategyVaultBalance = strategy.balanceOfVault() +
            stakedBalance;
        assertEq(strategyVaultBalance, stakedBalance, "!staked");

        // check that we can withdraw our full staked balance that we just deposited
        uint256 maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            fluidStaking
        );
        // check balance of fluid liquidity proxy (this is where our deposited funds flow)
        uint256 proxyBalance = asset.balanceOf(
            0x52Aa899454998Be5b000Ad077a46Bbe360F4e497
        );

        assertGe(proxyBalance, stakedBalance, "deposits missing from proxy");

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (stakedBalance > maxRedeemForVault) {
            // as long as user holds strategy shares, we still need to redeem more
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
            }
        } else {
            assertGe(
                maxRedeemForVault,
                stakedBalance,
                "can't redeem our staked balance"
            );
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
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
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // check that we are tracking our deposits correctly
        uint256 stakedBalance = strategy.balanceOfStake();
        uint256 strategyVaultBalance = strategy.balanceOfVault() +
            stakedBalance;
        assertEq(strategyVaultBalance, stakedBalance, "!staked");

        // check that we can withdraw our full staked balance that we just deposited
        uint256 maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            fluidStaking
        );
        // check balance of fluid liquidity proxy (this is where our deposited funds flow)
        uint256 proxyBalance = asset.balanceOf(
            0x52Aa899454998Be5b000Ad077a46Bbe360F4e497
        );

        assertGe(proxyBalance, stakedBalance, "deposits missing from proxy");

        // pull this out since we use it in two while loops
        uint256 toRedeem;

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (stakedBalance > maxRedeemForVault) {
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
            }
        } else {
            assertGe(
                maxRedeemForVault,
                stakedBalance,
                "can't redeem our staked balance"
            );
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        // check that we are tracking our deposits correctly
        stakedBalance = strategy.balanceOfStake();

        // check that we can withdraw our full staked balance that we just deposited
        maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            fluidStaking
        );

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (stakedBalance > maxRedeemForVault) {
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
            }
        } else {
            assertGe(
                maxRedeemForVault,
                stakedBalance,
                "can't redeem our staked balance"
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
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // check that we are tracking our deposits correctly
        uint256 stakedBalance = strategy.balanceOfStake();
        uint256 strategyVaultBalance = strategy.balanceOfVault() +
            stakedBalance;
        assertEq(strategyVaultBalance, stakedBalance, "!staked");

        // check that we can withdraw our full staked balance that we just deposited
        uint256 maxRedeemForVault = IStrategyInterface(fluidVault).maxRedeem(
            fluidStaking
        );
        // check balance of fluid liquidity proxy (this is where our deposited funds flow)
        uint256 proxyBalance = asset.balanceOf(
            0x52Aa899454998Be5b000Ad077a46Bbe360F4e497
        );

        assertGe(proxyBalance, stakedBalance, "deposits missing from proxy");

        // realistically here we need to loop through withdrawing more and waiting for expansion of withdrawable amount
        if (stakedBalance > maxRedeemForVault) {
            // as long as user holds strategy shares, we still need to redeem more
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
            }
        } else {
            assertGe(
                maxRedeemForVault,
                stakedBalance,
                "can't redeem our staked balance"
            );
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }
}
