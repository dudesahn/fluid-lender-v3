pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
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

    function test_emergencyWithdraw_maxUint(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // should be able to pass uint 256 max and not revert.
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // Make sure we can still withdraw the full amount
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

    // TODO: Add tests for any emergency function added.
}
