// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";
import {FluidLenderPolygon} from "src/FluidLenderPolygon.sol";

contract FluidLenderFactoryPolygon {
    /// @notice Management role controls important setters on this factory and deployed strategies
    address public management;

    /// @notice Address authorized for emergency procedures (shutdown and withdraw) on strategy
    address public emergencyAdmin;

    /// @notice Keeper address is allowed to report and tend deployed strategies
    address public keeper;

    /// @notice This address receives any performance fees
    address public performanceFeeRecipient;

    /// @notice Track the deployments. asset => strategy
    mapping(address asset => address strategy) public deployments;

    event NewFluidLender(address indexed strategy, address indexed asset);
    event AddressesSet(
        address indexed management,
        address indexed emergencyAdmin,
        address indexed keeper,
        address performanceFeeRecipient
    );

    constructor(
        address _management,
        address _emergencyAdmin,
        address _keeper,
        address _performanceFeeRecipient
    ) {
        require(
            _performanceFeeRecipient != address(0) &&
                _management != address(0) &&
                _emergencyAdmin != address(0),
            "ZERO_ADDRESS"
        );
        management = _management;
        emergencyAdmin = _emergencyAdmin;
        performanceFeeRecipient = _performanceFeeRecipient;
        //slither-disable-next-line missing-zero-check
        keeper = _keeper;
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
        IBase4626Compounder newStrategy = IBase4626Compounder(
            address(new FluidLenderPolygon(_asset, _name, _vault))
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
        try IBase4626Compounder(_strategy).asset() returns (address _asset) {
            return deployments[_asset] == _strategy;
        } catch {
            // If the call fails or reverts, return false
            return false;
        }
    }

    /**
     * @notice Set important addresses for this factory.
     * @dev Management and emergency admin control setters and emergency procedures for strategies.
     * @param _management The address to set as the management address.
     * @param _emergencyAdmin The address to set as the emergency admin.
     * @param _performanceFeeRecipient The address to set as the performance fee recipient address.
     * @param _keeper The address to set as the keeper address.
     */
    function setAddresses(
        address _management,
        address _emergencyAdmin,
        address _keeper,
        address _performanceFeeRecipient
    ) external onlyManagement {
        require(
            _performanceFeeRecipient != address(0) &&
                _management != address(0) &&
                _emergencyAdmin != address(0),
            "ZERO_ADDRESS"
        );
        management = _management;
        emergencyAdmin = _emergencyAdmin;
        performanceFeeRecipient = _performanceFeeRecipient;
        //slither-disable-next-line missing-zero-check
        keeper = _keeper;

        emit AddressesSet(
            _management,
            _emergencyAdmin,
            _keeper,
            _performanceFeeRecipient
        );
    }
}
