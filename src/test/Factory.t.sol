// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "src/test/utils/Setup.sol";

contract FactoryTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    // no need for explicit factory deployment testing since we use the factory to deploy strategies in Setup.sol
    function test_factory_status() public {
        // confirm our mapping works
        assertEq(
            strategyFactory.deployments(strategy.asset()),
            address(strategy)
        );
        assertEq(true, strategyFactory.isDeployedStrategy(address(strategy)));
        assertEq(false, strategyFactory.isDeployedStrategy(user));

        if (block.chainid == 1) {
            // shouldn't be able to deploy another strategy for the same gauge for curve factory
            vm.expectRevert("strategy exists");
            vm.prank(management);
            strategyFactory.newFluidLender(
                address(asset),
                "Fluid Lender",
                fluidVault,
                500
            );

            // make sure user can't deploy
            vm.expectRevert("!management");
            vm.prank(user);
            strategyFactory.newFluidLender(
                address(asset),
                "Fluid Lender",
                fluidVault,
                500
            );
        } else {
            // shouldn't be able to deploy another strategy for the same gauge for curve factory
            vm.expectRevert("strategy exists");
            vm.prank(management);
            strategyFactory.newFluidLender(
                address(asset),
                "Fluid Lender",
                fluidVault
            );

            // make sure user can't deploy
            vm.expectRevert("!management");
            vm.prank(user);
            strategyFactory.newFluidLender(
                address(asset),
                "Fluid Lender",
                fluidVault
            );
        }

        // now set operator address
        vm.prank(user);
        vm.expectRevert("!management");
        strategyFactory.setAddresses(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );
        vm.startPrank(management);
        vm.expectRevert("ZERO_ADDRESS");
        strategyFactory.setAddresses(
            address(0),
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );
        vm.expectRevert("ZERO_ADDRESS");
        strategyFactory.setAddresses(
            management,
            address(0),
            keeper,
            emergencyAdmin
        );
        vm.expectRevert("ZERO_ADDRESS");
        strategyFactory.setAddresses(
            management,
            performanceFeeRecipient,
            keeper,
            address(0)
        );
        strategyFactory.setAddresses(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );
        vm.stopPrank();

        assertEq(strategy.management(), management);
        assertEq(strategy.pendingManagement(), address(0));
        assertEq(strategy.performanceFee(), 1000);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
    }
}
