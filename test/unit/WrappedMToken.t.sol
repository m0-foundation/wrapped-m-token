// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IndexingMath } from "../../lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { Proxy } from "../../lib/common/src/Proxy.sol";
import { Test } from "../../lib/forge-std/src/Test.sol";

import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { MockEarnerManager, MockM, MockRegistrar } from "../utils/Mocks.sol";
import { WrappedMTokenHarness } from "../utils/WrappedMTokenHarness.sol";

// TODO: All operations involving earners should include demonstration of accrued yield being added to their balance.
// TODO: Add relevant unit tests while earning enabled/disabled.

contract WrappedMTokenTests is Test {
    uint56 internal constant _EXP_SCALED_ONE = IndexingMath.EXP_SCALED_ONE;

    uint56 internal constant _ONE_HUNDRED_PERCENT = 10_000;

    bytes32 internal constant _CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX = "wm_claim_override_recipient";

    bytes32 internal constant _EARNERS_LIST_NAME = "earners";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");

    address internal _excessDestination = makeAddr("excessDestination");
    address internal _migrationAdmin = makeAddr("migrationAdmin");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    MockEarnerManager internal _earnerManager;
    MockM internal _mToken;
    MockRegistrar internal _registrar;
    WrappedMTokenHarness internal _implementation;
    WrappedMTokenHarness internal _wrappedMToken;

    function setUp() external {
        _registrar = new MockRegistrar();

        _mToken = new MockM();

        _earnerManager = new MockEarnerManager();

        _implementation = new WrappedMTokenHarness(
            address(_mToken),
            address(_registrar),
            address(_earnerManager),
            _excessDestination,
            _migrationAdmin
        );

        _wrappedMToken = WrappedMTokenHarness(address(new Proxy(address(_implementation))));
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
        assertEq(_wrappedMToken.enableMIndex(), 0);
        assertEq(_wrappedMToken.disableIndex(), 0);
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(IWrappedMToken.ZeroMToken.selector);
        new WrappedMTokenHarness(address(0), address(0), address(0), address(0), address(0));
    }

    function test_constructor_zeroRegistrar() external {
        vm.expectRevert(IWrappedMToken.ZeroRegistrar.selector);
        new WrappedMTokenHarness(address(_mToken), address(0), address(0), address(0), address(0));
    }

    function test_constructor_zeroEarnerManager() external {
        vm.expectRevert(IWrappedMToken.ZeroEarnerManager.selector);
        new WrappedMTokenHarness(address(_mToken), address(_registrar), address(0), address(0), address(0));
    }

    function test_constructor_zeroExcessDestination() external {
        vm.expectRevert(IWrappedMToken.ZeroExcessDestination.selector);
        new WrappedMTokenHarness(
            address(_mToken),
            address(_registrar),
            address(_earnerManager),
            address(0),
            address(0)
        );
    }

    function test_constructor_zeroMigrationAdmin() external {
        vm.expectRevert(IWrappedMToken.ZeroMigrationAdmin.selector);
        new WrappedMTokenHarness(
            address(_mToken),
            address(_registrar),
            address(_earnerManager),
            _excessDestination,
            address(0)
        );
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

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 1_000);

        assertEq(_wrappedMToken.internalWrap(_alice, _alice, 1_000), 1_000);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 2_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 2_000);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
    }

    function test_wrap_toEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _mToken.setBalanceOf(_alice, 1_002);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 999);

        assertEq(_wrappedMToken.internalWrap(_alice, _alice, 999), 999);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 + 908);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 + 999);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 + 908);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 + 999);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 1);

        assertEq(_wrappedMToken.internalWrap(_alice, _alice, 1), 1);

        // No change due to principal round down on wrap.
        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 + 908 + 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 + 999 + 1);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 98);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 + 908 + 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 + 999 + 1);
        assertEq(_wrappedMToken.totalAccruedYield(), 99);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 2);

        assertEq(_wrappedMToken.internalWrap(_alice, _alice, 2), 2);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 + 908 + 0 + 1);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 + 999 + 1 + 2);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 97);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 + 908 + 0 + 1);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 + 999 + 1 + 2);
        assertEq(_wrappedMToken.totalAccruedYield(), 98);
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
        uint240 balanceWithYield_,
        uint240 balance_,
        uint240 wrapAmount_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        (balanceWithYield_, balance_) = _getFuzzedBalances(
            balanceWithYield_,
            balance_,
            _getMaxAmount(_wrappedMToken.currentIndex())
        );

        _setupAccount(_alice, accountEarning_, balanceWithYield_, balance_);

        wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(_wrappedMToken.currentIndex()) - balanceWithYield_));

        _mToken.setBalanceOf(_alice, wrapAmount_);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.wrap(_alice, wrapAmount_);

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + wrapAmount_);

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
        uint240 balanceWithYield_,
        uint240 balance_,
        uint240 wrapAmount_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        (balanceWithYield_, balance_) = _getFuzzedBalances(
            balanceWithYield_,
            balance_,
            _getMaxAmount(_wrappedMToken.currentIndex())
        );

        _setupAccount(_alice, accountEarning_, balanceWithYield_, balance_);

        wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(_wrappedMToken.currentIndex()) - balanceWithYield_));

        _mToken.setBalanceOf(_alice, wrapAmount_);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.wrap(_alice);

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + wrapAmount_);

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
        uint240 balanceWithYield_,
        uint240 balance_,
        uint240 wrapAmount_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        (balanceWithYield_, balance_) = _getFuzzedBalances(
            balanceWithYield_,
            balance_,
            _getMaxAmount(_wrappedMToken.currentIndex())
        );

        _setupAccount(_alice, accountEarning_, balanceWithYield_, balance_);

        wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(_wrappedMToken.currentIndex()) - balanceWithYield_));

        _mToken.setBalanceOf(_alice, wrapAmount_);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.wrapWithPermit(_alice, wrapAmount_, 0, 0, bytes32(0), bytes32(0));

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + wrapAmount_);

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
        uint240 balanceWithYield_,
        uint240 balance_,
        uint240 wrapAmount_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        (balanceWithYield_, balance_) = _getFuzzedBalances(
            balanceWithYield_,
            balance_,
            _getMaxAmount(_wrappedMToken.currentIndex())
        );

        _setupAccount(_alice, accountEarning_, balanceWithYield_, balance_);

        wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(_wrappedMToken.currentIndex()) - balanceWithYield_));

        _mToken.setBalanceOf(_alice, wrapAmount_);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.wrapWithPermit(_alice, wrapAmount_, 0, hex"");

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + wrapAmount_);

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
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 999, 909, false, false);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        _wrappedMToken.internalUnwrap(_alice, _alice, 1_000);
    }

    function test_internalUnwrap_fromNonEarner() external {
        _mToken.setIsEarning(address(_wrappedMToken), true);
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _mToken.setBalanceOf(address(_wrappedMToken), 1_000);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 1);

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 1), 1);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 999);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 999);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 499);

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 499), 499);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 500);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 500);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 500);

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 500), 500);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
    }

    function test_internalUnwrap_fromEarner() external {
        _mToken.setIsEarning(address(_wrappedMToken), true);
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _mToken.setBalanceOf(address(_wrappedMToken), 1_000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 1);

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 1), 1);

        // Change due to principal round up on unwrap.
        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 - 1);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 - 1);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 - 1);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 - 1);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 499);

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 499), 499);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 - 1 - 454);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 - 1 - 499);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 - 1 - 454);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 - 1 - 499);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 500);

        assertEq(_wrappedMToken.internalUnwrap(_alice, _alice, 500), 500);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 - 1 - 454 - 455); // 0
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 - 1 - 499 - 500); // 0
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 - 1 - 454 - 455); // 0
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 - 1 - 499 - 500); // 0
        assertEq(_wrappedMToken.totalAccruedYield(), 99);
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
        uint240 balanceWithYield_,
        uint240 balance_,
        uint240 unwrapAmount_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        (balanceWithYield_, balance_) = _getFuzzedBalances(
            balanceWithYield_,
            balance_,
            _getMaxAmount(_wrappedMToken.currentIndex())
        );

        _setupAccount(_alice, accountEarning_, balanceWithYield_, balance_);

        _mToken.setBalanceOf(address(_wrappedMToken), balance_);

        unwrapAmount_ = uint240(bound(unwrapAmount_, 0, (11 * balance_) / 10));

        if (unwrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else if (unwrapAmount_ > balance_) {
            vm.expectRevert(
                abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, balance_, unwrapAmount_)
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(_alice, address(0), unwrapAmount_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.unwrap(_alice, unwrapAmount_);

        if ((unwrapAmount_ == 0) || (unwrapAmount_ > balance_)) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ - unwrapAmount_);

        assertEq(
            accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(),
            _wrappedMToken.balanceOf(_alice)
        );
    }

    /* ============ unwrap entire balance ============ */
    function testFuzz_unwrap_entireBalance(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balanceWithYield_,
        uint240 balance_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        (balanceWithYield_, balance_) = _getFuzzedBalances(
            balanceWithYield_,
            balance_,
            _getMaxAmount(_wrappedMToken.currentIndex())
        );

        _setupAccount(_alice, accountEarning_, balanceWithYield_, balance_);

        _mToken.setBalanceOf(address(_wrappedMToken), balance_);

        if (balance_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(_alice, address(0), balance_);
        }

        vm.startPrank(_alice);
        _wrappedMToken.unwrap(_alice);

        if (balance_ == 0) return;

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
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        assertEq(_wrappedMToken.claimFor(_alice), 100);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_100);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_100);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
    }

    function test_claimFor_earner_withOverrideRecipient() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _registrar.set(
            keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, _alice)),
            bytes32(uint256(uint160(_bob)))
        );

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _bob, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 100);

        assertEq(_wrappedMToken.claimFor(_alice), 100);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 909);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        assertEq(_wrappedMToken.balanceOf(_bob), 100);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 100);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 909);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
    }

    function test_claimFor_earner_withFee() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, true);
        _earnerManager.setEarnerDetails(_alice, true, 1_500, _bob);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 15);

        assertEq(_wrappedMToken.claimFor(_alice), 100);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_085);
        assertEq(_wrappedMToken.balanceOf(_bob), 15);
    }

    function test_claimFor_earner_withFeeAboveOneHundredPercent() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, true);
        _earnerManager.setEarnerDetails(_alice, true, type(uint16).max, _bob);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 100);

        assertEq(_wrappedMToken.claimFor(_alice), 100);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_bob), 100);
    }

    function test_claimFor_earner_withOverrideRecipientAndFee() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _registrar.set(
            keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, _alice)),
            bytes32(uint256(uint160(_charlie)))
        );

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, true);
        _earnerManager.setEarnerDetails(_alice, true, 1_500, _bob);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _charlie, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 15);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _charlie, 85);

        assertEq(_wrappedMToken.claimFor(_alice), 100);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_bob), 15);
        assertEq(_wrappedMToken.balanceOf(_charlie), 85);
    }

    function testFuzz_claimFor(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balanceWithYield_,
        uint240 balance_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_,
        bool claimOverride_,
        uint16 feeRate_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        (balanceWithYield_, balance_) = _getFuzzedBalances(
            balanceWithYield_,
            balance_,
            _getMaxAmount(_wrappedMToken.currentIndex())
        );

        _setupAccount(_alice, accountEarning_, balanceWithYield_, balance_);

        if (feeRate_ != 0) {
            _wrappedMToken.setHasEarnerDetails(_alice, true);
            _earnerManager.setEarnerDetails(_alice, true, feeRate_, _bob);
        }

        if (claimOverride_) {
            _registrar.set(
                keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, _alice)),
                bytes32(uint256(uint160(_charlie)))
            );
        }

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        if (accruedYield_ != 0) {
            vm.expectEmit();
            emit IWrappedMToken.Claimed(_alice, claimOverride_ ? _charlie : _alice, accruedYield_);

            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, accruedYield_);
        }

        uint240 fee_ = (accruedYield_ * (feeRate_ > _ONE_HUNDRED_PERCENT ? _ONE_HUNDRED_PERCENT : feeRate_)) /
            _ONE_HUNDRED_PERCENT;

        if (fee_ != 0) {
            vm.expectEmit();
            emit IERC20.Transfer(_alice, _bob, fee_);
        }

        if (claimOverride_ && (accruedYield_ - fee_ != 0)) {
            vm.expectEmit();
            emit IERC20.Transfer(_alice, _charlie, accruedYield_ - fee_);
        }

        assertEq(_wrappedMToken.claimFor(_alice), accruedYield_);

        assertEq(
            _wrappedMToken.totalSupply(),
            _wrappedMToken.balanceOf(_alice) + _wrappedMToken.balanceOf(_bob) + _wrappedMToken.balanceOf(_charlie)
        );
    }

    /* ============ claimExcess ============ */
    function testFuzz_claimExcess(
        bool earningEnabled_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_,
        uint240 totalNonEarningSupply_,
        uint240 totalProjectedEarningSupply_,
        uint112 mPrincipalBalance_,
        int144 roundingError_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        uint240 maxAmount_ = _getMaxAmount(_wrappedMToken.currentIndex());

        totalNonEarningSupply_ = uint240(bound(totalNonEarningSupply_, 0, maxAmount_));

        totalProjectedEarningSupply_ = uint240(
            bound(totalProjectedEarningSupply_, 0, maxAmount_ - totalNonEarningSupply_)
        );

        uint112 totalEarningPrincipal_ = IndexingMath.getPrincipalAmountRoundedUp(
            totalProjectedEarningSupply_,
            _wrappedMToken.currentIndex()
        );

        mPrincipalBalance_ = uint112(bound(mPrincipalBalance_, 0, type(uint112).max));

        _mToken.setPrincipalBalanceOf(address(_wrappedMToken), mPrincipalBalance_);

        uint240 mBalance_ = IndexingMath.getPresentAmountRoundedDown(mPrincipalBalance_, currentMIndex_);

        _mToken.setBalanceOf(address(_wrappedMToken), mBalance_);

        _wrappedMToken.setTotalEarningPrincipal(totalEarningPrincipal_);
        _wrappedMToken.setTotalNonEarningSupply(totalNonEarningSupply_);

        roundingError_ = int144(bound(roundingError_, -1_000_000000, 1_000_000000));

        _wrappedMToken.setRoundingError(roundingError_);

        uint240 totalProjectedSupply_ = totalNonEarningSupply_ + totalProjectedEarningSupply_;
        int248 earmarked_ = int248(uint248(totalProjectedSupply_)) + roundingError_;
        int248 excess_ = earmarked_ <= 0 ? int248(uint248(mBalance_)) : int248(uint248(mBalance_)) - earmarked_;

        if (excess_ <= 0) {
            vm.expectRevert(IWrappedMToken.NoExcess.selector);
        } else {
            vm.expectEmit(false, false, false, false);
            emit IWrappedMToken.ExcessClaimed(uint240(uint248(excess_)));
        }

        uint240 claimed_ = _wrappedMToken.claimExcess();

        if (excess_ <= 0) return;

        assertLe(claimed_, uint248(excess_));
    }

    /* ============ transfer ============ */
    function test_transfer_invalidRecipient() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_alice);
        _wrappedMToken.transfer(address(0), 1_000);
    }

    function test_transfer_insufficientBalance_toSelf() external {
        _wrappedMToken.setAccountOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.transfer(_alice, 1_000);
    }

    function test_transfer_insufficientBalance_fromNonEarner_toNonEarner() external {
        _wrappedMToken.setAccountOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1_000);
    }

    function test_transfer_insufficientBalance_fromEarner_toNonEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 1_000, 1_001));
        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1_001);
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
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
    }

    function testFuzz_transfer_fromNonEarner_toNonEarner(
        uint256 supply_,
        uint256 aliceBalance_,
        uint256 transferAmount_
    ) external {
        supply_ = bound(supply_, 1, type(uint240).max);
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
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
    }

    function test_transfer_fromEarner_toNonEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setTotalNonEarningSupply(500);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.
        _wrappedMToken.setAccountOf(_bob, 500);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 545);
        assertEq(_wrappedMToken.balanceOf(_alice), 500);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);

        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 545);
        assertEq(_wrappedMToken.totalEarningSupply(), 500);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 1);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 544);
        assertEq(_wrappedMToken.balanceOf(_alice), 499);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);

        assertEq(_wrappedMToken.balanceOf(_bob), 1_001);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_001);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 544);
        assertEq(_wrappedMToken.totalEarningSupply(), 499);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);
    }

    function test_transfer_fromNonEarner_toEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(500);
        _wrappedMToken.setTotalEarningSupply(500);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);
        _wrappedMToken.setAccountOf(_bob, 500, 500, false, false); // 550 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_bob), 50);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        assertEq(_wrappedMToken.earningPrincipalOf(_bob), 954);
        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 49);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 500);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 954);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalAccruedYield(), 50);
    }

    function test_transfer_fromEarner_toEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_500);
        _wrappedMToken.setTotalEarningSupply(1_500);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.
        _wrappedMToken.setAccountOf(_bob, 500, 500, false, false); // 550 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 50);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 545);
        assertEq(_wrappedMToken.balanceOf(_alice), 500);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);

        assertEq(_wrappedMToken.earningPrincipalOf(_bob), 955);
        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 50);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_500);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_500);
        assertEq(_wrappedMToken.totalAccruedYield(), 150);
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
    }

    function test_transfer_earnerToSelf() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _alice, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_alice, 500);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);
    }

    function testFuzz_transfer(
        bool earningEnabled_,
        bool aliceEarning_,
        bool bobEarning_,
        uint240 aliceBalanceWithYield_,
        uint240 aliceBalance_,
        uint240 bobBalanceWithYield_,
        uint240 bobBalance_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_,
        uint240 amount_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        (aliceBalanceWithYield_, aliceBalance_) = _getFuzzedBalances(
            aliceBalanceWithYield_,
            aliceBalance_,
            _getMaxAmount(_wrappedMToken.currentIndex())
        );

        _setupAccount(_alice, aliceEarning_, aliceBalanceWithYield_, aliceBalance_);

        (bobBalanceWithYield_, bobBalance_) = _getFuzzedBalances(
            bobBalanceWithYield_,
            bobBalance_,
            _getMaxAmount(_wrappedMToken.currentIndex()) - aliceBalanceWithYield_
        );

        _setupAccount(_bob, bobEarning_, bobBalanceWithYield_, bobBalance_);

        amount_ = uint240(bound(amount_, 0, (11 * aliceBalance_) / 10));

        if (amount_ > aliceBalance_) {
            vm.expectRevert(
                abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, aliceBalance_, amount_)
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(_alice, _bob, amount_);
        }

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, amount_);

        if (amount_ > aliceBalance_) return;

        assertEq(_wrappedMToken.balanceOf(_alice), aliceBalance_ - amount_);
        assertEq(_wrappedMToken.balanceOf(_bob), bobBalance_ + amount_);

        if (aliceEarning_ && bobEarning_) {
            assertEq(_wrappedMToken.totalEarningSupply(), aliceBalance_ + bobBalance_);
        } else if (aliceEarning_) {
            assertEq(_wrappedMToken.totalEarningSupply(), aliceBalance_ - amount_);
            assertEq(_wrappedMToken.totalNonEarningSupply(), bobBalance_ + amount_);
        } else if (bobEarning_) {
            assertEq(_wrappedMToken.totalNonEarningSupply(), aliceBalance_ - amount_);
            assertEq(_wrappedMToken.totalEarningSupply(), bobBalance_ + amount_);
        } else {
            assertEq(_wrappedMToken.totalNonEarningSupply(), aliceBalance_ + bobBalance_);
        }
    }

    /* ============ startEarningFor ============ */
    function test_startEarningFor_notApprovedEarner() external {
        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.NotApprovedEarner.selector, _alice));
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarning_overflow() external {
        _mToken.setCurrentIndex(1_100000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        uint240 aliceBalance_ = uint240(type(uint112).max) + 20; // TODO: _getMaxAmount(1_100000000000) + 2; ?

        _wrappedMToken.setTotalNonEarningSupply(aliceBalance_);

        _wrappedMToken.setAccountOf(_alice, aliceBalance_);

        _earnerManager.setEarnerDetails(_alice, true, 0, address(0));

        vm.expectRevert(UIntMath.InvalidUInt112.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        _earnerManager.setEarnerDetails(_alice, true, 0, address(0));

        vm.expectEmit();
        emit IWrappedMToken.StartedEarning(_alice);

        _wrappedMToken.startEarningFor(_alice);

        assertEq(_wrappedMToken.isEarning(_alice), true);
        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 909);
        assertEq(_wrappedMToken.balanceOf(_alice), 1000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 909);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
    }

    function testFuzz_startEarningFor(
        bool earningEnabled_,
        uint240 balance_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        uint128 currentIndex_ = _wrappedMToken.currentIndex();

        balance_ = uint240(bound(balance_, 0, _getMaxAmount(currentIndex_)));

        _setupAccount(_alice, false, 0, balance_);

        _earnerManager.setEarnerDetails(_alice, true, 0, address(0));

        vm.expectEmit();
        emit IWrappedMToken.StartedEarning(_alice);

        _wrappedMToken.startEarningFor(_alice);

        uint112 earningPrincipal_ = IndexingMath.getPrincipalAmountRoundedDown(balance_, currentIndex_);

        assertEq(_wrappedMToken.isEarning(_alice), true);
        assertEq(_wrappedMToken.earningPrincipalOf(_alice), earningPrincipal_);
        assertEq(_wrappedMToken.balanceOf(_alice), balance_);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), balance_);
        assertEq(_wrappedMToken.totalEarningPrincipal(), earningPrincipal_);
    }

    /* ============ startEarningFor batch ============ */
    function test_startEarningFor_batch_earningIsDisabled() external {
        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.startEarningFor(new address[](2));
    }

    function test_startEarningFor_batch_notApprovedEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _earnerManager.setEarnerDetails(_alice, true, 0, address(0));

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.NotApprovedEarner.selector, _bob));
        _wrappedMToken.startEarningFor(accounts_);
    }

    function test_startEarningFor_batch() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _earnerManager.setEarnerDetails(_alice, true, 0, address(0));
        _earnerManager.setEarnerDetails(_bob, true, 0, address(0));

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        vm.expectEmit();
        emit IWrappedMToken.StartedEarning(_alice);

        vm.expectEmit();
        emit IWrappedMToken.StartedEarning(_bob);

        _wrappedMToken.startEarningFor(accounts_);
    }

    /* ============ stopEarningFor ============ */
    function test_stopEarningFor_isApprovedEarner() external {
        _earnerManager.setEarnerDetails(_alice, true, 0, address(0));

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.IsApprovedEarner.selector, _alice));
        _wrappedMToken.stopEarningFor(_alice);
    }

    function test_stopEarningFor() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        _wrappedMToken.stopEarningFor(_alice);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_100);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.isEarning(_alice), false);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_100);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
    }

    function testFuzz_stopEarningFor(
        bool earningEnabled_,
        uint240 balanceWithYield_,
        uint240 balance_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        (balanceWithYield_, balance_) = _getFuzzedBalances(
            balanceWithYield_,
            balance_,
            _getMaxAmount(_wrappedMToken.currentIndex())
        );

        _setupAccount(_alice, true, balanceWithYield_, balance_);

        uint240 accruedYield_ = _wrappedMToken.accruedYieldOf(_alice);

        if (accruedYield_ != 0) {
            vm.expectEmit();
            emit IWrappedMToken.Claimed(_alice, _alice, accruedYield_);

            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, accruedYield_);
        }

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        _wrappedMToken.stopEarningFor(_alice);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + accruedYield_);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.isEarning(_alice), false);

        assertEq(_wrappedMToken.totalNonEarningSupply(), balance_ + accruedYield_);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
    }

    /* ============ setClaimRecipient ============ */
    function test_setClaimRecipient() external {
        (, , , bool hasClaimRecipient_, ) = _wrappedMToken.getAccountOf(_alice);

        assertFalse(hasClaimRecipient_);
        assertEq(_wrappedMToken.getInternalClaimRecipientOf(_alice), address(0));

        vm.prank(_alice);
        _wrappedMToken.setClaimRecipient(_alice);

        (, , , hasClaimRecipient_, ) = _wrappedMToken.getAccountOf(_alice);

        assertTrue(hasClaimRecipient_);
        assertEq(_wrappedMToken.getInternalClaimRecipientOf(_alice), _alice);

        vm.prank(_alice);
        _wrappedMToken.setClaimRecipient(_bob);

        (, , , hasClaimRecipient_, ) = _wrappedMToken.getAccountOf(_alice);

        assertTrue(hasClaimRecipient_);
        assertEq(_wrappedMToken.getInternalClaimRecipientOf(_alice), _bob);

        vm.prank(_alice);
        _wrappedMToken.setClaimRecipient(address(0));

        (, , , hasClaimRecipient_, ) = _wrappedMToken.getAccountOf(_alice);

        assertFalse(hasClaimRecipient_);
        assertEq(_wrappedMToken.getInternalClaimRecipientOf(_alice), address(0));
    }

    /* ============ stopEarningFor batch ============ */
    function test_stopEarningFor_batch_isApprovedEarner() external {
        _earnerManager.setEarnerDetails(_bob, true, 0, address(0));

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.IsApprovedEarner.selector, _bob));
        _wrappedMToken.stopEarningFor(accounts_);
    }

    function test_stopEarningFor_batch() external {
        _wrappedMToken.setAccountOf(_alice, 0, 0, false, false);
        _wrappedMToken.setAccountOf(_bob, 0, 0, false, false);

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_bob);

        _wrappedMToken.stopEarningFor(accounts_);
    }

    /* ============ enableEarning ============ */
    function test_enableEarning_notApprovedEarner() external {
        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.NotApprovedEarner.selector, address(_wrappedMToken)));
        _wrappedMToken.enableEarning();
    }

    function test_enableEarning() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        _mToken.setCurrentIndex(1_210000000000);

        assertEq(_wrappedMToken.enableMIndex(), 0);
        assertEq(_wrappedMToken.currentIndex(), 1_000000000000);

        vm.expectEmit();
        emit IWrappedMToken.EarningEnabled(1_210000000000);

        _wrappedMToken.enableEarning();

        assertEq(_wrappedMToken.enableMIndex(), 1_210000000000);
        assertEq(_wrappedMToken.currentIndex(), 1_000000000000);
    }

    /* ============ disableEarning ============ */
    function test_disableEarning_earningIsDisabled() external {
        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.disableEarning();
    }

    function test_disableEarning_approvedEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, address(_wrappedMToken), true);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.IsApprovedEarner.selector, address(_wrappedMToken)));
        _wrappedMToken.disableEarning();
    }

    function test_disableEarning() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        assertEq(_wrappedMToken.enableMIndex(), 1_100000000000);
        assertEq(_wrappedMToken.disableIndex(), 0);
        assertEq(_wrappedMToken.currentIndex(), 1_100000000000);

        vm.expectEmit();
        emit IWrappedMToken.EarningDisabled(1_100000000000);

        _wrappedMToken.disableEarning();

        assertEq(_wrappedMToken.enableMIndex(), 0);
        assertEq(_wrappedMToken.disableIndex(), 1_100000000000);
        assertEq(_wrappedMToken.currentIndex(), 1_100000000000);
    }

    /* ============ balanceOf ============ */
    function test_balanceOf_nonEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
    }

    function test_balanceOf_earner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 500, 500, false, false); // 550 balance with yield.

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setEarningPrincipalOf(_alice, 1_000); // Earning principal has no bearing on balance.

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_500, false, false); // 1_815 balance with yield.

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
    }

    /* ============ balanceWithYieldOf ============ */
    function test_balanceWithYieldOf_nonEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 500);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 500);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_000);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_000);
    }

    function test_balanceWithYieldOf_earner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 500, 500, false, false); // 550 balance with yield.

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 550);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_100);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_210);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_500, false, false); // 1_815 balance with yield.

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_815);
    }

    /* ============ accruedYieldOf ============ */
    function test_accruedYieldOf_nonEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 500);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
    }

    function test_accruedYieldOf_earner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 500, 500, false, false); // 550 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 50);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 210);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_500, false, false); // 1_815 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 815);
    }

    /* ============ earningPrincipalOf ============ */
    function test_earningPrincipalOf() external {
        _wrappedMToken.setAccountOf(_alice, 0, 100, false, false);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 100);

        _wrappedMToken.setAccountOf(_alice, 0, 200, false, false);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 200);
    }

    /* ============ isEarning ============ */
    function test_isEarning() external {
        _wrappedMToken.setAccountOf(_alice, 0);

        assertFalse(_wrappedMToken.isEarning(_alice));

        _wrappedMToken.setAccountOf(_alice, 0, _EXP_SCALED_ONE, false, false);

        assertTrue(_wrappedMToken.isEarning(_alice));
    }

    /* ============ isEarningEnabled ============ */
    function test_isEarningEnabled() external {
        assertFalse(_wrappedMToken.isEarningEnabled());

        _wrappedMToken.setEnableMIndex(1_100000000000);

        assertTrue(_wrappedMToken.isEarningEnabled());

        _wrappedMToken.setEnableMIndex(0);

        assertFalse(_wrappedMToken.isEarningEnabled());

        _wrappedMToken.setEnableMIndex(1_100000000000);

        assertTrue(_wrappedMToken.isEarningEnabled());
    }

    /* ============ claimRecipientFor ============ */
    function test_claimRecipientFor() external view {
        assertEq(_wrappedMToken.claimRecipientFor(_alice), _alice);
    }

    function test_claimRecipientFor_hasClaimRecipient() external {
        _wrappedMToken.setAccountOf(_alice, 0, 0, true, false);
        _wrappedMToken.setInternalClaimRecipient(_alice, _bob);

        assertEq(_wrappedMToken.claimRecipientFor(_alice), _bob);
    }

    function test_claimRecipientFor_hasClaimOverrideRecipient() external {
        _registrar.set(
            keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, _alice)),
            bytes32(uint256(uint160(_charlie)))
        );

        assertEq(_wrappedMToken.claimRecipientFor(_alice), _charlie);
    }

    function test_claimRecipientFor_hasClaimRecipientAndOverrideRecipient() external {
        _wrappedMToken.setAccountOf(_alice, 0, 0, true, false);
        _wrappedMToken.setInternalClaimRecipient(_alice, _bob);

        _registrar.set(
            keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, _alice)),
            bytes32(uint256(uint160(_charlie)))
        );

        assertEq(_wrappedMToken.claimRecipientFor(_alice), _bob);
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
        assertEq(_wrappedMToken.currentIndex(), _EXP_SCALED_ONE);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.currentIndex(), _EXP_SCALED_ONE);

        _wrappedMToken.setDisableIndex(1_050000000000);

        assertEq(_wrappedMToken.currentIndex(), 1_050000000000);

        _wrappedMToken.setDisableIndex(1_100000000000);

        assertEq(_wrappedMToken.currentIndex(), 1_100000000000);

        _wrappedMToken.setEnableMIndex(1_100000000000);

        assertEq(_wrappedMToken.currentIndex(), 1_331000000000);

        _wrappedMToken.setEnableMIndex(1_155000000000);

        assertEq(_wrappedMToken.currentIndex(), 1_267619047619);

        _wrappedMToken.setEnableMIndex(1_210000000000);

        assertEq(_wrappedMToken.currentIndex(), 1_210000000000);

        _wrappedMToken.setEnableMIndex(1_270500000000);

        assertEq(_wrappedMToken.currentIndex(), 1_152380952380);

        _wrappedMToken.setEnableMIndex(1_331000000000);

        assertEq(_wrappedMToken.currentIndex(), 1_100000000000);

        _mToken.setCurrentIndex(1_464100000000);

        assertEq(_wrappedMToken.currentIndex(), 1_210000000000);
    }

    /* ============ excess ============ */
    function test_excess() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        assertEq(_wrappedMToken.excess(), 0);

        _wrappedMToken.setTotalNonEarningSupply(1_000);
        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _mToken.setBalanceOf(address(_wrappedMToken), 2_100);

        assertEq(_wrappedMToken.excess(), 0);

        _wrappedMToken.setRoundingError(1);

        assertEq(_wrappedMToken.excess(), -1);

        _mToken.setBalanceOf(address(_wrappedMToken), 2_101);

        assertEq(_wrappedMToken.excess(), 0);

        _mToken.setBalanceOf(address(_wrappedMToken), 2_102);

        assertEq(_wrappedMToken.excess(), 1);

        _mToken.setBalanceOf(address(_wrappedMToken), 3_102);

        assertEq(_wrappedMToken.excess(), 1_001);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.excess(), 891);

        _wrappedMToken.setRoundingError(0);

        assertEq(_wrappedMToken.excess(), 892);

        _wrappedMToken.setRoundingError(-1);

        assertEq(_wrappedMToken.excess(), 893);

        _wrappedMToken.setRoundingError(-2_210);

        assertEq(_wrappedMToken.excess(), 3_102);

        _wrappedMToken.setRoundingError(-2_211);

        assertEq(_wrappedMToken.excess(), 3_102);
    }

    function testFuzz_excess(
        bool earningEnabled_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_,
        uint240 totalNonEarningSupply_,
        uint240 totalProjectedEarningSupply_,
        uint112 mPrincipalBalance_,
        int144 roundingError_
    ) external {
        (currentMIndex_, enableMIndex_, disableIndex_) = _getFuzzedIndices(
            currentMIndex_,
            enableMIndex_,
            disableIndex_
        );

        _setupIndexes(earningEnabled_, currentMIndex_, enableMIndex_, disableIndex_);

        uint240 maxAmount_ = _getMaxAmount(_wrappedMToken.currentIndex());

        totalNonEarningSupply_ = uint240(bound(totalNonEarningSupply_, 0, maxAmount_));

        totalProjectedEarningSupply_ = uint240(
            bound(totalProjectedEarningSupply_, 0, maxAmount_ - totalNonEarningSupply_)
        );

        uint112 totalEarningPrincipal_ = IndexingMath.getPrincipalAmountRoundedUp(
            totalProjectedEarningSupply_,
            _wrappedMToken.currentIndex()
        );

        mPrincipalBalance_ = uint112(bound(mPrincipalBalance_, 0, type(uint112).max));

        _mToken.setPrincipalBalanceOf(address(_wrappedMToken), mPrincipalBalance_);

        uint240 mBalance_ = IndexingMath.getPresentAmountRoundedDown(mPrincipalBalance_, currentMIndex_);

        _mToken.setBalanceOf(address(_wrappedMToken), mBalance_);

        _wrappedMToken.setTotalEarningPrincipal(totalEarningPrincipal_);
        _wrappedMToken.setTotalNonEarningSupply(totalNonEarningSupply_);

        roundingError_ = int144(bound(roundingError_, -1_000_000000, 1_000_000000));

        _wrappedMToken.setRoundingError(roundingError_);

        uint240 totalProjectedSupply_ = totalNonEarningSupply_ + totalProjectedEarningSupply_;
        int248 earmarked_ = int248(uint248(totalProjectedSupply_)) + roundingError_;

        assertLe(_wrappedMToken.excess(), int248(uint248(mBalance_)) - earmarked_);
    }

    /* ============ totalAccruedYield ============ */
    function test_totalAccruedYield() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(909);
        _wrappedMToken.setTotalEarningSupply(1_000);

        assertEq(_wrappedMToken.totalAccruedYield(), 0);

        _wrappedMToken.setTotalEarningPrincipal(1_000);

        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        _wrappedMToken.setTotalEarningSupply(900);

        assertEq(_wrappedMToken.totalAccruedYield(), 200);

        _mToken.setCurrentIndex(1_331000000000);

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

    function _getFuzzedIndices(
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) internal pure returns (uint128, uint128, uint128) {
        currentMIndex_ = uint128(bound(currentMIndex_, _EXP_SCALED_ONE, 10 * _EXP_SCALED_ONE));
        enableMIndex_ = uint128(bound(enableMIndex_, _EXP_SCALED_ONE, currentMIndex_));

        disableIndex_ = uint128(
            bound(disableIndex_, _EXP_SCALED_ONE, (currentMIndex_ * _EXP_SCALED_ONE) / enableMIndex_)
        );

        return (currentMIndex_, enableMIndex_, disableIndex_);
    }

    function _setupIndexes(
        bool earningEnabled_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) internal {
        _mToken.setCurrentIndex(currentMIndex_);
        _wrappedMToken.setDisableIndex(disableIndex_);

        if (earningEnabled_) {
            _mToken.setIsEarning(address(_wrappedMToken), true);
            _wrappedMToken.setEnableMIndex(enableMIndex_);
        }
    }

    function _getFuzzedBalances(
        uint240 balanceWithYield_,
        uint240 balance_,
        uint240 maxAmount_
    ) internal view returns (uint240, uint240) {
        uint128 currentIndex_ = _wrappedMToken.currentIndex();

        balanceWithYield_ = uint240(bound(balanceWithYield_, 0, maxAmount_));
        balance_ = uint240(bound(balance_, (balanceWithYield_ * _EXP_SCALED_ONE) / currentIndex_, balanceWithYield_));

        return (balanceWithYield_, balance_);
    }

    function _setupAccount(
        address account_,
        bool accountEarning_,
        uint240 balanceWithYield_,
        uint240 balance_
    ) internal {
        if (accountEarning_) {
            uint112 principal_ = IndexingMath.getPrincipalAmountRoundedDown(
                balanceWithYield_,
                _wrappedMToken.currentIndex()
            );

            _wrappedMToken.setAccountOf(account_, balance_, principal_, false, false);
            _wrappedMToken.setTotalEarningPrincipal(_wrappedMToken.totalEarningPrincipal() + principal_);
            _wrappedMToken.setTotalEarningSupply(_wrappedMToken.totalEarningSupply() + balance_);
        } else {
            _wrappedMToken.setAccountOf(account_, balance_);
            _wrappedMToken.setTotalNonEarningSupply(_wrappedMToken.totalNonEarningSupply() + balance_);
        }
    }
}
