// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IStrategyFactoryInterface {
    function management() external view returns (address);

    function performanceFeeRecipient() external view returns (address);

    function keeper() external view returns (address);

    function emergencyAdmin() external view returns (address);

    function deployments(address) external view returns (address);

    function isDeployedStrategy(address) external view returns (bool);

    function newFluidLender(
        address _asset,
        string memory _name,
        address _vault,
        uint24 _feeBaseToAsset
    ) external returns (address);

    function newFluidLender(
        address _asset,
        string memory _name,
        address _vault
    ) external returns (address);

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) external;
}
