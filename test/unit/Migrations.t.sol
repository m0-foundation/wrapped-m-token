// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { Proxy } from "../../lib/common/src/Proxy.sol";
import { Test } from "../../lib/forge-std/src/Test.sol";

import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { WrappedMToken } from "../../src/WrappedMToken.sol";
import { WrappedMTokenMigratorV1 as WrappedMTokenMigrator } from "../../src/WrappedMTokenMigratorV1.sol";

import { MockRegistrar } from "./../utils/Mocks.sol";

contract Foo {
    function bar() external pure returns (uint256) {
        return 1;
    }
}

contract MigrationTests is Test {
    bytes32 internal constant _WM_MIGRATOR_KEY_PREFIX = "wm_migrator_v2";
    bytes32 internal constant _EM_MIGRATOR_KEY_PREFIX = "em_migrator_v1";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    address internal _mToken = makeAddr("mToken");
    address internal _excessDestination = makeAddr("excessDestination");
    address internal _swapFacility = makeAddr("swapFacility");
    address internal _migrationAdmin = makeAddr("migrationAdmin");

    function test_wrappedMToken_migration() external {
        MockRegistrar registrar_ = new MockRegistrar();
        address mToken_ = makeAddr("mToken");

        address implementation_ = address(
            new WrappedMToken(address(mToken_), address(registrar_), _excessDestination, _swapFacility, _migrationAdmin)
        );

        address proxy_ = address(new Proxy(address(implementation_)));
        address migrator_ = address(new WrappedMTokenMigrator(address(new Foo()), new address[](0)));

        registrar_.set(keccak256(abi.encode(_WM_MIGRATOR_KEY_PREFIX, proxy_)), bytes32(uint256(uint160(migrator_))));

        vm.expectRevert();
        Foo(proxy_).bar();

        IWrappedMToken(proxy_).migrate();

        assertEq(Foo(proxy_).bar(), 1);
    }

    function test_wrappedMToken_migration_fromAdmin() external {
        MockRegistrar registrar_ = new MockRegistrar();
        address mToken_ = makeAddr("mToken");

        address implementation_ = address(
            new WrappedMToken(address(mToken_), address(registrar_), _excessDestination, _swapFacility, _migrationAdmin)
        );

        address proxy_ = address(new Proxy(address(implementation_)));
        address migrator_ = address(new WrappedMTokenMigrator(address(new Foo()), new address[](0)));

        vm.expectRevert();
        Foo(proxy_).bar();

        vm.prank(_migrationAdmin);
        IWrappedMToken(proxy_).migrate(migrator_);

        assertEq(Foo(proxy_).bar(), 1);
    }
}
