// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IWrappedMToken } from "../interfaces/IWrappedMToken.sol";

import { WrappedMToken } from "../WrappedMToken.sol";

import { IAdministered, Administered } from "../components/Administered.sol";

interface IWrappedMToken_AM is IAdministered, IWrappedMToken {
    function migrate(address migrator_) external;
}

/**
 * @title  Admin-controlled upgrade/migration.
 * @author M^0 Labs
 */
contract WrappedMToken_AM is IWrappedMToken_AM, Administered, WrappedMToken {
    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address excessDestination_,
        address admin_
    ) WrappedMToken(name_, symbol_, mToken_, registrar_, excessDestination_) Administered(admin_) {}

    function migrate(address migrator_) external {
        _migrate(migrator_);
    }

    function _beforeMigrate(address migrator_) internal override {
        _revertIfNotAdmin();

        super._beforeMigrate(migrator_);
    }

    function _beforeStopEarning(address account_, uint128 currentIndex_) internal override {
        _claim(account_, currentIndex_);

        super._beforeStopEarning(account_, currentIndex_);
    }
}
