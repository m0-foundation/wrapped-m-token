// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IEarnerStatusManager } from "../../src/interfaces/IEarnerStatusManager.sol";

import { MockRegistrar } from "./../utils/Mocks.sol";
import { EarnerStatusManagerHarness } from "../utils/EarnerStatusManagerHarness.sol";

contract EarnerStatusManagerTests is Test {
    bytes32 internal constant _LIST_IGNORED = "earners_list_ignored";
    bytes32 internal constant _LIST = "earners";
    bytes32 internal constant _ADMIN_PREFIX = "wm_earner_status_admin_prefix";

    uint256 internal _adminIndex1 = 1;
    uint256 internal _adminIndex2 = 10;
    uint256 internal _adminIndex3 = 250;

    address internal _admin1 = makeAddr("admin1");
    address internal _admin2 = makeAddr("admin2");
    address internal _admin3 = makeAddr("admin3");

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    MockRegistrar internal _registrar;
    EarnerStatusManagerHarness internal _earnerStatusManager;

    function setUp() external {
        _registrar = new MockRegistrar();
        _earnerStatusManager = new EarnerStatusManagerHarness(address(_registrar));

        _registrar.set(keccak256(abi.encode(_ADMIN_PREFIX, _adminIndex1)), bytes32(uint256(uint160(_admin1))));
        _registrar.set(keccak256(abi.encode(_ADMIN_PREFIX, _adminIndex2)), bytes32(uint256(uint160(_admin2))));
        _registrar.set(keccak256(abi.encode(_ADMIN_PREFIX, _adminIndex3)), bytes32(uint256(uint160(_admin3))));

        _earnerStatusManager.setAdminsBitMask(
            (1 << (_adminIndex1 - 1)) | (1 << (_adminIndex2 - 1)) | (1 << (_adminIndex3 - 1))
        );
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

    /* ============ updateAdminIndex ============ */
    function test_updateAdminIndex_adminIndexAlreadySet() external {
        vm.expectRevert(IEarnerStatusManager.AdminIndexAlreadySet.selector);
        _earnerStatusManager.updateAdminIndex(_adminIndex1);

        vm.expectRevert(IEarnerStatusManager.AdminIndexAlreadySet.selector);
        _earnerStatusManager.updateAdminIndex(256);
    }

    function test_updateAdminIndex_add() external {
        uint256 adminIndex_ = 2;
        address admin_ = makeAddr("admin2");

        _registrar.set(keccak256(abi.encode(_ADMIN_PREFIX, adminIndex_)), bytes32(uint256(uint160(admin_))));

        _earnerStatusManager.updateAdminIndex(adminIndex_);

        assertEq(_earnerStatusManager.getAdmin(adminIndex_), admin_);
    }

    function test_updateAdminIndex_remove() external {
        _registrar.set(keccak256(abi.encode(_ADMIN_PREFIX, _adminIndex1)), bytes32(0));

        _earnerStatusManager.updateAdminIndex(_adminIndex1);

        assertEq(_earnerStatusManager.getAdmin(_adminIndex1), address(0));
    }

    /* ============ setStatus ============ */
    function test_setStatus_notAdmin() external {
        vm.expectRevert(IEarnerStatusManager.NotAdmin.selector);

        vm.prank(_alice);
        _earnerStatusManager.setStatus(_adminIndex1, _alice, true);
    }

    function test_setStatus() external {
        vm.prank(_admin1);
        _earnerStatusManager.setStatus(_adminIndex1, _alice, true);

        assertEq(_earnerStatusManager.getInternalStatus(_alice), 1);
    }

    /* ============ setStatuses ============ */
    function test_setStatuses_notAdmin() external {
        vm.expectRevert(IEarnerStatusManager.NotAdmin.selector);

        address[] memory accounts_ = new address[](0);
        bool[] memory statuses_ = new bool[](0);

        vm.prank(_alice);
        _earnerStatusManager.setStatuses(_adminIndex1, accounts_, statuses_);
    }

    function test_setStatuses_arrayLengthMismatch() external {
        address[] memory accounts_ = new address[](1);
        bool[] memory statuses_ = new bool[](2);

        vm.expectRevert(IEarnerStatusManager.ArrayLengthMismatch.selector);

        vm.prank(_admin1);
        _earnerStatusManager.setStatuses(_adminIndex1, accounts_, statuses_);
    }

    function test_setStatuses() external {
        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        bool[] memory statuses_ = new bool[](2);
        statuses_[0] = true;
        statuses_[1] = true;

        vm.prank(_admin1);
        _earnerStatusManager.setStatuses(_adminIndex1, accounts_, statuses_);

        assertEq(_earnerStatusManager.getInternalStatus(_alice), 1);
        assertEq(_earnerStatusManager.getInternalStatus(_bob), 1);
    }

    /* ============ statusFor ============ */
    function test_statusFor_listIgnored() external {
        assertFalse(_earnerStatusManager.statusFor(_alice));

        _registrar.set(_LIST_IGNORED, bytes32(uint256(1)));

        assertTrue(_earnerStatusManager.statusFor(_alice));
    }

    function test_statusFor_inList() external {
        assertFalse(_earnerStatusManager.statusFor(_alice));

        _registrar.setListContains(_LIST, _alice, true);

        assertTrue(_earnerStatusManager.statusFor(_alice));
    }

    function test_statusFor_setByAdmin() external {
        assertFalse(_earnerStatusManager.statusFor(_alice));

        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));

        assertTrue(_earnerStatusManager.statusFor(_alice));
    }

    function test_statusFor_listIgnoredAndInList() external {
        assertFalse(_earnerStatusManager.statusFor(_alice));

        _registrar.set(_LIST_IGNORED, bytes32(uint256(1)));
        _registrar.setListContains(_LIST, _alice, true);

        assertTrue(_earnerStatusManager.statusFor(_alice));
    }

    function test_statusFor_inListAndSetByAdmin() external {
        assertFalse(_earnerStatusManager.statusFor(_alice));

        _registrar.setListContains(_LIST, _alice, true);
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));

        assertTrue(_earnerStatusManager.statusFor(_alice));
    }

    function test_statusFor_listIgnoredSetByAdmin() external {
        assertFalse(_earnerStatusManager.statusFor(_alice));

        _registrar.set(_LIST_IGNORED, bytes32(uint256(1)));
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));

        assertTrue(_earnerStatusManager.statusFor(_alice));
    }

    function test_statusFor_listIgnoredAndInListAndSetByAdmin() external {
        assertFalse(_earnerStatusManager.statusFor(_alice));

        _registrar.set(_LIST_IGNORED, bytes32(uint256(1)));
        _registrar.setListContains(_LIST, _alice, true);
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));

        assertTrue(_earnerStatusManager.statusFor(_alice));
    }

    /* ============ statusesFor ============ */

    function test_statusesFor_listIgnored() external {
        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertFalse(statuses_[0]);
        assertFalse(statuses_[1]);
        assertFalse(statuses_[2]);

        _registrar.set(_LIST_IGNORED, bytes32(uint256(1)));

        statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertTrue(statuses_[0]);
        assertTrue(statuses_[1]);
        assertTrue(statuses_[2]);
    }

    function test_statusesFor_inList() external {
        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertFalse(statuses_[0]);
        assertFalse(statuses_[1]);
        assertFalse(statuses_[2]);

        _registrar.setListContains(_LIST, _alice, true);

        statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertTrue(statuses_[0]);
        assertFalse(statuses_[1]);
        assertFalse(statuses_[2]);
    }

    function test_statusesFor_setByAdmin() external {
        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertFalse(statuses_[0]);
        assertFalse(statuses_[1]);
        assertFalse(statuses_[2]);

        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setInternalStatus(_bob, 1 << (_adminIndex2 - 1));

        statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertTrue(statuses_[0]);
        assertTrue(statuses_[1]);
        assertFalse(statuses_[2]);
    }

    function test_statusesFor_listIgnoredAndInList() external {
        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertFalse(statuses_[0]);
        assertFalse(statuses_[1]);
        assertFalse(statuses_[2]);

        _registrar.set(_LIST_IGNORED, bytes32(uint256(1)));
        _registrar.setListContains(_LIST, _alice, true);

        statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertTrue(statuses_[0]);
        assertTrue(statuses_[1]);
        assertTrue(statuses_[2]);
    }

    function test_statusesFor_inListAndSetByAdmin() external {
        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertFalse(statuses_[0]);
        assertFalse(statuses_[1]);
        assertFalse(statuses_[2]);

        _registrar.setListContains(_LIST, _alice, true);
        _registrar.setListContains(_LIST, _carol, true);
        _earnerStatusManager.setInternalStatus(_bob, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setInternalStatus(_carol, 1 << (_adminIndex2 - 1));

        statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertTrue(statuses_[0]);
        assertTrue(statuses_[1]);
        assertTrue(statuses_[2]);
    }

    function test_statusesFor_listIgnoredSetByAdmin() external {
        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertFalse(statuses_[0]);
        assertFalse(statuses_[1]);
        assertFalse(statuses_[2]);

        _registrar.set(_LIST_IGNORED, bytes32(uint256(1)));
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setInternalStatus(_bob, 1 << (_adminIndex2 - 1));

        statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertTrue(statuses_[0]);
        assertTrue(statuses_[1]);
        assertTrue(statuses_[2]);
    }

    function test_statusesFor_listIgnoredAndInListAndSetByAdmin() external {
        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertFalse(statuses_[0]);
        assertFalse(statuses_[1]);
        assertFalse(statuses_[2]);

        _registrar.set(_LIST_IGNORED, bytes32(uint256(1)));
        _registrar.setListContains(_LIST, _alice, true);
        _registrar.setListContains(_LIST, _carol, true);
        _earnerStatusManager.setInternalStatus(_bob, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setInternalStatus(_carol, 1 << (_adminIndex2 - 1));

        statuses_ = _earnerStatusManager.statusesFor(accounts_);

        assertTrue(statuses_[0]);
        assertTrue(statuses_[1]);
        assertTrue(statuses_[2]);
    }

    /* ============ isListIgnored ============ */
    function test_isListIgnored() external {
        assertFalse(_earnerStatusManager.isListIgnored());

        _registrar.set(_LIST_IGNORED, bytes32(uint256(1)));

        assertTrue(_earnerStatusManager.isListIgnored());
    }

    /* ============ isInList ============ */
    function test_isInList() external {
        assertFalse(_earnerStatusManager.isInList(_alice));

        _registrar.setListContains(_LIST, _alice, true);

        assertTrue(_earnerStatusManager.isInList(_alice));
    }

    /* ============ getStatusByAdmins ============ */

    function test_getStatusByAdmins_setByExistingAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));

        assertTrue(_earnerStatusManager.getStatusByAdmins(_alice));
    }

    function test_getStatusByAdmins_setByMultipleExistingAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, (1 << (_adminIndex1 - 1)) | (1 << (_adminIndex2 - 1)));

        assertTrue(_earnerStatusManager.getStatusByAdmins(_alice));
    }

    function test_getStatusByAdmins_setByRemovedAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setAdminsBitMask((1 << (_adminIndex2 - 1)) | (1 << (_adminIndex3 - 1)));

        assertFalse(_earnerStatusManager.getStatusByAdmins(_alice));
    }

    function test_getStatusByAdmins_setByExistingAndRemovedAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, (1 << (_adminIndex1 - 1)) | (1 << (_adminIndex2 - 1)));
        _earnerStatusManager.setAdminsBitMask((1 << (_adminIndex2 - 1)) | (1 << (_adminIndex3 - 1)));

        assertTrue(_earnerStatusManager.getStatusByAdmins(_alice));
    }

    /* ============ getStatusByAdmin ============ */

    function test_getStatusByAdmin_setByExistingAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));

        assertTrue(_earnerStatusManager.getStatusByAdmin(_adminIndex1, _alice));
    }

    function test_getStatusByAdmin_setByMultipleExistingAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, (1 << (_adminIndex1 - 1)) | (1 << (_adminIndex2 - 1)));

        assertTrue(_earnerStatusManager.getStatusByAdmin(_adminIndex1, _alice));
    }

    function test_getStatusByAdmin_setByRemovedAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setAdminsBitMask((1 << (_adminIndex2 - 1)) | (1 << (_adminIndex3 - 1)));

        assertTrue(_earnerStatusManager.getStatusByAdmin(_adminIndex1, _alice));
    }

    function test_getStatusByAdmin_setByExistingAndRemovedAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, (1 << (_adminIndex1 - 1)) | (1 << (_adminIndex2 - 1)));
        _earnerStatusManager.setAdminsBitMask((1 << (_adminIndex2 - 1)) | (1 << (_adminIndex3 - 1)));

        assertTrue(_earnerStatusManager.getStatusByAdmin(_adminIndex1, _alice));
    }

    /* ============ getStatusesByAdmin ============ */

    function test_getStatusesByAdmin_setByExistingAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setInternalStatus(_bob, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setInternalStatus(_carol, 1 << (_adminIndex2 - 1));

        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.getStatusesByAdmin(_adminIndex1, accounts_);

        assertTrue(statuses_[0]);
        assertTrue(statuses_[1]);
        assertFalse(statuses_[2]);
    }

    function test_getStatusesByAdmin_setByMultipleExistingAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, (1 << (_adminIndex1 - 1)) | (1 << (_adminIndex2 - 1)));
        _earnerStatusManager.setInternalStatus(_bob, (1 << (_adminIndex1 - 1)) | (1 << (_adminIndex3 - 1)));
        _earnerStatusManager.setInternalStatus(_carol, (1 << (_adminIndex2 - 1)) | (1 << (_adminIndex3 - 1)));

        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.getStatusesByAdmin(_adminIndex1, accounts_);

        assertTrue(statuses_[0]);
        assertTrue(statuses_[1]);
        assertFalse(statuses_[2]);
    }

    function test_getStatusesByAdmin_setByRemovedAdmin() external {
        _earnerStatusManager.setInternalStatus(_alice, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setInternalStatus(_bob, 1 << (_adminIndex1 - 1));
        _earnerStatusManager.setInternalStatus(_carol, 1 << (_adminIndex2 - 1));

        _earnerStatusManager.setAdminsBitMask((1 << (_adminIndex2 - 1)) | (1 << (_adminIndex3 - 1)));

        address[] memory accounts_ = new address[](3);
        accounts_[0] = _alice;
        accounts_[1] = _bob;
        accounts_[2] = _carol;

        bool[] memory statuses_ = _earnerStatusManager.getStatusesByAdmin(_adminIndex1, accounts_);

        assertTrue(statuses_[0]);
        assertTrue(statuses_[1]);
        assertFalse(statuses_[2]);
    }

    /* ============ getAdmin ============ */
    function test_getAdmin() external view {
        for (uint256 adminIndex_; adminIndex_ <= 257; ++adminIndex_) {
            address expectedAdmin_ = adminIndex_ == _adminIndex1
                ? _admin1
                : adminIndex_ == _adminIndex2
                    ? _admin2
                    : adminIndex_ == _adminIndex3
                        ? _admin3
                        : address(0);

            assertEq(_earnerStatusManager.getAdmin(adminIndex_), expectedAdmin_);
        }
    }

    /* ============ isAdminIndexEnabled ============ */
    function test_isAdminIndexEnabled() external view {
        for (uint256 adminIndex_ = 1; adminIndex_ <= 256; ++adminIndex_) {
            bool expectedEnabled_ = adminIndex_ == _adminIndex1 ||
                adminIndex_ == _adminIndex2 ||
                adminIndex_ == _adminIndex3;

            assertEq(_earnerStatusManager.isAdminIndexEnabled(adminIndex_), expectedEnabled_);
        }
    }
}
