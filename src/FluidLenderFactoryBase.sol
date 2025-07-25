// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {FluidLenderBase} from "src/FluidLenderBase.sol";
import {IStrategyInterface} from "src/interfaces/IStrategyInterface.sol";

contract FluidLenderFactoryBase {
    event NewFluidLender(address indexed strategy, address indexed asset);

    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public emergencyAdmin;

    /// @notice Track the deployments. asset => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        require(
            _performanceFeeRecipient != address(0) &&
                _management != address(0) &&
                _emergencyAdmin != address(0),
            "ZERO_ADDRESS"
        );
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        //slither-disable-next-line missing-zero-check
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    modifier onlyManagement() {
        require(msg.sender == management, "!management");
        _;
    }

    /**
     * @notice Deploy a new Fluid Lender Strategy.
     * @dev This will set the msg.sender to all of the permissioned roles. Can only be called by management.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @return . The address of the new lender.
     */
    function newFluidLender(
        address _asset,
        string memory _name,
        address _vault
    ) external onlyManagement returns (address) {
        // slither-disable-start reentrancy-no-eth,reentrancy-events
        // make sure we don't already have a strategy deployed for the asset
        require(deployments[_asset] == address(0), "strategy exists");

        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new FluidLenderBase(_asset, _name, _vault))
        );
        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewFluidLender(address(newStrategy), _asset);

        deployments[_asset] = address(newStrategy);

        return address(newStrategy);
        // slither-disable-end reentrancy-no-eth,reentrancy-events
    }

    /**
     * @notice Check if a strategy has been deployed by this Factory
     * @param _strategy strategy address
     */
    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        try IStrategyInterface(_strategy).asset() returns (address _asset) {
            return deployments[_asset] == _strategy;
        } catch {
            // If the call fails or reverts, return false
            return false;
        }
    }

    /**
     * @notice Set important addresses for this factory.
     * @dev
     * @param _management The address to set as the management address.
     * @param _performanceFeeRecipient The address to set as the performance fee recipient address.
     * @param _keeper The address to set as the keeper address.
     */
    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) external onlyManagement {
        require(
            _performanceFeeRecipient != address(0) &&
                _management != address(0) &&
                _emergencyAdmin != address(0),
            "ZERO_ADDRESS"
        );
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        //slither-disable-next-line missing-zero-check
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }
}
