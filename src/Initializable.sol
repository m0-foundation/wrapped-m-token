// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IImplementation } from "./interfaces/IImplementation.sol";
import { IInitializable } from "./interfaces/IInitializable.sol";

contract Initializable is IInitializable {
    error ZeroAddress();
    error InitializationFailed(bytes errorData);

    /// @dev Storage slot with the address of the current factory. `keccak256('eip1967.proxy.implementation') - 1`.
    uint256 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function initialize(address implementation_, bytes calldata initializationArguments_) external {
        if (implementation_ == address(0)) revert();

        assembly {
            sstore(_IMPLEMENTATION_SLOT, implementation_)
        }

        // Get the specific initializer to use, as defined by the implementation.
        address initializer_ = IImplementation(implementation_).initializer();

        if (initializer_ == address(0)) revert();

        (bool success, bytes memory result) = initializer_.delegatecall(initializationArguments_);

        if (!success) revert InitializationFailed(result);
    }
}
