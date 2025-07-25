// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {FluidStructs} from "src/libraries/FluidStructs.sol";

interface IMerkleRewards {
    function claim(
        address recipient_,
        uint256 cumulativeAmount_,
        uint8 positionType_,
        bytes32 positionId_,
        uint256 cycle_,
        bytes32[] calldata merkleProof_,
        bytes memory metadata_
    ) external;
}

interface ILendingResolver {
    function getFTokenDetails(
        address fToken_
    ) external view returns (FluidStructs.FTokenDetails memory fTokenDetails_);
}

interface ILiquidtyResolver {
    function getOverallTokenData(
        address token_
    )
        external
        view
        returns (FluidStructs.OverallTokenData memory overallTokenData_);
}

interface IDexResolver {
    function getDexVariablesRaw(address dex_) external view returns (uint256);
}

interface IFluidDex {
    function swapIn(
        bool swap0to1_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        address to_
    ) external returns (uint256);
}
