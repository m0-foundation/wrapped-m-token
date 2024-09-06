// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { EarnerStatusManager } from "../../src/EarnerStatusManager.sol";

contract EarnerStatusManagerHarness is EarnerStatusManager {
    constructor(address registrar_) EarnerStatusManager(registrar_) {}

    function setInternalStatus(address account_, uint256 status_) external {
        _statuses[account_] = status_;
    }

    function setAdminsBitMask(uint256 adminsBitMask_) external {
        _adminsBitMask = adminsBitMask_;
    }

    function getInternalStatus(address account_) external view returns (uint256 status_) {
        return _statuses[account_];
    }
}
