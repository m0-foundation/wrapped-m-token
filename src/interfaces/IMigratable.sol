// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

/**
 * @title  Interface for exposing the ability to migrate a contract, extending the ERC-1967 interface.
 * @author M^0 Labs
 */
interface IMigratable {
    /* ============ Events ============ */

    /**
     * @notice Emitted when a migration to a new implementation is performed.
     * @param  migrator          The address that performed the migration.
     * @param  oldImplementation The address of the old implementation.
     * @param  newImplementation The address of the new implementation.
     */
    event Migrated(address indexed migrator, address indexed oldImplementation, address indexed newImplementation);

    /**
     * @notice Emitted when the implementation address for the proxy is changed.
     * @param  implementation The address of the new implementation for the proxy.
     */
    event Upgraded(address indexed implementation);

    /// @notice Emitted when attempting to migrate via an invalid migrator.
    error InvalidMigrator();

    /// @notice Emitted when the delegatecall to a migrator fails.
    error MigrationFailed();

    /// @notice Emitted when attempting to migrate via an migrator with address 0x0.
    error ZeroMigrator();

    /* ============ Interactive Functions ============ */

    /* ============ View/Pure Functions ============ */

    /// @notice Returns the address of the current implementation contract.
    function implementation() external view returns (address);
}
