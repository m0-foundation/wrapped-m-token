// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { IndexingMath } from "../../lib/common/src/libs/IndexingMath.sol";

import { TestBase } from "./TestBase.sol";

contract MigrationIntegrationTests is TestBase {
    function test_index_noMigration() external {
        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.currentIndex(), 1_073787769981);
    }

    function test_index_migrate_beforeEarningDisabled() external {
        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 0);
        assertEq(_wrappedMToken.enableMIndex(), IndexingMath.EXP_SCALED_ONE);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.currentIndex(), 1_073787769981);
    }

    function test_index_migrate_afterEarningDisabled() external {
        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        _removeFromList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.disableEarning();

        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 1_023463403719);
        assertEq(_wrappedMToken.enableMIndex(), 0);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);
    }
}
