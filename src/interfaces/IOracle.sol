// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

interface IOracle {
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256);

    // native APR from borrows
    function getSupplyRate(
        address _strategy,
        int256 _delta
    ) external view returns (uint256);

    // L2, in-kind rewards only
    function getRewardRate(
        address _strategy,
        int256 _delta
    ) external view returns (uint256);

    // mainnet and polygon
    function getRewardRates(
        address _strategy,
        int256 _delta
    ) external view returns (uint256, uint256); // in-kind, POL/FLUID

    // check reported FLUID price on mainnet or L2s
    function getFluidPriceUsdc() external view returns (uint256);

    // pol price on polygon
    function getPolPriceUsdc() external view returns (uint256);

    function setUseManualRewardsApr(bool _useManualRewardsApr) external;

    function setRewardsRate(
        address _market,
        uint256 _rewardTokensPerSecond
    ) external;

    function setManualRewardsApr(
        address _market,
        uint256 _manualRewardsApr
    ) external;
}
