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
        assertEq(_wrappedMToken.excess(), 51_276_223485);

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
        assertEq(_wrappedMToken.excess(), 5_127110);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC);

        /* ============ Bob Swaps USDC for wM ============ */

        deal(_USDC, _bob, 100_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 100_000e6);

        uint256 swapAmountOut_ = _swap(_bob, _bob, _USDC, address(_wrappedMToken), 100_000e6);

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
        assertEq(_wrappedMToken.excess(), 7299_827443);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC);

        /* ============ Dave Swaps wM for USDC ============ */

        _addToList(_EARNERS_LIST, _dave);
        _wrappedMToken.startEarningFor(_dave);

        _giveM(_dave, 100_100e6);
        _wrap(_dave, _dave, 100_100e6);

        assertEq(_mToken.balanceOf(_dave), 0);
        assertEq(_wrappedMToken.balanceOf(_dave), _daveBalanceOfWM += 100_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 100_099_999999);

        swapAmountOut_ = _swap(_dave, _dave, address(_wrappedMToken), _USDC, 100_000e6);

        // Check pool liquidity after the swap
        assertEq(IERC20(_USDC).balanceOf(_dave), _daveBalanceOfUSDC += 108_997_304660);
        assertEq(IERC20(_USDC).balanceOf(_pool), _poolBalanceOfUSDC -= 108_997_304660);
        assertEq(_wrappedMToken.balanceOf(_bob), _daveBalanceOfWM -= 9_199_173639);

        // The swap has triggered a wM transfer and the yield has been claimed to carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _poolAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_pool), _poolBalanceOfWM += 100_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_pool), _poolAccruedYield -= _poolAccruedYield);
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
            deadline: vm.getBlockTimestamp() + 30 minutes,
            amountIn: amountIn_,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        vm.prank(account_);
        return _router.exactInputSingle(params);
    }
}
