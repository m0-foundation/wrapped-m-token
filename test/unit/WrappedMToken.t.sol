// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IndexingMath } from "../../lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { Proxy } from "../../lib/common/src/Proxy.sol";
import { Test } from "../../lib/forge-std/src/Test.sol";

import { IMTokenLike } from "../../src/interfaces/IMTokenLike.sol";
import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { MockM, MockRegistrar } from "../utils/Mocks.sol";
import { WrappedMTokenHarness } from "../utils/WrappedMTokenHarness.sol";

// TODO: All operations involving earners should include demonstration of accrued yield being added to their balance.
// TODO: Add relevant unit tests while earning enabled/disabled.
// TODO: Remove unneeded _wrappedMToken.enableEarning.
// TODO: Expect call for IMTokenLike(mToken).transfer

contract WrappedMTokenTests is Test {
    uint56 internal constant _EXP_SCALED_ONE = IndexingMath.EXP_SCALED_ONE;

    bytes32 internal constant _CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX = "wm_claim_override_recipient";

    bytes32 internal constant _EARNERS_LIST_NAME = "earners";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");

    address internal _excessDestination = makeAddr("excessDestination");
    address internal _migrationAdmin = makeAddr("migrationAdmin");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    uint128 internal _currentIndex;

    MockM internal _mToken;
    MockRegistrar internal _registrar;
    WrappedMTokenHarness internal _implementation;
    WrappedMTokenHarness internal _wrappedMToken;

    function setUp() external {
        _registrar = new MockRegistrar();

        _mToken = new MockM();
        _mToken.setCurrentIndex(_EXP_SCALED_ONE);

        _implementation = new WrappedMTokenHarness(
            address(_mToken),
            address(_registrar),
            _excessDestination,
            _migrationAdmin
        );

        _wrappedMToken = WrappedMTokenHarness(address(new Proxy(address(_implementation))));

        _mToken.setCurrentIndex(_currentIndex = 1_100000068703);
    }

    /* ============ constants ============ */
    function test_constants() external view {
        assertEq(_wrappedMToken.EARNERS_LIST_IGNORED_KEY(), "earners_list_ignored");
        assertEq(_wrappedMToken.EARNERS_LIST_NAME(), _EARNERS_LIST_NAME);
        assertEq(_wrappedMToken.CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX(), _CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX);
        assertEq(_wrappedMToken.MIGRATOR_KEY_PREFIX(), "wm_migrator_v2");
    }

    /* ============ constructor ============ */
    function test_constructor() external view {
        assertEq(_wrappedMToken.migrationAdmin(), _migrationAdmin);
        assertEq(_wrappedMToken.mToken(), address(_mToken));
        assertEq(_wrappedMToken.registrar(), address(_registrar));
        assertEq(_wrappedMToken.excessDestination(), _excessDestination);
        assertEq(_wrappedMToken.name(), "M (Wrapped) by M^0");
        assertEq(_wrappedMToken.symbol(), "wM");
        assertEq(_wrappedMToken.decimals(), 6);
        assertEq(_wrappedMToken.implementation(), address(_implementation));
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(IWrappedMToken.ZeroMToken.selector);
        new WrappedMTokenHarness(address(0), address(0), address(0), address(0));
    }

    function test_constructor_zeroRegistrar() external {
        vm.expectRevert(IWrappedMToken.ZeroRegistrar.selector);
        new WrappedMTokenHarness(address(_mToken), address(0), address(0), address(0));
    }

    function test_constructor_zeroExcessDestination() external {
        vm.expectRevert(IWrappedMToken.ZeroExcessDestination.selector);
        new WrappedMTokenHarness(address(_mToken), address(_registrar), address(0), address(0));
    }

    function test_constructor_zeroMigrationAdmin() external {
        vm.expectRevert(IWrappedMToken.ZeroMigrationAdmin.selector);
        new WrappedMTokenHarness(address(_mToken), address(_registrar), _excessDestination, address(0));
    }

    function test_constructor_zeroImplementation() external {
        vm.expectRevert();
        WrappedMTokenHarness(address(new Proxy(address(0))));
    }

    /* ============ _wrap ============ */
    function test_internalWrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        _wrappedMToken.internalWrap(_alice, _alice, 0);
    }

    function test_internalWrap_invalidRecipient() external {
        _mToken.setBalanceOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        _wrappedMToken.internalWrap(_alice, address(0), 1_000);
    }

    function test_internalWrap_toNonEarner() external {
        _mToken.setBalanceOf(_alice, 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 1_000);

        assertEq(_wrappedMToken.internalWrap(_alice, _alice, 1_000), 1_000);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
    }

    function test_internalWrap_toEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 0, _EXP_SCALED_ONE);

        _mToken.setBalanceOf(_alice, 1_002);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 999);

        assertEq(_wrappedMToken.internalWrap(_alice, _alice, 999), 999);

        assertEq(_wrappedMToken.lastIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_alice), 999);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 909);
        assertEq(_wrappedMToken.totalEarningSupply(), 999);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 1);

        assertEq(_wrappedMToken.internalWrap(_alice, _alice, 1), 1);

        // No change due to principal round down on wrap.
        assertEq(_wrappedMToken.lastIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 910);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 2);

        assertEq(_wrappedMToken.internalWrap(_alice, _alice, 2), 2);

        assertEq(_wrappedMToken.lastIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_002);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 912);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_002);
    }

    /* ============ wrap ============ */
    function test_wrap_invalidAmount() external {
        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, uint256(type(uint240).max) + 1);
    }

    function testFuzz_wrap(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balance_,
        uint240 wrapAmount_,
        uint128 accountIndex_,
        uint128 currentIndex_
    ) external {
        accountEarning_ = earningEnabled_ && accountEarning_;

        if (earningEnabled_) {
            _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
        }

        accountIndex_ = uint128(bound(accountIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        balance_ = uint240(bound(balance_, 0, _getMaxAmount(accountIndex_)));

        if (accountEarning_) {
            _wrappedMToken.setAccountOf(_alice, balance_, accountIndex_);
            _wrappedMToken.setTotalEarningSupply(balance_);

            _wrappedMToken.setPrincipalOfTotalEarningSupply(
                IndexingMath.getPrincipalAmountRoundedDown(balance_, accountIndex_)
            );
        } else {
            _wrappedMToken.setAccountOf(_alice, balance_);
            _wrappedMToken.setTotalNonEarningSupply(balance_);
        }

        currentIndex_ = uint128(bound(currentIndex_, accountIndex_, 10 * _EXP_SCALED_ONE));
        wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(currentIndex_) - balance_));

        _mToken.setCurrentIndex(_currentIndex = currentIndex_);
        _mToken.setBalanceOf(_alice, wrapAmount_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.wrap(_alice, wrapAmount_);

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + accruedYield_ + wrapAmount_);

        assertEq(
            accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(),
            _wrappedMToken.balanceOf(_alice)
        );
    }

    /* ============ wrap entire balance ============ */
    function test_wrap_entireBalance_invalidAmount() external {
        _mToken.setBalanceOf(_alice, uint256(type(uint240).max) + 1);

        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, uint256(type(uint240).max) + 1);
    }

    function testFuzz_wrap_entireBalance(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balance_,
        uint240 wrapAmount_,
        uint128 accountIndex_,
        uint128 currentIndex_
    ) external {
        accountEarning_ = earningEnabled_ && accountEarning_;

        if (earningEnabled_) {
            _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
        }

        accountIndex_ = uint128(bound(accountIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        balance_ = uint240(bound(balance_, 0, _getMaxAmount(accountIndex_)));

        if (accountEarning_) {
            _wrappedMToken.setAccountOf(_alice, balance_, accountIndex_);
            _wrappedMToken.setTotalEarningSupply(balance_);

            _wrappedMToken.setPrincipalOfTotalEarningSupply(
                IndexingMath.getPrincipalAmountRoundedDown(balance_, accountIndex_)
            );
        } else {
            _wrappedMToken.setAccountOf(_alice, balance_);
            _wrappedMToken.setTotalNonEarningSupply(balance_);
        }

        currentIndex_ = uint128(bound(currentIndex_, accountIndex_, 10 * _EXP_SCALED_ONE));
        wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(currentIndex_) - balance_));

        _mToken.setCurrentIndex(_currentIndex = currentIndex_);
        _mToken.setBalanceOf(_alice, wrapAmount_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.wrap(_alice);

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + accruedYield_ + wrapAmount_);

        assertEq(
            accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(),
            _wrappedMToken.balanceOf(_alice)
        );
    }

    /* ============ wrapWithPermit vrs ============ */
    function test_wrapWithPermit_vrs_invalidAmount() external {
        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _wrappedMToken.wrapWithPermit(_alice, uint256(type(uint240).max) + 1, 0, 0, bytes32(0), bytes32(0));
    }

    function testFuzz_wrapWithPermit_vrs(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balance_,
        uint240 wrapAmount_,
        uint128 accountIndex_,
        uint128 currentIndex_
    ) external {
        accountEarning_ = earningEnabled_ && accountEarning_;

        if (earningEnabled_) {
            _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
        }

        accountIndex_ = uint128(bound(accountIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        balance_ = uint240(bound(balance_, 0, _getMaxAmount(accountIndex_)));

        if (accountEarning_) {
            _wrappedMToken.setAccountOf(_alice, balance_, accountIndex_);
            _wrappedMToken.setTotalEarningSupply(balance_);

            _wrappedMToken.setPrincipalOfTotalEarningSupply(
                IndexingMath.getPrincipalAmountRoundedDown(balance_, accountIndex_)
            );
        } else {
            _wrappedMToken.setAccountOf(_alice, balance_);
            _wrappedMToken.setTotalNonEarningSupply(balance_);
        }

        currentIndex_ = uint128(bound(currentIndex_, accountIndex_, 10 * _EXP_SCALED_ONE));
        wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(currentIndex_) - balance_));

        _mToken.setCurrentIndex(_currentIndex = currentIndex_);
        _mToken.setBalanceOf(_alice, wrapAmount_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.wrapWithPermit(_alice, wrapAmount_, 0, 0, bytes32(0), bytes32(0));

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + accruedYield_ + wrapAmount_);

        assertEq(
            accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(),
            _wrappedMToken.balanceOf(_alice)
        );
    }

    /* ============ wrapWithPermit signature ============ */
    function test_wrapWithPermit_signature_invalidAmount() external {
        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _wrappedMToken.wrapWithPermit(_alice, uint256(type(uint240).max) + 1, 0, hex"");
    }

    function testFuzz_wrapWithPermit_signature(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balance_,
        uint240 wrapAmount_,
        uint128 accountIndex_,
        uint128 currentIndex_
    ) external {
        accountEarning_ = earningEnabled_ && accountEarning_;

        if (earningEnabled_) {
            _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
        }

        accountIndex_ = uint128(bound(accountIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        balance_ = uint240(bound(balance_, 0, _getMaxAmount(accountIndex_)));

        if (accountEarning_) {
            _wrappedMToken.setAccountOf(_alice, balance_, accountIndex_);
            _wrappedMToken.setTotalEarningSupply(balance_);

            _wrappedMToken.setPrincipalOfTotalEarningSupply(
                IndexingMath.getPrincipalAmountRoundedDown(balance_, accountIndex_)
            );
        } else {
            _wrappedMToken.setAccountOf(_alice, balance_);
            _wrappedMToken.setTotalNonEarningSupply(balance_);
        }

        currentIndex_ = uint128(bound(currentIndex_, accountIndex_, 10 * _EXP_SCALED_ONE));
        wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(currentIndex_) - balance_));

        _mToken.setCurrentIndex(_currentIndex = currentIndex_);
        _mToken.setBalanceOf(_alice, wrapAmount_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.wrapWithPermit(_alice, wrapAmount_, 0, hex"");

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + accruedYield_ + wrapAmount_);

        assertEq(
            accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(),
            _wrappedMToken.balanceOf(_alice)
        );
    }

    /* ============ _unwrap ============ */
    function test_internalUnwrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        _wrappedMToken.internalUnwrap(_alice, _alice, 0);
    }

    function test_internalUnwrap_insufficientBalance_fromNonEarner() external {
        _wrappedMToken.setAccountOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        _wrappedMToken.internalUnwrap(_alice, _alice, 1_000);
    }

    function test_internalUnwrap_insufficientBalance_fromEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 999, _currentIndex);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        _wrappedMToken.internalUnwrap(_alice, _alice, 1_000);
    }

    function test_internalUnwrap_fromNonEarner() external {
        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        _mToken.setBalanceOf(address(_wrappedMToken), 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 500);

        vm.expectCall(address(_mToken), abi.encodeWithSelector(IMTokenLike.transfer.selector, _alice, 500));

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 500), 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 500);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 500);

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 500), 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
    }

    function test_internalUnwrap_fromNonEarner_toMEarnerWhileWrapperNotEarning() external {
        _wrappedMToken.setTotalNonEarningSupply(500);

        _wrappedMToken.setAccountOf(_alice, 500);

        _mToken.setBalanceOf(address(_wrappedMToken), 501);

        _mToken.setIsEarning(_bob, true);
        _mToken.setPrincipalBalanceOf(_bob, 905);

        vm.expectCall(address(_mToken), abi.encodeWithSelector(IMTokenLike.transfer.selector, _bob, 501));

        assertEq(_wrappedMToken.internalUnwrap(_alice, _bob, 500), 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
    }

    function test_internalUnwrap_fromEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, _currentIndex);

        _mToken.setBalanceOf(address(_wrappedMToken), 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 1);

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 1), 1);

        // Change due to principal round up on unwrap.
        assertEq(_wrappedMToken.lastIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_alice), 999);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 999);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 999);

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 999), 999);

        assertEq(_wrappedMToken.lastIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
    }

    /* ============ unwrap ============ */
    function test_unwrap_invalidAmount() external {
        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, uint256(type(uint240).max) + 1);
    }

    function testFuzz_unwrap(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balance_,
        uint240 unwrapAmount_,
        uint128 accountIndex_,
        uint128 currentIndex_
    ) external {
        accountEarning_ = earningEnabled_ && accountEarning_;

        if (earningEnabled_) {
            _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
        }

        accountIndex_ = uint128(bound(accountIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        balance_ = uint240(bound(balance_, 0, _getMaxAmount(accountIndex_)));

        if (accountEarning_) {
            _wrappedMToken.setAccountOf(_alice, balance_, accountIndex_);
            _wrappedMToken.setTotalEarningSupply(balance_);

            _wrappedMToken.setPrincipalOfTotalEarningSupply(
                IndexingMath.getPrincipalAmountRoundedDown(balance_, accountIndex_)
            );
        } else {
            _wrappedMToken.setAccountOf(_alice, balance_);
            _wrappedMToken.setTotalNonEarningSupply(balance_);
        }

        currentIndex_ = uint128(bound(currentIndex_, accountIndex_, 10 * _EXP_SCALED_ONE));

        _mToken.setCurrentIndex(_currentIndex = currentIndex_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        _mToken.setBalanceOf(address(_wrappedMToken), balance_ + accruedYield_);

        unwrapAmount_ = uint240(bound(unwrapAmount_, 0, (11 * (balance_ + accruedYield_)) / 10));

        if (unwrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else if (unwrapAmount_ > balance_ + accruedYield_) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IWrappedMToken.InsufficientBalance.selector,
                    _alice,
                    balance_ + accruedYield_,
                    unwrapAmount_
                )
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(_alice, address(0), unwrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.unwrap(_alice, unwrapAmount_);

        if ((unwrapAmount_ == 0) || (unwrapAmount_ > balance_ + accruedYield_)) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + accruedYield_ - unwrapAmount_);

        assertEq(
            accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(),
            _wrappedMToken.balanceOf(_alice)
        );
    }

    /* ============ unwrap entire balance ============ */
    function testFuzz_unwrap_entireBalance(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balance_,
        uint128 accountIndex_,
        uint128 currentIndex_
    ) external {
        accountEarning_ = earningEnabled_ && accountEarning_;

        if (earningEnabled_) {
            _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
        }

        accountIndex_ = uint128(bound(accountIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        balance_ = uint240(bound(balance_, 0, _getMaxAmount(accountIndex_)));

        if (accountEarning_) {
            _wrappedMToken.setAccountOf(_alice, balance_, accountIndex_);
            _wrappedMToken.setTotalEarningSupply(balance_);

            _wrappedMToken.setPrincipalOfTotalEarningSupply(
                IndexingMath.getPrincipalAmountRoundedDown(balance_, accountIndex_)
            );
        } else {
            _wrappedMToken.setAccountOf(_alice, balance_);
            _wrappedMToken.setTotalNonEarningSupply(balance_);
        }

        currentIndex_ = uint128(bound(currentIndex_, accountIndex_, 10 * _EXP_SCALED_ONE));

        _mToken.setCurrentIndex(_currentIndex = currentIndex_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        _mToken.setBalanceOf(address(_wrappedMToken), balance_ + accruedYield_);

        if (balance_ + accruedYield_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(_alice, address(0), balance_ + accruedYield_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.unwrap(_alice);

        if (balance_ + accruedYield_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), 0);

        assertEq(accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(), 0);
    }

    function testFuzz_wrap_unwrap_roundtripFull(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balance_,
        uint240 wrapAmount_,
        uint128 accountIndex_,
        uint128 currentIndex_
    ) external {
        accountEarning_ = earningEnabled_ && accountEarning_;

        if (earningEnabled_) {
            _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
        }

        accountIndex_ = uint128(bound(accountIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        // balance_ = uint240(bound(balance_, 0, _getMaxAmount(accountIndex_)));
        // restrict to smaller amounts to make it's not just an issue with impractical values
        balance_ = uint240(bound(balance_, 0, 1e12));

        if (accountEarning_) {
            _wrappedMToken.setAccountOf(_alice, balance_, accountIndex_);
            _wrappedMToken.setTotalEarningSupply(balance_);

            _wrappedMToken.setPrincipalOfTotalEarningSupply(
                IndexingMath.getPrincipalAmountRoundedDown(balance_, accountIndex_)
            );
        } else {
            _wrappedMToken.setAccountOf(_alice, balance_);
            _wrappedMToken.setTotalNonEarningSupply(balance_);
        }

        currentIndex_ = uint128(bound(currentIndex_, accountIndex_, 10 * _EXP_SCALED_ONE));
        // wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(currentIndex_) - balance_));
        // restrict to smaller amounts to make it's not just an issue with impractical values
        wrapAmount_ = uint240(bound(wrapAmount_, 0, 1e12));

        _mToken.setCurrentIndex(_currentIndex = currentIndex_);
        _mToken.setBalanceOf(_alice, wrapAmount_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice);

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + accruedYield_ + wrapAmount_);

        assertEq(
            accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(),
            _wrappedMToken.balanceOf(_alice)
        );
    
        // Goal: check if roundtrip behavior is an issue if the wrapped M token is eating the rounding issues

        // if (balance_ + accruedYield_ == 0) {
        //     vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        // } else {
        //     vm.expectEmit();
        //     emit IERC20.Transfer(_alice, address(0), balance_ + accruedYield_);
        // }

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice);

        if (balance_ + accruedYield_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), 0);

        assertEq(accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(), 0);        
    }

    /* ============ claimFor ============ */
    function test_claimFor_nonEarner() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.prank(_alice);
        assertEq(_wrappedMToken.claimFor(_alice), 0);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
    }

    function test_claimFor_earner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 1_000, _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        assertEq(_wrappedMToken.claimFor(_alice), 100);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_100);
    }

    function test_claimFor_earner_withOverrideRecipient() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _registrar.set(
            keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, _alice)),
            bytes32(uint256(uint160(_bob)))
        );

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 1_000, _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _bob, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 100);

        assertEq(_wrappedMToken.claimFor(_alice), 100);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_bob), 100);
    }

    function testFuzz_claimFor(uint240 balance_, uint128 accountIndex_, uint128 index_, bool claimOverride_) external {
        accountIndex_ = uint128(bound(index_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        balance_ = uint240(bound(balance_, 0, _getMaxAmount(accountIndex_)));
        index_ = uint128(bound(index_, accountIndex_, 10 * _EXP_SCALED_ONE));

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        if (claimOverride_) {
            _registrar.set(
                keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, _alice)),
                bytes32(uint256(uint160(_charlie)))
            );
        }

        _wrappedMToken.enableEarning();

        _wrappedMToken.setTotalEarningSupply(balance_);

        _wrappedMToken.setAccountOf(_alice, balance_, accountIndex_);

        _mToken.setCurrentIndex(index_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        if (accruedYield_ != 0) {
            vm.expectEmit();
            emit IWrappedMToken.Claimed(_alice, claimOverride_ ? _charlie : _alice, accruedYield_);

            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, accruedYield_);
        }

        assertEq(_wrappedMToken.claimFor(_alice), accruedYield_);

        assertEq(
            _wrappedMToken.totalSupply(),
            _wrappedMToken.balanceOf(_alice) + _wrappedMToken.balanceOf(_bob) + _wrappedMToken.balanceOf(_charlie)
        );
    }

    /* ============ claimExcess ============ */
    function testFuzz_claimExcess(
        uint128 index_,
        uint240 totalNonEarningSupply_,
        uint112 principalOfTotalEarningSupply_,
        uint240 mBalance_
    ) external {
        index_ = uint128(bound(index_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));

        totalNonEarningSupply_ = uint240(bound(totalNonEarningSupply_, 0, _getMaxAmount(index_)));

        uint240 totalEarningSupply_ = uint112(bound(principalOfTotalEarningSupply_, 0, _getMaxAmount(index_)));

        principalOfTotalEarningSupply_ = uint112(totalEarningSupply_ / index_);

        mBalance_ = uint240(bound(mBalance_, totalNonEarningSupply_ + totalEarningSupply_, type(uint240).max));

        _mToken.setBalanceOf(address(_wrappedMToken), mBalance_);
        _wrappedMToken.setTotalNonEarningSupply(totalNonEarningSupply_);
        _wrappedMToken.setPrincipalOfTotalEarningSupply(principalOfTotalEarningSupply_);

        _mToken.setCurrentIndex(index_);

        uint240 expectedExcess_ = _wrappedMToken.excess();

        vm.expectCall(
            address(_mToken),
            abi.encodeCall(_mToken.transfer, (_wrappedMToken.excessDestination(), expectedExcess_))
        );

        vm.expectEmit();
        emit IWrappedMToken.ExcessClaimed(expectedExcess_);

        assertEq(_wrappedMToken.claimExcess(), expectedExcess_);
        assertEq(_wrappedMToken.excess(), 0);
    }

    /* ============ transfer ============ */
    function test_transfer_invalidRecipient() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_alice);
        _wrappedMToken.transfer(address(0), 1_000);
    }

    function test_transfer_insufficientBalance_fromNonEarner_toNonEarner() external {
        _wrappedMToken.setAccountOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1_000);
    }

    function test_transfer_insufficientBalance_fromEarner_toNonEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 999, _currentIndex);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1_000);
    }

    function test_transfer_fromNonEarner_toNonEarner() external {
        _wrappedMToken.setTotalNonEarningSupply(1_500);

        _wrappedMToken.setAccountOf(_alice, 1_000);
        _wrappedMToken.setAccountOf(_bob, 500);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_500);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
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

        _wrappedMToken.setAccountOf(_alice, aliceBalance_);
        _wrappedMToken.setAccountOf(_bob, bobBalance);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, transferAmount_);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, transferAmount_);

        assertEq(_wrappedMToken.balanceOf(_alice), aliceBalance_ - transferAmount_);
        assertEq(_wrappedMToken.balanceOf(_bob), bobBalance + transferAmount_);

        assertEq(_wrappedMToken.totalNonEarningSupply(), supply_);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
    }

    function test_transfer_fromEarner_toNonEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setTotalNonEarningSupply(500);

        _wrappedMToken.setAccountOf(_alice, 1_000, _currentIndex);
        _wrappedMToken.setAccountOf(_bob, 500);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.lastIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 500);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 1);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1);

        assertEq(_wrappedMToken.lastIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_alice), 499);

        assertEq(_wrappedMToken.balanceOf(_bob), 1_001);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_001);
        assertEq(_wrappedMToken.totalEarningSupply(), 499);
    }

    function test_transfer_fromNonEarner_toEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(454);
        _wrappedMToken.setTotalEarningSupply(500);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);
        _wrappedMToken.setAccountOf(_bob, 500, _currentIndex);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        assertEq(_wrappedMToken.lastIndexOf(_bob), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 500);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
    }

    function test_transfer_fromEarner_toEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(1_363);
        _wrappedMToken.setTotalEarningSupply(1_500);

        _wrappedMToken.setAccountOf(_alice, 1_000, _currentIndex);
        _wrappedMToken.setAccountOf(_bob, 500, _currentIndex);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.lastIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        assertEq(_wrappedMToken.lastIndexOf(_bob), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_500);
    }

    function test_transfer_nonEarnerToSelf() external {
        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _alice, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_alice, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
    }

    function test_transfer_earnerToSelf() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, _currentIndex);

        _mToken.setCurrentIndex((_currentIndex * 5) / 3); // 1_833333447838

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 666);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _alice, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_alice, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_666);
    }

    function testFuzz_transfer(
        bool earningEnabled_,
        bool aliceEarning_,
        bool bobEarning_,
        uint240 aliceBalance_,
        uint240 bobBalance_,
        uint128 aliceIndex_,
        uint128 bobIndex_,
        uint128 currentIndex_,
        uint240 amount_
    ) external {
        aliceEarning_ = earningEnabled_ && aliceEarning_;
        bobEarning_ = earningEnabled_ && bobEarning_;

        if (earningEnabled_) {
            _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);
            _wrappedMToken.enableEarning();
        }

        aliceIndex_ = uint128(bound(aliceIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        aliceBalance_ = uint240(bound(aliceBalance_, 0, _getMaxAmount(aliceIndex_) / 4));

        if (aliceEarning_) {
            _wrappedMToken.setAccountOf(_alice, aliceBalance_, aliceIndex_);
            _wrappedMToken.setTotalEarningSupply(aliceBalance_);

            _wrappedMToken.setPrincipalOfTotalEarningSupply(
                IndexingMath.getPrincipalAmountRoundedDown(aliceBalance_, aliceIndex_)
            );
        } else {
            _wrappedMToken.setAccountOf(_alice, aliceBalance_);
            _wrappedMToken.setTotalNonEarningSupply(aliceBalance_);
        }

        bobIndex_ = uint128(bound(bobIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        bobBalance_ = uint240(bound(bobBalance_, 0, _getMaxAmount(bobIndex_) / 4));

        if (bobEarning_) {
            _wrappedMToken.setAccountOf(_bob, bobBalance_, bobIndex_);
            _wrappedMToken.setTotalEarningSupply(_wrappedMToken.totalEarningSupply() + bobBalance_);

            _wrappedMToken.setPrincipalOfTotalEarningSupply(
                IndexingMath.getPrincipalAmountRoundedDown(
                    _wrappedMToken.totalEarningSupply() + bobBalance_,
                    aliceIndex_ > bobIndex_ ? aliceIndex_ : bobIndex_
                )
            );
        } else {
            _wrappedMToken.setAccountOf(_bob, bobBalance_);
            _wrappedMToken.setTotalNonEarningSupply(_wrappedMToken.totalNonEarningSupply() + bobBalance_);
        }

        currentIndex_ = uint128(
            bound(currentIndex_, aliceIndex_ > bobIndex_ ? aliceIndex_ : bobIndex_, 10 * _EXP_SCALED_ONE)
        );

        _mToken.setCurrentIndex(_currentIndex = currentIndex_);

        uint240 aliceAccruedYield_ = _wrappedMToken.accruedYieldOf(_alice);
        uint240 bobAccruedYield_ = _wrappedMToken.accruedYieldOf(_bob);

        amount_ = uint240(bound(amount_, 0, (11 * (aliceBalance_ + aliceAccruedYield_)) / 10));

        if (amount_ > aliceBalance_ + aliceAccruedYield_) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IWrappedMToken.InsufficientBalance.selector,
                    _alice,
                    aliceBalance_ + aliceAccruedYield_,
                    amount_
                )
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(_alice, _bob, amount_);
        }

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, amount_);

        if (amount_ > aliceBalance_ + aliceAccruedYield_) return;

        assertEq(_wrappedMToken.balanceOf(_alice), aliceBalance_ + aliceAccruedYield_ - amount_);
        assertEq(_wrappedMToken.balanceOf(_bob), bobBalance_ + bobAccruedYield_ + amount_);

        if (aliceEarning_ && bobEarning_) {
            assertEq(
                _wrappedMToken.totalEarningSupply(),
                aliceBalance_ + aliceAccruedYield_ + bobBalance_ + bobAccruedYield_
            );
        } else if (aliceEarning_) {
            assertEq(_wrappedMToken.totalEarningSupply(), aliceBalance_ + aliceAccruedYield_ - amount_);
            assertEq(_wrappedMToken.totalNonEarningSupply(), bobBalance_ + bobAccruedYield_ + amount_);
        } else if (bobEarning_) {
            assertEq(_wrappedMToken.totalNonEarningSupply(), aliceBalance_ + aliceAccruedYield_ - amount_);
            assertEq(_wrappedMToken.totalEarningSupply(), bobBalance_ + bobAccruedYield_ + amount_);
        } else {
            assertEq(
                _wrappedMToken.totalNonEarningSupply(),
                aliceBalance_ + aliceAccruedYield_ + bobBalance_ + bobAccruedYield_
            );
        }
    }

    /* ============ startEarningFor ============ */
    function test_startEarningFor_earningIsDisabled() external {
        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor_notApprovedEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.NotApprovedEarner.selector, _alice));
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarning_overflow() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        uint256 aliceBalance_ = uint256(type(uint112).max) + 20;

        _mToken.setCurrentIndex(_currentIndex = _EXP_SCALED_ONE);

        _wrappedMToken.setTotalNonEarningSupply(aliceBalance_);

        _wrappedMToken.setAccountOf(_alice, aliceBalance_);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.expectRevert(UIntMath.InvalidUInt112.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.expectEmit();
        emit IWrappedMToken.StartedEarning(_alice);

        _wrappedMToken.startEarningFor(_alice);

        assertEq(_wrappedMToken.isEarning(_alice), true);
        assertEq(_wrappedMToken.lastIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.balanceOf(_alice), 1000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
    }

    function testFuzz_startEarningFor(uint240 balance_, uint128 index_) external {
        balance_ = uint240(bound(balance_, 0, _getMaxAmount(_currentIndex)));
        index_ = uint128(bound(index_, _currentIndex, 10 * _EXP_SCALED_ONE));

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setTotalNonEarningSupply(balance_);

        _wrappedMToken.setAccountOf(_alice, balance_);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        _mToken.setCurrentIndex(index_);

        vm.expectEmit();
        emit IWrappedMToken.StartedEarning(_alice);

        _wrappedMToken.startEarningFor(_alice);

        assertEq(_wrappedMToken.isEarning(_alice), true);
        assertEq(_wrappedMToken.lastIndexOf(_alice), index_);
        assertEq(_wrappedMToken.balanceOf(_alice), balance_);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), balance_);
    }

    /* ============ stopEarningFor ============ */
    function test_stopEarningFor_isApprovedEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.IsApprovedEarner.selector, _alice));
        _wrappedMToken.stopEarningFor(_alice);
    }

    function test_stopEarningFor() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 999, _currentIndex);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        _wrappedMToken.stopEarningFor(_alice);

        assertEq(_wrappedMToken.balanceOf(_alice), 999);
        assertEq(_wrappedMToken.isEarning(_alice), false);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 999);
        assertEq(_wrappedMToken.totalEarningSupply(), 1);
    }

    function testFuzz_stopEarningFor(uint240 balance_, uint128 accountIndex_, uint128 index_) external {
        accountIndex_ = uint128(bound(index_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        balance_ = uint240(bound(balance_, 0, _getMaxAmount(accountIndex_)));
        index_ = uint128(bound(index_, accountIndex_, 10 * _EXP_SCALED_ONE));

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setTotalEarningSupply(balance_);

        _wrappedMToken.setAccountOf(_alice, balance_, accountIndex_);

        _mToken.setCurrentIndex(index_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        _wrappedMToken.stopEarningFor(_alice);

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + accruedYield_);
        assertEq(_wrappedMToken.isEarning(_alice), false);

        assertEq(_wrappedMToken.totalNonEarningSupply(), balance_ + accruedYield_);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
    }

    /* ============ enableEarning ============ */
    function test_enableEarning_notApprovedEarner() external {
        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.NotApprovedEarner.selector, address(_wrappedMToken)));
        _wrappedMToken.enableEarning();
    }

    function test_enableEarning_earningCannotBeReenabled() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), false);

        _wrappedMToken.disableEarning();

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        vm.expectRevert(IWrappedMToken.EarningCannotBeReenabled.selector);
        _wrappedMToken.enableEarning();
    }

    function test_enableEarning() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        vm.expectEmit();
        emit IWrappedMToken.EarningEnabled(_currentIndex);

        _wrappedMToken.enableEarning();
    }

    /* ============ disableEarning ============ */
    function test_disableEarning_earningIsDisabled() external {
        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.disableEarning();

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), false);

        _wrappedMToken.disableEarning();

        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.disableEarning();
    }

    function test_disableEarning_approvedEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.IsApprovedEarner.selector, address(_wrappedMToken)));
        _wrappedMToken.disableEarning();
    }

    function test_disableEarning() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), false);

        vm.expectEmit();
        emit IWrappedMToken.EarningDisabled(_currentIndex);

        _wrappedMToken.disableEarning();
    }

    /* ============ balanceOf ============ */
    function test_balanceOf_nonEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        _mToken.setCurrentIndex(2 * _currentIndex);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
    }

    function test_balanceOf_earner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 500, _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setAccountOf(_alice, 1_000, _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        _mToken.setCurrentIndex(2 * _currentIndex);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 3 * _currentIndex);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
    }

    /* ============ balanceWithYieldOf ============ */
    function test_balanceWithYieldOf_nonEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 500);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 500);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_000);

        _mToken.setCurrentIndex(2 * _currentIndex);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_000);
    }

    function test_balanceWithYieldOf_earner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 500, _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 550);

        _wrappedMToken.setAccountOf(_alice, 1_000, _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_100);

        _mToken.setCurrentIndex(2 * _currentIndex);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 2_200);

        _wrappedMToken.setAccountOf(_alice, 1_000, 3 * _currentIndex);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_000);
    }

    /* ============ accruedYieldOf ============ */
    function test_accruedYieldOf_nonEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 500);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        _mToken.setCurrentIndex(2 * _currentIndex);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
    }

    function test_accruedYieldOf_earner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setAccountOf(_alice, 500, _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 50);

        _wrappedMToken.setAccountOf(_alice, 1_000, _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        _mToken.setCurrentIndex(2 * _currentIndex);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 1_200);

        _wrappedMToken.setAccountOf(_alice, 1_000, 3 * _currentIndex);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
    }

    /* ============ lastIndexOf ============ */
    function test_lastIndexOf() external {
        _wrappedMToken.setAccountOf(_alice, 0, _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.lastIndexOf(_alice), _EXP_SCALED_ONE);

        _wrappedMToken.setAccountOf(_alice, 0, 2 * _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.lastIndexOf(_alice), 2 * _EXP_SCALED_ONE);
    }

    /* ============ isEarning ============ */
    function test_isEarning() external {
        _wrappedMToken.setAccountOf(_alice, 0);

        assertFalse(_wrappedMToken.isEarning(_alice));

        _wrappedMToken.setAccountOf(_alice, 0, _EXP_SCALED_ONE);

        assertTrue(_wrappedMToken.isEarning(_alice));
    }

    /* ============ isEarningEnabled ============ */
    function test_isEarningEnabled() external {
        assertFalse(_wrappedMToken.isEarningEnabled());

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        assertTrue(_wrappedMToken.isEarningEnabled());

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), false);

        _wrappedMToken.disableEarning();

        assertFalse(_wrappedMToken.isEarningEnabled());
    }

    /* ============ wasEarningEnabled ============ */
    function test_wasEarningEnabled() external {
        assertFalse(_wrappedMToken.wasEarningEnabled());

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        assertTrue(_wrappedMToken.wasEarningEnabled());

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), false);

        _wrappedMToken.disableEarning();

        assertTrue(_wrappedMToken.wasEarningEnabled());
    }

    /* ============ claimOverrideRecipientFor ============ */
    function test_claimOverrideRecipientFor() external {
        assertEq(_wrappedMToken.claimOverrideRecipientFor(_alice), address(0));

        _registrar.set(
            keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, _alice)),
            bytes32(uint256(uint160(_charlie)))
        );

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_alice), _charlie);
    }

    /* ============ totalSupply ============ */
    function test_totalSupply_onlyTotalNonEarningSupply() external {
        _wrappedMToken.setTotalNonEarningSupply(500);

        assertEq(_wrappedMToken.totalSupply(), 500);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        assertEq(_wrappedMToken.totalSupply(), 1_000);
    }

    function test_totalSupply_onlyTotalEarningSupply() external {
        _wrappedMToken.setTotalEarningSupply(500);

        assertEq(_wrappedMToken.totalSupply(), 500);

        _wrappedMToken.setTotalEarningSupply(1_000);

        assertEq(_wrappedMToken.totalSupply(), 1_000);
    }

    function test_totalSupply() external {
        _wrappedMToken.setTotalEarningSupply(400);

        _wrappedMToken.setTotalNonEarningSupply(600);

        assertEq(_wrappedMToken.totalSupply(), 1_000);

        _wrappedMToken.setTotalEarningSupply(700);

        assertEq(_wrappedMToken.totalSupply(), 1_300);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        assertEq(_wrappedMToken.totalSupply(), 1_700);
    }

    /* ============ currentIndex ============ */
    function test_currentIndex() external {
        assertEq(_wrappedMToken.currentIndex(), 0);

        _mToken.setCurrentIndex(2 * _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.currentIndex(), 0);

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        assertEq(_wrappedMToken.currentIndex(), 2 * _EXP_SCALED_ONE);

        _mToken.setCurrentIndex(3 * _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.currentIndex(), 3 * _EXP_SCALED_ONE);

        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), false);

        _wrappedMToken.disableEarning();

        assertEq(_wrappedMToken.currentIndex(), 3 * _EXP_SCALED_ONE);

        _mToken.setCurrentIndex(4 * _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.currentIndex(), 3 * _EXP_SCALED_ONE);
    }

    /* ============ excess ============ */
    function test_excess() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        assertEq(_wrappedMToken.excess(), 0);

        _wrappedMToken.setTotalNonEarningSupply(1_000);
        _wrappedMToken.setPrincipalOfTotalEarningSupply(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _mToken.setBalanceOf(address(_wrappedMToken), 2_100);

        assertEq(_wrappedMToken.excess(), 0);

        _mToken.setBalanceOf(address(_wrappedMToken), 2_101);

        assertEq(_wrappedMToken.excess(), 0);

        _mToken.setBalanceOf(address(_wrappedMToken), 2_102);

        assertEq(_wrappedMToken.excess(), 1);

        _mToken.setBalanceOf(address(_wrappedMToken), 3_102);

        assertEq(_wrappedMToken.excess(), 1_001);
    }

    /* ============ totalAccruedYield ============ */
    function test_totalAccruedYield() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _wrappedMToken.enableEarning();

        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setTotalEarningSupply(1_000);

        assertEq(_wrappedMToken.totalAccruedYield(), 0);

        _wrappedMToken.setPrincipalOfTotalEarningSupply(1_000);

        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        _wrappedMToken.setTotalEarningSupply(900);

        assertEq(_wrappedMToken.totalAccruedYield(), 200);

        _mToken.setCurrentIndex(_currentIndex = 1_210000000000);

        assertEq(_wrappedMToken.totalAccruedYield(), 310);
    }

    /* ============ utils ============ */
    function _getPrincipalAmountRoundedDown(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return IndexingMath.divide240By128Down(presentAmount_, index_);
    }

    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return IndexingMath.multiply112By128Down(principalAmount_, index_);
    }

    function _getMaxAmount(uint128 index_) internal pure returns (uint240 maxAmount_) {
        return (uint240(type(uint112).max) * index_) / _EXP_SCALED_ONE;
    }
}
