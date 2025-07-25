// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import {FluidStructs} from "src/libraries/FluidStructs.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";
import {ILendingResolver, ILiquidtyResolver, IDexResolver} from "src/interfaces/FluidInterfaces.sol";
import {IChainlinkCalcs} from "src/interfaces/IChainlinkCalcs.sol";

contract FluidAprOracleBase {
    /// @notice Operator role can update merkle reward info
    address public operator;

    /// @notice Whether we manually set the rewards APR instead of calculating using price and manual reward rates
    bool public useManualRewardsApr;

    /// @notice Mapping for Fluid market => reward tokens per second (in FLUID)
    mapping(address market => uint256 rewardTokensPerSecond) public rewards;

    /// @notice Mapping for Fluid market => manual rewards apr
    mapping(address market => uint256 rewardsApr) public manualRewardsApr;

    /// @notice Fluid's lending resolver contract.
    ILendingResolver public constant LENDING_RESOLVER =
        ILendingResolver(0x3aF6FBEc4a2FE517F56E402C65e3f4c3e18C1D86);

    /// @notice Fluid's liquidity resolver contract.
    ILiquidtyResolver public constant LIQUIDITY_RESOLVER =
        ILiquidtyResolver(0x35A915336e2b3349FA94c133491b915eD3D3b0cd);

    /// @notice Fluid's DEX resolver contract.
    IDexResolver public constant DEX_RESOLVER =
        IDexResolver(0xa3B18522827491f10Fc777d00E69B3669Bf8c1f8);

    /// @notice Yearn's Chainlink calculation helper contract.
    IChainlinkCalcs public constant CHAINLINK_CALCS =
        IChainlinkCalcs(0x20e1F95cd5CD6954f16B7455a4C8fA1aDb99eb4D);

    /// @notice FLUID-WETH pair on Fluid DEX. Best source to price FLUID on Base.
    address public constant FLUID_WETH_DEX =
        0xdE632C3a214D5f14C1d8ddF0b92F8BCd188fee45;

    /// @notice WETH token address
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    /// @notice Seconds in a year
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

    /**
     * @notice Get the base supply APR for a given strategy.
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return supplyRate The expected supply apr for the strategy represented as 1e18.
     */
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

    /**
     * @notice Get the reward APRs for a given strategy.
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return assetRewardRate The expected in-kind asset reward rate for the strategy represented as 1e18.
     * @return fluidRewardRate The expected FLUID reward apr for the strategy represented as 1e18.
     */
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
                if (fToken == 0x1943FA26360f038230442525Cf1B9125b5DCB401) {
                    // fetch our EURC price from chainlink
                    uint256 eurcPrice = CHAINLINK_CALCS.getPriceUsdc(
                        ERC4626(fToken).asset()
                    );
                    fluidRewardRate = (fluidRewardRate * 1e6) / eurcPrice;
                }
            }
        }
    }

    /// @notice Get price of FLUID token in USDC.
    function getFluidPriceUsdc() public view returns (uint256 fluidPrice) {
        // pull the price from the Fluid DEX
        uint256 storageVar = DEX_RESOLVER.getDexVariablesRaw(FLUID_WETH_DEX);

        /// Next 40 bits => 41-80 => last stored price of pool. BigNumber (32 bits precision, 8 bits exponent)
        uint256 X40 = 0xffffffffff;
        uint256 X8 = 0xff;
        uint256 fluidInWeth = (storageVar >> 41) & X40;
        fluidInWeth = (fluidInWeth >> 8) << (fluidInWeth & X8);

        // use chainlink to convert weth to USDC (6 decimals)
        fluidPrice = (fluidInWeth * CHAINLINK_CALCS.getPriceUsdc(WETH)) / 1e27;
    }

    /* ========== SETTERS ========== */

    /**
     * @notice Set the reward tokens per second for a given fToken market/vault.
     * @dev May only be called by operator.
     * @param _market The fToken to adjust
     * @param _rewardTokensPerSecond Reward tokens per second. Pull this data from Fluid's API.
     */
    function setRewardsRate(
        address _market,
        uint256 _rewardTokensPerSecond
    ) external onlyOperator {
        if (_rewardTokensPerSecond > 0) {
            require(!useManualRewardsApr, "!rewards");
        }
        rewards[_market] = _rewardTokensPerSecond;
    }

    /**
     * @notice Set the manual reward token APR for a given fToken market/vault.
     * @dev May only be called by operator.
     * @param _market The fToken to adjust
     * @param _manualRewardsApr Reward token APR, 1e18 = 100%. Pull this data from Fluid's API.
     */
    function setManualRewardsApr(
        address _market,
        uint256 _manualRewardsApr
    ) external onlyOperator {
        if (_manualRewardsApr > 0) {
            require(useManualRewardsApr, "!manualRewards");
        }
        manualRewardsApr[_market] = _manualRewardsApr;
    }

    /**
     * @notice Update the operator address.
     * @dev May only be called by operator.
     * @param _operator The new operator.
     */
    function setOperator(address _operator) external onlyOperator {
        require(_operator != address(0), "ZERO_ADDRESS");
        operator = _operator;
    }

    /**
     * @notice Set whether to use manual reward apr or rewards rate for APR calculations.
     * @dev May only be called by operator.
     * @param _useManualRewardsApr Whether to use manual rewards APR or not. Ideally this stays false.
     */
    function setUseManualRewardsApr(
        bool _useManualRewardsApr
    ) external onlyOperator {
        useManualRewardsApr = _useManualRewardsApr;
    }
}
