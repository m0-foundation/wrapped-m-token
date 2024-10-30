// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IndexingMath } from "../lib/common/src/libs/IndexingMath.sol";

import { ListOfEarnersToMigrate } from "./ListOfEarnersToMigrate.sol";

/**
 * @title  Migrator contract for migrating a WrappedMToken contract from V1 to V2.
 * @author M^0 Labs
 */
contract WrappedMTokenMigratorV1 {
    /* ============ Structs ============ */

    /**
     * @dev   Struct to represent an account's balance and yield earning details with last index (prior version).
     * @param isEarning Whether the account is actively earning yield.
     * @param balance   The present amount of tokens held by the account.
     * @param lastIndex The index of the last interaction for the account (0 for non-earning accounts).
     */
    struct IndexBasedAccount {
        // First Slot
        bool isEarning;
        uint240 balance;
        // Second slot
        uint128 lastIndex;
    }

    /**
     * @dev   Struct to represent an account's balance and yield earning details.
     * @param isEarning        Whether the account is actively earning yield.
     * @param balance          The present amount of tokens held by the account.
     * @param earningPrincipal The earning principal for the account (0 for non-earning accounts).
     */
    struct Account {
        // First Slot
        bool isEarning;
        uint240 balance;
        // Second slot
        uint112 earningPrincipal;
    }

    /// @dev Storage slot with the address of the current factory. `keccak256('eip1967.proxy.implementation') - 1`.
    uint256 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public immutable newImplementation;

    address public immutable listOfEarnerToMigrate;

    constructor(address newImplementation_, address[] memory earners_) {
        newImplementation = newImplementation_;

        listOfEarnerToMigrate = address(new ListOfEarnersToMigrate(earners_));
    }

    fallback() external virtual {
        _migrateEarners();

        address newImplementation_ = newImplementation;

        assembly {
            sstore(_IMPLEMENTATION_SLOT, newImplementation_)
        }
    }

    function _migrateEarners() internal {
        address[] memory earners_ = ListOfEarnersToMigrate(listOfEarnerToMigrate).getEarners();

        mapping(address => Account) storage accounts_ = _getAccounts();

        uint256 index_ = earners_.length;

        while (index_ > 0) {
            Account storage accountInfo_ = accounts_[earners_[--index_]];

            if (!accountInfo_.isEarning) continue;

            IndexBasedAccount storage accountInfoV1_;

            assembly {
                accountInfoV1_.slot := accountInfo_.slot
            }

            uint128 lastIndex_ = accountInfoV1_.lastIndex;

            delete accountInfoV1_.lastIndex;

            accountInfo_.earningPrincipal = IndexingMath.getPrincipalAmountRoundedDown(
                accountInfoV1_.balance,
                lastIndex_
            );
        }
    }

    function _getAccounts() internal pure returns (mapping(address => Account) storage accounts_) {
        assembly {
            accounts_.slot := 6 // `_accounts` is slot 6 in v1.
        }
    }
}
