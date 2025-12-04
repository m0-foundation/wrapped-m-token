// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {
    IAccessControl
} from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Proxy } from "../../../lib/common/src/Proxy.sol";

import { IPausable } from "../../../src/components/pausable/IPausable.sol";

import { PausableHarness } from "../../harness/PausableHarness.sol";

import { BaseUnitTest } from "../../utils/BaseUnitTest.sol";

contract PausableUnitTests is BaseUnitTest {
    PausableHarness public pausable;

    function setUp() public {
        PausableHarness implementation = new PausableHarness();
        pausable = PausableHarness(address(new Proxy(address(implementation))));

        pausable.initialize(_pauser);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertTrue(IAccessControl(address(pausable)).hasRole(_PAUSER_ROLE, _pauser));
    }

    function test_initialize_zeroPauser() external {
        address implementation = address(new PausableHarness());
        pausable = PausableHarness(address(new Proxy(address(implementation))));

        vm.expectRevert(IPausable.ZeroPauser.selector);
        pausable.initialize(address(0));
    }

    /* ============ pause ============ */

    function test_pause_onlyPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _alice,
                pausable.PAUSER_ROLE()
            )
        );

        vm.prank(_alice);
        pausable.pause();
    }

    function test_pause() external {
        vm.prank(_pauser);
        pausable.pause();

        assertTrue(pausable.paused());
    }

    /* ============ unpause ============ */

    function test_unpause_onlyPauser() external {
        vm.prank(_pauser);
        pausable.pause();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _alice,
                pausable.PAUSER_ROLE()
            )
        );

        vm.prank(_alice);
        pausable.unpause();
    }

    function test_unpause() external {
        vm.prank(_pauser);
        pausable.pause();

        vm.prank(_pauser);
        pausable.unpause();

        assertFalse(pausable.paused());
    }
}
