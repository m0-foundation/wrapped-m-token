// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IClaimRecipientManager } from "../../src/interfaces/IClaimRecipientManager.sol";

import { MockRegistrar } from "./../utils/Mocks.sol";
import { ClaimRecipientManagerHarness } from "../utils/ClaimRecipientManagerHarness.sol";

contract ClaimRecipientManagerTests is Test {
    bytes32 internal constant _CLAIM_OVERRIDE_RECIPIENT_PREFIX = "wm_claim_override_recipient";
    bytes32 internal constant _CLAIM_RECIPIENT_ADMIN_LIST = "wm_claim_recipient_admins";

    address internal _admin = makeAddr("admin");

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    MockRegistrar internal _registrar;
    ClaimRecipientManagerHarness internal _claimRecipientManager;

    function setUp() external {
        _registrar = new MockRegistrar();
        _claimRecipientManager = new ClaimRecipientManagerHarness(address(_registrar));

        _registrar.setListContains(_CLAIM_RECIPIENT_ADMIN_LIST, _admin, true);
    }

    /* ============ initial state ============ */
    function test_initialState() external view {
        assertEq(_claimRecipientManager.registrar(), address(_registrar));
    }

    /* ============ constructor ============ */
    function test_constructor_zeroRegistrar() external {
        vm.expectRevert(IClaimRecipientManager.ZeroRegistrar.selector);
        new ClaimRecipientManagerHarness(address(0));
    }

    /* ============ setClaimRecipient ============ */
    function test_setClaimRecipient_notAdmin() external {
        vm.expectRevert(IClaimRecipientManager.NotClaimRecipientAdmin.selector);

        vm.prank(_alice);
        _claimRecipientManager.setClaimRecipient(_alice, _bob);
    }

    function test_setClaimRecipient() external {
        vm.prank(_admin);
        _claimRecipientManager.setClaimRecipient(_alice, _bob);

        assertEq(_claimRecipientManager.getInternalClaimRecipient(_alice), _bob);
    }

    /* ============ setClaimRecipients ============ */
    function test_setClaimRecipients_notAdmin() external {
        vm.expectRevert(IClaimRecipientManager.NotClaimRecipientAdmin.selector);

        address[] memory accounts_ = new address[](1);
        accounts_[0] = _alice;

        address[] memory recipients_ = new address[](1);
        recipients_[0] = _bob;

        vm.prank(_alice);
        _claimRecipientManager.setClaimRecipients(accounts_, recipients_);
    }

    function test_setClaimRecipients_arrayLengthMismatch() external {
        address[] memory accounts_ = new address[](1);
        address[] memory recipients_ = new address[](2);

        vm.expectRevert(IClaimRecipientManager.ArrayLengthMismatch.selector);

        vm.prank(_admin);
        _claimRecipientManager.setClaimRecipients(accounts_, recipients_);
    }

    function test_setClaimRecipients() external {
        vm.prank(_admin);

        address[] memory accounts_ = new address[](2);
        accounts_[0] = _alice;
        accounts_[1] = _bob;

        address[] memory recipients_ = new address[](2);
        recipients_[0] = _carol;
        recipients_[1] = _dave;

        _claimRecipientManager.setClaimRecipients(accounts_, recipients_);

        assertEq(_claimRecipientManager.getInternalClaimRecipient(_alice), _carol);
        assertEq(_claimRecipientManager.getInternalClaimRecipient(_bob), _dave);
    }

    /* ============ claimRecipientOverrideFor ============ */
    function test_claimRecipientOverrideFor() external {
        assertEq(_claimRecipientManager.claimRecipientOverrideFor(_alice), address(0));

        _registrar.set(
            keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_PREFIX, _alice)),
            bytes32(uint256(uint160(_bob)))
        );

        assertEq(_claimRecipientManager.claimRecipientOverrideFor(_alice), _bob);
    }

    /* ============ claimRecipientFor ============ */
    function test_claimRecipientFor() external {
        assertEq(_claimRecipientManager.claimRecipientFor(_alice), address(0));

        _claimRecipientManager.setInternalClaimRecipient(_alice, _bob);

        assertEq(_claimRecipientManager.claimRecipientFor(_alice), _bob);

        _registrar.set(
            keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_PREFIX, _alice)),
            bytes32(uint256(uint160(_carol)))
        );

        assertEq(_claimRecipientManager.claimRecipientFor(_alice), _carol);
    }

    /* ============ isClaimRecipientAdmin ============ */
    function test_isClaimRecipientAdmin() external view {
        assertTrue(_claimRecipientManager.isClaimRecipientAdmin(_admin));
        assertFalse(_claimRecipientManager.isClaimRecipientAdmin(_alice));
    }
}
