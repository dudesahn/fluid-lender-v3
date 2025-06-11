// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "src/periphery/FluidStructs.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ILendingResolver, ILiquidtyResolver} from "src/interfaces/FluidInterfaces.sol";
import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";
import {UniswapV3SwapSimulator, ISwapRouter} from "src/periphery/UniswapV3SwapSimulator.sol";

contract FluidAprOraclePolygon {
    /// @notice Operator role can set rewardTokensPerSecond
    address public operator;

    /// @notice Fluid's lending resolver contract. Address differs by chain.
    address public immutable lendingResolver;

    /// @notice Fluid's liquidity resolver contract. Address differs by chain.
    address public immutable liquidityResolver;

    /// @notice Mapping for Fluid market => reward tokens per second (in WPOL)
    mapping(address market => uint256 rewardTokensPerSecond) public rewards;

    // internal state vars used for pricing WPOL
    address constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant WPOL = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    uint256 constant YEAR = 31536000;

    constructor(
        address _operator,
        address _lendingResolver,
        address _liquidityResolver
    ) {
        operator = _operator;
        lendingResolver = _lendingResolver;
        liquidityResolver = _liquidityResolver;
    }

    // uint256 baseApr = 1e14 * resolver.getFTokenDetails(fToken).supplyRate // returned in bps from resolver
    // can skip everything below for direct rewards, as it's returned in the resolver struct as rewardsRate w/ 1e14

    // I think to adjust for the any changes to the totalSupply with adding or removing debt, we can literally just multiply the supplyRate by the old supply and divide by the new one
    // then for the rewardsApr we can use the rewards helper contract since we put in totalAssets there...similarly, add or subtract from totalAssets
    // similarly assume that the apr for FLUID rewards will change according to the assets added or removed
    // for the rewardsApr YES use totalAssets, as the supply stuff below is from the liquidity layer which is different
    // for any of the stupid bonus FLUID rewards, similarly use and adjust totalAssets, and also probably discount the APR the API returns by like 10% just to be conservative for price movements, etc.

    // what we need to manipulate
    // supplyRate = borrowRate * (10000 - fee) * borrowWithInterest / supplyWithInterest

    // totalSupply = supplyWithInterest + supplyInterestFree
    // supplyWithInterest = supplyRawInterest * supplyExchangePrice / decimals

    // totalBorrow = borrowWithInterest_ + borrowInterestFree
    // borrowWithInterest_ = borrowRawInterest * borrowExchangePrice / decimals

    // SO, when we adjust what we are depositing, we can just multiply by the old supplyWithInterest which is just totalSupply - supplyInterestFree

    // pull base APR from calling on the lending resolver FTokenDetails["supplyRate"]

    // FLUID rewards on mainnet
    // should be able to actually post the details of the campaign directly to the APR oracle, and then calculate the ∆ from there. reached out to them about this
    // should actually be able to reverse-calculate the amount of FLUID rewards per period from the APR, price, and totalAssets (supply?); should check if USDC and USDT match amounts and across periods
    // can pull the data from here for tokens per second: https://merkle.api.fluid.instadapp.io/programs/inst-rewards-dec-2024/apr

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
        address fToken = IBase4626Compounder(_strategy).vault();

        FluidStructs.FTokenDetails memory tokenDetails = ILendingResolver(
            lendingResolver
        ).getFTokenDetails(fToken);
        uint256 supplyRate = tokenDetails.supplyRate * 1e14;
        uint256 assetRewardRate = tokenDetails.rewardsRate * 1e14;

        FluidStructs.OverallTokenData memory tokenData = ILiquidtyResolver(
            liquidityResolver
        ).getOverallTokenData(ERC4626(fToken).asset());

        // calculate what our new assets will be
        uint256 assets = tokenDetails.totalAssets;
        uint256 supply = tokenData.totalSupply - tokenData.supplyInterestFree;
        uint256 oldSupply = supply;
        if (_delta < 0) {
            assets = assets - uint256(-_delta);
            supply = supply - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
            supply = supply + uint256(_delta);
        }

        if (assets == 0 || supply == 0) {
            return 0;
        }

        // adjust based on changes in supply
        supplyRate = (supplyRate * oldSupply) / supply;

        // adjust based on changes in assets
        if (assetRewardRate > 0) {
            assetRewardRate =
                (assetRewardRate * tokenDetails.totalAssets) /
                assets;
        }

        uint256 polRewardRate;
        // check our mapping to see if we have any rewardsRates set
        // note that these calculations expect only USDC or USDT to have WPOL rewards (6 decimals)
        if (rewards[fToken] != 0) {
            // adjust based on changes in assets
            uint256 polPriceUSDC = getPolPriceUsdc();
            polRewardRate = (polPriceUSDC * rewards[fToken] * YEAR) / assets;
        }

        apr = supplyRate + assetRewardRate + polRewardRate;
    }

    function getPolPriceUsdc() public view returns (uint256 polInUsdc) {
        polInUsdc = UniswapV3SwapSimulator.simulateExactInputSingle(
            ISwapRouter(UNISWAP_V3_ROUTER),
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WPOL,
                tokenOut: USDC,
                fee: 500,
                recipient: address(0),
                deadline: block.timestamp,
                amountIn: 1e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function setRewards(
        address _markets,
        uint256 _rewardTokensPerSecond
    ) external {
        require(msg.sender == operator, "!operator");
        rewards[_markets] = _rewardTokensPerSecond;
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "!operator");
        operator = _operator;
    }
}
