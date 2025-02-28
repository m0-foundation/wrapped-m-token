// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { EarnerManager } from "../../src/EarnerManager.sol";

contract EarnerManagerHarness is EarnerManager {
    constructor(address registrar_) EarnerManager(registrar_) {}

    function setInternalEarnerDetails(address account_, address admin_, uint16 feeRate_) external {
        _earnerDetails[account_] = EarnerDetails(admin_, feeRate_);
    }

    function setDetails(address account_, bool status_, uint16 feeRate_) external {
        _setDetails(account_, status_, feeRate_);
    }

    function setMigrationAdmin(address migrationAdmin_) external {
        migrationAdmin = migrationAdmin_;
    }

    function setInternalPendingMigrationAdmin(address pendingMigrationAdmin_) external {
        pendingMigrationAdmin = pendingMigrationAdmin_;
    }
}
