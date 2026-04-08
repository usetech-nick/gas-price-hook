// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {GasPriceFeesHook} from "../src/GasPriceFeesHook.sol";

contract GasPriceFeesHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    GasPriceFeesHook hook;
    PoolKey poolKey;
    PoolId poolId;

    function setUp() public {
        // Deploy fresh PoolManager and routers
        deployFreshManagerAndRouters();

        // Calculate hook address with correct flags
        // Our hook uses: beforeInitialize, beforeSwap, afterSwap
        uint160 flags = uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        // Deploy hook to an address with the correct flags
        address hookAddress = address(flags);
        deployCodeTo("GasPriceFeesHook.sol:GasPriceFeesHook", abi.encode(manager), hookAddress);
        hook = GasPriceFeesHook(hookAddress);

        // Deploy test tokens
        deployMintAndApprove2Currencies();

        // Initialize pool with dynamic fees (required by our hook)
        (poolKey, poolId) = initPool(
            currency0,
            currency1,
            IHooks(address(hook)),
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Must be dynamic!
            SQRT_PRICE_1_1
        );

        // Add liquidity so we can swap
        modifyLiquidityRouter.modifyLiquidity(poolKey, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_hookDeployed() public view {
        assertEq(address(hook.poolManager()), address(manager));
    }

    function test_initialMovingAverage() public view {
        // Note: deployCodeTo runs constructor with tx.gasprice=0 in tests
        // So initial count is 1, but gas price is 0
        assertEq(hook.movingAverageGasPriceCount(), 1);
    }

    function test_revert_nonDynamicFee() public {
        // Try to create pool WITHOUT dynamic fees - should revert
        // PoolManager wraps hook errors, so we just expect any revert
        vm.expectRevert();
        initPool(
            currency0,
            currency1,
            IHooks(address(hook)),
            3000, // Static fee, not dynamic
            SQRT_PRICE_1_1
        );
    }

    /*//////////////////////////////////////////////////////////////
                            FEE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getFee_zeroAverage_returnsBaseFee() public view {
        // When average is 0, should return BASE_FEE
        uint24 fee = hook.getFee(100);
        assertEq(fee, hook.BASE_FEE());
    }

    function test_getFee_normalGas() public {
        // First do a swap to set a non-zero average
        vm.txGasPrice(50 gwei);
        swap(poolKey, true, -1e18, ZERO_BYTES);

        // When gas equals average, fee should equal BASE_FEE
        uint128 avg = hook.movingAverageGasPrice();
        uint24 fee = hook.getFee(avg);
        assertEq(fee, hook.BASE_FEE());
    }

    function test_getFee_highGas() public {
        // First do a swap to set a non-zero average
        vm.txGasPrice(50 gwei);
        swap(poolKey, true, -1e18, ZERO_BYTES);

        // When gas is 2x average, fee should be 2x BASE_FEE
        uint128 avg = hook.movingAverageGasPrice();
        uint24 fee = hook.getFee(avg * 2);
        assertEq(fee, hook.BASE_FEE() * 2);
    }

    function test_getFee_lowGas() public {
        // First do a swap to set a non-zero average
        vm.txGasPrice(50 gwei);
        swap(poolKey, true, -1e18, ZERO_BYTES);

        // When gas is 0.5x average, fee should be 0.5x BASE_FEE
        uint128 avg = hook.movingAverageGasPrice();
        uint24 fee = hook.getFee(avg / 2);
        assertEq(fee, hook.BASE_FEE() / 2);
    }

    function test_getFee_capped() public {
        // First do a swap with low gas to set a low average
        vm.txGasPrice(1 gwei);
        swap(poolKey, true, -1e18, ZERO_BYTES);

        // Extremely high gas relative to average should cap at 100%
        // With BASE_FEE=5000, need ratio > 200 to hit 1_000_000 cap
        uint128 avg = hook.movingAverageGasPrice();
        uint128 extremeGas = avg * 250;
        uint24 fee = hook.getFee(extremeGas);
        assertEq(fee, 1_000_000);
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_swap_updatesMovingAverage() public {
        uint104 countBefore = hook.movingAverageGasPriceCount();

        // Perform a swap
        swap(poolKey, true, -1e18, ZERO_BYTES);

        // Count should increase
        assertEq(hook.movingAverageGasPriceCount(), countBefore + 1);
    }

    function test_swap_multipleUpdates() public {
        uint104 countBefore = hook.movingAverageGasPriceCount();

        // Perform multiple swaps
        swap(poolKey, true, -1e18, ZERO_BYTES);
        swap(poolKey, false, -1e18, ZERO_BYTES);
        swap(poolKey, true, -1e18, ZERO_BYTES);

        // Count should increase by 3
        assertEq(hook.movingAverageGasPriceCount(), countBefore + 3);
    }

    function test_swap_differentGasPrices() public {
        // First swap to establish baseline
        vm.txGasPrice(50 gwei);
        swap(poolKey, true, -1e18, ZERO_BYTES);

        uint128 avgBefore = hook.movingAverageGasPrice();
        assertGt(avgBefore, 0);

        // Swap with higher gas price
        vm.txGasPrice(100 gwei);
        swap(poolKey, false, -1e18, ZERO_BYTES);

        // Average should increase
        assertGt(hook.movingAverageGasPrice(), avgBefore);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_getFee_neverOverflows(uint128 gasPrice) public view {
        // Should never revert
        uint24 fee = hook.getFee(gasPrice);
        // Fee should always be <= 1_000_000 (100%)
        assertLe(fee, 1_000_000);
    }

    function testFuzz_movingAverage_alwaysUpdates(uint64 gasPrice) public {
        // Use uint64 since vm.txGasPrice requires < 2^64
        vm.assume(gasPrice > 0);
        vm.txGasPrice(gasPrice);

        uint104 countBefore = hook.movingAverageGasPriceCount();
        swap(poolKey, true, -1e18, ZERO_BYTES);

        assertEq(hook.movingAverageGasPriceCount(), countBefore + 1);
    }
}
