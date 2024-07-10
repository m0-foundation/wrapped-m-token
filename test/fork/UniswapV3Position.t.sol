// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

import { IMTokenLike } from "../../src/interfaces/IMTokenLike.sol";
import { WrappedMToken } from "../../src/WrappedMToken.sol";

import { UniswapV3PositionManager } from "../utils/UniswapV3PositionManager.sol";
import { TestUtils } from "../utils/TestUtils.sol";

contract UniswapV3PositionForkTest is TestUtils {
    uint256 public mainnetFork;

    /// @dev USDC on Ethereum Mainnet
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev Uniswap V3 stable pair fee
    uint24 public constant POOL_FEE = 100; // 0.01% in bps

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    address internal _migrationAdmin = makeAddr("migrationAdmin");

    // Earner rate model address on mainnet
    address internal _earnerRateModel = address(0x6b198067E22d3A4e5aB8CeCda41a6Da56DBf5F59);

    // TTG Registrar address on mainnet
    address internal _registrar = address(0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c);

    // Minter Gateway address on mainnet
    address internal _minterGateway = address(0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E);

    // M token address on mainnet
    IMTokenLike internal _mToken = IMTokenLike(address(0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b));
    WrappedMToken internal _wrappedMToken;

    function setUp() external {
        mainnetFork = vm.createFork(vm.rpcUrl("mainnet"), 19_882_407); // block at which the M token index was first updated
        vm.selectFork(mainnetFork);

        vm.deal(_alice, 100 ether);

        _wrappedMToken = new WrappedMToken(address(_mToken), _migrationAdmin);

        _mockStartEarningMCall(_wrappedMToken, _registrar);

        vm.makePersistent(address(_mToken));
        vm.makePersistent(address(_wrappedMToken));
    }

    function test_uniswapV3Position_nonEarning() public {
        vm.selectFork(mainnetFork);

        UniswapV3PositionManager positionManager_ = new UniswapV3PositionManager();

        address pool_ = positionManager_.createPool(address(_wrappedMToken), USDC, POOL_FEE);

        uint256 mintAmount_ = 10_000_000e6;

        vm.prank(_minterGateway);
        _mToken.mint(_alice, mintAmount_);

        vm.prank(_alice);
        IERC20(address(_mToken)).approve(address(_wrappedMToken), mintAmount_);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, mintAmount_);

        deal(USDC, _alice, mintAmount_);

        vm.prank(_alice);
        _wrappedMToken.approve(address(positionManager_), mintAmount_);

        vm.prank(_alice);
        IERC20(USDC).approve(address(positionManager_), mintAmount_);

        vm.prank(_alice);
        positionManager_.mintNewPosition(POOL_FEE, address(_wrappedMToken), USDC, mintAmount_);

        assertEq(_wrappedMToken.balanceOf(pool_), mintAmount_);
        assertEq(IERC20(USDC).balanceOf(pool_), mintAmount_);

        // Check that WM is earning M
        assertTrue(_mToken.isEarning(address(_wrappedMToken)));

        // Check that the pool is not earning
        assertFalse(_wrappedMToken.isEarning(pool_));

        // Initialize index
        _mockUpdateIndexCall(_mToken, _registrar, _earnerRateModel, _EARNER_RATE);

        // Move 1 year forward and check that no yield has accrued
        uint32 timeElapsed_ = 365 days;
        vm.warp(block.timestamp + timeElapsed_);

        // Update index
        uint128 currentIndex_ = _mockUpdateIndexCall(_mToken, _registrar, _earnerRateModel, _EARNER_RATE);
        assertEq(currentIndex_, _getContinuousIndexAt(_EARNER_RATE, _EXP_SCALED_ONE, timeElapsed_));

        // Wrapped M is earning M and has accrued yield.
        uint240 accruedYield_ = _getAccruedYield(uint240(mintAmount_), _EXP_SCALED_ONE, currentIndex_);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), mintAmount_ + accruedYield_);

        // `startEarningFor` hasn't been called so no WM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(pool_), mintAmount_);
        assertEq(_wrappedMToken.accruedYieldOf(pool_), 0);

        // USDC balance is unchanged since no swap has been performed.
        assertEq(IERC20(USDC).balanceOf(pool_), mintAmount_);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), accruedYield_);
    }

    function test_uniswapV3Position_earning() public {
        vm.selectFork(mainnetFork);

        UniswapV3PositionManager positionManager_ = new UniswapV3PositionManager();

        address pool_ = positionManager_.createPool(address(_wrappedMToken), USDC, POOL_FEE);

        uint256 mintAmount_ = 10_000_000e6;

        vm.prank(_minterGateway);
        _mToken.mint(_alice, mintAmount_);

        vm.prank(_alice);
        IERC20(address(_mToken)).approve(address(_wrappedMToken), mintAmount_);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, mintAmount_);

        deal(USDC, _alice, mintAmount_);

        vm.prank(_alice);
        _wrappedMToken.approve(address(positionManager_), mintAmount_);

        vm.prank(_alice);
        IERC20(USDC).approve(address(positionManager_), mintAmount_);

        vm.prank(_alice);
        positionManager_.mintNewPosition(POOL_FEE, address(_wrappedMToken), USDC, mintAmount_);

        assertEq(_wrappedMToken.balanceOf(pool_), mintAmount_);
        assertEq(IERC20(USDC).balanceOf(pool_), mintAmount_);

        _mockIsEarning(_registrar, pool_, true);
        _wrappedMToken.startEarningFor(pool_);

        // Check that WM is earning M
        assertTrue(_mToken.isEarning(address(_wrappedMToken)));

        // Check that the pool is earning WM
        assertTrue(_wrappedMToken.isEarning(pool_));

        // Initialize index
        _mockUpdateIndexCall(_mToken, _registrar, _earnerRateModel, _EARNER_RATE);

        // Move 1 year forward and check that yield has accrued
        uint32 timeElapsed_ = 365 days;
        vm.warp(block.timestamp + timeElapsed_);

        // Update index
        uint128 currentIndex_ = _mockUpdateIndexCall(_mToken, _registrar, _earnerRateModel, _EARNER_RATE);
        assertEq(currentIndex_, _getContinuousIndexAt(_EARNER_RATE, _EXP_SCALED_ONE, timeElapsed_));

        // Wrapped M is earning M and has accrued yield.
        uint240 accruedYield_ = _getAccruedYield(uint240(mintAmount_), _EXP_SCALED_ONE, currentIndex_);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), mintAmount_ + accruedYield_);

        // `startEarningFor` has been called so WM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(pool_), mintAmount_);
        assertEq(_wrappedMToken.accruedYieldOf(pool_), accruedYield_);

        // No excess yield has accrued in the wrapped M contract since the pool is the only earner.
        assertEq(_wrappedMToken.excess(), 0);

        // USDC balance is unchanged since no swap has been performed.
        assertEq(IERC20(USDC).balanceOf(pool_), mintAmount_);

        // Bob decides to swap 1M USDC in exchange of WM.
        uint256 swapAmountIn_ = 1_000_000e6;
        deal(USDC, _bob, swapAmountIn_);

        vm.prank(_bob);
        IERC20(USDC).approve(address(positionManager_), swapAmountIn_);

        vm.prank(_bob);
        uint256 swapAmountOut_ = positionManager_.swapExactInputSingle(
            USDC,
            swapAmountIn_,
            address(_wrappedMToken),
            POOL_FEE
        );

        // Check pool liquidity after the swap
        assertEq(IERC20(USDC).balanceOf(_bob), 0);
        assertEq(IERC20(USDC).balanceOf(pool_), mintAmount_ + swapAmountIn_);
        assertEq(_wrappedMToken.balanceOf(_bob), swapAmountOut_);

        // The swap has triggered a WM transfer and the yield has been claimed for the pool.
        assertApproxEqAbs(_wrappedMToken.balanceOf(pool_), mintAmount_ - swapAmountOut_ + accruedYield_, 2);
    }
}
