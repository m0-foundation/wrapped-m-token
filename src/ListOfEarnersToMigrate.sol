// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title  Helper contract to retrieve earners for migrating a WrappedMToken contract from V1 to V2.
 * @author M0 Labs
 */
contract ListOfEarnersToMigrate {
    /// @notice Emitted when the earners array is not strictly ascending (which would allow duplicates or the zero address).
    error EarnersNotSortedOrUnique();

    address[] public earners;

    constructor(address[] memory earners_) {
        // NOTE: Requiring strictly ascending addresses guarantees the list is sorted, free of duplicates and free of
        //       the zero address. Duplicates would corrupt the v1->v2 principal migration, as a repeated address
        //       would have its `lastIndex` slot overwritten by the principal computed on the first pass.
        uint160 previous_;

        for (uint256 i; i < earners_.length; ++i) {
            uint160 current_ = uint160(earners_[i]);

            if (current_ <= previous_) revert EarnersNotSortedOrUnique();

            previous_ = current_;
        }

        earners = earners_;
    }

    function getEarners() external view returns (address[] memory earners_) {
        return earners;
    }
}
