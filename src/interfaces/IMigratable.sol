// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

/**
 * @title  Interface for exposing the ability to migrate a contract, extending the ERC-1967 interface.
 * @author M^0 Labs
 */
interface IMigratable {
    /* ============ Events ============ */

    /**
     * @notice Emitted when a migration to a new implementation is performed.
     * @param  migrator          The account that stopped earning.
     * @param  oldImplementation The account that stopped earning.
     * @param  newImplementation The account that stopped earning.
     */
    event Migrated(address indexed migrator, address indexed oldImplementation, address indexed newImplementation);

    /**
     * @notice Emitted when the implementation address for the proxy is changed.
     * @param  implementation The address of the new implementation for the proxy.
     */
    event Upgraded(address indexed implementation);

    /// @notice Emitted when calling `stopEarning` for an account approved as earner by TTG.
    error InvalidMigrator();

    /// @notice Emitted when the delegatecall to a migrator fails.
    error MigrationFailed();

    /// @notice Emitted when calling `stopEarning` for an account approved as earner by TTG.
    error ZeroMigrator();

    /* ============ Interactive Functions ============ */

    /// @notice Performs an arbitrarily defined migration.
    function migrate() external;

    /* ============ View/Pure Functions ============ */

    /// @notice Returns the address of the implementation contract.
    function implementation() external view returns (address implementation);
}
