// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title  Helper contract to retrieve earners for migrating a WrappedMToken contract from V1 to V2.
 * @author M^0 Labs
 */
contract ListOfEarnersToMigrate {
    address[] public earners;

    constructor(address[] memory earners_) {
        earners = earners_;
    }

    function getEarners() external view returns (address[] memory earners_) {
        return earners;
    }
}
