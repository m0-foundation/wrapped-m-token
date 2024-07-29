// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { IERC20Extended } from "../lib/common/src/interfaces/IERC20Extended.sol";
import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { IWrappedMToken } from "../src/interfaces/IWrappedMToken.sol";

import { IndexingMath } from "../src/libs/IndexingMath.sol";

import { Proxy } from "../src/Proxy.sol";

import { MockM, MockRegistrar } from "./utils/Mocks.sol";
import { WrappedMTokenHarness } from "./utils/WrappedMTokenHarness.sol";

// NOTE: Due to `_indexOfTotalEarningSupply` a helper to overestimate `totalEarningSupply()`, there is little reason
//       to programmatically expect its value rather than ensuring `totalEarningSupply()` is acceptable.

contract WrappedMTokenTests is Test {
    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _CLAIM_DESTINATION_PREFIX = "wm_claim_destination";
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "wm_migrator_v1";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");

    address internal _migrationAdmin = makeAddr("migrationAdmin");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    address internal _vault = makeAddr("vault");

    uint128 internal _currentIndex;

    MockM internal _mToken;
    MockRegistrar internal _registrar;
    WrappedMTokenHarness internal _implementation;
    WrappedMTokenHarness internal _wrappedMToken;

    function setUp() external {
        _registrar = new MockRegistrar();
        _registrar.setVault(_vault);

        _mToken = new MockM();
        _mToken.setCurrentIndex(_EXP_SCALED_ONE);
        _mToken.setTtgRegistrar(address(_registrar));

        _implementation = new WrappedMTokenHarness(address(_mToken), _migrationAdmin);

        _wrappedMToken = WrappedMTokenHarness(address(new Proxy(address(_implementation))));

        _mToken.setCurrentIndex(_currentIndex = 1_100000068703);
    }

    /* ============ constructor ============ */
    function test_constructor() external view {
        assertEq(_wrappedMToken.implementation(), address(_implementation));
        assertEq(_wrappedMToken.mToken(), address(_mToken));
        assertEq(_wrappedMToken.registrar(), address(_registrar));
        assertEq(_wrappedMToken.vault(), _vault);
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(IWrappedMToken.ZeroMToken.selector);
        new WrappedMTokenHarness(address(0), address(0));
    }

    function test_constructor_zeroMigrationAdmin() external {
        vm.expectRevert(IWrappedMToken.ZeroMigrationAdmin.selector);
        new WrappedMTokenHarness(address(_mToken), address(0));
    }

    function test_constructor_zeroImplementation() external {
        vm.expectRevert();
        WrappedMTokenHarness(address(new Proxy(address(0))));
    }

    /* ============ wrap ============ */
    function test_wrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        _wrappedMToken.wrap(_alice, 0);
    }

    function test_wrap_invalidRecipient() external {
        _mToken.setBalanceOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_alice);
        _wrappedMToken.wrap(address(0), 1_000);
    }

    function test_wrap_invalidAmount() external {
        _mToken.setBalanceOf(_alice, uint256(type(uint240).max) + 1);

        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, uint256(type(uint240).max) + 1);
    }

    function test_wrap_toNonEarner() external {
        _mToken.setBalanceOf(_alice, 1_000);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, 1_000);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
        assertEq(_wrappedMToken.indexOfTotalEarningSupply(), 0);
    }

    function test_wrap_toEarner() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, true, _EXP_SCALED_ONE, 0);

        _mToken.setBalanceOf(_alice, 1_002);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, 999);

        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 908);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 998);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 908);
        assertEq(_wrappedMToken.totalEarningSupply(), 999);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, 1);

        // No change due to principal round down on wrap.
        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 908);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 998);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 908);
        assertEq(_wrappedMToken.totalEarningSupply(), 1000);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, 2);

        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 909);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 999);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 909);
        assertEq(_wrappedMToken.totalEarningSupply(), 1002);
    }

    /* ============ unwrap ============ */
    function test_unwrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        _wrappedMToken.unwrap(_alice, 0);
    }

    function test_unwrap_insufficientBalance_fromNonEarner() external {
        _wrappedMToken.setBalanceOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 1_000);
    }

    function test_unwrap_insufficientBalance_fromEarner() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 1_000);
    }

    function test_unwrap_fromNonEarner() external {
        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setBalanceOf(_alice, 1_000);

        _mToken.setBalanceOf(address(_wrappedMToken), 1_000);

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 500);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), 500);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 500);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
        assertEq(_wrappedMToken.indexOfTotalEarningSupply(), 0);

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 500);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
        assertEq(_wrappedMToken.indexOfTotalEarningSupply(), 0);
    }

    function test_unwrap_fromEarner() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);

        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);

        assertEq(_wrappedMToken.balanceOf(_alice), 999);

        _mToken.setBalanceOf(address(_wrappedMToken), 1_000);

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 1);

        // Change due to principal round up on unwrap.
        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 907);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 997);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 999);

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 997);

        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 2); // TODO: Fix?
    }

    /* ============ transfer ============ */
    function test_transfer_invalidRecipient() external {
        _wrappedMToken.setBalanceOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_alice);
        _wrappedMToken.transfer(address(0), 1_000);
    }

    function test_transfer_insufficientBalance_fromNonEarner_toNonEarner() external {
        _wrappedMToken.setBalanceOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1_000);
    }

    function test_transfer_insufficientBalance_fromEarner_toNonEarner() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1_000);
    }

    function test_transfer_fromNonEarner_toNonEarner() external {
        _wrappedMToken.setTotalNonEarningSupply(1_500);

        _wrappedMToken.setBalanceOf(_alice, 1_000);
        _wrappedMToken.setBalanceOf(_bob, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), 500);

        assertEq(_wrappedMToken.internalBalanceOf(_bob), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_500);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
        assertEq(_wrappedMToken.indexOfTotalEarningSupply(), 0);
    }

    function testFuzz_onlyWrap(bool earn_, uint240 wrapAmount_) external {
        _mToken.setBalanceOf(_alice, wrapAmount_);

        if (earn_) {
            _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
            _registrar.setListContains(_EARNERS_LIST, _alice, true);
            _wrappedMToken.startEarningFor(_alice);
        }

        bool revertCond1 = wrapAmount_ == 0;
        bool revertCond2 = earn_ && wrapAmount_ > uint256(type(uint112).max) * _currentIndex / _EXP_SCALED_ONE + 2;

        vm.startPrank(_alice);
        if (revertCond1) vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        else if (revertCond2) vm.expectRevert(UIntMath.InvalidUInt112.selector);
        _wrappedMToken.wrap(_alice, wrapAmount_);

        if (revertCond1 || revertCond2) return;

        uint256 supply = earn_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply();
        _assertApproxEq(supply, wrapAmount_, "total earning supply");
        _assertAndLimit(_alice, wrapAmount_, "alice balance");
    }

    function testFuzz_onlyUnwrap(bool earn_, uint240 wrapAmount_, uint240 unWrapAmount_) external {
        wrapAmount_ = wrapAmount_ % (uint240(type(uint112).max) * _currentIndex / _EXP_SCALED_ONE + 3);

        if (earn_) {
            _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
            _registrar.setListContains(_EARNERS_LIST, _alice, true);
            _wrappedMToken.startEarningFor(_alice);
        }

        if (wrapAmount_ > 0) {
            _mToken.setBalanceOf(address(_alice), wrapAmount_);
            vm.prank(_alice);
            _wrappedMToken.wrap(_alice, wrapAmount_);
        }

        bool revertCond1 = unWrapAmount_ == 0;
        bool revertCond2 = unWrapAmount_ > _wrappedMToken.balanceOf(_alice);

        if (revertCond1) vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        else if (revertCond2) 
            vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, 
                _alice, _wrappedMToken.balanceOf(_alice), unWrapAmount_));

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, unWrapAmount_);

        if (revertCond1 || revertCond2) return;
        
        uint256 supply_ = earn_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply();
        _assertApproxEqRatio(supply_, wrapAmount_ - unWrapAmount_, "total earning supply");
        _assertAndLimit(_alice, wrapAmount_ - unWrapAmount_, "alice balance");
    }

    function testFuzz_onlyTransfer(
        bool aliceEarn_, 
        bool bobEarn_, 
        uint240 aliceAmount_, 
        uint240 bobAmount_, 
        uint240 transferAmount_
    ) external {
        uint240 maxAmount_ = (uint240(type(uint112).max) * _currentIndex / _EXP_SCALED_ONE + 1);
        aliceAmount_ = aliceAmount_ % (maxAmount_ + 1);
        bobAmount_ = bobAmount_ % (maxAmount_ + 1);
        transferAmount_ = transferAmount_ % (maxAmount_ + 1);

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);
        _wrappedMToken.enableEarning();

        if (aliceEarn_) {
            _registrar.setListContains(_EARNERS_LIST, _alice, true);
            _wrappedMToken.startEarningFor(_alice);
        }
        if (bobEarn_) {
            _registrar.setListContains(_EARNERS_LIST, _bob, true);
            _wrappedMToken.startEarningFor(_bob);
        }

        if (aliceAmount_ > 0) {
            _mToken.setBalanceOf(address(_alice), aliceAmount_);
            vm.prank(_alice);
            _wrappedMToken.wrap(_alice, aliceAmount_);
        }

        if (bobAmount_ > 0) {
            _mToken.setBalanceOf(address(_bob), bobAmount_);
            vm.prank(_bob);
            _wrappedMToken.wrap(_bob, bobAmount_);
        }

        bool revertCond1 = transferAmount_ > _wrappedMToken.balanceOf(_alice);
        bool revertCond2 = bobEarn_ && bobAmount_ + transferAmount_ > maxAmount_ + 1;

        if (revertCond1) 
            vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, 
                _alice, _wrappedMToken.balanceOf(_alice), transferAmount_));
        else if (revertCond2) vm.expectRevert(UIntMath.InvalidUInt112.selector);

        vm.prank(_alice);        
        _wrappedMToken.transfer(_bob, transferAmount_);

        if (revertCond1 || revertCond2) return;

        _assertAndLimit(_alice, aliceAmount_ - transferAmount_, "alice balance");
        _assertAndLimit(_bob, bobAmount_ + transferAmount_, "bob balance");

        uint256 earningSupply_ = _wrappedMToken.totalEarningSupply();
        uint256 bobEarningSupply_ = bobEarn_ ? bobAmount_ + transferAmount_ : 0;
        uint256 aliceEarningSupply_ = aliceEarn_ ? aliceAmount_ - transferAmount_ : 0;
        _assertApproxEqRatio(earningSupply_, bobEarningSupply_ + aliceEarningSupply_, "earning supply");
        uint256 nonEarningSupply_ = _wrappedMToken.totalNonEarningSupply();
        uint256 bobNonEarningSupply_ = bobEarn_ ? 0 : bobAmount_ + transferAmount_;
        uint256 aliceNonEarningSupply_ = aliceEarn_ ? 0 : aliceAmount_ - transferAmount_;
        _assertApproxEqRatio(nonEarningSupply_, bobNonEarningSupply_ + aliceNonEarningSupply_, "non earning supply");
    }

    function testFuzz_onlyStartEarningFor(uint240 wrapAmount_) external {
        wrapAmount_ = wrapAmount_ % (uint240(type(uint112).max) * _currentIndex / _EXP_SCALED_ONE + 3);
        
        _mToken.setBalanceOf(address(_alice), wrapAmount_);
        vm.prank(_alice);
        if (wrapAmount_ > 0) _wrappedMToken.wrap(_alice, wrapAmount_);

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);
        _wrappedMToken.enableEarning();
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _wrappedMToken.startEarningFor(_alice);

        _assertAndLimit(_alice, wrapAmount_, "alice balance");

        _assertApproxEq(_wrappedMToken.totalEarningSupply(), wrapAmount_, "earning supply");
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
    }

    function testFuzz_onlyStopEarningFor(uint240 wrapAmount_) external {
        wrapAmount_ = wrapAmount_ % (uint240(type(uint112).max) * _currentIndex / _EXP_SCALED_ONE + 3);

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);
        _wrappedMToken.enableEarning();
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _wrappedMToken.startEarningFor(_alice);
        
        _mToken.setBalanceOf(address(_wrappedMToken), wrapAmount_);
        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, wrapAmount_);

        _registrar.setListContains(_EARNERS_LIST, _alice, false);
        _wrappedMToken.stopEarningFor(_alice);

        _assertAndLimit(_alice, wrapAmount_, "alice balance");

        _assertApproxEq(_wrappedMToken.totalNonEarningSupply(), wrapAmount_, "earning supply");
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
    }

    function testFuzz_claimFor(uint240 wrapAmount_, uint128 idxIncrease_) external {
        wrapAmount_ = wrapAmount_ % (uint240(type(uint112).max) * _currentIndex / _EXP_SCALED_ONE + 3);

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);
        _wrappedMToken.enableEarning();
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _wrappedMToken.startEarningFor(_alice);
        
        _mToken.setBalanceOf(address(_alice), wrapAmount_);
        vm.prank(_alice);
        if (wrapAmount_ > 0) _wrappedMToken.wrap(_alice, wrapAmount_);

        uint128 newIndex_ = _currentIndex + idxIncrease_ % _EXP_SCALED_ONE;
        _mToken.setCurrentIndex(newIndex_);

        uint256 newBalance_ = wrapAmount_ * newIndex_ / _currentIndex;

        _assertAndLimit(_alice, newBalance_, "alice balance");

        _assertApproxEq(_wrappedMToken.totalEarningSupply(), newBalance_, "total earning supply");
    }

    function testFuzz_claimExcess(uint240 aliceWrapAmount_, uint240 bobWrapAmount_, uint128 idxIncrease_) external {
        aliceWrapAmount_ = aliceWrapAmount_ % (uint240(type(uint112).max) * _currentIndex / _EXP_SCALED_ONE + 3);
        bobWrapAmount_ = bobWrapAmount_ % (uint240(type(uint112).max) * _currentIndex / _EXP_SCALED_ONE + 3);
        uint128 newIndex_ = _currentIndex + idxIncrease_ % _EXP_SCALED_ONE;
        
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);
        _wrappedMToken.enableEarning();
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _wrappedMToken.startEarningFor(_alice);
        
        _mToken.setBalanceOf(_alice, aliceWrapAmount_);
        vm.prank(_alice);
        if (aliceWrapAmount_ > 0) _wrappedMToken.wrap(_alice, aliceWrapAmount_);
        vm.stopPrank();

        _mToken.setBalanceOf(_bob, bobWrapAmount_);
        vm.prank(_bob);
        if (bobWrapAmount_ > 0) _wrappedMToken.wrap(_bob, bobWrapAmount_);

        _mToken.setBalanceOf(address(_wrappedMToken), (aliceWrapAmount_ + bobWrapAmount_) * newIndex_ / _currentIndex);
        _mToken.setCurrentIndex(newIndex_);

        _wrappedMToken.claimExcess();
        uint256 expectedBalance_ = bobWrapAmount_ * newIndex_ / _currentIndex - bobWrapAmount_;

        _assertApproxEq(_mToken.balanceOf(_vault), expectedBalance_, "vault");

        _assertApproxEq(_wrappedMToken.totalNonEarningSupply(), bobWrapAmount_, "earning supply");
        _assertApproxEq(_wrappedMToken.totalEarningSupply(), aliceWrapAmount_, "non earning supply");
    }

    struct TestData {
        uint256 aliceWrap1;
        uint256 aliceWrap2;
        uint256 bobWrap1;
        uint256 bobWrap2;
        uint256 aliceTransfer;
        uint256 bobUnwrap;
        bool aliceIsEarning;
        bool bobIsEarning;
        uint128[7] mTokenIdx;
    }

    function testFuzz_wrap_transfer_unwrap(TestData memory data_) external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _registrar.setListContains(_EARNERS_LIST, _bob, true);
        _wrappedMToken.enableEarning();

        data_.aliceWrap1 = data_.aliceWrap1 % 1_000e6;
        data_.aliceWrap2 = data_.aliceWrap2 % 1_000e6;
        data_.bobWrap1 = data_.bobWrap1 % 1_000e6;
        data_.bobWrap2 = data_.bobWrap2 % 1_000e6;

        uint128[8] memory mTokenIdx_;
        mTokenIdx_[0] = _currentIndex;
        for (uint i = 0; i < 7; i++) {
            data_.mTokenIdx[i] = data_.mTokenIdx[i] % _EXP_SCALED_ONE;
            mTokenIdx_[i + 1] = mTokenIdx_[i] + data_.mTokenIdx[i];
        }

        _mToken.setBalanceOf(_alice, data_.aliceWrap1 + data_.aliceWrap2);
        _mToken.setBalanceOf(_bob, data_.bobWrap1 + data_.bobWrap2);
        uint256 totalMBalance = data_.aliceWrap1 + data_.aliceWrap2 + data_.bobWrap1 + data_.bobWrap2;
        _mToken.setBalanceOf(address(_wrappedMToken), totalMBalance * mTokenIdx_[7] / mTokenIdx_[0]);

        if (data_.aliceIsEarning) _wrappedMToken.startEarningFor(_alice);

        vm.prank(_alice);
        if (data_.aliceWrap1 != 0) _wrappedMToken.wrap(_alice, data_.aliceWrap1);

        _mToken.setCurrentIndex(_currentIndex = _currentIndex + data_.mTokenIdx[0]);
        
        vm.prank(_bob);
        if (data_.bobWrap1 != 0) _wrappedMToken.wrap(_bob, data_.bobWrap1);
        
        if (data_.bobIsEarning) _wrappedMToken.startEarningFor(_bob);

        _mToken.setCurrentIndex(_currentIndex = _currentIndex + data_.mTokenIdx[1]);

        vm.prank(_bob);
        if (data_.bobWrap2 != 0) _wrappedMToken.wrap(_bob, data_.bobWrap2);

        _mToken.setCurrentIndex(_currentIndex = _currentIndex + data_.mTokenIdx[2]);

        vm.prank(_alice);
        if (data_.aliceWrap2 != 0) _wrappedMToken.wrap(_alice, data_.aliceWrap2);

        _mToken.setCurrentIndex(_currentIndex = _currentIndex + data_.mTokenIdx[3]);

        uint256 aliceBalance_ = data_.aliceIsEarning
            ? data_.aliceWrap1 * mTokenIdx_[4] / mTokenIdx_[0] + data_.aliceWrap2 * mTokenIdx_[4] / mTokenIdx_[3]
            : data_.aliceWrap1 + data_.aliceWrap2;
        aliceBalance_ = _assertAndLimit(_alice, aliceBalance_, "alice balance");
        uint256 firstAliceTransfer_ = data_.aliceTransfer % (aliceBalance_ + 1);
        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, firstAliceTransfer_);

        _mToken.setCurrentIndex(_currentIndex = _currentIndex + data_.mTokenIdx[4]);

        uint256 aliceBalanceLeft_ = aliceBalance_ - firstAliceTransfer_;
        if (data_.aliceIsEarning) aliceBalanceLeft_ = aliceBalanceLeft_ * mTokenIdx_[5] / mTokenIdx_[4];
        aliceBalanceLeft_ = _assertAndLimit(_alice, aliceBalanceLeft_, "alice remaining balance");
        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, aliceBalanceLeft_);
        assertEq(_wrappedMToken.balanceOf(_alice), 0);

        _mToken.setCurrentIndex(_currentIndex = _currentIndex + data_.mTokenIdx[5]);

        uint256 bobBalance_ = data_.aliceIsEarning 
            ? aliceBalance_ * mTokenIdx_[6] / mTokenIdx_[4] 
            : firstAliceTransfer_ * mTokenIdx_[6] / mTokenIdx_[4] + aliceBalanceLeft_ * mTokenIdx_[6] / mTokenIdx_[5];
        if (!data_.bobIsEarning) bobBalance_ = firstAliceTransfer_ + aliceBalanceLeft_;

        bobBalance_ += data_.bobIsEarning 
            ? data_.bobWrap1 * mTokenIdx_[6] / mTokenIdx_[1] + data_.bobWrap2 * mTokenIdx_[6] / mTokenIdx_[2]
            : data_.bobWrap1 + data_.bobWrap2;
        
        bobBalance_ = _assertAndLimit(_bob, bobBalance_, "bob balance");

        uint256 firstBobUnwrap_ = data_.bobUnwrap % (bobBalance_ + 1);
        vm.prank(_bob);
        if (firstBobUnwrap_ == 0) vm.expectRevert(); 
        _wrappedMToken.unwrap(_bob, firstBobUnwrap_);

        _mToken.setCurrentIndex(_currentIndex = _currentIndex + data_.mTokenIdx[6]);

        bobBalance_ = bobBalance_ - firstBobUnwrap_;
        if (data_.bobIsEarning) bobBalance_ = bobBalance_ * mTokenIdx_[7] / mTokenIdx_[6];
        bobBalance_ = _assertAndLimit(_bob, bobBalance_, "bob remaining balance");

        vm.prank(_bob);
        if (bobBalance_ == 0) vm.expectRevert();
        _wrappedMToken.unwrap(_bob, bobBalance_);
        assertEq(_wrappedMToken.balanceOf(_bob), 0);

        _assertApproxEq(_wrappedMToken.totalEarningSupply(), 0, "totalEarningSupply");
        _assertApproxEq(_wrappedMToken.totalNonEarningSupply(), 0, "totalNonEarningSupply");
    }

    function _assertAndLimit(address user_, uint256 expectedBalance_, string memory step_) internal returns(uint256) {
        _wrappedMToken.claimFor(user_);
        uint256 realBalance_ = _wrappedMToken.balanceOf(user_);
        _assertApproxEq(realBalance_, expectedBalance_, step_);
        return _wrappedMToken.balanceOf(user_);
    }

    function _assertApproxEq(uint256 a, uint256 b, string memory message) internal pure {
        assertGe(a + 100, b, string.concat(message, " not greater"));
        assertGe(b + 100, a, string.concat(message, " not smaller"));
    }

    function _assertApproxEqRatio(uint256 a, uint256 b, string memory message) internal pure {
        assertGe(a, b * 99999 / 1e6, string.concat(message, " not greater"));
        assertGe(b, a * 99999 / 1e6, string.concat(message, " not smaller"));
    }

    function testFuzz_transfer_fromNonEarner_toNonEarner(
        uint256 supply_,
        uint256 aliceBalance_,
        uint256 transferAmount_
    ) external {
        supply_ = bound(supply_, 1, type(uint112).max);
        aliceBalance_ = bound(aliceBalance_, 1, supply_);
        transferAmount_ = bound(transferAmount_, 1, aliceBalance_);
        uint256 bobBalance = supply_ - aliceBalance_;

        _wrappedMToken.setTotalNonEarningSupply(supply_);

        _wrappedMToken.setBalanceOf(_alice, aliceBalance_);
        _wrappedMToken.setBalanceOf(_bob, bobBalance);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, transferAmount_);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), aliceBalance_ - transferAmount_);
        assertEq(_wrappedMToken.internalBalanceOf(_bob), bobBalance + transferAmount_);

        assertEq(_wrappedMToken.totalNonEarningSupply(), supply_);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
        assertEq(_wrappedMToken.indexOfTotalEarningSupply(), 0);
    }

    function test_transfer_fromEarner_toNonEarner() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);
        _wrappedMToken.setTotalNonEarningSupply(500);

        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);

        _wrappedMToken.setBalanceOf(_bob, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 453);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 498);

        assertEq(_wrappedMToken.internalBalanceOf(_bob), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1);

        // Change due to principal round up on burn.
        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 451);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 496);

        assertEq(_wrappedMToken.internalBalanceOf(_bob), 1_001);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_001);
        assertEq(_wrappedMToken.totalEarningSupply(), 499);
    }

    function test_transfer_fromNonEarner_toEarner() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(455);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);
        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setBalanceOf(_alice, 1_000);

        _wrappedMToken.setAccountOf(_bob, true, _currentIndex, 500);

        assertEq(_wrappedMToken.internalBalanceOf(_bob), 499);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), 499);

        assertEq(_wrappedMToken.internalPrincipalOf(_bob), 909);
        assertEq(_wrappedMToken.internalIndexOf(_bob), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_bob), 999);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 499);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_002);
    }

    function test_transfer_fromEarner_toEarner() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(1_364);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);

        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);

        _wrappedMToken.setAccountOf(_bob, true, _currentIndex, 500);

        assertEq(_wrappedMToken.internalBalanceOf(_bob), 499);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 452);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 497);

        assertEq(_wrappedMToken.internalPrincipalOf(_bob), 909);
        assertEq(_wrappedMToken.internalIndexOf(_bob), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_bob), 999);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_501);
    }

    function test_transfer_nonEarnerToSelf() external {
        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setBalanceOf(_alice, 1_000);

        vm.prank(_alice);
        _wrappedMToken.transfer(_alice, 500);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
        assertEq(_wrappedMToken.indexOfTotalEarningSupply(), 0);
    }

    function test_transfer_earnerToSelf() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);

        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);
        assertEq(_wrappedMToken.balanceOf(_alice), 999);

        _mToken.setCurrentIndex((_currentIndex * 5) / 3); // 1833333447838

        _wrappedMToken.claimFor(_alice);

        assertEq(_wrappedMToken.balanceOf(_alice), 1666);

        vm.prank(_alice);
        _wrappedMToken.transfer(_alice, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 1666);
    }

    /* ============ startEarningFor ============ */
    function test_startEarningFor_notApprovedEarner() external {
        vm.expectRevert(IWrappedMToken.NotApprovedEarner.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor_earningIsDisabled() external {
        _registrar.setListContains(_EARNERS_LIST, _alice, true);

        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.startEarningFor(_alice);

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), false);

        _wrappedMToken.disableEarning();

        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setBalanceOf(_alice, 1_000);

        _registrar.setListContains(_EARNERS_LIST, _alice, true);

        vm.expectEmit();
        emit IWrappedMToken.StartedEarning(_alice);

        _wrappedMToken.startEarningFor(_alice);

        assertEq(_wrappedMToken.isEarning(_alice), true);
        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 909);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 999);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
    }

    function test_startEarning_overflow() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        uint256 aliceBalance_ = uint256(type(uint112).max) + 20;

        _mToken.setCurrentIndex(_currentIndex = _EXP_SCALED_ONE);

        _wrappedMToken.setTotalNonEarningSupply(aliceBalance_);

        _wrappedMToken.setBalanceOf(_alice, aliceBalance_);

        _registrar.setListContains(_EARNERS_LIST, _alice, true);

        vm.expectRevert(UIntMath.InvalidUInt112.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    /* ============ stopEarningFor ============ */
    function test_stopEarningForAccount_isApprovedEarner() external {
        _registrar.setListContains(_EARNERS_LIST, _alice, true);

        vm.expectRevert(IWrappedMToken.IsApprovedEarner.selector);
        _wrappedMToken.stopEarningFor(_alice);
    }

    function test_stopEarningFor() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);

        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);

        _registrar.setListContains(_EARNERS_LIST, _alice, false);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        _wrappedMToken.stopEarningFor(_alice);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), 999);
        assertEq(_wrappedMToken.isEarning(_alice), false);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 999);
        assertEq(_wrappedMToken.totalEarningSupply(), 1); // TODO: Fix?
    }

    /* ============ enableEarning ============ */
    function test_enableEarning_notApprovedEarner() external {
        vm.expectRevert(IWrappedMToken.NotApprovedEarner.selector);
        _wrappedMToken.enableEarning();
    }

    function test_enableEarning_earningCannotBeReenabled() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), false);

        _wrappedMToken.disableEarning();

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        vm.expectRevert(IWrappedMToken.EarningCannotBeReenabled.selector);
        _wrappedMToken.enableEarning();
    }

    function test_enableEarning() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        vm.expectEmit();
        emit IWrappedMToken.EarningEnabled(_currentIndex);

        _wrappedMToken.enableEarning();
    }

    /* ============ disableEarning ============ */
    function test_disableEarning_earningIsDisabled() external {
        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.disableEarning();

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), false);

        _wrappedMToken.disableEarning();

        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.disableEarning();
    }

    function test_disableEarning_approvedEarner() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        vm.expectRevert(IWrappedMToken.IsApprovedEarner.selector);
        _wrappedMToken.disableEarning();
    }

    function test_disableEarning() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), false);

        vm.expectEmit();
        emit IWrappedMToken.EarningDisabled(_currentIndex);

        _wrappedMToken.disableEarning();
    }

    /* ============ balanceOf ============ */
    function test_balanceOf_nonEarner() external {
        _wrappedMToken.setBalanceOf(_alice, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setBalanceOf(_alice, 1_000);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
    }

    function test_balanceOf_earner() external {
        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, true, _EXP_SCALED_ONE, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setBalanceOf(_alice, 1_000);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        _wrappedMToken.setIndexOf(_alice, 2 * _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
    }

    /* ============ totalNonEarningSupply ============ */
    function test_totalNonEarningSupply() external {
        _wrappedMToken.setTotalNonEarningSupply(500);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 500);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
    }

    function test_totalEarningSupply() external {
        // TODO: more variations
        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);

        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
    }

    /* ============ totalSupply ============ */
    function test_totalSupply_onlyTotalNonEarningSupply() external {
        _wrappedMToken.setTotalNonEarningSupply(500);

        assertEq(_wrappedMToken.totalSupply(), 500);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        assertEq(_wrappedMToken.totalSupply(), 1_000);
    }

    function test_totalSupply_onlyTotalEarningSupply() external {
        // TODO: more variations
        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);

        assertEq(_wrappedMToken.totalSupply(), 1_000);
    }

    function test_totalSupply() external {
        // TODO: more variations
        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);

        _wrappedMToken.setTotalNonEarningSupply(500);

        assertEq(_wrappedMToken.totalSupply(), 1_500);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        assertEq(_wrappedMToken.totalSupply(), 2_000);
    }

    /* ============ currentIndex ============ */
    function test_currentIndex() external {
        assertEq(_wrappedMToken.currentIndex(), 0);

        _mToken.setCurrentIndex(2 * _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.currentIndex(), 0);

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        assertEq(_wrappedMToken.currentIndex(), 2 * _EXP_SCALED_ONE);

        _mToken.setCurrentIndex(3 * _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.currentIndex(), 3 * _EXP_SCALED_ONE);

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), false);

        _wrappedMToken.disableEarning();

        assertEq(_wrappedMToken.currentIndex(), 3 * _EXP_SCALED_ONE);

        _mToken.setCurrentIndex(4 * _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.currentIndex(), 3 * _EXP_SCALED_ONE);
    }

    /* ============ utils ============ */
    function _getPrincipalAmountRoundedDown(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return IndexingMath.divide240By128Down(presentAmount_, index_);
    }

    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return IndexingMath.multiply112By128Down(principalAmount_, index_);
    }

    function _getPresentAmountRoundedUp(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return IndexingMath.multiply112By128Up(principalAmount_, index_);
    }
}
