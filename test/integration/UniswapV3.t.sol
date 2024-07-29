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

    // _USDC on Ethereum Mainnet
    address internal constant _USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Uniswap V3 stable pair fee
    uint24 internal constant _POOL_FEE = 100; // 0.01% in bps

    address internal _pool;

    uint256 internal _wrapperBalanceOfM;
    uint256 internal _poolBalanceOfWM;

    uint256 internal _poolAccruedYield;

    function setUp() public override {
        super.setUp();

        _addToList(_EARNERS_LIST, address(_wrappedMToken));

        _wrappedMToken.enableEarning();

        _pool = _createPool();
    }

    function test_initialState() external view {
        assertTrue(_mToken.isEarning(address(_wrappedMToken)));
        assertFalse(_wrappedMToken.isEarning(_pool));
    }

    function test_uniswapV3_nonEarning() external {
        // NOTE: Give 100e6 more so that rounding errors do not prevent _mintNewPosition of 1_000_000e6.
        _giveM(_alice, 1_000_100e6);
        _wrap(_alice, _alice, 1_000_100e6);

        deal(_USDC, _alice, 1_000_100e6);

        _mintNewPosition(_alice, _alice, 1_000_000e6);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(_pool), 0);

        assertEq(_wrappedMToken.balanceOf(_alice), 99_999999);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), 100e6);
        assertEq(IERC20(_USDC).balanceOf(_pool), 1_000_000e6);

        // Move 1 year forward and check that no yield has accrued
        vm.warp(block.timestamp + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 51_276_223485);

        // `startEarningFor` hasn't been called so no WM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_pool), 1_000_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), 0);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 51_276_223485);

        // _USDC balance is unchanged since no swap has been performed.
        assertEq(IERC20(_USDC).balanceOf(_pool), 1_000_000e6);
    }

    function test_uniswapV3_earning() public {
        // NOTE: Give 100e6 more so that rounding errors do not prevent _mintNewPosition of 1_000_000e6.
        _giveM(_alice, 1_000_100e6);
        _wrap(_alice, _alice, 1_000_100e6);

        deal(_USDC, _alice, 1_000_100e6);

        _mintNewPosition(_alice, _alice, 1_000_000e6);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(_pool), 0);

        assertEq(_wrappedMToken.balanceOf(_alice), 99_999999);
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), 100e6);
        assertEq(IERC20(_USDC).balanceOf(_pool), 1_000_000e6);

        _setClaimOverrideRecipient(_pool, _carol);

        _addToList(_EARNERS_LIST, _pool);
        _wrappedMToken.startEarningFor(_pool);

        // Check that the pool is earning WM
        assertTrue(_wrappedMToken.isEarning(_pool));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_pool), _carol);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM -= 1);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), 0);

        // Move 1 year forward and check that yield has accrued
        vm.warp(block.timestamp + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 51_276_223485);

        // `startEarningFor` has been called so WM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield += 51_271_096376);

        // No excess yield has accrued in the wrapped M contract since the pool is the only earner.
        assertEq(_wrappedMToken.excess(), 5_127109);

        // _USDC balance is unchanged since no swap has been performed.
        assertEq(IERC20(_USDC).balanceOf(_pool), 1_000_000e6);

        // Bob decides to swap 1M _USDC in exchange of WM.
        deal(_USDC, _bob, 100_000e6);

        uint256 swapAmountOut_ = _swap(_bob, _bob, _USDC, address(_wrappedMToken), 100_000e6);

        // Check pool liquidity after the swap
        assertEq(IERC20(_USDC).balanceOf(_bob), 0);
        assertEq(IERC20(_USDC).balanceOf(_pool), 1_000_000e6 + 100_000e6);
        assertEq(_wrappedMToken.balanceOf(_bob), swapAmountOut_);

        // The swap has triggered a WM transfer and the yield has been claimed toi carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _poolAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM -= (swapAmountOut_ + 2));
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);

        _addToList(_EARNERS_LIST, _dave);
        _wrappedMToken.startEarningFor(_dave);

        // NOTE: Give 100e6 more so that rounding errors do not prevent _swap of 1_000_000e6.
        _giveM(_dave, 100_100e6);
        _wrap(_dave, _dave, 100_100e6);

        assertEq(_wrappedMToken.balanceOf(_dave), 100_099_999999);

        swapAmountOut_ = _swap(_dave, _dave, address(_wrappedMToken), _USDC, 100_000e6);
    }

    function testFuzz_uniswapV3_earning(uint256 wmAlice_, uint256 bobUsdc_, uint256 wmDave_) public {
        wmAlice_ = bound(wmAlice_, 1, type(uint256).max); // Uniswap fails for 0 amounts
        wmAlice_ = wmAlice_ % _mToken.balanceOf(_mSource);
        bobUsdc_ = bobUsdc_ % 1e12;

        _giveM(_alice, wmAlice_ + 1e5);
        _wrap(_alice, _alice, wmAlice_ + 1e5);

        wmDave_ = bound(wmAlice_, 1, type(uint256).max);
        wmDave_ = wmDave_ % (_mToken.balanceOf(_mSource));

        deal(_USDC, _alice, wmAlice_ + 1e5);

        _mintNewPosition(_alice, _alice, wmAlice_);

        assertEq(_mToken.balanceOf(_alice), 0);
        _assertApproxEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += wmAlice_ + 1e5, "Wrapped M balance 1");
        assertEq(_mToken.balanceOf(_pool), 0);

        _assertApproxEq(_wrappedMToken.balanceOf(_alice), 1e5, "Alice WM balance");
        _assertApproxEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += wmAlice_, "Pool WM balance");

        assertEq(IERC20(_USDC).balanceOf(_alice), 1e5);
        assertEq(IERC20(_USDC).balanceOf(_pool), wmAlice_);

        _setClaimOverrideRecipient(_pool, _carol);

        _addToList(_EARNERS_LIST, _pool);
        _wrappedMToken.startEarningFor(_pool);

        // Check that the pool is earning WM
        assertTrue(_wrappedMToken.isEarning(_pool));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_pool), _carol);

        _assertApproxEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM, "Pool WM balance earning");
        assertEq(_wrappedMToken.accruedYieldOf(_pool), 0);

        uint128 idx_ = _mToken.currentIndex();

        // Move 1 year forward and check that yield has accrued
        vm.warp(block.timestamp + 365 days);

        uint128 newIdx_ = _mToken.currentIndex();

        // Wrapped M is earning M and has accrued yield.
        _assertApproxEq(
            _mToken.balanceOf(address(_wrappedMToken)), 
            _wrapperBalanceOfM = _wrapperBalanceOfM * newIdx_ / idx_, 
            "Wrapped M balance 2"
        );

        // `startEarningFor` has been called so WM yield has accrued in the pool.
        _assertApproxEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM, "Pool WM balance 2");
        _assertApproxEq(
            _wrappedMToken.accruedYieldOf(_pool),
            _poolAccruedYield = _poolBalanceOfWM * newIdx_ / idx_ - _poolBalanceOfWM,
            "Pool accrued yield"
        );

        // No excess yield has accrued in the wrapped M contract since the pool is the only earner.
        _assertApproxEq(_wrappedMToken.excess(), 1e5 * newIdx_ / idx_ - 1e5, "Excess yield"); 

        // _USDC balance is unchanged since no swap has been performed.
        assertEq(IERC20(_USDC).balanceOf(_pool), wmAlice_);

        // Bob decides to swap 1M _USDC in exchange of WM.
        deal(_USDC, _bob, bobUsdc_);

        uint256 swapAmountOut_ = _swap(_bob, _bob, _USDC, address(_wrappedMToken), bobUsdc_);

        // Check pool liquidity after the swap
        assertEq(IERC20(_USDC).balanceOf(_bob), 0);
        assertEq(IERC20(_USDC).balanceOf(_pool), wmAlice_ + bobUsdc_);

        _assertApproxEq(_wrappedMToken.balanceOf(_bob), swapAmountOut_, "Bob WM balance");

        // The swap has triggered a WM transfer and the yield has been claimed toi carol for the pool.
        _assertApproxEq(_wrappedMToken.balanceOf(_carol), _poolAccruedYield, "Carol WM balance");
        _assertApproxEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM -= swapAmountOut_ + 2, "Pool WM balance 3");
        _assertApproxEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield, "Pool accrued yield 2");

        _addToList(_EARNERS_LIST, _dave);
        _wrappedMToken.startEarningFor(_dave);

        // NOTE: Give 100e6 more so that rounding errors do not prevent _swap of 1_000_000e6.
        _giveM(_dave, wmDave_ + 1e5);
        _wrap(_dave, _dave, wmDave_ + 1e5);

        _assertApproxEq(_wrappedMToken.balanceOf(_dave), wmDave_ + 1e5, "Dave WM balance");

        swapAmountOut_ = _swap(_dave, _dave, address(_wrappedMToken), _USDC, wmDave_);
    }

    function _assertApproxEq(uint256 a, uint256 b, string memory message) internal pure {
        assertGe(a + 100, b, string.concat(message, " not greater"));
        assertGe(b + 100, a, string.concat(message, " not smaller"));
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
            deadline: block.timestamp
        });

        (tokenId_, liquidity_, amount0_, amount1_) = _positionManager.mint(params_);
    }

    function _swap(
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
            deadline: block.timestamp + 30 minutes,
            amountIn: amountIn_,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        vm.prank(account_);
        return _router.exactInputSingle(params);
    }
}
