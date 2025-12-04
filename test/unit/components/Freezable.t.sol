// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {
    IAccessControl
} from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Proxy } from "../../../lib/common/src/Proxy.sol";

import { IFreezable } from "../../../src/components/freezable/IFreezable.sol";

import { FreezableHarness } from "../../harness/FreezableHarness.sol";

import { BaseUnitTest } from "../../utils/BaseUnitTest.sol";

contract FreezableUnitTests is BaseUnitTest {
    FreezableHarness public freezable;

    function setUp() external {
        FreezableHarness implementation = new FreezableHarness();
        freezable = FreezableHarness(address(new Proxy(address(implementation))));

        freezable.initialize(_freezeManager);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertTrue(IAccessControl(address(freezable)).hasRole(_FREEZE_MANAGER_ROLE, _freezeManager));
    }

    function test_initialize_zeroFreezeManager() external {
        address implementation = address(new FreezableHarness());
        freezable = FreezableHarness(address(new Proxy(address(implementation))));

        vm.expectRevert(IFreezable.ZeroFreezeManager.selector);
        freezable.initialize(address(0));
    }

    /* ============ freeze ============ */

    function test_freeze_onlyFreezeManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _alice,
                _FREEZE_MANAGER_ROLE
            )
        );

        vm.prank(_alice);
        freezable.freeze(_bob);
    }

    function test_freeze_returnEarlyIfFrozen() public {
        vm.expectEmit();
        emit IFreezable.Frozen(_alice, block.timestamp);

        vm.prank(_freezeManager);
        freezable.freeze(_alice);

        assertTrue(freezable.isFrozen(_alice));

        vm.prank(_freezeManager);
        freezable.freeze(_alice);

        assertTrue(freezable.isFrozen(_alice));
    }

    function test_freeze() public {
        vm.expectEmit();
        emit IFreezable.Frozen(_alice, block.timestamp);

        vm.prank(_freezeManager);
        freezable.freeze(_alice);

        assertTrue(freezable.isFrozen(_alice));
    }

    /* ============ freezeAccounts ============ */

    function test_freezeAccounts_onlyFreezeManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _alice,
                _FREEZE_MANAGER_ROLE
            )
        );

        vm.prank(_alice);
        freezable.freezeAccounts(_accounts);
    }

    function test_freezeAccounts_returnEarlyIfFrozen() public {
        address[] memory _accounts = new address[](2);
        _accounts[0] = _alice;
        _accounts[1] = _alice;

        vm.expectEmit();
        emit IFreezable.Frozen(_alice, block.timestamp);

        vm.prank(_freezeManager);
        freezable.freezeAccounts(_accounts);
    }

    function test_freezeAccounts() public {
        for (uint256 i; i < _accounts.length; ++i) {
            vm.expectEmit();
            emit IFreezable.Frozen(_accounts[i], block.timestamp);
        }

        vm.prank(_freezeManager);
        freezable.freezeAccounts(_accounts);

        for (uint256 i; i < _accounts.length; ++i) {
            assertTrue(freezable.isFrozen(_accounts[i]));
        }
    }

    /* ============ unfreeze ============ */

    function test_unfreeze_onlyFreezeManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _alice,
                _FREEZE_MANAGER_ROLE
            )
        );

        vm.prank(_alice);
        freezable.unfreeze(_bob);
    }

    function test_freeze_returnEarlyIfNotFrozen() public {
        assertFalse(freezable.isFrozen(_alice));

        vm.prank(_freezeManager);
        freezable.unfreeze(_alice);

        assertFalse(freezable.isFrozen(_alice));
    }

    function test_unfreeze() public {
        vm.prank(_freezeManager);
        freezable.freeze(_alice);

        assertTrue(freezable.isFrozen(_alice));

        vm.expectEmit();
        emit IFreezable.Unfrozen(_alice, block.timestamp);

        vm.prank(_freezeManager);
        freezable.unfreeze(_alice);

        assertFalse(freezable.isFrozen(_alice));
    }

    /* ============ unfreezeAccounts ============ */

    function test_unfreezeAccounts_onlyFreezeManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _alice,
                _FREEZE_MANAGER_ROLE
            )
        );

        vm.prank(_alice);
        freezable.unfreezeAccounts(_accounts);
    }

    function test_unfreezeAccounts_returnEarlyIfNotFrozen() public {
        vm.prank(_freezeManager);
        freezable.freeze(_alice);

        assertTrue(freezable.isFrozen(_alice));
        assertFalse(freezable.isFrozen(_bob));

        address[] memory _accounts = new address[](2);
        _accounts[0] = _alice;
        _accounts[1] = _bob;

        vm.expectEmit();
        emit IFreezable.Unfrozen(_alice, block.timestamp);

        vm.prank(_freezeManager);
        freezable.unfreezeAccounts(_accounts);

        assertFalse(freezable.isFrozen(_alice));
        assertFalse(freezable.isFrozen(_bob));
    }

    function test_unfreezeAccounts() public {
        vm.prank(_freezeManager);
        freezable.freezeAccounts(_accounts);

        for (uint256 i; i < _accounts.length; ++i) {
            vm.expectEmit();
            emit IFreezable.Unfrozen(_accounts[i], block.timestamp);
        }

        vm.prank(_freezeManager);
        freezable.unfreezeAccounts(_accounts);

        for (uint256 i; i < _accounts.length; ++i) {
            assertFalse(freezable.isFrozen(_accounts[i]));
        }
    }

    /* ============ _revertIfFrozen ============ */

    function test_revertIfFrozen() public {
        vm.prank(_freezeManager);
        freezable.freeze(_alice);

        assertTrue(freezable.isFrozen(_alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        freezable.revertIfFrozenInternal(_alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, _alice));

        freezable.revertIfFrozen(_alice);
    }

    /* ============ _revertIfNotFrozen ============ */

    function test_revertIfNotFrozen() public {
        assertFalse(freezable.isFrozen(_alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, _alice));

        freezable.revertIfNotFrozenInternal(_alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, _alice));

        freezable.revertIfNotFrozen(_alice);
    }
}
