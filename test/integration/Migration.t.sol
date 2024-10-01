// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ClaimRecipientManager } from "../../src/ClaimRecipientManager.sol";
import { WrappedMToken } from "../../src/WrappedMToken.sol";
import { MigratorV1 } from "../../src/MigratorV1.sol";

import { TestBase } from "./TestBase.sol";

contract MorphoBlueTests is TestBase {
    function setUp() external {
        _deployV2Components();
    }

    function test_migration() external {
        _migrate();

        assertEq(_wrappedMToken.claimRecipientManager(), address(_claimRecipientManager));
        assertEq(_wrappedMToken.claimRecipientFor(_alice), _alice);
    }

    function test_migration_fromAdmin() external {
        _migrateFromAdmin();

        assertEq(_wrappedMToken.claimRecipientManager(), address(_claimRecipientManager));
        assertEq(_wrappedMToken.claimRecipientFor(_alice), _alice);
    }
}
