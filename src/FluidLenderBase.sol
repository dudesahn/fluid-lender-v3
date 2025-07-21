// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {IAuction} from "src/interfaces/IAuction.sol";
import {IMerkleRewards} from "src/interfaces/FluidInterfaces.sol";
import {IFluidDex} from "src/interfaces/FluidInterfaces.sol";
import {ISwapRouter} from "@slipstream/periphery/interfaces/ISwapRouter.sol";

contract FluidLenderBase is Base4626Compounder {
    using SafeERC20 for ERC20;

    /// @notice Address for our reward token auction
    address public auction;

    /// @notice Whether to sell rewards using auction or Uniswap V3
    bool public useAuction;

    /// @notice True if strategy deposits are open to any address
    bool public openDeposits;

    /// @notice Tick spacing for WETH to USDC swaps on Slipstream
    int24 public wethToUsdcSwapTickSpacing;

    /// @notice Tick spacing for USDC to asset swaps on Slipstream
    int24 public usdcToAssetSwapTickSpacing;

    /// @notice Set this so we don't try and sell dust.
    uint256 public minAmountToSell;

    /// @notice Mapping of addresses and whether they are allowed to deposit to this strategy
    mapping(address => bool) public allowed;

    /// @notice Address for Fluid's FLUID-WETH DEX pair
    IFluidDex public constant FLUID_DEX =
        IFluidDex(0xdE632C3a214D5f14C1d8ddF0b92F8BCd188fee45);

    /// @notice Aerodrome's Slipstream (aka UniV3/CL) router
    ISwapRouter public constant SLIPSTREAM_ROUTER =
        ISwapRouter(0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5);

    /// @notice Address for Fluid's merkle claim
    /// @dev This is the same on Base and Arbitrum
    IMerkleRewards public constant MERKLE_CLAIM =
        IMerkleRewards(0x94312a608246Cecfce6811Db84B3Ef4B2619054E);

    /// @notice FLUID token address
    /// @dev This is the same on Base and Arbitrum
    ERC20 public constant FLUID =
        ERC20(0x61E030A56D33e8260FdD81f03B162A79Fe3449Cd);

    /// @notice WETH token address
    ERC20 public constant WETH =
        ERC20(0x4200000000000000000000000000000000000006);

    /// @notice USDC token address
    ERC20 public constant USDC =
        ERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

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
        FLUID.forceApprove(address(FLUID_DEX), type(uint256).max);

        // default to 100 tick spacing for WETH-USDC
        if (address(asset) != address(WETH)) {
            WETH.forceApprove(address(SLIPSTREAM_ROUTER), type(uint256).max);
            wethToUsdcSwapTickSpacing = 100;
        }

        // default to 50 tick spacing for USDC-EURC
        if (address(asset) != address(USDC)) {
            USDC.forceApprove(address(SLIPSTREAM_ROUTER), type(uint256).max);
            usdcToAssetSwapTickSpacing = 50;
        }
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
        // use Fluid DEX and Aerodrome to sell FLUID to underlying
        uint256 balance = FLUID.balanceOf(address(this));
        if (balance > minAmountToSell && !useAuction) {
            _sellFluidToWeth(balance);
            _sellWethToAsset();
        }
    }

    function _sellFluidToWeth(uint256 _fluidToSell) internal {
        FLUID_DEX.swapIn(true, _fluidToSell, 0, address(this));
    }

    /**
     * @notice Handles native ETH received by the contract and automatically wraps to WETH
     * @dev Fluid's DEX returns ETH, not WETH
     */
    receive() external payable {
        if (address(this).balance != 0) {
            IWETH(address(WETH)).deposit{value: address(this).balance}();
        }
    }

    function _sellWethToAsset() internal {
        uint256 wethBalance = WETH.balanceOf(address(this));

        if (wethBalance > 1e12) {
            if (address(asset) != address(WETH)) {
                SLIPSTREAM_ROUTER.exactInputSingle(
                    getSwapRouterInput(address(WETH), wethBalance)
                );
            }
        }

        if (address(asset) == address(USDC) || usdcToAssetSwapTickSpacing == 0)
            return;

        uint256 usdcBalance = USDC.balanceOf(address(this));

        if (usdcBalance >= 1e3) {
            SLIPSTREAM_ROUTER.exactInputSingle(
                getSwapRouterInput(address(USDC), usdcBalance)
            );
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

    /**
     * @notice Creates swap parameters for Slipstream router
     * @param _tokenIn Address of input token (WETH or USDC)
     * @param _amountIn Amount of input tokens to swap
     * @return Swap parameters struct for Slipstream router
     */
    function getSwapRouterInput(
        address _tokenIn,
        uint256 _amountIn
    ) internal view returns (ISwapRouter.ExactInputSingleParams memory) {
        return
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: address(asset),
                tickSpacing: _tokenIn == address(WETH)
                    ? wethToUsdcSwapTickSpacing
                    : usdcToAssetSwapTickSpacing,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
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

    /// @notice Sets tick spacing for WETH -> USDC swap
    /// @param _wethToUsdcSwapTickSpacing Tick spacing
    /// @dev Only callable by management
    function setWethToUsdcSwapTickSpacing(
        int24 _wethToUsdcSwapTickSpacing
    ) external onlyManagement {
        wethToUsdcSwapTickSpacing = _wethToUsdcSwapTickSpacing;
    }

    /// @notice Sets tick spacing for USDC -> Asset swap
    /// @param _usdcToAssetSwapTickSpacing Tick spacing
    /// @dev Only callable by management
    function setUsdcToAssetSwapTickSpacing(
        int24 _usdcToAssetSwapTickSpacing
    ) external onlyManagement {
        usdcToAssetSwapTickSpacing = _usdcToAssetSwapTickSpacing;
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
