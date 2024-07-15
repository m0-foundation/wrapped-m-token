// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { IMigratable } from "./interfaces/IMigratable.sol";

abstract contract Migratable is IMigratable {
    /* ============ Variables ============ */

    /// @dev Storage slot with the address of the current factory. `keccak256('eip1967.proxy.implementation') - 1`.
    uint256 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /* ============ Interactive Functions ============ */

    function migrate() external {
        _migrate(_getMigrator());
    }

    /* ============ View/Pure Functions ============ */

    function implementation() public view returns (address implementation_) {
        assembly {
            implementation_ := sload(_IMPLEMENTATION_SLOT)
        }
    }

    /* ============ Internal Interactive Functions ============ */

    function _migrate(address migrator_) internal {
        if (migrator_ == address(0)) revert ZeroMigrator();

        if (migrator_.code.length == 0) revert InvalidMigrator();

        address oldImplementation_ = implementation();

        migrator_.delegatecall("");

        address newImplementation_ = implementation();

        emit Migrated(migrator_, oldImplementation_, newImplementation_);
        emit Upgraded(newImplementation_);
    }

    /* ============ Internal View/Pure Functions ============ */

    function _getMigrator() internal view virtual returns (address migrator_);
}
