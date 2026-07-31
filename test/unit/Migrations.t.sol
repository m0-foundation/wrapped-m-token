// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { Proxy } from "../../lib/common/src/Proxy.sol";
import { Test } from "../../lib/forge-std/src/Test.sol";

import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { WrappedMToken } from "../../src/WrappedMToken.sol";
import { WrappedMTokenMigratorV1 as WrappedMTokenMigrator } from "../../src/WrappedMTokenMigratorV1.sol";

import { MockRegistrar } from "./../utils/Mocks.sol";

contract Foo {
    address public admin;
    address public freezeManager;
    address public pauser;
    address public forcedTransferManager;
    address public excessManager;
    address public excessDestination;

    function bar() external pure returns (uint256) {
        return 1;
    }

    function initialize(
        address admin_,
        address freezeManager_,
        address pauser_,
        address forcedTransferManager_,
        address excessManager_,
        address excessDestination_
    ) public {
        admin = admin_;
        freezeManager = freezeManager_;
        pauser = pauser_;
        forcedTransferManager = forcedTransferManager_;
        excessManager = excessManager_;
        excessDestination = excessDestination_;
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
    address internal _swapFacility = makeAddr("swapFacility");

    address internal _admin = makeAddr("admin");
    address internal _excessManager = makeAddr("excessManager");
    address internal _excessDestination = makeAddr("excessDestination");
    address internal _freezeManager = makeAddr("freezeManager");
    address internal _forcedTransferManager = makeAddr("forcedTransferManager");
    address internal _migrationAdmin = makeAddr("migrationAdmin");
    address internal _pauser = makeAddr("pauser");

    function test_wrappedMToken_migration() external {
        MockRegistrar registrar_ = new MockRegistrar();
        address mToken_ = makeAddr("mToken");

        address implementation_ = address(
            new WrappedMToken(address(mToken_), address(registrar_), _swapFacility, _migrationAdmin)
        );

        address proxy_ = address(new Proxy(address(implementation_)));
        address migrator_ = address(
            new WrappedMTokenMigrator(
                address(new Foo()),
                new address[](0),
                _admin,
                _freezeManager,
                _pauser,
                _forcedTransferManager,
                _excessManager,
                _excessDestination
            )
        );

        registrar_.set(keccak256(abi.encode(_WM_MIGRATOR_KEY_PREFIX, proxy_)), bytes32(uint256(uint160(migrator_))));

        vm.expectRevert();
        Foo(proxy_).bar();

        IWrappedMToken(proxy_).migrate();

        assertEq(Foo(proxy_).bar(), 1);
        assertEq(Foo(proxy_).admin(), _admin);
        assertEq(Foo(proxy_).freezeManager(), _freezeManager);
        assertEq(Foo(proxy_).pauser(), _pauser);
        assertEq(Foo(proxy_).forcedTransferManager(), _forcedTransferManager);
        assertEq(Foo(proxy_).excessManager(), _excessManager);
        assertEq(Foo(proxy_).excessDestination(), _excessDestination);
    }

    function test_wrappedMToken_migration_fromAdmin() external {
        MockRegistrar registrar_ = new MockRegistrar();
        address mToken_ = makeAddr("mToken");

        address implementation_ = address(
            new WrappedMToken(address(mToken_), address(registrar_), _swapFacility, _migrationAdmin)
        );

        address proxy_ = address(new Proxy(address(implementation_)));
        address migrator_ = address(
            new WrappedMTokenMigrator(
                address(new Foo()),
                new address[](0),
                _admin,
                _freezeManager,
                _pauser,
                _forcedTransferManager,
                _excessManager,
                _excessDestination
            )
        );

        vm.expectRevert();
        Foo(proxy_).bar();

        vm.prank(_migrationAdmin);
        IWrappedMToken(proxy_).migrate(migrator_);

        assertEq(Foo(proxy_).bar(), 1);
        assertEq(Foo(proxy_).admin(), _admin);
        assertEq(Foo(proxy_).freezeManager(), _freezeManager);
        assertEq(Foo(proxy_).pauser(), _pauser);
        assertEq(Foo(proxy_).forcedTransferManager(), _forcedTransferManager);
        assertEq(Foo(proxy_).excessManager(), _excessManager);
        assertEq(Foo(proxy_).excessDestination(), _excessDestination);
    }
}
