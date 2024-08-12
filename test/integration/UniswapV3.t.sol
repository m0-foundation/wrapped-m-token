// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { TestBase } from "./TestBase.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

import {
    INonfungiblePositionManager,
    IUniswapV3Factory,
    IUniswapV3Pool,
    ISwapRouter
} from "./vendor/uniswap-v3/Interfaces.sol";

import { Utils } from "./vendor/uniswap-v3/Utils.sol";

contract UniswapV3IntegrationTests is TestBase {
    // Uniswap V3 Position Manager on Ethereum Mainnet
    INonfungiblePositionManager internal constant _positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    // Uniswap V3 Factory on Ethereum Mainnet
    IUniswapV3Factory internal constant _factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    // Uniswap V3 Router on Ethereum Mainnet
    ISwapRouter internal constant _router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // USDC on Ethereum Mainnet
    address internal constant _USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Uniswap V3 stable pair fee
    uint24 internal constant _POOL_FEE = 100; // 0.01% in bps

    address internal _pool;

    uint256 internal _wrapperBalanceOfM;

    uint256 internal _poolBalanceOfUSDC;
    uint256 internal _aliceBalanceOfUSDC;
    uint256 internal _bobBalanceOfUSDC;
    uint256 internal _carolBalanceOfUSDC;
    uint256 internal _daveBalanceOfUSDC;

    uint256 internal _poolBalanceOfWM;
    uint256 internal _aliceBalanceOfWM;
    uint256 internal _bobBalanceOfWM;
    uint256 internal _carolBalanceOfWM;
    uint256 internal _daveBalanceOfWM;

    uint256 internal _poolAccruedYield;
    uint256 internal _bobAccruedYield;

    function setUp() public override {
        super.setUp();

        _addToList(_EARNERS_LIST, address(_wrappedMToken));

        _wrappedMToken.enableEarning();

        _pool = _createPool();
    }

    function test_initialState() external view {
        assertTrue(_mToken.isEarning(address(_wrappedMToken)));
        assertEq(_wrappedMToken.isEarningEnabled(), true);
        assertFalse(_wrappedMToken.isEarning(_pool));
    }

    function test_uniswapV3_nonEarning() external {
        /* ============ Alice Mints New LP Position ============ */

        _giveM(_alice, 1_000_100e6);
        _wrap(_alice, _alice, 1_000_100e6);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        _mintNewPosition(_alice, _alice, 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC += 1_000_000e6);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that no yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 51_276_223485);

        // `startEarningFor` hasn't been called so no wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 51_276_223483);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC);

        // TODO: Bob Swaps USDC for wM
        // TODO: Second 1-Year Time Warp
        // TODO: Dave Swaps wM for USDC
    }

    function test_uniswapV3_earning() external {
        /* ============ Alice Mints New LP Position ============ */

        _giveM(_alice, 1_000_100e6);
        _wrap(_alice, _alice, 1_000_100e6);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        _mintNewPosition(_alice, _alice, 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC = 1_000_000e6);

        /* ============ Pool Becomes An Earner ============ */

        _setClaimOverrideRecipient(_pool, _carol);

        _addToList(_EARNERS_LIST, _pool);
        _wrappedMToken.startEarningFor(_pool);

        assertTrue(_wrappedMToken.isEarning(_pool));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_pool), _carol);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 51_276_223485);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield += 51_271_096375);

        // No excess yield has accrued in the wrapped M contract since the pool is the only earner.
        assertEq(_wrappedMToken.excess(), 5_127108);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC);

        /* ============ Bob Swaps Exact USDC for wM ============ */

        deal(_USDC, _bob, 100_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 100_000e6);

        uint256 swapAmountOut_ = _swapExactInput(_bob, _bob, _USDC, address(_wrappedMToken), 100_000e6);

        // Check pool liquidity after the swap
        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 100_000e6);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC += 100_000e6);
        assertEq(_wrappedMToken.balanceOf(_bob), swapAmountOut_);

        // The swap has triggered a wM transfer and the yield has been claimed to carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM -= swapAmountOut_);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);

        /* ============ Second 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 53_905_211681);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield += 46_610_511346);

        // No excess yield has accrued in the wrapped M contract since the pool is the only earner.
        assertEq(_wrappedMToken.excess(), 7299_827441);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC);

        /* ============ Dave (Earner) Swaps Exact wM for USDC ============ */

        _addToList(_EARNERS_LIST, _dave);
        _wrappedMToken.startEarningFor(_dave);

        _giveM(_dave, 100_100e6);
        _wrap(_dave, _dave, 100_100e6);

        assertEq(_mToken.balanceOf(_dave), 0);
        assertEq(_wrappedMToken.balanceOf(_dave), _daveBalanceOfWM += 100_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 100_099_999999);

        swapAmountOut_ = _swapExactInput(_dave, _dave, address(_wrappedMToken), _USDC, 100_000e6);

        // Check pool liquidity after the swap.
        assertEq(IERC20(_USDC).balanceOf(_dave), _daveBalanceOfUSDC += swapAmountOut_);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC -= swapAmountOut_);

        // The swap has triggered a wM transfer and the yield has been claimed to carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 100_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);
    }

    function testFuzz_uniswapV3_earning(uint256 aliceAmount_, uint256 bobUsdc_, uint256 daveWrappedM_) public {
        aliceAmount_ = bound(aliceAmount_, 1e6, _mToken.balanceOf(_mSource) / 10);
        bobUsdc_ = bound(bobUsdc_, 1e6, 1e12);
        daveWrappedM_ = bound(daveWrappedM_, 1e6, _mToken.balanceOf(_mSource) / 10);

        /* ============ Alice Mints New LP Position ============ */

        _giveM(_alice, aliceAmount_ + 2);
        _wrap(_alice, _alice, aliceAmount_ + 2);

        assertApproxEqAbs(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += aliceAmount_, 3);

        deal(_USDC, _alice, aliceAmount_);

        _mintNewPosition(_alice, _alice, aliceAmount_);

        assertApproxEqAbs(_wrappedMToken.balanceOf(_alice), 0, 10);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += aliceAmount_);

        assertEq(IERC20(_USDC).balanceOf(_alice), 0);
        assertEq(IERC20(_USDC).balanceOf(_pool), aliceAmount_);

        /* ============ Pool Becomes An Earner ============ */

        _setClaimOverrideRecipient(_pool, _carol);

        _addToList(_EARNERS_LIST, _pool);
        _wrappedMToken.startEarningFor(_pool);

        // Check that the pool is earning WM
        assertTrue(_wrappedMToken.isEarning(_pool));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_pool), _carol);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield);

        /* ============ First 1-Year Time Warp ============ */

        uint128 index_ = _mToken.currentIndex();

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        uint128 newIndex_ = _mToken.currentIndex();

        // Wrapped M is earning M and has accrued yield.
        assertApproxEqAbs(
            _mToken.balanceOf(address(_wrappedMToken)),
            _wrapperBalanceOfM = (_wrapperBalanceOfM * newIndex_) / index_,
            10
        );

        // `startEarningFor` has been called so WM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM);

        assertApproxEqAbs(
            _poolAccruedYield += _wrappedMToken.accruedYieldOf(_pool),
            (_poolBalanceOfWM * newIndex_) / index_ - _poolBalanceOfWM,
            10
        );

        // No excess yield has accrued in the wrapped M contract since the pool is the only earner.
        assertApproxEqAbs(_wrappedMToken.excess(), 0, 10);

        // _USDC balance is unchanged since no swap has been performed.
        assertEq(IERC20(_USDC).balanceOf(_pool), aliceAmount_);

        /* ============ Bob Swaps Exact USDC for wM ============ */

        deal(_USDC, _bob, bobUsdc_);

        uint256 swapOutWM_ = _swapExactInput(_bob, _bob, _USDC, address(_wrappedMToken), bobUsdc_);

        // Check pool liquidity after the swap
        assertEq(IERC20(_USDC).balanceOf(_bob), 0);
        assertEq(IERC20(_USDC).balanceOf(_pool), aliceAmount_ + bobUsdc_);
        assertEq(_wrappedMToken.balanceOf(_bob), swapOutWM_);

        // The swap has triggered a wM transfer and the yield has been claimed to carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM -= swapOutWM_);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);

        /* ============ Second 1-Year Time Warp ============ */

        index_ = _mToken.currentIndex();

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        newIndex_ = _mToken.currentIndex();

        // Wrapped M is earning M and has accrued yield.
        assertApproxEqAbs(
            _mToken.balanceOf(address(_wrappedMToken)),
            _wrapperBalanceOfM = (_wrapperBalanceOfM * newIndex_) / index_,
            10
        );

        // `startEarningFor` has been called so WM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM);

        assertApproxEqAbs(
            _poolAccruedYield += _wrappedMToken.accruedYieldOf(_pool),
            (_poolBalanceOfWM * newIndex_) / index_ - _poolBalanceOfWM,
            10
        );

        // USDC balance is unchanged since no swap has been performed.
        assertEq(IERC20(_USDC).balanceOf(_pool), aliceAmount_ + bobUsdc_);

        /* ============ Dave (Earner) Swaps Exact wM for USDC ============ */

        _addToList(_EARNERS_LIST, _dave);
        _wrappedMToken.startEarningFor(_dave);

        // NOTE: Give 2 more so that rounding errors do not prevent _swap.
        _giveM(_dave, daveWrappedM_ + 2);
        _wrap(_dave, _dave, daveWrappedM_ + 2);

        assertApproxEqAbs(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += daveWrappedM_, 6);

        uint256 swapOutUSDC_ = _swapExactInput(_dave, _dave, address(_wrappedMToken), _USDC, daveWrappedM_);

        // Check pool liquidity after the swap.
        assertEq(IERC20(_USDC).balanceOf(_dave), swapOutUSDC_);
        assertEq(IERC20(_USDC).balanceOf(_pool), aliceAmount_ + bobUsdc_ - swapOutUSDC_);

        // The swap has triggered a wM transfer and the yield has been claimed to carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += daveWrappedM_);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);
    }

    function test_uniswapV3_exactInputOrOutputForEarnersAndNonEarners() public {
        /* ============ Pool Becomes An Earner ============ */

        _setClaimOverrideRecipient(_pool, _carol);

        _addToList(_EARNERS_LIST, _pool);
        _wrappedMToken.startEarningFor(_pool);

        assertTrue(_wrappedMToken.isEarning(_pool));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_pool), _carol);

        /* ============ Alice Mints New LP Position ============ */

        _giveM(_alice, 1_000_100e6);
        _wrap(_alice, _alice, _mToken.balanceOf(_alice));

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_099_999999);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        _mintNewPosition(_alice, _alice, 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 1_000_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC = 1_000_000e6);

        // Totals checks: pool is the only earner.
        assertEq(_wrappedMToken.totalEarningSupply(), _poolBalanceOfWM);
        assertEq(_wrappedMToken.totalNonEarningSupply(), _aliceBalanceOfWM);
        assertEq(_wrappedMToken.totalAccruedYield(), _poolAccruedYield);

        /* ============ 10-Day Time Warp ============ */

        // Move 10 days forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 10 days);

        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield += 1_370_801702);

        // Totals checks.
        assertEq(_wrappedMToken.totalEarningSupply(), _poolBalanceOfWM);
        assertEq(_wrappedMToken.totalNonEarningSupply(), _aliceBalanceOfWM);
        assertEq(_wrappedMToken.totalAccruedYield(), _poolAccruedYield + 1);

        /* ============ 2 Non-Earners and 2 Earners are Initialized ============ */

        _giveM(_bob, 100_100e6);
        _wrap(_bob, _bob, 100_100e6);

        _giveM(_dave, 100_100e6);
        _wrap(_dave, _dave, 100_100e6);

        _addToList(_EARNERS_LIST, _eric);
        _wrappedMToken.startEarningFor(_eric);

        _giveM(_eric, 100_100e6);
        _wrap(_eric, _eric, 100_100e6);

        _addToList(_EARNERS_LIST, _frank);
        _wrappedMToken.startEarningFor(_frank);

        _giveM(_frank, 100_100e6);
        _wrap(_frank, _frank, 100_100e6);

        /* ============ Bob (Non-Earner) Swaps Exact wM for USDC ============ */

        _swapExactInput(_bob, _bob, address(_wrappedMToken), _USDC, 100_000e6);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 100_000e6);

        // Check that carol received yield.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);

        /* ============ 1-Day Time Warp ============ */

        // Move 1 day forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 1 days);

        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield += 150_695251);

        // Claim yield for the pool and check that carol received yield.
        _wrappedMToken.claimFor(_pool);

        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);

        /* ============ 5-Day Time Warp ============ */

        // Move 5 days forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 5 days);

        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield += 753_682738);

        /* ============ Eric (Earner) Swaps Exact wM for USDC ============ */

        _swapExactInput(_eric, _eric, address(_wrappedMToken), _USDC, 100_000e6);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 100_000e6);

        // Check that carol received yield.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);

        /* ============ 3-Day Time Warp ============ */

        // Move 3 days forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 3 days);

        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield += 493_252029);

        /* ============ Dave (Non-Earner) Swaps wM for Exact USDC ============ */

        // Option 3: Exact output parameter swap from non-earner
        uint256 daveOutput_ = _swapExactOutput(_dave, _dave, address(_wrappedMToken), _USDC, 10_000e6);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += daveOutput_);

        // Check that carol received yield.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);

        /* ============ 7-Day Time Warp ============ */

        // Move 7 day forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 7 days);

        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield += 1_165_220368);

        /* ============ Frank (Earner) Swaps wM for Exact USDC ============ */

        uint256 frankOutput_ = _swapExactOutput(_frank, _frank, address(_wrappedMToken), _USDC, 10_000e6);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += frankOutput_);

        // Check that carol received yield.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);
    }

    function test_uniswapV3_increaseDecreaseLiquidityAndFees() public {
        /* ============ Pool Becomes An Earner ============ */

        _setClaimOverrideRecipient(_pool, _carol);

        _addToList(_EARNERS_LIST, _pool);
        _wrappedMToken.startEarningFor(_pool);

        assertTrue(_wrappedMToken.isEarning(_pool));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_pool), _carol);

        /* ============ Fund Alice (Non-Earner) and Bob (Earner) ============ */

        _giveM(_alice, 2_000_100e6);
        _wrap(_alice, _alice, _mToken.balanceOf(_alice));

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 2_000_099_999999);

        deal(_USDC, _alice, 2_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 2_000_100e6);

        _addToList(_EARNERS_LIST, _bob);
        _wrappedMToken.startEarningFor(_bob);

        _giveM(_bob, 2_000_100e6);
        _wrap(_bob, _bob, _mToken.balanceOf(_bob));

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 2_000_100_000000);

        deal(_USDC, _bob, 2_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 2_000_100e6);

        /* ============ Alice (Non-Earner) and Bob (Earner) Mint New LP Positions ============ */

        (uint256 aliceTokenId_, , , ) = _mintNewPosition(_alice, _alice, 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC += 1_000_000e6);

        (uint256 bobTokenId_, , , ) = _mintNewPosition(_bob, _bob, 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC += 1_000_000e6);

        /* ============ 10-Day Time Warp ============ */

        // Move 10 days forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 10 days);

        assertEq(_wrappedMToken.accruedYieldOf(_bob), _bobAccruedYield += 550_891667);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield += 1_101_673168);

        /* ============ Dave (Non-Earner) Swaps Exact wM for USDC ============ */

        _giveM(_dave, 100_100e6);
        _wrap(_dave, _dave, 100_100e6);

        assertEq(_wrappedMToken.balanceOf(_dave), _daveBalanceOfWM += 100_099_999999);

        _swapExactInput(_dave, _dave, address(_wrappedMToken), _USDC, 100_000e6);

        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC -= 95_229_024894);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 100_000e6);

        // Check that carol received yield.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);

        /* ============ Alice (Non-Earner) And Bob (Earner) Collect Fees ============ */

        (uint256 aliceAmountWM_, uint256 aliceAmountUSDC_) = _collect(_alice, aliceTokenId_);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += aliceAmountWM_);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM -= aliceAmountWM_);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += aliceAmountUSDC_);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC -= aliceAmountUSDC_);

        (uint256 bobAmountWM_, uint256 bobAmountUSDC_) = _collect(_bob, bobTokenId_);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += bobAmountWM_ + _bobAccruedYield);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM -= bobAmountWM_);

        assertEq(_wrappedMToken.accruedYieldOf(_bob), _bobAccruedYield -= _bobAccruedYield);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += bobAmountUSDC_);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC -= bobAmountUSDC_);

        /* ============ Alice (Non-Earner) Decreases Liquidity And Bob (Earner) Increases Liquidity ============ */

        (aliceAmountWM_, aliceAmountUSDC_) = _decreaseLiquidityCurrentRange(_alice, aliceTokenId_, 500_000e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += aliceAmountWM_);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM -= aliceAmountWM_);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += aliceAmountUSDC_);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC -= aliceAmountUSDC_);

        (, bobAmountWM_, bobAmountUSDC_) = _increaseLiquidityCurrentRange(_bob, bobTokenId_, 100_000e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= bobAmountWM_);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += bobAmountWM_);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= bobAmountUSDC_);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC += bobAmountUSDC_);
    }

    function _createPool() internal returns (address pool_) {
        pool_ = _factory.createPool(address(_wrappedMToken), _USDC, _POOL_FEE);
        IUniswapV3Pool(pool_).initialize(Utils.encodePriceSqrt(1, 1));
    }

    function _approve(address token_, address account_, address spender_, uint256 amount_) internal {
        vm.prank(account_);
        IERC20(token_).approve(spender_, amount_);
    }

    function _transfer(address token_, address sender_, address recipient_, uint256 amount_) internal {
        vm.prank(sender_);
        IERC20(token_).transfer(recipient_, amount_);
    }

    function _mintNewPosition(
        address account_,
        address recipient_,
        uint256 amount_
    ) internal returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0_, uint256 amount1_) {
        _approveWM(account_, address(_positionManager), amount_);
        _approve(_USDC, account_, address(_positionManager), amount_);

        vm.prank(account_);
        INonfungiblePositionManager.MintParams memory params_ = INonfungiblePositionManager.MintParams({
            token0: address(_wrappedMToken),
            token1: _USDC,
            fee: _POOL_FEE,
            tickLower: Utils.MIN_TICK,
            tickUpper: Utils.MAX_TICK,
            amount0Desired: amount_,
            amount1Desired: amount_,
            amount0Min: 0,
            amount1Min: 0,
            recipient: recipient_,
            deadline: vm.getBlockTimestamp()
        });

        (tokenId_, liquidity_, amount0_, amount1_) = _positionManager.mint(params_);
    }

    function _increaseLiquidityCurrentRange(
        address account_,
        uint256 tokenId_,
        uint256 amount_
    ) internal returns (uint128 liquidity_, uint256 amount0_, uint256 amount1_) {
        _approveWM(account_, address(_positionManager), amount_);
        _approve(_USDC, account_, address(_positionManager), amount_);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId_,
                amount0Desired: amount_,
                amount1Desired: amount_,
                amount0Min: 0,
                amount1Min: 0,
                deadline: vm.getBlockTimestamp()
            });

        vm.prank(account_);
        return _positionManager.increaseLiquidity(params);
    }

    function _decreaseLiquidityCurrentRange(
        address account_,
        uint256 tokenId_,
        uint128 liquidity_
    ) internal returns (uint256 amount0_, uint256 amount1_) {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId_,
                liquidity: liquidity_,
                amount0Min: 0,
                amount1Min: 0,
                deadline: vm.getBlockTimestamp()
            });

        vm.prank(account_);
        (amount0_, amount1_) = _positionManager.decreaseLiquidity(params);

        _collect(account_, tokenId_);
    }

    function _collect(address account_, uint256 tokenId_) internal returns (uint256 amount0_, uint256 amount1_) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId_,
            recipient: account_,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        vm.prank(account_);
        (amount0_, amount1_) = _positionManager.collect(params);
    }

    function _swapExactInput(
        address account_,
        address recipient_,
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_
    ) internal returns (uint256 amountOut_) {
        _approve(tokenIn_, account_, address(_router), amountIn_);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn_,
            tokenOut: tokenOut_,
            fee: _POOL_FEE,
            recipient: recipient_,
            deadline: vm.getBlockTimestamp() + 30 minutes,
            amountIn: amountIn_,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        vm.prank(account_);
        return _router.exactInputSingle(params);
    }

    function _swapExactOutput(
        address account_,
        address recipient_,
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_
    ) internal returns (uint256 amountIn_) {
        _approve(tokenIn_, account_, address(_router), type(uint256).max);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn_,
            tokenOut: tokenOut_,
            fee: _POOL_FEE,
            recipient: recipient_,
            deadline: vm.getBlockTimestamp() + 30 minutes,
            amountOut: amountOut_,
            amountInMaximum: type(uint256).max,
            sqrtPriceLimitX96: 0
        });

        vm.prank(account_);
        return _router.exactOutputSingle(params);
    }
}
