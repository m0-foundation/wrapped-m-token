// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IMigratable } from "./interfaces/IMigratable.sol";

abstract contract Migratable is IMigratable {
    /* ============ Variables ============ */

    /// @dev Storage slot with the address of the current factory. `keccak256('eip1967.proxy.implementation') - 1`.
    bytes32 private constant _IMPLEMENTATION_SLOT =
        bytes32(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);

    /* ============ Interactive Functions ============ */

    function migrate() external {
        address migrator_ = _getMigrator();

        if (migrator_ == address(0)) revert ZeroMigrator();

        address oldImplementation_ = implementation();

        migrator_.delegatecall("");

        emit Migrate(migrator_, oldImplementation_, implementation());
    }

    /* ============ View/Pure Functions ============ */

    function implementation() public view returns (address implementation_) {
        bytes32 slot_ = _IMPLEMENTATION_SLOT;

        assembly {
            implementation_ := sload(slot_)
        }
    }

    /* ============ Internal View/Pure Functions ============ */

    function _getMigrator() internal view virtual returns (address migrator_);
}
