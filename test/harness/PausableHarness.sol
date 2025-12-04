// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Pausable } from "../../src/components/pausable/Pausable.sol";

contract PausableHarness is Pausable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address pauser) public initializer {
        __Pausable_init(pauser);
    }
}
