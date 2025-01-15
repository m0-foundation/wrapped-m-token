// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title  Migrator contract for migrating a WrappedMToken contract.
 * @author M^0 Labs
 */
abstract contract WrappedMTokenMigrator {
    /// @dev Storage slot with the address of the current factory. `keccak256('eip1967.proxy.implementation') - 1`.
    uint256 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public immutable newImplementation;

    constructor(address newImplementation_) {
        newImplementation = newImplementation_;
    }

    fallback() external virtual {
        address newImplementation_ = newImplementation;

        assembly {
            sstore(_IMPLEMENTATION_SLOT, newImplementation_)
        }
    }
}
