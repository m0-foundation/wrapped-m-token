// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {
    IAccessControl
} from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import {
    PausableUpgradeable
} from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { IndexingMath } from "../../lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { Proxy } from "../../lib/common/src/Proxy.sol";

import {
    IForcedTransferable
} from "../../lib/evm-m-extensions/src/components/forcedTransferable/IForcedTransferable.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/freezable/IFreezable.sol";
import { IPausable } from "../../lib/evm-m-extensions/src/components/pausable/IPausable.sol";

import { ISwapFacilityLike } from "../../src/interfaces/ISwapFacilityLike.sol";
import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { WrappedMTokenHarness } from "../harness/WrappedMTokenHarness.sol";

import { BaseUnitTest } from "../utils/BaseUnitTest.sol";
import { MockM, MockRegistrar, MockSwapFacility } from "../utils/Mocks.sol";

// TODO: All operations involving earners should include demonstration of accrued yield being added to their balance.
// TODO: Add relevant unit tests while earning enabled/disabled.
contract WrappedMTokenTests is BaseUnitTest {
    WrappedMTokenHarness internal _implementation;

    function setUp() external {
        _registrar = new MockRegistrar();

        _mToken = new MockM();

        _swapFacility = new MockSwapFacility(address(_mToken));

        _implementation = new WrappedMTokenHarness(
            address(_mToken),
            address(_registrar),
            _excessDestination,
            address(_swapFacility),
            _migrationAdmin
        );

        _wrappedMToken = WrappedMTokenHarness(address(new Proxy(address(_implementation))));
        _wrappedMToken.initialize(_admin, _freezeManager, _pauser, _forcedTransferManager);
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
        assertEq(_wrappedMToken.swapFacility(), address(_swapFacility));
        assertEq(_wrappedMToken.name(), "M (Wrapped) by M0");
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

    function test_constructor_zeroExcessDestination() external {
        vm.expectRevert(IWrappedMToken.ZeroExcessDestination.selector);
        new WrappedMTokenHarness(address(_mToken), address(_registrar), address(0), address(0), address(0));
    }

    function test_constructor_zeroSwapFacility() external {
        vm.expectRevert(IWrappedMToken.ZeroSwapFacility.selector);
        new WrappedMTokenHarness(address(_mToken), address(_registrar), _excessDestination, address(0), address(0));
    }

    function test_constructor_zeroMigrationAdmin() external {
        vm.expectRevert(IWrappedMToken.ZeroMigrationAdmin.selector);
        new WrappedMTokenHarness(
            address(_mToken),
            address(_registrar),
            _excessDestination,
            address(_swapFacility),
            address(0)
        );
    }

    function test_constructor_zeroImplementation() external {
        vm.expectRevert();
        WrappedMTokenHarness(address(new Proxy(address(0))));
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertTrue(IAccessControl(address(_wrappedMToken)).hasRole(bytes32(0x00), _admin));
        assertTrue(IAccessControl(address(_wrappedMToken)).hasRole(_FREEZE_MANAGER_ROLE, _freezeManager));
        assertTrue(IAccessControl(address(_wrappedMToken)).hasRole(_PAUSER_ROLE, _pauser));
        assertTrue(
            IAccessControl(address(_wrappedMToken)).hasRole(_FORCED_TRANSFER_MANAGER_ROLE, _forcedTransferManager)
        );
    }

    function test_initialize_zeroAdmin() external {
        WrappedMTokenHarness wrappedMToken_ = WrappedMTokenHarness(address(new Proxy(address(_implementation))));

        vm.expectRevert(IWrappedMToken.ZeroAdmin.selector);
        wrappedMToken_.initialize(address(0), _freezeManager, _pauser, _forcedTransferManager);
    }

    function test_initialize_zeroFreezeManager() external {
        WrappedMTokenHarness wrappedMToken_ = WrappedMTokenHarness(address(new Proxy(address(_implementation))));

        vm.expectRevert(IFreezable.ZeroFreezeManager.selector);
        wrappedMToken_.initialize(_admin, address(0), _pauser, _forcedTransferManager);
    }

    function test_initialize_zeroPauser() external {
        WrappedMTokenHarness wrappedMToken_ = WrappedMTokenHarness(address(new Proxy(address(_implementation))));

        vm.expectRevert(IPausable.ZeroPauser.selector);
        wrappedMToken_.initialize(_admin, _freezeManager, address(0), _forcedTransferManager);
    }

    function test_initialize_zeroForcedTransferManager() external {
        WrappedMTokenHarness wrappedMToken_ = WrappedMTokenHarness(address(new Proxy(address(_implementation))));

        vm.expectRevert(IForcedTransferable.ZeroForcedTransferManager.selector);
        wrappedMToken_.initialize(_admin, _freezeManager, _pauser, address(0));
    }

    /* ============ _approve ============ */

    function test_approve_frozenAccount() public {
        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        vm.prank(_alice);
        _wrappedMToken.approve(_bob, 1_000);
    }

    function test_approve_frozenSpender() public {
        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _bob));

        vm.prank(_alice);
        _wrappedMToken.approve(_bob, 1_000);
    }

    /* ============ _wrap ============ */
    function test_internalWrap_enforcedPause() external {
        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(_alice);
        _wrappedMToken.internalWrap(_alice, _alice, 1_000);
    }

    function test_internalWrap_frozenAccount() external {
        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        vm.prank(_alice);
        _wrappedMToken.internalWrap(_alice, _bob, 1_000);
    }

    function test_internalWrap_frozenRecipient() external {
        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _bob));

        vm.prank(_alice);
        _wrappedMToken.internalWrap(_alice, _bob, 1_000);
    }

    function test_internalWrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(_alice);
        _wrappedMToken.internalWrap(_alice, _alice, 0);
    }

    function test_internalWrap_invalidRecipient() external {
        _mToken.setBalanceOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_alice);
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

        vm.prank(_alice);
        _wrappedMToken.internalWrap(_alice, _alice, 1_000);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 2_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 2_000);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
    }

    function test_internalWrap_toEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _mToken.setBalanceOf(_alice, 1_002);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 999);

        vm.prank(_alice);
        _wrappedMToken.internalWrap(_alice, _alice, 999);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 + 908);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 + 999);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 + 909); // round up total earning principal
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 + 999);
        assertEq(_wrappedMToken.totalAccruedYield(), 101);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 1);

        vm.prank(_alice);
        _wrappedMToken.internalWrap(_alice, _alice, 1);

        // No change due to principal round down on wrap.
        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 + 908 + 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 + 999 + 1);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 98);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 + 908 + 2);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 + 999 + 1);
        assertEq(_wrappedMToken.totalAccruedYield(), 101);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 2);

        vm.prank(_alice);
        _wrappedMToken.internalWrap(_alice, _alice, 2);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 + 908 + 0 + 1);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 + 999 + 1 + 2);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 97);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 + 908 + 0 + 4);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 + 999 + 1 + 2);
        assertEq(_wrappedMToken.totalAccruedYield(), 102);
    }

    /* ============ wrap ============ */
    function test_wrap_notSwapFacility() external {
        vm.expectRevert(IWrappedMToken.NotSwapFacility.selector);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, 1_000);
    }

    function test_wrap_frozenAccount() external {
        _mToken.setBalanceOf(_alice, 1_000);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.mockCall(
            address(_swapFacility),
            abi.encodeWithSelector(ISwapFacilityLike.msgSender.selector),
            abi.encode(_alice)
        );

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        vm.prank(_alice);
        _swapFacility.swapInM(address(_wrappedMToken), 1_000, _alice);
    }

    function test_wrap_frozenRecipient() external {
        _mToken.setBalanceOf(_alice, 1_000);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_bob);

        vm.mockCall(
            address(_swapFacility),
            abi.encodeWithSelector(ISwapFacilityLike.msgSender.selector),
            abi.encode(_alice)
        );

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _bob));

        vm.prank(_alice);
        _swapFacility.swapInM(address(_wrappedMToken), 1_000, _bob);
    }

    function test_wrap_invalidAmount() external {
        _mToken.setBalanceOf(_alice, uint256(type(uint240).max) + 1);

        vm.mockCall(
            address(_swapFacility),
            abi.encodeWithSelector(ISwapFacilityLike.msgSender.selector),
            abi.encode(_alice)
        );

        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _swapFacility.swapInM(address(_wrappedMToken), uint256(type(uint240).max) + 1, _alice);
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

        _setupAccount(_alice, earningEnabled_ && accountEarning_, balanceWithYield_, balance_);

        wrapAmount_ = uint240(bound(wrapAmount_, 0, _getMaxAmount(_wrappedMToken.currentIndex()) - balanceWithYield_));

        _mToken.setBalanceOf(_alice, wrapAmount_);

        if (wrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(0), _alice, wrapAmount_);
        }

        vm.mockCall(
            address(_swapFacility),
            abi.encodeWithSelector(ISwapFacilityLike.msgSender.selector),
            abi.encode(_alice)
        );

        vm.startPrank(_alice);
        _swapFacility.swapInM(address(_wrappedMToken), wrapAmount_, _alice);

        if (wrapAmount_ == 0) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ + wrapAmount_);

        assertEq(
            earningEnabled_ && accountEarning_
                ? _wrappedMToken.totalEarningSupply()
                : _wrappedMToken.totalNonEarningSupply(),
            _wrappedMToken.balanceOf(_alice)
        );
    }

    /* ============ wrap entire balance ============ */
    function test_wrap_entireBalance_invalidAmount() external {
        _mToken.setBalanceOf(_alice, uint256(type(uint240).max) + 1);

        vm.mockCall(
            address(_swapFacility),
            abi.encodeWithSelector(ISwapFacilityLike.msgSender.selector),
            abi.encode(_alice)
        );

        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _swapFacility.swapInM(address(_wrappedMToken), uint256(type(uint240).max) + 1, _alice);
    }

    /* ============ _unwrap ============ */
    function test_internalUnwrap_enforcedPause() external {
        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 1_000);
    }

    function test_internal_unwrap_frozenAccount() external {
        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 1_000);
    }

    function test_internalUnwrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 0);
    }

    function test_internalUnwrap_insufficientBalance_fromNonEarner() external {
        _wrappedMToken.setAccountOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 1_000);
    }

    function test_internalUnwrap_insufficientBalance_fromEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setAccountOf(_alice, 999, 909, false);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 1_000);
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

        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 1);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 999);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 999);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 499);

        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 499);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), 500);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 500);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 500);

        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 500);

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

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalAccruedYield(), 100);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 1);

        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 1);

        // Change due to principal round up on unwrap.
        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 - 1);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 - 1);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 - 1);
        assertEq(_wrappedMToken.totalAccruedYield(), 101);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 499);

        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 499);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 - 1 - 454);
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 - 1 - 499);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 - 1 - 454 + 2);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 - 1 - 499);
        assertEq(_wrappedMToken.totalAccruedYield(), 102);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, address(0), 500);

        vm.prank(_alice);
        _wrappedMToken.internalUnwrap(_alice, 500);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 1_000 - 1 - 454 - 455); // 0
        assertEq(_wrappedMToken.balanceOf(_alice), 1_000 - 1 - 499 - 500); // 0
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 1_000 - 1 - 454 - 455 + 3);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000 - 1 - 499 - 500); // 0
        assertEq(_wrappedMToken.totalAccruedYield(), 103);
    }

    /* ============ unwrap ============ */
    function test_unwrap_notSwapFacility() external {
        vm.expectRevert(IWrappedMToken.NotSwapFacility.selector);

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 1_000);
    }

    function test_unwrap_frozenAccount() external {
        uint256 amount_ = 1_000;
        _wrappedMToken.setAccountOf(_alice, amount_);

        vm.prank(_alice);
        _wrappedMToken.approve(address(_swapFacility), amount_);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.mockCall(
            address(_swapFacility),
            abi.encodeWithSelector(ISwapFacilityLike.msgSender.selector),
            abi.encode(_alice)
        );

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        vm.prank(_alice);
        _swapFacility.swapOutM(address(_wrappedMToken), amount_, _alice);
    }

    function test_unwrap_invalidAmount() external {
        vm.prank(_alice);
        _wrappedMToken.approve(address(_swapFacility), uint256(type(uint240).max) + 1);

        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _swapFacility.swapOutM(address(_wrappedMToken), uint256(type(uint240).max) + 1, _alice);
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

        vm.startPrank(_alice);
        _wrappedMToken.approve(address(_swapFacility), unwrapAmount_);

        if (unwrapAmount_ == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, (0)));
        } else if (unwrapAmount_ > balance_) {
            vm.expectRevert(
                abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, balance_, unwrapAmount_)
            );
        } else {
            vm.expectEmit();
            emit IERC20.Transfer(address(_swapFacility), address(0), unwrapAmount_);
        }

        vm.mockCall(
            address(_swapFacility),
            abi.encodeWithSelector(ISwapFacilityLike.msgSender.selector),
            abi.encode(_alice)
        );

        vm.startPrank(_alice);
        _swapFacility.swapOutM(address(_wrappedMToken), unwrapAmount_, _alice);

        if ((unwrapAmount_ == 0) || (unwrapAmount_ > balance_)) return;

        assertEq(_wrappedMToken.balanceOf(_alice), balance_ - unwrapAmount_);

        assertEq(
            accountEarning_ ? _wrappedMToken.totalEarningSupply() : _wrappedMToken.totalNonEarningSupply(),
            _wrappedMToken.balanceOf(_alice)
        );
    }

    /* ============ claimFor ============ */
    function test_claimFor_enforcedPause() external {
        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _wrappedMToken.claimFor(_alice);
    }

    function test_claimFor_frozenAccount() external {
        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        vm.prank(_alice);
        _wrappedMToken.claimFor(_alice);
    }

    function test_claimFor_frozenClaimRecipient() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, true); // 1_100 balance with yield.
        _wrappedMToken.setInternalClaimRecipient(_alice, _bob);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _bob));

        vm.prank(_alice);
        _wrappedMToken.claimFor(_alice);
    }

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

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

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

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

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
        assertEq(_wrappedMToken.totalEarningPrincipal(), 910);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000); // round up total earning principal
        assertEq(_wrappedMToken.totalAccruedYield(), 1);
    }

    function testFuzz_claimFor(
        bool earningEnabled_,
        bool accountEarning_,
        uint240 balanceWithYield_,
        uint240 balance_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_,
        bool claimOverride_
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

        if (claimOverride_ && (accruedYield_ != 0)) {
            vm.expectEmit();
            emit IERC20.Transfer(_alice, _charlie, accruedYield_);
        }

        assertEq(_wrappedMToken.claimFor(_alice), accruedYield_);

        assertEq(
            _wrappedMToken.totalSupply(),
            _wrappedMToken.balanceOf(_alice) + _wrappedMToken.balanceOf(_bob) + _wrappedMToken.balanceOf(_charlie)
        );
    }

    /* ============ claimExcess ============ */
    function test_claimExcess_enforcedPause() external {
        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _wrappedMToken.claimExcess();
    }

    function testFuzz_claimExcess(
        bool earningEnabled_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_,
        uint240 totalNonEarningSupply_,
        uint240 totalProjectedEarningSupply_,
        uint112 mPrincipalBalance_
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

        uint240 earmarked_ = totalNonEarningSupply_ + _wrappedMToken.projectedEarningSupply();
        int240 excess_ = int240(mBalance_) - int240(earmarked_);

        if (excess_ > 0) {
            vm.expectEmit(false, false, false, false);
            emit IWrappedMToken.ExcessClaimed(uint240(excess_));
        }

        uint240 claimed_ = _wrappedMToken.claimExcess();

        if (excess_ <= 0) {
            assertEq(claimed_, 0);
        } else {
            assertLe(claimed_, uint240(excess_));
        }

        assertEq(_wrappedMToken.balanceOf(_excessDestination), claimed_);
    }

    /* ============ transfer ============ */
    function test_transfer_enforcedPause() external {
        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 100);
    }

    function test_transfer_invalidRecipient() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_alice);
        _wrappedMToken.transfer(address(0), 1_000);
    }

    function test_transfer_frozenSender() external {
        uint256 amount = 1_000;
        _wrappedMToken.setAccountOf(_alice, amount);

        // Alice allows Charlie to transfer tokens on her behalf
        vm.prank(_alice);
        _wrappedMToken.approve(_charlie, amount);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_charlie);

        // Reverts cause Charlie is frozen and cannot transfer tokens on Alice's behalf
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _charlie));

        vm.prank(_charlie);
        _wrappedMToken.transferFrom(_alice, _bob, amount);
    }

    function test_transfer_frozenAccount() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);
    }

    function test_transfer_frozenRecipient() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _bob));

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);
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

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.
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
        assertEq(_wrappedMToken.totalEarningPrincipal(), 546);
        assertEq(_wrappedMToken.totalEarningSupply(), 500);
        assertEq(_wrappedMToken.totalAccruedYield(), 101);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 1);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 1);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 544);
        assertEq(_wrappedMToken.balanceOf(_alice), 499);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 99);

        assertEq(_wrappedMToken.balanceOf(_bob), 1_001);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_001);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 546);
        assertEq(_wrappedMToken.totalEarningSupply(), 499);
        assertEq(_wrappedMToken.totalAccruedYield(), 102);
    }

    function test_transfer_fromNonEarner_toEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(500);
        _wrappedMToken.setTotalEarningSupply(500);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);
        _wrappedMToken.setAccountOf(_bob, 500, 500, false); // 550 balance with yield.

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
        assertEq(_wrappedMToken.totalEarningPrincipal(), 955);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
        assertEq(_wrappedMToken.totalAccruedYield(), 51);
    }

    function test_transfer_fromEarner_toEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_500);
        _wrappedMToken.setTotalEarningSupply(1_500);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.
        _wrappedMToken.setAccountOf(_bob, 500, 500, false); // 550 balance with yield.

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

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

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
    function test_startEarningFor_enforcedPause() external {
        _wrappedMToken.setEnableMIndex(1_100000000000);

        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor_notApprovedEarner() external {
        _mToken.setCurrentIndex(1_100000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.NotApprovedEarner.selector, _alice));
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor_earningIsDisabled() external {
        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor_frozenAccount() external {
        _mToken.setCurrentIndex(1_100000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarning_overflow() external {
        _mToken.setCurrentIndex(1_100000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        uint240 aliceBalance_ = uint240(type(uint112).max) + 20; // TODO: _getMaxAmount(1_100000000000) + 2; ?

        _wrappedMToken.setTotalNonEarningSupply(aliceBalance_);

        _wrappedMToken.setAccountOf(_alice, aliceBalance_);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.expectRevert(UIntMath.InvalidUInt112.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.expectEmit();
        emit IWrappedMToken.StartedEarning(_alice);

        _wrappedMToken.startEarningFor(_alice);

        assertEq(_wrappedMToken.isEarning(_alice), true);
        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 909);
        assertEq(_wrappedMToken.balanceOf(_alice), 1000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 910);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000);
    }

    function testFuzz_startEarningFor(
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

        _setupIndexes(true, currentMIndex_, enableMIndex_, disableIndex_);

        uint128 currentIndex_ = _wrappedMToken.currentIndex();

        balance_ = uint240(bound(balance_, 0, _getMaxAmount(currentIndex_)));

        _setupAccount(_alice, false, 0, balance_);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.expectEmit();
        emit IWrappedMToken.StartedEarning(_alice);

        _wrappedMToken.startEarningFor(_alice);

        uint112 principalDown_ = IndexingMath.getPrincipalAmountRoundedDown(balance_, currentIndex_);
        uint112 principalUp_ = IndexingMath.getPrincipalAmountRoundedUp(balance_, currentIndex_);

        assertEq(_wrappedMToken.isEarning(_alice), true);
        assertEq(_wrappedMToken.earningPrincipalOf(_alice), principalDown_);
        assertEq(_wrappedMToken.balanceOf(_alice), balance_);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), balance_);
        assertEq(_wrappedMToken.totalEarningPrincipal(), principalUp_);
    }

    /* ============ startEarningFor batch ============ */
    function test_startEarningFor_batch_enforcedPause() external {
        _wrappedMToken.setEnableMIndex(1_100000000000);

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _wrappedMToken.startEarningFor(accounts_);
    }

    function test_startEarningFor_batch_earningIsDisabled() external {
        vm.expectRevert(IWrappedMToken.EarningIsDisabled.selector);
        _wrappedMToken.startEarningFor(new address[](2));
    }

    function test_startEarningFor_batch_notApprovedEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.NotApprovedEarner.selector, _bob));
        _wrappedMToken.startEarningFor(accounts_);
    }

    function test_startEarningFor_batch_frozenAccount() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);
        _registrar.setListContains(_EARNERS_LIST_NAME, _bob, true);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_bob);

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _bob));
        _wrappedMToken.startEarningFor(accounts_);
    }

    function test_startEarningFor_batch() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);
        _registrar.setListContains(_EARNERS_LIST_NAME, _bob, true);

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
        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.IsApprovedEarner.selector, _alice));
        _wrappedMToken.stopEarningFor(_alice);
    }

    function test_stopEarningFor_enforcedPause() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false);

        vm.prank(_pauser);
        _wrappedMToken.pause();

        // stopEarningFor succeeds while paused: skipTransfer=true, yield stays on account.
        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        _wrappedMToken.stopEarningFor(_alice);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_100);
        assertEq(_wrappedMToken.isEarning(_alice), false);
    }

    function test_stopEarningFor_frozenAccount() external {
        _wrappedMToken.setIsEarningOf(_alice, true);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        _wrappedMToken.stopEarningFor(_alice);
    }

    function test_stopEarningFor_frozenClaimRecipient() external {
        _wrappedMToken.setIsEarningOf(_alice, true);

        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, true); // 1_100 balance with yield.
        _wrappedMToken.setInternalClaimRecipient(_alice, _bob);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_bob);

        // Not paused, so skipTransfer=false: _claim tries to transfer yield to frozen _bob → reverts.
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _bob));

        _wrappedMToken.stopEarningFor(_alice);
    }

    function test_stopEarningFor() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

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
        (, , , bool hasClaimRecipient_) = _wrappedMToken.getAccountOf(_alice);

        assertFalse(hasClaimRecipient_);
        assertEq(_wrappedMToken.getInternalClaimRecipientOf(_alice), address(0));

        vm.prank(_alice);
        _wrappedMToken.setClaimRecipient(_alice);

        (, , , hasClaimRecipient_) = _wrappedMToken.getAccountOf(_alice);

        assertTrue(hasClaimRecipient_);
        assertEq(_wrappedMToken.getInternalClaimRecipientOf(_alice), _alice);

        vm.prank(_alice);
        _wrappedMToken.setClaimRecipient(_bob);

        (, , , hasClaimRecipient_) = _wrappedMToken.getAccountOf(_alice);

        assertTrue(hasClaimRecipient_);
        assertEq(_wrappedMToken.getInternalClaimRecipientOf(_alice), _bob);

        vm.prank(_alice);
        _wrappedMToken.setClaimRecipient(address(0));

        (, , , hasClaimRecipient_) = _wrappedMToken.getAccountOf(_alice);

        assertFalse(hasClaimRecipient_);
        assertEq(_wrappedMToken.getInternalClaimRecipientOf(_alice), address(0));
    }

    /* ============ stopEarningFor batch ============ */
    function test_stopEarningFor_batch_isApprovedEarner() external {
        _registrar.setListContains(_EARNERS_LIST_NAME, _bob, true);

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.IsApprovedEarner.selector, _bob));
        _wrappedMToken.stopEarningFor(accounts_);
    }

    function test_stopEarningFor_batch() external {
        _wrappedMToken.setAccountOf(_alice, 0, 0, false);
        _wrappedMToken.setAccountOf(_bob, 0, 0, false);

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_bob);

        _wrappedMToken.stopEarningFor(accounts_);
    }

    /* ============ freeze / _beforeFreeze ============ */
    function test_freeze_claimsAccruedYield() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        vm.expectEmit();
        emit IFreezable.Frozen(_alice, block.timestamp);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_100);
        assertEq(_wrappedMToken.isEarning(_alice), false);
        assertTrue(_wrappedMToken.isFrozen(_alice));

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_100);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningPrincipal(), 0);
    }

    function test_freeze_skipsClaimRecipientRouting() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, true);
        _wrappedMToken.setInternalClaimRecipient(_alice, _bob); // has explicit claim recipient

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_bob);

        // Pause the contract so skipTransfer=true in _beforeFreeze -> _stopEarningFor -> _claim.
        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _bob, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        vm.expectEmit();
        emit IFreezable.Frozen(_alice, block.timestamp);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_100);
        assertEq(_wrappedMToken.balanceOf(_bob), 0); // yield not routed (paused)
        assertEq(_wrappedMToken.isEarning(_alice), false);
        assertTrue(_wrappedMToken.isFrozen(_alice));
    }

    function test_freeze_whilePaused() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectEmit();
        emit IFreezable.Frozen(_alice, block.timestamp);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        assertTrue(_wrappedMToken.isFrozen(_alice));
    }

    function test_freeze_approvedEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false);

        // _alice is an approved earner — freeze still works.
        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.expectEmit();
        emit IWrappedMToken.Claimed(_alice, _alice, 100);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), _alice, 100);

        vm.expectEmit();
        emit IWrappedMToken.StoppedEarning(_alice);

        vm.expectEmit();
        emit IFreezable.Frozen(_alice, block.timestamp);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_100);
        assertEq(_wrappedMToken.isEarning(_alice), false);
        assertTrue(_wrappedMToken.isFrozen(_alice));
    }

    /* ============ forceTransfer ============ */
    function test_forceTransfer_unauthorized() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _alice,
                _FORCED_TRANSFER_MANAGER_ROLE
            )
        );

        vm.prank(_alice);
        _wrappedMToken.forceTransfer(_alice, _bob, 1_000);
    }

    function test_forceTransfer_notFrozen() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, _alice));

        vm.prank(_forcedTransferManager);
        _wrappedMToken.forceTransfer(_alice, _bob, 500);
    }

    function test_forceTransfer_frozenEarnerCannotBeReEnabled() external {
        // Regression: a frozen account must not be re-enabled as an earner, otherwise
        // `forceTransfer` would run `_subtractNonEarningAmount` on an earning account and
        // corrupt supply accounting.
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalEarningPrincipal(1_000);
        _wrappedMToken.setTotalEarningSupply(1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false);

        // `_alice` remains an approved earner even after being frozen.
        _registrar.setListContains(_EARNERS_LIST_NAME, _alice, true);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        // Freezing claimed yield (100) and stopped earning, moving the balance to non-earning.
        assertEq(_wrappedMToken.isEarning(_alice), false);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_100);

        // Re-enabling earning on the still-frozen account must revert.
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));
        _wrappedMToken.startEarningFor(_alice);

        // The account stays non-earning, so `forceTransfer` keeps accounting correct.
        vm.prank(_forcedTransferManager);
        _wrappedMToken.forceTransfer(_alice, _bob, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 600);
        assertEq(_wrappedMToken.balanceOf(_bob), 500);
        assertEq(_wrappedMToken.totalEarningSupply(), 0);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_100);
    }

    function test_forceTransfer_invalidRecipient() external {
        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_forcedTransferManager);
        _wrappedMToken.forceTransfer(_alice, address(0), 500);
    }

    function test_forceTransfer_frozenRecipient() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_bob);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _bob));

        vm.prank(_forcedTransferManager);
        _wrappedMToken.forceTransfer(_alice, _bob, 500);
    }

    function test_forceTransfer_zeroAmount() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 0);

        vm.expectEmit();
        emit IForcedTransferable.ForcedTransfer(_alice, _bob, _forcedTransferManager, 0);

        vm.prank(_forcedTransferManager);
        _wrappedMToken.forceTransfer(_alice, _bob, 0);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.balanceOf(_bob), 0);
    }

    function test_forceTransfer_insufficientBalance() external {
        _wrappedMToken.setAccountOf(_alice, 1_000);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 1_000, 2_000));

        vm.prank(_forcedTransferManager);
        _wrappedMToken.forceTransfer(_alice, _bob, 2_000);
    }

    function test_forceTransfer_toNonEarner() external {
        _wrappedMToken.setTotalNonEarningSupply(1_500);

        _wrappedMToken.setAccountOf(_alice, 1_000);
        _wrappedMToken.setAccountOf(_bob, 500);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_500);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.expectEmit();
        emit IForcedTransferable.ForcedTransfer(_alice, _bob, _forcedTransferManager, 500);

        vm.prank(_forcedTransferManager);
        _wrappedMToken.forceTransfer(_alice, _bob, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);
        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);

        // Net totalNonEarningSupply unchanged (moved within non-earning).
        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_500);
    }

    function test_forceTransfer_toEarner() external {
        _mToken.setCurrentIndex(1_210000000000);
        _wrappedMToken.setEnableMIndex(1_100000000000);

        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setTotalEarningPrincipal(500);
        _wrappedMToken.setTotalEarningSupply(500);

        _wrappedMToken.setAccountOf(_alice, 1_000);
        _wrappedMToken.setAccountOf(_bob, 500, 500, false);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.expectEmit();
        emit IForcedTransferable.ForcedTransfer(_alice, _bob, _forcedTransferManager, 500);

        vm.prank(_forcedTransferManager);
        _wrappedMToken.forceTransfer(_alice, _bob, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);
        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 500); // decreased by 500
        assertEq(_wrappedMToken.totalEarningSupply(), 1_000); // increased by 500
    }

    function test_forceTransfer_whilePaused() external {
        _wrappedMToken.setTotalNonEarningSupply(1_500);

        _wrappedMToken.setAccountOf(_alice, 1_000);
        _wrappedMToken.setAccountOf(_bob, 500);

        vm.prank(_freezeManager);
        _wrappedMToken.freeze(_alice);

        vm.prank(_pauser);
        _wrappedMToken.pause();

        vm.expectEmit();
        emit IERC20.Transfer(_alice, _bob, 500);

        vm.expectEmit();
        emit IForcedTransferable.ForcedTransfer(_alice, _bob, _forcedTransferManager, 500);

        vm.prank(_forcedTransferManager);
        _wrappedMToken.forceTransfer(_alice, _bob, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);
        assertEq(_wrappedMToken.balanceOf(_bob), 1_000);
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

        _wrappedMToken.setAccountOf(_alice, 500, 500, false); // 550 balance with yield.

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setEarningPrincipalOf(_alice, 1_000); // Earning principal has no bearing on balance.

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_500, false); // 1_815 balance with yield.

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

        _wrappedMToken.setAccountOf(_alice, 500, 500, false); // 550 balance with yield.

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 550);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_100);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.balanceWithYieldOf(_alice), 1_210);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_500, false); // 1_815 balance with yield.

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

        _wrappedMToken.setAccountOf(_alice, 500, 500, false); // 550 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 50);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_000, false); // 1_100 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 210);

        _wrappedMToken.setAccountOf(_alice, 1_000, 1_500, false); // 1_815 balance with yield.

        assertEq(_wrappedMToken.accruedYieldOf(_alice), 815);
    }

    /* ============ earningPrincipalOf ============ */
    function test_earningPrincipalOf() external {
        _wrappedMToken.setAccountOf(_alice, 0, 100, false);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 100);

        _wrappedMToken.setAccountOf(_alice, 0, 200, false);

        assertEq(_wrappedMToken.earningPrincipalOf(_alice), 200);
    }

    /* ============ isEarning ============ */
    function test_isEarning() external {
        _wrappedMToken.setAccountOf(_alice, 0);

        assertFalse(_wrappedMToken.isEarning(_alice));

        _wrappedMToken.setAccountOf(_alice, 0, _EXP_SCALED_ONE, false);

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
        _wrappedMToken.setAccountOf(_alice, 0, 0, true);
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
        _wrappedMToken.setAccountOf(_alice, 0, 0, true);
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

        _mToken.setBalanceOf(address(_wrappedMToken), 2_101);

        assertEq(_wrappedMToken.excess(), 1);

        _mToken.setBalanceOf(address(_wrappedMToken), 2_102);

        assertEq(_wrappedMToken.excess(), 2);

        _mToken.setBalanceOf(address(_wrappedMToken), 3_102);

        assertEq(_wrappedMToken.excess(), 1_002);

        _mToken.setCurrentIndex(1_331000000000);

        assertEq(_wrappedMToken.excess(), 892);
    }

    function testFuzz_excess(
        bool earningEnabled_,
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_,
        uint240 totalNonEarningSupply_,
        uint240 totalProjectedEarningSupply_,
        uint112 mPrincipalBalance_
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

        uint240 earmarked_ = totalNonEarningSupply_ + totalProjectedEarningSupply_;

        assertLe(_wrappedMToken.excess(), int248(uint248(mBalance_)) - int248(uint248(earmarked_)));
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

            _wrappedMToken.setAccountOf(account_, balance_, principal_, false);
            _wrappedMToken.setTotalEarningPrincipal(_wrappedMToken.totalEarningPrincipal() + principal_);
            _wrappedMToken.setTotalEarningSupply(_wrappedMToken.totalEarningSupply() + balance_);
        } else {
            _wrappedMToken.setAccountOf(account_, balance_);
            _wrappedMToken.setTotalNonEarningSupply(_wrappedMToken.totalNonEarningSupply() + balance_);
        }
    }
}
