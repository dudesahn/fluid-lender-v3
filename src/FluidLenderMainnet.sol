// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {IMerkleRewards} from "src/interfaces/FluidInterfaces.sol";

contract FluidLenderMainnet is UniswapV3Swapper, Base4626Compounder {
    using SafeERC20 for ERC20;

    /// @notice Address for our reward token auction
    address public auction;

    /// @notice Whether to sell rewards using auction or Uniswap V3
    bool public useAuction;

    /// @notice True if strategy deposits are open to any address
    bool public openDeposits;

    /// @notice Mapping of addresses and whether they are allowed to deposit to this strategy
    mapping(address => bool) public allowed;

    /// @notice Fluid rewards merkle claim contract
    IMerkleRewards public constant MERKLE_CLAIM =
        IMerkleRewards(0x7060FE0Dd3E31be01EFAc6B28C8D38018fD163B0);

    /// @notice FLUID token address
    ERC20 public constant FLUID =
        ERC20(0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb);

    /**
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy.
     * @param _vault ERC4626 vault token to use.
     * @param _feeBaseToAsset Fee for UniV3 pool of WETH <> asset. Use 0 if asset is WETH.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault,
        uint24 _feeBaseToAsset
    ) Base4626Compounder(_asset, _name, _vault) {
        FLUID.forceApprove(router, type(uint256).max);

        // Set the min amount for the swapper to sell
        // 0.3% pool better execution at relatively small size than deeper 1% pool
        _setUniFees(address(FLUID), base, 3000); // UniV3 fees in 1/100 of bps
        if (address(asset) != base) {
            require(_feeBaseToAsset > 0, "!fee");
            _setUniFees(base, address(asset), _feeBaseToAsset);
        }
        minAmountToSell = 100e18; // 100 FLUID = 400 USD
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
        // do UniV3 selling here of FLUID to underlying
        uint256 balance = FLUID.balanceOf(address(this));
        if (balance > minAmountToSell && !useAuction) {
            _swapFrom(address(FLUID), address(asset), balance, 0);
        }
    }

    /**
     * @notice Kick an auction for a given token.
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
     * @param _fluidToBase UniV3 swap fee for FLUID => base (WETH)
     * @param _baseToAsset UniV3 swap fee for base => asset
     */
    function setUniFees(
        uint24 _fluidToBase,
        uint24 _baseToAsset
    ) external onlyManagement {
        _setUniFees(address(FLUID), base, _fluidToBase);
        _setUniFees(base, address(asset), _baseToAsset);
    }

    /**
     * @notice Set the minimum amount of FLUID to sell
     * @dev Can only be called by management.
     * @param _minAmountToSell minimum amount to sell in wei
     */
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
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
