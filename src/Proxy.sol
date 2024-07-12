// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

contract Proxy {
    /// @dev Storage slot with the address of the current factory. `keccak256('eip1967.proxy.implementation') - 1`.
    bytes32 private constant _IMPLEMENTATION_SLOT =
        bytes32(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);

    constructor(address implementation_) {
        if (implementation_ == address(0)) revert();

        bytes32 slot_ = _IMPLEMENTATION_SLOT;

        assembly {
            sstore(slot_, implementation_)
        }
    }

    fallback() external payable virtual {
        bytes32 slot_ = _IMPLEMENTATION_SLOT;
        bytes32 implementation_;

        assembly {
            implementation_ := sload(slot_)
        }

        assembly {
            calldatacopy(0, 0, calldatasize())

            let result_ := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)

            returndatacopy(0, 0, returndatasize())

            switch result_
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
