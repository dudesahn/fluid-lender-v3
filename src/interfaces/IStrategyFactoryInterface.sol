// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IStrategyFactoryInterface {
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

    function management() external view returns (address);

    function performanceFeeRecipient() external view returns (address);

    function keeper() external view returns (address);
}
