// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { EarnerStatusManager } from "../../src/EarnerStatusManager.sol";

contract EarnerStatusManagerHarness is EarnerStatusManager {
    constructor(address registrar_) EarnerStatusManager(registrar_) {}

    function setInternalEarnerStatus(address account_, bool earnerStatus_) external {
        _earnerStatuses[account_] = earnerStatus_;
    }

    function getInternalEarnerStatus(address account_) external view returns (bool earnerStatus_) {
        return _earnerStatuses[account_];
    }
}
