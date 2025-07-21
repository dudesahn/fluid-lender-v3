// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

interface IChainlinkCalcs {
    // yearn's chainlink helper
    function getPriceUsdc(address) external view returns (uint256);
}
