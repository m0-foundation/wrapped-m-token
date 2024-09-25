// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { WrappedMToken } from "../../src/WrappedMToken.sol";
import { Proxy } from "../../src/Proxy.sol";

import { MockM, MockRegistrar } from "./../utils/Mocks.sol";

contract WrappedMTokenV2 {
    function foo() external pure returns (uint256) {
        return 1;
    }
}

contract WrappedMTokenMigratorV1 {
    bytes32 private constant _IMPLEMENTATION_SLOT =
        bytes32(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);

    address public immutable implementationV2;

    constructor(address implementationV2_) {
        implementationV2 = implementationV2_;
    }

    fallback() external virtual {
        bytes32 slot_ = _IMPLEMENTATION_SLOT;
        address implementationV2_ = implementationV2;

        assembly {
            sstore(slot_, implementationV2_)
        }
    }
}

contract MigrationTests is Test {
    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "wm_migrator_v1";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    address internal _migrationAdmin = makeAddr("migrationAdmin");

    address internal _vault = makeAddr("vault");

    MockM internal _mToken;
    MockRegistrar internal _registrar;
    WrappedMToken internal _implementation;
    IWrappedMToken internal _wrappedMToken;

    function setUp() external {
        _registrar = new MockRegistrar();
        _registrar.setVault(_vault);

        _mToken = new MockM();
        _mToken.setCurrentIndex(_EXP_SCALED_ONE);
        _mToken.setTtgRegistrar(address(_registrar));

        _implementation = new WrappedMToken(address(_mToken), _migrationAdmin);

        _wrappedMToken = IWrappedMToken(address(new Proxy(address(_implementation))));
    }

    function test_migration() external {
        WrappedMTokenV2 implementationV2_ = new WrappedMTokenV2();
        address migrator_ = address(new WrappedMTokenMigratorV1(address(implementationV2_)));

        _registrar.set(
            keccak256(abi.encode(_MIGRATOR_V1_PREFIX, address(_wrappedMToken))),
            bytes32(uint256(uint160(migrator_)))
        );

        vm.expectRevert();
        WrappedMTokenV2(address(_wrappedMToken)).foo();

        _wrappedMToken.migrate();

        assertEq(WrappedMTokenV2(address(_wrappedMToken)).foo(), 1);
    }

    function test_migration_fromAdmin() external {
        WrappedMTokenV2 implementationV2_ = new WrappedMTokenV2();
        address migrator_ = address(new WrappedMTokenMigratorV1(address(implementationV2_)));

        vm.expectRevert();
        WrappedMTokenV2(address(_wrappedMToken)).foo();

        vm.prank(_migrationAdmin);
        _wrappedMToken.migrate(migrator_);

        assertEq(WrappedMTokenV2(address(_wrappedMToken)).foo(), 1);
    }
}
