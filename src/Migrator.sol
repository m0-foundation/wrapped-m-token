// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

contract Migrator {
    bytes32 private constant _IMPLEMENTATION_SLOT =
        bytes32(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);

    address internal immutable _implementation;

    constructor(address implementation_) {
        _implementation = implementation_;
    }

    fallback() external virtual {
        bytes32 slot_ = _IMPLEMENTATION_SLOT;
        address implementation_ = _implementation;

        assembly {
            sstore(slot_, implementation_)
        }
    }
}
