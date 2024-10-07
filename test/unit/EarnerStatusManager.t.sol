// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IEarnerStatusManager } from "../../src/interfaces/IEarnerStatusManager.sol";

import { MockRegistrar } from "./../utils/Mocks.sol";
import { EarnerStatusManagerHarness } from "../utils/EarnerStatusManagerHarness.sol";

contract EarnerStatusManagerTests is Test {
    bytes32 internal constant _EARNERS_LIST_IGNORED = "earners_list_ignored";
    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _EARNER_STATUS_ADMIN_LIST = "wm_earner_status_admins";

    address internal _admin = makeAddr("admin");

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    MockRegistrar internal _registrar;
    EarnerStatusManagerHarness internal _earnerStatusManager;

    function setUp() external {
        _registrar = new MockRegistrar();
        _earnerStatusManager = new EarnerStatusManagerHarness(address(_registrar));

        _registrar.setListContains(_EARNER_STATUS_ADMIN_LIST, _admin, true);
    }

    /* ============ initial state ============ */
    function test_initialState() external view {
        assertEq(_earnerStatusManager.registrar(), address(_registrar));
    }

    /* ============ constructor ============ */
    function test_constructor_zeroRegistrar() external {
        vm.expectRevert(IEarnerStatusManager.ZeroRegistrar.selector);
        new EarnerStatusManagerHarness(address(0));
    }

    /* ============ setEarnerStatus ============ */
    function test_setEarnerStatus_notAdmin() external {
        vm.expectRevert(IEarnerStatusManager.NotEarnerStatusAdmin.selector);

        vm.prank(_alice);
        _earnerStatusManager.setEarnerStatus(_alice, true);
    }

    function test_setEarnerStatus() external {
        vm.prank(_admin);
        _earnerStatusManager.setEarnerStatus(_alice, true);

        assertTrue(_earnerStatusManager.getInternalEarnerStatus(_alice));
    }

    /* ============ setEarnerStatuses ============ */
    function test_setEarnerStatuses_notAdmin() external {
        vm.expectRevert(IEarnerStatusManager.NotEarnerStatusAdmin.selector);

        address[] memory accounts_ = new address[](0);
        bool[] memory earnerStatuses = new bool[](0);

        vm.prank(_alice);
        _earnerStatusManager.setEarnerStatuses(accounts_, earnerStatuses);
    }

    function test_setEarnerStatuses_arrayLengthMismatch() external {
        address[] memory accounts_ = new address[](1);
        bool[] memory earnerStatuses = new bool[](2);

        vm.expectRevert(IEarnerStatusManager.ArrayLengthMismatch.selector);

        vm.prank(_admin);
        _earnerStatusManager.setEarnerStatuses(accounts_, earnerStatuses);
    }

    function test_setEarnerStatuses() external {
        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        bool[] memory earnerStatuses = new bool[](2);
        earnerStatuses[0] = true;
        earnerStatuses[1] = true;

        vm.prank(_admin);
        _earnerStatusManager.setEarnerStatuses(accounts_, earnerStatuses);

        assertTrue(_earnerStatusManager.getInternalEarnerStatus(_alice));
        assertTrue(_earnerStatusManager.getInternalEarnerStatus(_bob));
    }

    /* ============ earnerStatusFor ============ */
    function test_earnerStatusFor_listIgnored() external {
        assertFalse(_earnerStatusManager.earnerStatusFor(_alice));

        _registrar.set(_EARNERS_LIST_IGNORED, bytes32(uint256(1)));

        assertTrue(_earnerStatusManager.earnerStatusFor(_alice));
    }

    function test_earnerStatusFor_inList() external {
        assertFalse(_earnerStatusManager.earnerStatusFor(_alice));

        _registrar.setListContains(_EARNERS_LIST, _alice, true);

        assertTrue(_earnerStatusManager.earnerStatusFor(_alice));
    }

    function test_earnerStatusFor_setByAdmin() external {
        assertFalse(_earnerStatusManager.earnerStatusFor(_alice));

        _earnerStatusManager.setInternalEarnerStatus(_alice, true);

        assertTrue(_earnerStatusManager.earnerStatusFor(_alice));
    }

    function test_earnerStatusFor_listIgnoredAndInList() external {
        assertFalse(_earnerStatusManager.earnerStatusFor(_alice));

        _registrar.set(_EARNERS_LIST_IGNORED, bytes32(uint256(1)));
        _registrar.setListContains(_EARNERS_LIST, _alice, true);

        assertTrue(_earnerStatusManager.earnerStatusFor(_alice));
    }

    function test_earnerStatusFor_inListAndSetByAdmin() external {
        assertFalse(_earnerStatusManager.earnerStatusFor(_alice));

        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _earnerStatusManager.setInternalEarnerStatus(_alice, true);

        assertTrue(_earnerStatusManager.earnerStatusFor(_alice));
    }

    function test_earnerStatusFor_listIgnoredSetByAdmin() external {
        assertFalse(_earnerStatusManager.earnerStatusFor(_alice));

        _registrar.set(_EARNERS_LIST_IGNORED, bytes32(uint256(1)));
        _earnerStatusManager.setInternalEarnerStatus(_alice, true);

        assertTrue(_earnerStatusManager.earnerStatusFor(_alice));
    }

    function test_earnerStatusFor_listIgnoredAndInListAndSetByAdmin() external {
        assertFalse(_earnerStatusManager.earnerStatusFor(_alice));

        _registrar.set(_EARNERS_LIST_IGNORED, bytes32(uint256(1)));
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _earnerStatusManager.setInternalEarnerStatus(_alice, true);

        assertTrue(_earnerStatusManager.earnerStatusFor(_alice));
    }

    /* ============ isEarnerListIgnored ============ */
    function test_isEarnerListIgnored() external {
        assertFalse(_earnerStatusManager.isEarnerListIgnored());

        _registrar.set(_EARNERS_LIST_IGNORED, bytes32(uint256(1)));

        assertTrue(_earnerStatusManager.isEarnerListIgnored());
    }

    /* ============ isInEarnerList ============ */
    function test_isInEarnerList() external {
        assertFalse(_earnerStatusManager.isInEarnerList(_alice));

        _registrar.setListContains(_EARNERS_LIST, _alice, true);

        assertTrue(_earnerStatusManager.isInEarnerList(_alice));
    }

    /* ============ isEarnerStatusAdmin ============ */
    function test_isEarnerStatusAdmin() external view {
        assertTrue(_earnerStatusManager.isEarnerStatusAdmin(_admin));
        assertFalse(_earnerStatusManager.isEarnerStatusAdmin(_alice));
    }
}
