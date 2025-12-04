// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Freezable } from "../../src/components/freezable/Freezable.sol";

contract FreezableHarness is Freezable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address freezeManager) public initializer {
        __Freezable_init(freezeManager);
    }

    function revertIfFrozenInternal(address account) external view {
        _revertIfFrozen(_getFreezableStorageLocation(), account);
    }

    function revertIfFrozen(address account) external view {
        _revertIfFrozen(account);
    }

    function revertIfNotFrozenInternal(address account) external view {
        _revertIfNotFrozen(_getFreezableStorageLocation(), account);
    }

    function revertIfNotFrozen(address account) external view {
        _revertIfNotFrozen(account);
    }
}
