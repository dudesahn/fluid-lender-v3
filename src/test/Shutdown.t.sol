pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdown_can_withdraw(uint256 _amount) public {
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

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
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

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_shutdown_emergency_withdraw_max_uint(uint256 _amount) public {
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

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // should be able to pass uint 256 max and not revert.
        // a strategy must be shutdown in order to emergency withdraw
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // Make sure we can still withdraw the full amount
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

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_shutdown_max_util_after_deposit() public {
        // Deposit into strategy
        uint256 _amount = 100_000 * 10 ** asset.decimals();
        mintAndDepositIntoStrategy(strategy, user, _amount);
        bool isMaxUtil = causeMaxUtil(_amount);
        if (!isMaxUtil) {
            console2.log("Skip test, not max util for this market");
            return;
        }

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // assets shouldn't have gone anywhere
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // balance of assets should be zero in strategy still
        assertEq(strategy.balanceOfAsset(), 0, "!assets");

        // value of vault should be positive
        uint256 valueOfVault = strategy.valueOfVault();
        assertGt(valueOfVault, 0, "!value");
        console2.log("Value of vault tokens:", valueOfVault);

        // management steps in to get funds out ASAP
        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        // balance of assets should be greater than zero now
        uint256 balanceOfAssets = strategy.balanceOfAsset();
        console2.log("Balance of loose assets:", balanceOfAssets);
        console2.log(
            "Balance of loose vault token:",
            strategy.balanceOfVault()
        );
        console2.log(
            "Balance of staked vault tokens:",
            strategy.balanceOfStake()
        );

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            if (userToWithdraw > 0) {
                vm.prank(user);
                strategy.withdraw(userToWithdraw, user, user);
            }

            // there will likely be some amount to withdraw since we don't yoink all loose liquidity in Fluid

            // check and make sure that our user still holds some amount of strategy tokens
            // add extra multiplier by 1e18 to add precision
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / (1e18 * 10 ** asset.decimals());
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                (1e18 * 10 ** asset.decimals());
            // these should be equal, but give 100 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 100);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            assertEq(strategy.totalAssets(), 0, "!zero");

            if (noBaseYield) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
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
    }

    // this one shouldn't be much different than normal
    function test_shutdown_max_util_before_deposit() public {
        // Deposit into strategy
        uint256 _amount = 100_000 * 10 ** asset.decimals();
        bool isMaxUtil = causeMaxUtil(_amount);
        if (!isMaxUtil) {
            console2.log("Skip test, not max util for this market");
            return;
        }
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // assets shouldn't have gone anywhere
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // balance of assets should be zero in strategy still
        assertEq(strategy.balanceOfAsset(), 0, "!assets");

        // value of vault should be positive
        uint256 valueOfVault = strategy.valueOfVault();
        assertGt(valueOfVault, 0, "!value");
        console2.log("Value of vault tokens:", valueOfVault);

        // management steps in to get funds out ASAP
        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        // balance of assets should be greater than zero now
        uint256 balanceOfAssets = strategy.balanceOfAsset();
        console2.log("Balance of loose assets:", balanceOfAssets);
        console2.log(
            "Balance of loose vault token:",
            strategy.balanceOfVault()
        );
        console2.log(
            "Balance of staked vault tokens:",
            strategy.balanceOfStake()
        );

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            if (userToWithdraw > 0) {
                vm.prank(user);
                strategy.withdraw(userToWithdraw, user, user);
            }

            // there will likely be some amount to withdraw since we don't yoink all loose liquidity in Fluid

            // check and make sure that our user still holds some amount of strategy tokens
            // add extra multiplier by 1e18 to add precision
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / (1e18 * 10 ** asset.decimals());
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                (1e18 * 10 ** asset.decimals());
            // these should be equal, but give 100 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 100);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            assertEq(strategy.totalAssets(), 0, "!zero");

            if (noBaseYield) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
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
    }

    // TODO: Add tests for any emergency function added.
}
