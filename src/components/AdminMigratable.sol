// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IAdminMigratable {
    event Migrated(address indexed migrator, address indexed oldImplementation, address indexed newImplementation);

    event Upgraded(address indexed implementation);

    error InvalidMigrator();

    error MigrationFailed();

    error ZeroMigrator();

    function migrate(address migrator) external;

    function implementation() external view returns (address);
}

abstract contract AdminMigratable is IAdminMigratable {
    /// @dev Storage slot with the address of the current factory. `keccak256('eip1967.proxy.implementation') - 1`.
    uint256 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function migrate(address migrator_) external {
        _revertIfNotAdmin();

        if (migrator_ == address(0)) revert ZeroMigrator();

        if (migrator_.code.length == 0) revert InvalidMigrator();

        address oldImplementation_ = implementation();

        (bool success_, ) = migrator_.delegatecall("");
        if (!success_) revert MigrationFailed();

        address newImplementation_ = implementation();

        emit Migrated(migrator_, oldImplementation_, newImplementation_);

        // NOTE: Redundant event emitted to conform to the EIP-1967 standard.
        emit Upgraded(newImplementation_);
    }

    function implementation() public view returns (address implementation_) {
        assembly {
            implementation_ := sload(_IMPLEMENTATION_SLOT)
        }
    }

    function _revertIfNotAdmin() internal virtual;
}
