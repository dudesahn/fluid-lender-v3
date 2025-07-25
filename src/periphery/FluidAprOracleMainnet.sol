// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {FluidStructs} from "src/libraries/FluidStructs.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ILendingResolver, ILiquidtyResolver} from "src/interfaces/FluidInterfaces.sol";
import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";
import {UniswapV3SwapSimulator, ISwapRouter} from "src/libraries/UniswapV3SwapSimulator.sol";
import {IChainlinkCalcs} from "src/interfaces/IChainlinkCalcs.sol";

contract FluidAprOracleMainnet {
    /// @notice Operator role can set rewardTokensPerSecond
    address public operator;

    /// @notice Whether we manually set the rewards APR instead of calculating using price and manual reward rates
    bool public useManualRewardsApr;

    /// @notice Mapping for Fluid market => reward tokens per second (in FLUID)
    mapping(address market => uint256 rewardTokensPerSecond) public rewards;

    /// @notice Mapping for Fluid market => manual rewards apr
    mapping(address market => uint256 rewardsApr) public manualRewardsApr;

    /// @notice Fluid's lending resolver contract.
    ILendingResolver public constant LENDING_RESOLVER =
        ILendingResolver(0xC215485C572365AE87f908ad35233EC2572A3BEC);

    /// @notice Fluid's liquidity resolver contract.
    ILiquidtyResolver public constant LIQUIDITY_RESOLVER =
        ILiquidtyResolver(0xF82111c4354622AB12b9803cD3F6164FCE52e847);

    /// @notice Array of our fToken markets with bonus rewards
    address[] public marketsWithRewards;

    // internal state vars used for pricing FLUID
    address public constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant FLUID = 0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IChainlinkCalcs public constant CHAINLINK_CALCS =
        IChainlinkCalcs(0xc8D60D8273E69E63eAFc4EA342f96AD593A4ba10);
    uint256 public constant YEAR = 31536000;

    constructor(address _operator) {
        require(_operator != address(0), "ZERO_ADDRESS");
        operator = _operator;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "!operator");
        _;
    }

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return apr The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256 apr) {
        uint256 supplyRate = getSupplyRate(_strategy, _delta);
        (uint256 assetRewardRate, uint256 fluidRewardRate) = getRewardRates(
            _strategy,
            _delta
        );

        apr = supplyRate + assetRewardRate + fluidRewardRate;
    }

    function getFluidPriceUsdc() public view returns (uint256 fluidPrice) {
        uint256 fluidInWeth = UniswapV3SwapSimulator.simulateExactInputSingle(
            ISwapRouter(UNISWAP_V3_ROUTER),
            ISwapRouter.ExactInputSingleParams({
                tokenIn: FLUID,
                tokenOut: WETH,
                fee: 3000,
                recipient: address(0),
                deadline: block.timestamp,
                amountIn: 1e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // use chainlink to convert weth to USDC (6 decimals)
        fluidPrice = (fluidInWeth * CHAINLINK_CALCS.getPriceUsdc(WETH)) / 1e18;
    }

    function getSupplyRate(
        address _strategy,
        int256 _delta
    ) public view returns (uint256 supplyRate) {
        address fToken = IBase4626Compounder(_strategy).vault();

        FluidStructs.FTokenDetails memory tokenDetails = LENDING_RESOLVER
            .getFTokenDetails(fToken);
        supplyRate = tokenDetails.supplyRate * 1e14;

        FluidStructs.OverallTokenData memory tokenData;
        // make a special case for WETH
        if (ERC4626(fToken).asset() == WETH) {
            tokenData = LIQUIDITY_RESOLVER.getOverallTokenData(
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
            );
        } else {
            tokenData = LIQUIDITY_RESOLVER.getOverallTokenData(
                ERC4626(fToken).asset()
            );
        }

        // calculate what our new assets will be
        uint256 supply = tokenData.totalSupply - tokenData.supplyInterestFree;
        uint256 oldSupply = supply;
        if (_delta < 0) {
            supply = supply - uint256(-_delta);
        } else {
            supply = supply + uint256(_delta);
        }

        if (supply == 0) {
            return 0;
        }

        // adjust based on changes in supply
        supplyRate = (supplyRate * oldSupply) / supply;
    }

    function getRewardRates(
        address _strategy,
        int256 _delta
    ) public view returns (uint256 assetRewardRate, uint256 fluidRewardRate) {
        address fToken = IBase4626Compounder(_strategy).vault();

        FluidStructs.FTokenDetails memory tokenDetails = LENDING_RESOLVER
            .getFTokenDetails(fToken);
        assetRewardRate = tokenDetails.rewardsRate * 1e4;

        // calculate what our new assets will be
        uint256 assets = tokenDetails.totalAssets;
        if (_delta < 0) {
            assets = assets - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
        }

        if (assets == 0) {
            return (0, 0);
        }

        // adjust based on changes in assets
        if (assetRewardRate > 0) {
            assetRewardRate =
                (assetRewardRate * tokenDetails.totalAssets) /
                assets;
        }

        // check our mapping to see if we have any rewardsRates set
        // note that these calculations expect only stablecoins to have extra rewards
        if (rewards[fToken] != 0 || useManualRewardsApr) {
            if (useManualRewardsApr) {
                fluidRewardRate = manualRewardsApr[fToken];
            } else {
                // adjust based on changes in assets
                uint256 fluidPriceUSDC = getFluidPriceUsdc();
                uint256 decimalsAdjustment = 10 **
                    (ERC4626(fToken).decimals() - 6);
                fluidRewardRate =
                    (fluidPriceUSDC *
                        rewards[fToken] *
                        YEAR *
                        decimalsAdjustment) /
                    assets;
            }
        }
    }

    /* ========== SETTERS ========== */

    function setRewardsRate(
        address _market,
        uint256 _rewardTokensPerSecond
    ) external onlyOperator {
        if (_rewardTokensPerSecond > 0) {
            require(!useManualRewardsApr, "!rewards");
        }
        rewards[_market] = _rewardTokensPerSecond;
    }

    function setManualRewardsApr(
        address _market,
        uint256 _manualRewardsApr
    ) external onlyOperator {
        if (_manualRewardsApr > 0) {
            require(useManualRewardsApr, "!manualRewards");
        }
        manualRewardsApr[_market] = _manualRewardsApr;
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setUseManualRewardsApr(
        bool _useManualRewardsApr
    ) external onlyOperator {
        useManualRewardsApr = _useManualRewardsApr;
    }
}
