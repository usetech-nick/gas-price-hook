// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

contract GasPriceFeesHook is BaseHook {
    using LPFeeLibrary for uint24;

    uint128 public movingAverageGasPrice; // current average gas price
    uint104 public movingAverageGasPriceCount; // the number of txns we've observed to get to that value

    uint24 public constant BASE_FEE = 5000; // pips, 0.5% fee

    error MustBeDynamicFees();

    constructor(IPoolManager _manager) BaseHook(_manager) {
        updateMovingAverage();
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal pure override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustBeDynamicFees();
        return IHooks.beforeInitialize.selector;
    }

    function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // 1. Get current gas price
        uint128 currentGasPrice = uint128(tx.gasprice);

        // 2. Calculate fee based on gas price comparison
        uint24 fee = getFee(currentGasPrice);

        // 3. Return with the dynamic fee
        // The fee has OVERRIDE_FEE_FLAG set so PoolManager uses our fee
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    /// @notice Calculate fee based on current gas price vs moving average
    /// @dev Higher gas = higher fee, lower gas = lower fee
    function getFee(uint128 currentGasPrice) public view returns (uint24) {
        // Edge case: first swap, no average yet
        if (movingAverageGasPrice == 0) {
            return BASE_FEE;
        }

        // Calculate fee: BASE_FEE * (currentGasPrice / movingAverageGasPrice)
        // Example: BASE_FEE=5000 (0.5%), current=100 gwei, avg=50 gwei
        //          fee = 5000 * 100 / 50 = 10000 (1.0%)
        uint256 fee = (uint256(BASE_FEE) * currentGasPrice) / movingAverageGasPrice;

        // Cap at max fee (100% = 1_000_000 pips)
        if (fee > 1_000_000) {
            return 1_000_000;
        }

        return uint24(fee);
    }

    function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        updateMovingAverage();
        return (IHooks.afterSwap.selector, 0);
    }

    function updateMovingAverage() internal {
        uint128 gasPrice = uint128(tx.gasprice);

        movingAverageGasPrice =
            (movingAverageGasPrice * movingAverageGasPriceCount + gasPrice) / (movingAverageGasPriceCount + 1);
        movingAverageGasPriceCount += 1;
    }
}
