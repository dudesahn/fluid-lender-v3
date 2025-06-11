// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {IMerkleRewards} from "src/interfaces/FluidInterfaces.sol";

contract FluidLenderPolygon is Base4626Compounder, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    /// @notice Address for our reward token auction
    address public auction;

    IMerkleRewards public constant MERKLE_CLAIM =
        IMerkleRewards(0xF90D6eA5d0B4CAD69530543CA00eE6cab94B09f4);

    /// @notice WPOL token address
    ERC20 public constant WPOL =
        ERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    /**
     * @dev Vault must match lp_token() for the staking pool.
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy.
     * @param _vault ERC4626 vault token to use.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault
    ) Base4626Compounder(_asset, _name, _vault) {
        WPOL.forceApprove(router, type(uint256).max);

        // Set the min amount for the swapper to sell
        // 0.05% pool for both USDC and USDT
        _setUniFees(address(WPOL), address(asset), 500); // UniV3 fees in 1/100 of bps
        minAmountToSell = 1000e18; // 1000 POL = 200 USD
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Manually sell any accumulated rewards above minAmountToSell.
    function manualRewardSell() external onlyKeepers {
        _claimAndSellRewards();
    }

    /**
     * @notice Claim rewards from the merkle distributor
     * @dev Can only be called by management. All values should be pulled from Fluid's API.
     * @param _recipient Recipient of rewards, must be msg.sender.
     * @param _cumulativeAmount Total amount of rewards to claim.
     * @param _positionType Type that our Fluid position is (lending, vault, etc).
     * @param _positionId ID of our strategy's position.
     * @param _cycle Current rewards cycle.
     * @param _merkleProof Merkle proof data.
     * @param _metadata Any extra metadata for the claim. Must match exactly from API.
     */
    function claimRewards(
        address _recipient,
        uint256 _cumulativeAmount,
        uint8 _positionType,
        bytes32 _positionId,
        uint256 _cycle,
        bytes32[] calldata _merkleProof,
        bytes memory _metadata
    ) external onlyManagement {
        MERKLE_CLAIM.claim(
            _recipient,
            _cumulativeAmount,
            _positionType,
            _positionId,
            _cycle,
            _merkleProof,
            _metadata
        );
    }

    function _claimAndSellRewards() internal override {
        // do UniV3 selling here of WPOL to underlying
        uint256 balance = WPOL.balanceOf(address(this));
        if (balance > minAmountToSell) {
            _swapFrom(address(WPOL), address(asset), balance, 0);
        }
    }

    /**
     * @dev Kick an auction for a given token.
     * @param _token The token that is being sold.
     */
    function kickAuction(
        address _token
    ) external onlyKeepers returns (uint256) {
        return _kickAuction(_token);
    }

    function _kickAuction(address _from) internal virtual returns (uint256) {
        require(
            _from != address(asset) && _from != address(vault),
            "cannot kick"
        );
        uint256 _balance = ERC20(_from).balanceOf(address(this));
        ERC20(_from).safeTransfer(auction, _balance);
        return IAuction(auction).kick(_from);
    }

    /* ========== SETTERS ========== */

    /**
     * @notice Use to update our auction address.
     * @dev Can only be called by management.
     * @param _auction Address of new auction.
     */
    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            require(IAuction(_auction).want() == address(asset), "wrong want");
            require(
                IAuction(_auction).receiver() == address(this),
                "wrong receiver"
            );
        }
        auction = _auction;
    }

    /**
     * @notice Set fees for Uniswap V3
     * @dev Can only be called by management.
     * @param _polToAsset UniV3 swap fee for WPOL => asset
     */
    function setUniFees(uint24 _polToAsset) external onlyManagement {
        _setUniFees(address(WPOL), address(asset), _polToAsset);
    }

    /**
     * @notice Set the minimum amount of WPOL to sell
     * @dev Can only be called by management.
     * @param _minAmountToSell minimum amount to sell in wei
     */
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }
}
