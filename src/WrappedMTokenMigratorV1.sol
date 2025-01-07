// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IndexingMath } from "../lib/common/src/libs/IndexingMath.sol";

import { ListOfEarnersToMigrate } from "./ListOfEarnersToMigrate.sol";

/**
 * @title  Migrator contract for migrating a WrappedMToken contract from V1 to V2.
 * @author M^0 Labs
 */
contract WrappedMTokenMigratorV1 {
    /// @notice Emitted when the `enableDisableEarningIndices` array has an invalid length.
    error InvalidEnableDisableEarningIndicesArrayLength();

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

    address public immutable migrationAdmin;

    constructor(address newImplementation_, address[] memory earners_, address migrationAdmin_) {
        if ((newImplementation = newImplementation_) == address(0)) revert();

        listOfEarnerToMigrate = address(new ListOfEarnersToMigrate(earners_));

        if ((migrationAdmin = migrationAdmin_) == address(0)) revert();
    }

    fallback() external virtual {
        _migrateEarners();

        _setMigrationAdmin(migrationAdmin);

        (bool earningEnabled_, uint128 disableIndex_) = _clearEnableDisableEarningIndices();

        if (earningEnabled_) {
            _setEnableMIndex(IndexingMath.EXP_SCALED_ONE);
        } else {
            _setDisableIndex(disableIndex_);
        }

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

    /**
     * @dev   Sets the `migrationAdmin` slot to `migrationAdmin_`.
     * @param migrationAdmin_ The address of the account to set the `migrationAdmin_` to.
     */
    function _setMigrationAdmin(address migrationAdmin_) internal {
        assembly {
            sstore(9, migrationAdmin_) // `migrationAdmin` is slot 9 in v2.
        }
    }

    /**
     * @dev    Clears the entire `_enableDisableEarningIndices` array in storage, returning useful information.
     * @return earningEnabled_ Whether earning is enabled.
     * @return disableIndex_   The index when earning was disabled, if any.
     */
    function _clearEnableDisableEarningIndices() internal returns (bool earningEnabled_, uint128 disableIndex_) {
        uint128[] storage array_;

        assembly {
            array_.slot := 7 // `_enableDisableEarningIndices` was slot 7 in v1.
        }

        // If the array is empty, earning is disabled and thus the disable index was non-existent.
        if (array_.length == 0) return (false, 0);

        // If the array has one element, earning is enabled and the disable index is non-existent.
        if (array_.length == 1) {
            array_.pop();
            return (true, 0);
        }

        // If the array has two elements, earning is disabled and the disable index is the second element.
        if (array_.length == 2) {
            disableIndex_ = array_[1];
            array_.pop();
            array_.pop();
            return (false, disableIndex_);
        }

        // In v1, it is not possible for the `_enableDisableEarningIndices` array to have more than two elements.
        revert InvalidEnableDisableEarningIndicesArrayLength();
    }

    /**
     * @dev   Sets the `enableMIndex` slot to `index_`.
     * @param index_ The index to set the `enableMIndex .
     */
    function _setEnableMIndex(uint128 index_) internal {
        assembly {
            sstore(7, index_) // `enableMIndex` is the lower half of slot 7 in v2.
        }
    }

    /**
     * @dev   Sets the `disableIndex` slot to `index_`.
     * @param index_ The index to set the `disableIndex .
     */
    function _setDisableIndex(uint128 index_) internal {
        assembly {
            sstore(7, shl(128, index_)) // `disableIndex` is the upper half of slot 7 in v2.
        }
    }
}
