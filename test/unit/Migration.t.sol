// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { Proxy } from "../../lib/common/src/Proxy.sol";
import { Test } from "../../lib/forge-std/src/Test.sol";

import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { WrappedMToken } from "../../src/WrappedMToken.sol";
import { MigratorV1 as Migrator } from "../../src/MigratorV1.sol";

import { MockRegistrar } from "./../utils/Mocks.sol";

contract WrappedMTokenV3 {
    function foo() external pure returns (uint256) {
        return 1;
    }
}

contract MigrationTests is Test {
    bytes32 internal constant _MIGRATOR_KEY_PREFIX = "wm_migrator_v2";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    address internal _mToken = makeAddr("mToken");

    address internal _excessDestination = makeAddr("excessDestination");
    address internal _migrationAdmin = makeAddr("migrationAdmin");

    MockRegistrar internal _registrar;
    WrappedMToken internal _implementation;
    IWrappedMToken internal _wrappedMToken;

    function setUp() external {
        _registrar = new MockRegistrar();

        _implementation = new WrappedMToken(_mToken, address(_registrar), _excessDestination, _migrationAdmin);

        _wrappedMToken = IWrappedMToken(address(new Proxy(address(_implementation))));
    }

    function test_migration() external {
        WrappedMTokenV3 implementationV3_ = new WrappedMTokenV3();
        address migrator_ = address(new Migrator(address(implementationV3_)));

        _registrar.set(
            keccak256(abi.encode(_MIGRATOR_KEY_PREFIX, address(_wrappedMToken))),
            bytes32(uint256(uint160(migrator_)))
        );

        vm.expectRevert();
        WrappedMTokenV3(address(_wrappedMToken)).foo();

        _wrappedMToken.migrate();

        assertEq(WrappedMTokenV3(address(_wrappedMToken)).foo(), 1);
    }

    function test_migration_fromAdmin() external {
        WrappedMTokenV3 implementationV3_ = new WrappedMTokenV3();
        address migrator_ = address(new Migrator(address(implementationV3_)));

        vm.expectRevert();
        WrappedMTokenV3(address(_wrappedMToken)).foo();

        vm.prank(_migrationAdmin);
        _wrappedMToken.migrate(migrator_);

        assertEq(WrappedMTokenV3(address(_wrappedMToken)).foo(), 1);
    }
}
