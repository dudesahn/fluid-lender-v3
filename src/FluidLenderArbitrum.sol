// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {IMerkleRewards} from "src/interfaces/FluidInterfaces.sol";
import {IFluidDex} from "src/interfaces/FluidInterfaces.sol";

contract FluidLenderArbitrum is UniswapV3Swapper, Base4626Compounder {
    using SafeERC20 for ERC20;

    /// @notice Address for our reward token auction
    address public auction;

    /// @notice Whether to sell rewards using auction or Uniswap V3
    bool public useAuction;

    /// @notice True if strategy deposits are open to any address
    bool public openDeposits;

    /// @notice Mapping of addresses and whether they are allowed to deposit to this strategy
    mapping(address => bool) public allowed;

    /// @notice Address for Fluid's FLUID-WETH DEX pair
    IFluidDex public constant FLUID_DEX =
        IFluidDex(0x2886a01a0645390872a9eb99dAe1283664b0c524);

    /// @notice Address for Fluid's merkle claim
    /// @dev This is the same on Base and Arbitrum
    IMerkleRewards public constant MERKLE_CLAIM =
        IMerkleRewards(0x94312a608246Cecfce6811Db84B3Ef4B2619054E);

    /// @notice FLUID token address
    /// @dev This is the same on Base and Arbitrum
    ERC20 public constant FLUID =
        ERC20(0x61E030A56D33e8260FdD81f03B162A79Fe3449Cd);

    /**
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy.
     * @param _vault ERC4626 vault token to use.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault // address _fluidDex
    ) Base4626Compounder(_asset, _name, _vault) {
        // update for WETH address on arbitrum. UniV3 router is same address as mainnet.
        base = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

        FLUID.forceApprove(address(FLUID_DEX), type(uint256).max);
        ERC20(base).forceApprove(router, type(uint256).max);

        // Set the min amount for the swapper to sell, 0.05% for both USDC and USDT-WETH pools
        _setUniFees(base, address(asset), 500); // UniV3 fees in 1/100 of bps
        minAmountToSell = 100e18; // 100 FLUID = 600 USD
    }

    /* ========== VIEW FUNCTIONS ========== */

    function availableDepositLimit(
        address _receiver
    ) public view override returns (uint256) {
        if (openDeposits || allowed[_receiver]) {
            // Return the max amount the vault will allow for deposits.
            return vault.maxDeposit(address(this));
        } else {
            return 0;
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Manually sell any accumulated rewards above minAmountToSell.
    function manualRewardSell() external onlyKeepers {
        _claimAndSellRewards();
    }

    /**
     * @notice Claim rewards from the merkle distributor
     * @dev All values should be pulled from Fluid's API.
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
    ) external {
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
        // use Fluid DEX and UniV3 to sell FLUID to underlying
        uint256 balance = FLUID.balanceOf(address(this));
        if (balance > minAmountToSell && !useAuction) {
            _sellFluidToWeth(balance);
            balance = ERC20(base).balanceOf(address(this));
            _swapFrom(base, address(asset), balance, 0);
        }
    }

    function _sellFluidToWeth(uint256 _fluidToSell) internal {
        FLUID_DEX.swapIn(true, _fluidToSell, 0, address(this));
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
     * @notice Set the minimum amount of rewardsToken to sell.
     * @dev Can only be called by management.
     * @param _minAmountToSell minimum amount to sell in wei.
     */
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /**
     * @notice Set fees for UniswapV3 to sell WETH to asset.
     * @dev Can only be called by management.
     * @param _baseToAsset Fee for selling base to asset
     */
    function setUniV3Fees(uint24 _baseToAsset) external onlyManagement {
        _setUniFees(base, address(asset), _baseToAsset);
    }

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
     * @notice Set whether to use auction or UniV3 for rewards selling.
     * @dev Can only be called by management.
     * @param _useAuction Use auction to sell rewards (true) or UniV3 (false).
     */
    function setUseAuction(bool _useAuction) external onlyManagement {
        if (_useAuction) require(auction != address(0), "!auction");
        useAuction = _useAuction;
    }

    /**
     * @notice Set whether deposits are open to anyone or restricted to our allowed mapping.
     * @dev Can only be called by management.
     * @param _openDeposits Allow deposits from anyone (true) or use mapping (false).
     */
    function setOpenDeposits(bool _openDeposits) external onlyManagement {
        openDeposits = _openDeposits;
    }

    /**
     * @notice Set whether an address can deposit to the strategy or not.
     * @dev Can only be called by management.
     * @param _depositor Address to set mapping for.
     * @param _allowed Whether the address is allowed to deposit to the strategy.
     */
    function setAllowed(
        address _depositor,
        bool _allowed
    ) external onlyManagement {
        allowed[_depositor] = _allowed;
    }
}
