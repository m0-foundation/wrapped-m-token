// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { ListOfEarnersToMigrate } from "../../src/ListOfEarnersToMigrate.sol";

import { EarnersAddresses } from "../../script/EarnersAddresses.sol";

contract ListOfEarnersToMigrateTests is Test {
    function test_constructor_empty() external {
        ListOfEarnersToMigrate list_ = new ListOfEarnersToMigrate(new address[](0));

        assertEq(list_.getEarners().length, 0);
    }

    function test_constructor_single() external {
        address[] memory earners_ = new address[](1);
        earners_[0] = address(1);

        ListOfEarnersToMigrate list_ = new ListOfEarnersToMigrate(earners_);

        address[] memory stored_ = list_.getEarners();

        assertEq(stored_.length, 1);
        assertEq(stored_[0], address(1));
    }

    function test_constructor_sortedAscending() external {
        address[] memory earners_ = new address[](3);
        earners_[0] = address(1);
        earners_[1] = address(2);
        earners_[2] = address(3);

        ListOfEarnersToMigrate list_ = new ListOfEarnersToMigrate(earners_);

        address[] memory stored_ = list_.getEarners();

        assertEq(stored_.length, 3);
        assertEq(stored_[0], address(1));
        assertEq(stored_[1], address(2));
        assertEq(stored_[2], address(3));
    }

    function test_constructor_revertsOnUnsorted() external {
        address[] memory earners_ = new address[](3);
        earners_[0] = address(1);
        earners_[1] = address(3);
        earners_[2] = address(2);

        vm.expectRevert(ListOfEarnersToMigrate.EarnersNotSortedOrUnique.selector);
        new ListOfEarnersToMigrate(earners_);
    }

    function test_constructor_revertsOnDuplicate() external {
        address[] memory earners_ = new address[](3);
        earners_[0] = address(1);
        earners_[1] = address(2);
        earners_[2] = address(2);

        vm.expectRevert(ListOfEarnersToMigrate.EarnersNotSortedOrUnique.selector);
        new ListOfEarnersToMigrate(earners_);
    }

    function test_constructor_revertsOnZeroAddress() external {
        address[] memory earners_ = new address[](2);
        earners_[0] = address(0);
        earners_[1] = address(1);

        vm.expectRevert(ListOfEarnersToMigrate.EarnersNotSortedOrUnique.selector);
        new ListOfEarnersToMigrate(earners_);
    }

    function test_constructor_committedEarnersAreDeployable() external {
        _assertDeployable(EarnersAddresses.getEthereumEarners());
        _assertDeployable(EarnersAddresses.getArbitrumEarners());
        _assertDeployable(EarnersAddresses.getPlumeEarners());
    }

    function _assertDeployable(address[] memory earners_) internal {
        address[] memory stored_ = new ListOfEarnersToMigrate(earners_).getEarners();

        assertEq(stored_.length, earners_.length);

        for (uint256 i_ = 1; i_ < stored_.length; ++i_) {
            assertTrue(uint160(stored_[i_ - 1]) < uint160(stored_[i_]));
        }
    }
}
