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

        _wrappedMToken.startEarningM();
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

    /* ============ wrap ============ */

    function test_deposit_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        _wrappedMToken.wrap(_alice, 0);
    }

    function test_deposit_invalidRecipient() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        _wrappedMToken.wrap(address(0), 1_000);
    }

    function test_deposit_invalidAmount() external {
        vm.expectRevert(UIntMath.InvalidUInt240.selector);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, uint256(type(uint240).max) + 1);
    }

    function test_deposit_toNonEarner() external {
        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, 1_000);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), 1_000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 1_000);
        assertEq(_wrappedMToken.principalOfTotalEarningSupply(), 0);
        assertEq(_wrappedMToken.indexOfTotalEarningSupply(), 0);
    }

    function test_deposit_toEarner() external {
        _wrappedMToken.setAccountOf(_alice, true, _EXP_SCALED_ONE, 0);

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

    function test_withdraw_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        _wrappedMToken.unwrap(_alice, 0);
    }

    function test_withdraw_insufficientBalance_fromNonEarner() external {
        _wrappedMToken.setBalanceOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 1_000);
    }

    function test_withdraw_insufficientBalance_fromEarner() external {
        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IWrappedMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 1_000);
    }

    function test_withdraw_fromNonEarner() external {
        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setBalanceOf(_alice, 1_000);

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

    function test_withdraw_fromEarner() external {
        _wrappedMToken.setPrincipalOfTotalEarningSupply(909);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);

        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);

        assertEq(_wrappedMToken.balanceOf(_alice), 999);

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
        _wrappedMToken.setPrincipalOfTotalEarningSupply(455);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);
        _wrappedMToken.setTotalNonEarningSupply(1_000);

        _wrappedMToken.setBalanceOf(_alice, 1_000);

        _wrappedMToken.setAccountOf(_bob, true, _currentIndex, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.internalBalanceOf(_alice), 500);

        assertEq(_wrappedMToken.internalPrincipalOf(_bob), 908);
        assertEq(_wrappedMToken.internalIndexOf(_bob), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_bob), 998);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 500);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_001);
    }

    function test_transfer_fromEarner_toEarner() external {
        _wrappedMToken.setPrincipalOfTotalEarningSupply(1_364);
        _wrappedMToken.setIndexOfTotalEarningSupply(_currentIndex);

        _wrappedMToken.setAccountOf(_alice, true, _currentIndex, 1_000);

        _wrappedMToken.setAccountOf(_bob, true, _currentIndex, 500);

        vm.prank(_alice);
        _wrappedMToken.transfer(_bob, 500);

        assertEq(_wrappedMToken.internalPrincipalOf(_alice), 453);
        assertEq(_wrappedMToken.internalIndexOf(_alice), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_alice), 498);

        assertEq(_wrappedMToken.internalPrincipalOf(_bob), 908);
        assertEq(_wrappedMToken.internalIndexOf(_bob), _currentIndex);
        assertEq(_wrappedMToken.internalBalanceOf(_bob), 998);

        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalEarningSupply(), 1_501);
    }

    /* ============ startEarningFor ============ */
    function test_startEarningFor_notApprovedEarner() external {
        vm.expectRevert(IWrappedMToken.NotApprovedEarner.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor_notInEarningState() external {
        _mToken.stopEarning(address(_wrappedMToken));

        _registrar.setListContains(_EARNERS_LIST, _alice, true);

        vm.expectRevert(IWrappedMToken.NotInEarningState.selector);
        _wrappedMToken.startEarningFor(_alice);
    }

    function test_startEarningFor() external {
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

    /* ============ startEarningM ============ */
    function test_startEarningM_allowedToEarnOnlyOnce() external {
        assertEq(_mToken.isEarning(address(_wrappedMToken)), true);

        _wrappedMToken.stopEarningM();

        vm.expectRevert(IWrappedMToken.AllowedToEarnOnlyOnce.selector);
        _wrappedMToken.startEarningM();
    }

    /* ============ stopEarningM ============ */
    function test_stopEarningM() external {
        assertEq(_mToken.isEarning(address(_wrappedMToken)), true);
        assertEq(_wrappedMToken.mIndexWhenEarningStopped(), 0);

        _wrappedMToken.stopEarningM();

        assertEq(_mToken.isEarning(address(_wrappedMToken)), false);
        assertEq(_wrappedMToken.mIndexWhenEarningStopped(), _mToken.currentIndex());

        _mToken.setCurrentIndex(_currentIndex = _EXP_SCALED_ONE);

        assertEq(_wrappedMToken.currentIndex(), _wrappedMToken.mIndexWhenEarningStopped());
    }

    /* ============ balanceOf ============ */
    function test_balanceOf_nonEarner() external {
        _wrappedMToken.setBalanceOf(_alice, 500);

        assertEq(_wrappedMToken.balanceOf(_alice), 500);

        _wrappedMToken.setBalanceOf(_alice, 1_000);

        assertEq(_wrappedMToken.balanceOf(_alice), 1_000);
    }

    function test_balanceOf_earner() external {
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

    /* ============ utils ============ */
    function _getPrincipalAmountRoundedDown(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return IndexingMath.divide240By128Down(presentAmount_, index_);
    }

    function _getPrincipalAmountRoundedUp(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return IndexingMath.divide240By128Up(presentAmount_, index_);
    }

    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return IndexingMath.multiply112By128Down(principalAmount_, index_);
    }

    function _getPresentAmountRoundedUp(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return IndexingMath.multiply112By128Up(principalAmount_, index_);
    }
}
