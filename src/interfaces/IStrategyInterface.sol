// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";
import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";

interface IStrategyInterface is IBase4626Compounder, IUniswapV3Swapper {
    /**
     * @notice Claim rewards from the merkle distributor
     * @dev Can only be called by management. All values should be pulled from Fluid's API.
     * @param recipient_ Recipient of rewards, must be msg.sender.
     * @param cumulativeAmount_ Total amount of rewards to claim.
     * @param positionType_ Type that our Fluid position is (lending, vault, etc).
     * @param positionId_ ID of our strategy's position.
     * @param cycle_ Current rewards cycle.
     * @param merkleProof_ Merkle proof data.
     * @param metadata_ Any extra metadata for the claim. Must match exactly from API.
     */
    function claim(
        address recipient_,
        uint256 cumulativeAmount_,
        uint8 positionType_,
        bytes32 positionId_,
        uint256 cycle_,
        bytes32[] calldata merkleProof_,
        bytes memory metadata_
    ) external;

    /**
     * @dev Kick an auction for a given token.
     * @param _token The token that is being sold.
     */
    function kickAuction(address _token) external returns (uint256);

    /**
     * @notice Set fees for Uniswap V3
     * @dev Can only be called by management.
     * @param _polToAsset UniV3 swap fee for WPOL => asset
     */
    function setUniV3Fees(uint24 _polToAsset) external;

    /**
     * @notice Set fees for Uniswap V3
     * @dev Can only be called by management.
     * @param _fluidToBase UniV3 swap fee for FLUID => base (WETH)
     * @param _baseToAsset UniV3 swap fee for base => asset
     */
    function setUniV3Fees(uint24 _fluidToBase, uint24 _baseToAsset) external;

    /**
     * @notice Use to update our auction address.
     * @dev Can only be called by management.
     * @param _auction Address of new auction.
     */
    function setAuction(address _auction) external;

    /**
     * @notice Set the minimum amount of reward token to sell
     * @dev Can only be called by management.
     * @param _minAmountToSell minimum amount to sell in wei
     */
    function setMinFluidToSell(uint256 _minAmountToSell) external;

    /**
     * @notice Set the minimum amount of reward token to sell
     * @dev Can only be called by management.
     * @param _minAmountToSell minimum amount to sell in wei
     */
    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function allowed(address _depositor) external view returns (bool);

    function setOpenDeposits(bool _openDeposits) external;

    function setAllowed(address _depositor, bool _allowed) external;

    function balanceOfRewards() external view returns (uint256);

    function FLUID() external view returns (address);

    function WPOL() external view returns (address);

    function auction() external view returns (address);

    function claimRewards() external;

    function minAmountToSell() external view returns (uint256);

    function minFluidToSell() external view returns (uint256);

    function openDeposits() external view returns (bool);

    function setUseAuction(bool _useAuction) external;

    function manualRewardSell() external;
}
