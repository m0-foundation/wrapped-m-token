// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IMigratable {
    event Migrated(address indexed migrator, address indexed oldImplementation, address indexed newImplementation);

    event Upgraded(address indexed implementation);

    error InvalidMigrator();

    /// @notice Emitted when the delegatecall to the migrator fails.
    error MigrationFailed();

    error ZeroMigrator();

    function migrate() external;

    function implementation() external view returns (address implementation);
}
