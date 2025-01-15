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
}
