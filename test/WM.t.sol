// SPDX-License-Identifier: UNTITLED

pragma solidity 0.8.23;

import { Test } from "../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../lib/protocol/src/libs/ContinuousIndexingMath.sol";

import { MockRateModel, MockTTGRegistrar } from "../lib/protocol/test/utils/Mocks.sol";

import { TTGRegistrarReader } from "../src/libs/TTGRegistrarReader.sol";

import { IWM } from "../src/interfaces/IWM.sol";

import { DeployBase } from "./utils/DeployBase.sol";

import { MTokenHarness } from "./utils/MTokenHarness.sol";
import { WMHarness } from "./utils/WMHarness.sol";
import { YMHarness } from "./utils/YMHarness.sol";

import { TestUtils } from "./utils/TestUtils.sol";

contract WMTest is TestUtils, DeployBase {
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
    YMHarness internal _yM;

    function setUp() external {
        _earnerRateModel = new MockRateModel();

        _earnerRateModel.setRate(_earnerRate);

        _registrar = new MockTTGRegistrar();

        _registrar.updateConfig(TTGRegistrarReader.EARNER_RATE_MODEL, address(_earnerRateModel));

        _mToken = new MTokenHarness(address(_registrar), _minterGateway);

        _mToken.setLatestRate(_earnerRate);

        _initialIndex = 1_000000000000;

        (_wM, _yM) = deploy(address(this), 4, address(_mToken), address(_registrar));
    }

    /* ============ constructor ============ */
    function test_constructor() external {
        assertEq(_wM.decimals(), _mToken.decimals());
        assertEq(_wM.mToken(), address(_mToken));
        assertEq(_wM.yMToken(), address(_yM));
        assertEq(_wM.ttgRegistrar(), address(_registrar));

        assertEq(_yM.decimals(), _mToken.decimals());
        assertEq(_yM.mToken(), address(_mToken));
        assertEq(_yM.wMToken(), address(_wM));
        assertEq(_wM.ttgRegistrar(), address(_registrar));
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(IWM.ZeroMToken.selector);
        new WMHarness(address(0), address(_yM), address(_registrar));
    }

    function test_constructor_zeroYMToken() external {
        vm.expectRevert(IWM.ZeroYMToken.selector);
        new WMHarness(address(_mToken), address(0), address(_registrar));
    }

    function test_constructor_zeroTTGRegistrar() external {
        vm.expectRevert(IWM.ZeroTTGRegistrar.selector);
        new WMHarness(address(_mToken), address(_yM), address(0));
    }

    /* ============ balanceOf ============ */
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
        balance_ = bound(balance_, 0, type(uint240).max);

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
        _wM.increaseBalanceOf(_alice, balance_);
        _mToken.increaseBalanceOf(address(_wM), balance_, true);
        _mToken.setIsEarning(address(_wM), true);

        // For the first deposit, YM is minted 1:1 with M.
        _yM.increaseBalanceOf(_alice, balance_);

        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        assertEq(_yM.balanceOf(_alice), balance_);
        assertEq(_yM.totalSupply(), balance_);

        // Balance of underlying M should be 0 since no interest has accrued yet.
        assertEq(_yM.balanceOfEarnedM(_alice), 0);

        // Balance of underlying M token should be the same.
        assertEq(_mToken.balanceOf(address(_wM)), balance_);
        assertEq(_mToken.totalSupply(), balance_);

        vm.warp(vm.getBlockTimestamp() + _ONE_YEAR);

        // Balance should stay the same.
        assertEq(_wM.balanceOf(_alice), balance_);
        assertEq(_wM.totalSupply(), balance_);

        uint128 deltaIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, _ONE_YEAR) - _initialIndex;
        uint240 earnedM_ = _getPresentAmountRoundedDown(uint112(balance_), deltaIndex_);
        uint256 expectedUnderlyingBalance_ = balance_ + earnedM_;

        // Balance of underlying M token should have increased.
        assertEq(_mToken.balanceOf(address(_wM)), expectedUnderlyingBalance_);
        assertEq(_mToken.totalSupply(), expectedUnderlyingBalance_);

        // Balance of underlying M should be equal to the earned M.
        assertEq(_yM.balanceOfEarnedM(_alice), earnedM_);

        // For the second deposit, YM is minted at the exchange rate between M and YM.
        _yM.increaseBalanceOf(_bob, balance_);

        _wM.totalEarnedM();

        assertEq(_yM.balanceOfEarnedM(_alice), earnedM_);
        // No accumulated earned M yet.
        assertEq(_yM.balanceOfEarnedM(_bob), 0);
    }

    function testFuzz_balanceOf_earner(uint256 balance_, uint256 elapsedTime_) external {
        balance_ = bound(balance_, 0, type(uint112).max);
        _wM.increaseBalanceOf(_alice, balance_);

        assertEq(_wM.balanceOf(_alice), balance_);

        elapsedTime_ = bound(elapsedTime_, 0, type(uint32).max);
        vm.warp(vm.getBlockTimestamp() + elapsedTime_);

        // Balance should stay the same.
        assertApproxEqAbs(_wM.balanceOf(_alice), balance_, 100);

        // Balance of the underlying should have compounded continuously by 10% for `elapsedTime_`.
        uint128 deltaIndex_ = _getContinuousIndexAt(_earnerRate, _initialIndex, uint32(elapsedTime_)) - _initialIndex;
        uint240 earnedM_ = _getPresentAmountRoundedDown(uint112(balance_), deltaIndex_);
        uint256 expectedUnderlyingBalance_ = balance_ + earnedM_;
    }
}
