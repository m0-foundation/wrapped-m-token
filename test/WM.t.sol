// SPDX-License-Identifier: UNTITLED

pragma solidity 0.8.23;

import { console2 } from "../lib/forge-std/src/Test.sol";
import { ContinuousIndexingMath } from "../lib/protocol/src/libs/ContinuousIndexingMath.sol";

import { MockRateModel, MockTTGRegistrar } from "../lib/protocol/test/utils/Mocks.sol";

import { TTGRegistrarReader } from "../src/libs/TTGRegistrarReader.sol";

import { IWM } from "../src/interfaces/IWM.sol";

import { MTokenHarness } from "./utils/MTokenHarness.sol";
import { WMHarness } from "./utils/WMHarness.sol";

import { TestUtils } from "./utils/TestUtils.sol";

contract WMTest is TestUtils {
    uint32 internal constant _ONE_YEAR = 31_556_952;

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");
    address internal _minterGateway = makeAddr("minterGateway");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    uint32 internal _earnerRate = ContinuousIndexingMath.BPS_SCALED_ONE / 10; // 10% APY

    uint128 internal _initialIndex;

    MockRateModel internal _earnerRateModel;
    MockTTGRegistrar internal _registrar;
    MTokenHarness internal _mToken;

    WMHarness internal _wM;

    function setUp() external {
        _earnerRateModel = new MockRateModel();

        _earnerRateModel.setRate(_earnerRate);

        _registrar = new MockTTGRegistrar();

        _registrar.updateConfig(TTGRegistrarReader.EARNER_RATE_MODEL, address(_earnerRateModel));

        _mToken = new MTokenHarness(address(_registrar), _minterGateway);

        _mToken.setLatestRate(_earnerRate);

        _initialIndex = 1_000000000000;

        _wM = new WMHarness(address(_mToken), address(_registrar));
    }

    /* ============ constructor ============ */
    function test_constructor() external {
        assertEq(_wM.decimals(), _mToken.decimals());
        assertEq(_wM.mToken(), address(_mToken));
        assertEq(_wM.ttgRegistrar(), address(_registrar));
        assertEq(_wM.index(), _mToken.currentIndex());
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(IWM.ZeroMToken.selector);
        new WMHarness(address(0), address(_registrar));
    }

    function test_constructor_zeroTTGRegistrar() external {
        vm.expectRevert(IWM.ZeroTTGRegistrar.selector);
        new WMHarness(address(_mToken), address(0));
    }

    // /* ============ balanceOf ============ */
    function test_balanceOf_nonEarner() external {
        uint256 balance_ = 1_000e6;
        _wM.increaseBalanceOf(_alice, balance_);
        _mToken.increaseBalanceOf(address(_wM), balance_, false);

        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        // Balance of underlying M token should be the same.
        assertEq(_mToken.balanceOf(address(_wM)), balance_);
        assertEq(_mToken.totalSupply(), balance_);
    }

    function testFuzz_balanceOf_nonEarner(uint256 balance_) external {
        balance_ = bound(balance_, 0, type(uint112).max);

        _wM.increaseBalanceOf(_alice, balance_);
        _mToken.increaseBalanceOf(address(_wM), balance_, false);

        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        // Balance of underlying M token should be the same.
        assertEq(_mToken.balanceOf(address(_wM)), balance_);
        assertEq(_mToken.totalSupply(), balance_);
    }

    function test_balanceOf_earner() external {
        uint256 balance_ = 1_000e6;

        _wM.setIsEarning(_alice, _initialIndex, true);
        _wM.increaseBalanceOf(_alice, balance_);

        _mToken.setIsEarning(address(_wM), true);
        _mToken.increaseBalanceOf(address(_wM), balance_, true);

        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        // Balance of underlying M token should be the same.
        assertEq(_mToken.balanceOf(address(_wM)), balance_);
        assertEq(_mToken.totalSupply(), balance_);

        // Warp 1 year into the future.
        vm.warp(vm.getBlockTimestamp() + _ONE_YEAR);

        uint128 oneYearIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, _ONE_YEAR);
        uint128 deltaIndex_ = oneYearIndex_ - _initialIndex;
        uint240 earnedM_ = _getPresentAmountRoundedDown(
            _getPrincipalAmountRoundedDown(uint240(balance_), _initialIndex),
            deltaIndex_
        );

        uint256 expectedUnderlyingBalance_ = balance_ + earnedM_;

        // Balance of underlying M token should have increased.
        assertEq(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_);
        assertEq(_mToken.totalSupply(), expectedUnderlyingBalance_);

        // Balance of WM should stay the same since no claim has occurred.
        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);
    }

    // function testFuzz_balanceOf_earner(uint256 balance_, uint256 elapsedTime_) external {
    //     balance_ = bound(balance_, 0, type(uint112).max);
    //     _wM.increaseBalanceOf(_alice, balance_);
    //
    //     assertEq(_wM.balanceOf(_alice), balance_);
    //
    //     elapsedTime_ = bound(elapsedTime_, 0, type(uint32).max);
    //     vm.warp(vm.getBlockTimestamp() + elapsedTime_);
    //
    //     // Balance should stay the same.
    //     assertEq(_wM.balanceOf(_alice), balance_);
    //
    //     // Balance of the underlying should have compounded continuously by 10% for `elapsedTime_`.
    //     uint128 deltaIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, uint32(elapsedTime_)) - _initialIndex;
    //     uint240 earnedM_ = _getPresentAmountRoundedDown(
    //         _getPrincipalAmountRoundedDown(uint240(balance_), _initialIndex),
    //         deltaIndex_
    //     );
    //
    //     uint256 expectedUnderlyingBalance_ = balance_ + earnedM_;
    //
    //     // Balance of underlying M token should have increased.
    //     assertEq(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_);
    //     assertEq(_mToken.totalSupply(), expectedUnderlyingBalance_);
    //
    //     // Balance of WM should stay the same since no claim has occurred.
    //     assertEq(_wM.balanceOf(_alice), balance_);
    //     assertEq(_wM.totalSupply(), balance_);
    // }

    function test_balanceOf_earner_afterClaim() external {
        uint256 balance_ = 1_000e6;

        _wM.setIsEarning(_alice, _initialIndex, true);
        _wM.increaseBalanceOf(_alice, balance_);

        _mToken.setIsEarning(address(_wM), true);
        _mToken.increaseBalanceOf(address(_wM), balance_, true);

        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        // Balance of underlying M token should be the same.
        assertEq(_mToken.balanceOf(address(_wM)), balance_);
        assertEq(_mToken.totalSupply(), balance_);

        // Warp 1 year into the future.
        vm.warp(vm.getBlockTimestamp() + _ONE_YEAR);

        // Balance of WM should stay the same.
        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        uint128 oneYearIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, _ONE_YEAR);
        uint128 deltaIndex_ = oneYearIndex_ - _initialIndex;
        uint240 earnedM_ = _getPresentAmountRoundedDown(
            _getPrincipalAmountRoundedDown(uint240(balance_), _initialIndex),
            deltaIndex_
        );

        uint256 expectedUnderlyingBalance_ = balance_ + earnedM_;

        // Balance of underlying M token should have increased.
        assertEq(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_);
        assertEq(_mToken.totalSupply(), expectedUnderlyingBalance_);

        // Alice claims her earned M.
        vm.prank(_alice);
        _wM.claim(_alice);

        // WM balance of Alice should have increased.
        assertEq(_wM.balanceOf(_alice), _mToken.balanceOf(address(_wM)));
        assertEq(_wM.balanceOf(_alice), expectedUnderlyingBalance_);
        assertEq(_wM.totalSupply(), _mToken.totalSupply());
        assertEq(_wM.totalSupply(), expectedUnderlyingBalance_);

        // Warp half a year into the future.
        uint32 halfYear_ = _ONE_YEAR / 2;
        vm.warp(vm.getBlockTimestamp() + halfYear_);

        deltaIndex_ = _getContinuousIndexAt(_earnerRate, oneYearIndex_, halfYear_) - oneYearIndex_;
        earnedM_ = _getPresentAmountRoundedUp(
            _getPrincipalAmountRoundedDown(uint240(expectedUnderlyingBalance_), oneYearIndex_),
            deltaIndex_
        );

        expectedUnderlyingBalance_ += earnedM_;

        // Balance of underlying M token should have increased.
        assertEq(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_);
        assertEq(_mToken.totalSupply(), expectedUnderlyingBalance_);

        // Before claiming the earned M, the excess earned M
        // should be equivalent to amount that will be claimed by Alice.
        assertEq(_wM.totalExcessEarnedM(), expectedUnderlyingBalance_ - _mToken.totalSupply());

        // Alice claims her earned M.
        vm.prank(_alice);
        _wM.claim(_alice);

        // TODO: figure out why there is a 1 wei difference
        // WM balance of Alice should have increased.
        assertApproxEqAbs(_wM.balanceOf(_alice), _mToken.balanceOf(address(_wM)), 1);
        assertApproxEqAbs(_wM.balanceOf(_alice), expectedUnderlyingBalance_, 1);
        assertApproxEqAbs(_wM.totalSupply(), _mToken.totalSupply(), 1);
        assertApproxEqAbs(_wM.totalSupply(), expectedUnderlyingBalance_, 1);

        // After claiming, there shouldn't be any excess earned M.
        assertEq(_wM.totalExcessEarnedM(), 0);

        // Warp another year into the future.
        vm.warp(vm.getBlockTimestamp() + _ONE_YEAR);

        uint128 oneYearAndAHalfIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, _ONE_YEAR + _ONE_YEAR / 2);
        deltaIndex_ = _getContinuousIndexAt(_earnerRate, oneYearAndAHalfIndex_, _ONE_YEAR) - oneYearAndAHalfIndex_;
        earnedM_ = _getPresentAmountRoundedDown(
            _getPrincipalAmountRoundedDown(uint240(expectedUnderlyingBalance_), oneYearAndAHalfIndex_),
            deltaIndex_
        );

        expectedUnderlyingBalance_ += earnedM_;

        assertEq(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_);
        assertEq(_mToken.totalSupply(), expectedUnderlyingBalance_);

        assertEq(_wM.totalExcessEarnedM(), expectedUnderlyingBalance_ - _mToken.totalSupply());

        vm.prank(_alice);
        _wM.claim(_alice);

        assertApproxEqAbs(_wM.balanceOf(_alice), _mToken.balanceOf(address(_wM)), 1);
        assertApproxEqAbs(_wM.balanceOf(_alice), expectedUnderlyingBalance_, 1);
        assertApproxEqAbs(_wM.totalSupply(), _mToken.totalSupply(), 1);
        assertApproxEqAbs(_wM.totalSupply(), expectedUnderlyingBalance_, 1);

        assertEq(_wM.totalExcessEarnedM(), 0);
    }

    function test_balanceOf_earner_afterClaimAndDeposit() external {
        uint256 balance_ = 1_000e6;

        _wM.setIsEarning(_alice, _initialIndex, true);
        _wM.increaseBalanceOf(_alice, balance_);

        _mToken.setIsEarning(address(_wM), true);
        _mToken.increaseBalanceOf(address(_wM), balance_, true);

        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        // Balance of underlying M token should be the same.
        assertEq(_mToken.balanceOf(address(_wM)), balance_);
        assertEq(_mToken.totalSupply(), balance_);

        // Warp 1 year into the future.
        vm.warp(vm.getBlockTimestamp() + _ONE_YEAR);

        // Balance of WM should stay the same.
        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        uint128 oneYearIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, _ONE_YEAR);
        uint128 deltaIndex_ = oneYearIndex_ - _initialIndex;
        uint240 earnedM_ = _getPresentAmountRoundedDown(
            _getPrincipalAmountRoundedDown(uint240(balance_), _initialIndex),
            deltaIndex_
        );

        uint256 expectedUnderlyingBalance_ = balance_ + earnedM_;

        // Balance of underlying M token should have increased.
        assertEq(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_);
        assertEq(_mToken.totalSupply(), expectedUnderlyingBalance_);

        // Alice claims her earned M.
        vm.prank(_alice);
        _wM.claim(_alice);

        // WM balance of Alice should have increased.
        assertEq(_wM.balanceOf(_alice), _mToken.balanceOf(address(_wM)));
        assertEq(_wM.balanceOf(_alice), expectedUnderlyingBalance_);
        assertEq(_wM.totalSupply(), _mToken.totalSupply());
        assertEq(_wM.totalSupply(), expectedUnderlyingBalance_);

        // Alice deposits more M.
        balance_ = 1_500e6;
        expectedUnderlyingBalance_ += balance_;

        _mToken.setIsEarning(_alice, true);

        // Round up since M rounds up in favor of the protocol when transferring.
        _mToken.increaseBalanceOf(_alice, balance_ + 1, true);

        vm.prank(_alice);
        _mToken.approve(address(_wM), type(uint256).max);

        vm.prank(_alice);
        _wM.deposit(_alice, balance_);

        // Balance of underlying M token should have increased.
        assertApproxEqAbs(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_, 1);
        assertApproxEqAbs(_mToken.totalSupply(), expectedUnderlyingBalance_, 1);

        // WM balance of Alice should have increased.
        assertEq(_wM.balanceOf(_alice), expectedUnderlyingBalance_);
        assertApproxEqAbs(_wM.balanceOf(_alice), _mToken.balanceOf(address(_wM)), 1);
        assertEq(_wM.totalSupply(), expectedUnderlyingBalance_);
        assertApproxEqAbs(_wM.totalSupply(), _mToken.totalSupply(), 1);
    }

    function test_balanceOf_earner_afterClaimAndRedeem() external {
        uint256 balance_ = 1_000e6;

        _wM.setIsEarning(_alice, _initialIndex, true);
        _wM.increaseBalanceOf(_alice, balance_);

        _mToken.setIsEarning(address(_wM), true);
        _mToken.increaseBalanceOf(address(_wM), balance_, true);

        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        // Balance of underlying M token should be the same.
        assertEq(_mToken.balanceOf(address(_wM)), balance_);
        assertEq(_mToken.totalSupply(), balance_);

        // Warp 1 year into the future.
        vm.warp(vm.getBlockTimestamp() + _ONE_YEAR);

        // Balance of WM should stay the same.
        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        uint128 oneYearIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, _ONE_YEAR);
        uint128 deltaIndex_ = oneYearIndex_ - _initialIndex;
        uint240 earnedM_ = _getPresentAmountRoundedDown(
            _getPrincipalAmountRoundedDown(uint240(balance_), _initialIndex),
            deltaIndex_
        );

        uint256 expectedUnderlyingBalance_ = balance_ + earnedM_;

        // Balance of underlying M token should have increased.
        assertEq(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_);
        assertEq(_mToken.totalSupply(), expectedUnderlyingBalance_);

        // Alice claims her earned M.
        vm.prank(_alice);
        _wM.claim(_alice);

        // WM balance of Alice should have increased.
        assertEq(_wM.balanceOf(_alice), _mToken.balanceOf(address(_wM)));
        assertEq(_wM.balanceOf(_alice), expectedUnderlyingBalance_);
        assertEq(_wM.totalSupply(), _mToken.totalSupply());
        assertEq(_wM.totalSupply(), expectedUnderlyingBalance_);

        // Alice redeems WM.
        uint256 redeem_ = 500e6;
        expectedUnderlyingBalance_ -= redeem_;

        _mToken.setIsEarning(_alice, true);

        vm.prank(_alice);
        _wM.redeem(_alice, redeem_);

        // Balance of underlying M token should have decreased.
        assertApproxEqAbs(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_, 1);
        assertApproxEqAbs(_mToken.totalSupply(), _wM.totalSupply() + _mToken.balanceOf(_alice), 1);

        // WM balance of Alice should have decreased.
        assertEq(_wM.balanceOf(_alice), expectedUnderlyingBalance_);
        assertApproxEqAbs(_wM.balanceOf(_alice), _mToken.balanceOf(address(_wM)), 1);
        assertEq(_wM.totalSupply(), expectedUnderlyingBalance_);
        assertApproxEqAbs(_wM.totalSupply(), _mToken.totalSupply() - _mToken.balanceOf(_alice), 1);
    }
}
