// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IUniswapV3Pool} from "@uniswap-v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {Simulate, TickMath} from "./UniswapV3SwapSimulatorCore.sol";
import {ISwapRouter} from "@periphery/interfaces/Uniswap/V3/ISwapRouter.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

interface ISwapRouterWithFactory is ISwapRouter {
    function factory() external view returns (address);
}

/// @title Library for simulating swaps on Uniswap V3
/// @notice Provides functions to simulate swap outcomes without executing actual transactions
/// @dev Uses Uniswap v3 concentrated liquidity pools for price calculations
library UniswapV3SwapSimulator {
    /// @notice Simulates a single exact input swap without executing the actual swap
    /// @param router The swap router contract to use for the simulation
    /// @param params The parameters for the exact input single swap
    /// @return amountOut The expected output amount from the simulated swap
    /// @dev Uses the pool's current state to calculate the expected output amount
    function simulateExactInputSingle(
        ISwapRouter router,
        ISwapRouter.ExactInputSingleParams memory params
    ) external view returns (uint256 amountOut) {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = getPool(
            router,
            params.tokenIn,
            params.tokenOut,
            params.fee
        );
        (int256 _amount0, int256 _amount1) = Simulate.simulateSwap(
            pool,
            zeroForOne,
            int256(params.amountIn),
            params.sqrtPriceLimitX96 == 0
                ? (
                    zeroForOne
                        ? TickMath.MIN_SQRT_RATIO + 1
                        : TickMath.MAX_SQRT_RATIO - 1
                )
                : params.sqrtPriceLimitX96
        );
        return uint256(-(zeroForOne ? _amount1 : _amount0));
    }

    function getPool(
        ISwapRouter router,
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (IUniswapV3Pool) {
        return
            IUniswapV3Pool(
                IUniswapV3Factory(
                    ISwapRouterWithFactory(address(router)).factory()
                ).getPool(tokenA, tokenB, fee)
            );
    }
}
