// SPDX-License-Identifier: UNTITLED

pragma solidity 0.8.23;

import { Test } from "../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../lib/protocol/src/libs/ContinuousIndexingMath.sol";

import { MockRateModel, MockTTGRegistrar } from "../lib/protocol/test/utils/Mocks.sol";
import { MTokenHarness } from "../lib/protocol/test/utils/MTokenHarness.sol";

import { TTGRegistrarReader } from "../src/libs/TTGRegistrarReader.sol";

import { IWM } from "../src/interfaces/IWM.sol";

import { WM } from "../src/WM.sol";

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

        vm.warp(vm.getBlockTimestamp() + 30_057_038); // Just enough time for the index to be ~1.1.

        _initialIndex = 1_100000068703;

        _wM = new WMHarness(address(_mToken), address(_registrar));
    }

    /* ============ constructor ============ */
    function test_constructor() external {
        assertEq(_wM.decimals(), _wM.decimals());
        assertEq(_wM.yieldToken(), address(_mToken));
        assertEq(_wM.ttgRegistrar(), address(_registrar));
        assertEq(_wM.latestIndex(), _initialIndex);
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(IWM.ZeroMToken.selector);
        new WM(address(0), address(_registrar));
    }

    function test_constructor_zeroTTGRegistrar() external {
        vm.expectRevert(IWM.ZeroTTGRegistrar.selector);
        new WM(address(_mToken), address(0));
    }

    /* ============ balanceOf ============ */
    function test_balanceOf_nonEarner() external {
        uint256 balance_ = 1_000e6;
        _wM.setBalance(_alice, balance_);

        assertEq(_wM.balanceOf(_alice), balance_);

        vm.warp(vm.getBlockTimestamp() + _ONE_YEAR);

        // Balance should stay the same.
        assertEq(_wM.balanceOf(_alice), balance_);
    }

    function testFuzz_balanceOf_nonEarner(uint256 balance_) external {
        _wM.setBalance(_alice, balance_);

        assertEq(_wM.balanceOf(_alice), balance_);

        vm.warp(vm.getBlockTimestamp() + _ONE_YEAR);

        // Balance should stay the same.
        assertEq(_wM.balanceOf(_alice), balance_);
    }

    function test_balanceOf_earner() external {
        uint112 balance_ = 1_000e6;
        _wM.setBalance(_alice, balance_);

        _wM.setIsEarning(_alice, true);
        _wM.setLatestIndex(_alice, _initialIndex);

        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.latestIndex(), _initialIndex);

        vm.warp(vm.getBlockTimestamp() + _ONE_YEAR);

        uint128 deltaIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, _ONE_YEAR) - _initialIndex;
        uint240 earnedM_ = _getPresentAmountRoundedDown(balance_, deltaIndex_);
        uint256 expectedBalance_ = balance_ + earnedM_;

        // Balance should have compounded continuously by 10% for a year.
        assertEq(_wM.balanceOf(_alice), expectedBalance_);
    }

    function testFuzz_balanceOf_earner(uint256 balance_, uint256 elapsedTime_) external {
        balance_ = bound(balance_, 0, type(uint112).max);
        _wM.setBalance(_alice, balance_);

        _wM.setIsEarning(_alice, true);
        _wM.setLatestIndex(_alice, _initialIndex);

        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.latestIndex(), _initialIndex);

        elapsedTime_ = bound(elapsedTime_, 0, type(uint32).max);
        vm.warp(vm.getBlockTimestamp() + elapsedTime_);

        uint128 deltaIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, uint32(elapsedTime_)) - _initialIndex;
        uint240 earnedM_ = _getPresentAmountRoundedDown(uint112(balance_), deltaIndex_);
        uint256 expectedBalance_ = balance_ + earnedM_;

        // Balance should have compounded continuously by 10% for `elapsedTime_`.
        assertApproxEqAbs(_wM.balanceOf(_alice), expectedBalance_, 100);
    }
}
