// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { IMigratable } from "./interfaces/IMigratable.sol";

/**
 * @title  Abstract implementation for exposing the ability to migrate a contract, extending ERC-1967.
 * @author M^0 Labs
 */
abstract contract Migratable is IMigratable {
    /* ============ Variables ============ */

    /// @dev Storage slot with the address of the current factory. `keccak256('eip1967.proxy.implementation') - 1`.
    uint256 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public immutable initializer;

    /* ============ Constructor ============ */

    constructor(address initializer_) {
        initializer = initializer_; // TODO: check zero.
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IMigratable
    function implementation() public view returns (address implementation_) {
        assembly {
            implementation_ := sload(_IMPLEMENTATION_SLOT)
        }
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Performs an arbitrary migration by delegate-calling `migrator_`.
     * @param migrator_ The address of a migrator contract.
     */
    function _migrate(address migrator_) internal {
        if (migrator_ == address(0)) revert ZeroMigrator();

        if (migrator_.code.length == 0) revert InvalidMigrator();

        _beforeMigrate(migrator_);

        address oldImplementation_ = implementation();

        (bool success_, ) = migrator_.delegatecall("");

        if (!success_) revert MigrationFailed();

        address newImplementation_ = implementation();

        emit Migrated(migrator_, oldImplementation_, newImplementation_);

        // NOTE: Redundant event emitted to conform to the EIP-1967 standard.
        emit Upgraded(newImplementation_);

        _afterMigrate(migrator_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeMigrate(address migrator_) internal virtual {}

    function _afterMigrate(address migrator_) internal virtual {}
}
