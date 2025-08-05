// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {Base4626Compounder, ERC20, SafeERC20} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
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

    /// @notice Dust threshold used to prevent tiny deposits
    uint256 public constant DUST = 1_000;

    /**
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy.
     * @param _vault ERC4626 vault token to use.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault
    ) Base4626Compounder(_asset, _name, _vault) {
        FLUID.forceApprove(router, type(uint256).max);

        // Set the min amount for the swapper to sell
        // 0.3% pool better execution at relatively small size than deeper 1% pool
        _setUniFees(address(FLUID), base, 3000); // UniV3 fees in 1/100 of bps
        if (address(asset) != base) {
            // 0.05% for both USDC and USDT-WETH pools
            _setUniFees(base, address(asset), 500);
        }
        minAmountToSell = 100e18; // 100 FLUID = 600 USD
    }

    /* ========== VIEW FUNCTIONS ========== */

    function balanceOfRewards() public view returns (uint256) {
        return FLUID.balanceOf(address(this));
    }

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
        uint256 balance = balanceOfRewards();
        if (balance > minAmountToSell && !useAuction) {
            _swapFrom(address(FLUID), address(asset), balance, 0);
        }
        balance = balanceOfAsset();
        if (!TokenizedStrategy.isShutdown()) {
            // no need to waste gas on depositing dust
            if (balance > DUST) {
                _deployFunds(balance);
            }
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
        return Auction(auction).kick(_from);
    }

    /* ========== SETTERS ========== */

    /**
     * @notice Use to update our auction address.
     * @dev Can only be called by management.
     * @param _auction Address of new auction.
     */
    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            require(
                Auction(_auction).want() == address(asset) ||
                    Auction(_auction).want() == address(vault),
                "wrong want"
            );
            require(
                Auction(_auction).receiver() == address(this),
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
    function setUniV3Fees(
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
