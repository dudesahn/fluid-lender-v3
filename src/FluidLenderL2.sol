// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {IMerkleRewards} from "src/interfaces/FluidInterfaces.sol";

contract FluidLenderL2 is Base4626Compounder {
    using SafeERC20 for ERC20;

    /// @notice Address for our reward token auction
    address public auction;

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
    ) Base4626Compounder(_asset, _name, _vault) {}

    /* ========== MUTATIVE FUNCTIONS ========== */

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
}
