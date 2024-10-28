// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";

import {IStaking} from "./interfaces/FluidInterfaces.sol";

contract StrategyFluidLender is Base4626Compounder, TradeFactorySwapper {
    using SafeERC20 for ERC20;

    IStaking public immutable staking; // address of the Fluid staking contract

    /**
     * @dev Vault must match lp_token() for the staking pool.
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy.
     * @param _vault ERC4626 vault token to use.
     * @param _staking Staking pool to use.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _staking
    ) Base4626Compounder(_asset, _name, _vault) {
        staking = IStaking(_staking);
        require(_vault == staking.stakingToken(), "token mismatch");

        ERC20(_vault).forceApprove(_staking, type(uint256).max);
    }

    /* ========== BASE4626 FUNCTIONS ========== */

    /**
     * @notice Balance of vault tokens staked in the staking contract
     */
    function balanceOfStake() public view override returns (uint256) {
        return staking.balanceOf(address(this));
    }

    function _stake() internal override {
        // deposit any loose vault tokens to the staking contract
        staking.stake(balanceOfVault());
    }

    function _unStake(uint256 _amount) internal override {
        // _amount is already in vault shares, no need to convert
        staking.withdraw(_amount);
    }

    function vaultsMaxWithdraw() public view override returns (uint256) {
        // we don't need to consider loose asset here since availableWithdrawLimit() includes that
        return
            Math.min(
                valueOfVault(),
                vault.convertToAssets(vault.maxRedeem(address(staking)))
            );
    }

    function _claimAndSellRewards() internal override {
        _claimRewards();
    }

    /* ========== TRADE FACTORY FUNCTIONS ========== */

    function claimRewards() external override onlyManagement {
        _claimRewards();
    }

    function _claimRewards() internal override {
        staking.getReward();
    }

    /**
     * @notice Use to add tokens to our rewardTokens array. Also enables token on trade factory if one is set.
     * @dev Can only be called by management.
     * @param _token Address of token to add.
     */
    function addToken(address _token) external onlyManagement {
        require(
            _token != address(asset) && _token != address(vault),
            "!allowed"
        );
        _addToken(_token, address(asset));
    }

    /**
     * @notice Use to remove tokens from our rewardTokens array. Also disables token on trade factory.
     * @dev Can only be called by management.
     * @param _token Address of token to remove.
     */
    function removeToken(address _token) external onlyManagement {
        _removeToken(_token, address(asset));
    }

    /**
     * @notice Use to update our trade factory.
     * @dev Can only be called by management.
     * @param _tradeFactory Address of new trade factory.
     */
    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, address(asset));
    }
}
