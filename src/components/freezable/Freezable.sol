// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

import {
    AccessControlUpgradeable
} from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { IFreezable } from "./IFreezable.sol";

abstract contract FreezableStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.Freezable
    struct FreezableStorageStruct {
        mapping(address account => bool isFrozen) isFrozen;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.Freezable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _FREEZABLE_STORAGE_LOCATION =
        0x2fd5767309dce890c526ace85d7fe164825199d7dcd99c33588befc51b32ce00;

    function _getFreezableStorageLocation() internal pure returns (FreezableStorageStruct storage $) {
        assembly {
            $.slot := _FREEZABLE_STORAGE_LOCATION
        }
    }
}

/**
 * @title Freezable
 * @notice Upgradeable contract that allows for the freezing of accounts.
 * @dev Imported from https://github.com/m0-foundation/m0-evm-m-extensions/blob/7609e5e9151589e2078d91d0d95e1d0fef4278ce/src/components/freezable/Freezable.sol
 * @dev This contract is used to prevent certain accounts from interacting with the contract.
 * @author M0 Labs
 */
abstract contract Freezable is IFreezable, FreezableStorageLayout, AccessControlUpgradeable {
    /* ============ Variables ============ */

    /// @inheritdoc IFreezable
    bytes32 public constant FREEZE_MANAGER_ROLE = keccak256("FREEZE_MANAGER_ROLE");

    /* ============ Initializer ============ */

    /**
     * @notice Initializes the contract with the given freeze manager.
     * @param freezeManager The address of a freeze manager.
     */
    function __Freezable_init(address freezeManager) internal onlyInitializing {
        if (freezeManager == address(0)) revert ZeroFreezeManager();
        _grantRole(FREEZE_MANAGER_ROLE, freezeManager);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IFreezable
    function freeze(address account) external onlyRole(FREEZE_MANAGER_ROLE) {
        _freeze(_getFreezableStorageLocation(), account);
    }

    /// @inheritdoc IFreezable
    function freezeAccounts(address[] calldata accounts) external onlyRole(FREEZE_MANAGER_ROLE) {
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();

        for (uint256 i; i < accounts.length; ++i) {
            _freeze($, accounts[i]);
        }
    }

    /// @inheritdoc IFreezable
    function unfreeze(address account) external onlyRole(FREEZE_MANAGER_ROLE) {
        _unfreeze(_getFreezableStorageLocation(), account);
    }

    /// @inheritdoc IFreezable
    function unfreezeAccounts(address[] calldata accounts) external onlyRole(FREEZE_MANAGER_ROLE) {
        FreezableStorageStruct storage $ = _getFreezableStorageLocation();

        for (uint256 i; i < accounts.length; ++i) {
            _unfreeze($, accounts[i]);
        }
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IFreezable
    function isFrozen(address account) public view returns (bool) {
        return _getFreezableStorageLocation().isFrozen[account];
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @notice Internal function that freezes an account.
     * @param $ The storage location of the freezable contract.
     * @param account The account to freeze.
     */
    function _freeze(FreezableStorageStruct storage $, address account) internal {
        // Return early if the account is already frozen
        if ($.isFrozen[account]) return;

        $.isFrozen[account] = true;

        emit Frozen(account, block.timestamp);
    }

    /**
     * @notice Internal function that unfreezes an account.
     * @param $ The storage location of the freezable contract.
     * @param account The account to unfreeze.
     */
    function _unfreeze(FreezableStorageStruct storage $, address account) internal {
        // Return early if the account is not frozen
        if (!$.isFrozen[account]) return;

        $.isFrozen[account] = false;

        emit Unfrozen(account, block.timestamp);
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @notice Internal function that reverts if an account is frozen.
     * @dev Called by inheriting contracts to check if an account is frozen.
     * @param $ The storage location of the freezable contract.
     * @param account The account to check.
     */
    function _revertIfFrozen(FreezableStorageStruct storage $, address account) internal view {
        if ($.isFrozen[account]) revert AccountFrozen(account);
    }

    /**
     * @notice Internal function that reverts if an account is frozen.
     * @dev Called by inheriting contracts to check if an account is frozen.
     * @param account The account to check.
     */
    function _revertIfFrozen(address account) internal view {
        if (_getFreezableStorageLocation().isFrozen[account]) revert AccountFrozen(account);
    }

    /**
     * @notice Internal function that reverts if an account is not frozen.
     * @dev Called by inheriting contracts to check if an account is not frozen.
     * @param $ The storage location of the freezable contract.
     * @param account The account to check.
     */
    function _revertIfNotFrozen(FreezableStorageStruct storage $, address account) internal view {
        if (!$.isFrozen[account]) revert AccountNotFrozen(account);
    }

    /**
     * @notice Internal function that reverts if an account is not frozen.
     * @dev Called by inheriting contracts to check if an account is not frozen.
     * @param account The account to check.
     */
    function _revertIfNotFrozen(address account) internal view {
        if (!_getFreezableStorageLocation().isFrozen[account]) revert AccountNotFrozen(account);
    }
}
