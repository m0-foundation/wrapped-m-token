// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IWrappedMToken } from "../interfaces/IWrappedMToken.sol";

import { WrappedMToken } from "../WrappedMToken.sol";

import { IAdministered, Administered } from "../components/Administered.sol";
import { IAdminMigratable, AdminMigratable } from "../components/AdminMigratable.sol";
import { IAdminApprovedEarners, AdminApprovedEarners } from "../components/AdminApprovedEarners.sol";

interface IWrappedMToken_AM_AEW is IAdminApprovedEarners, IAdminMigratable, IAdministered, IWrappedMToken {}

/**
 * @title  Admin-controlled upgrade/migration and admin-controlled earner whitelist.
 * @author M^0 Labs
 */
contract WrappedMToken_AM_AEW is
    IWrappedMToken_AM_AEW,
    AdminApprovedEarners,
    AdminMigratable,
    Administered,
    WrappedMToken
{
    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address excessDestination_,
        address admin_
    ) WrappedMToken(name_, symbol_, mToken_, registrar_, excessDestination_) Administered(admin_) {}

    function _revertIfNotAdmin() internal view override(AdminApprovedEarners, AdminMigratable, Administered) {
        Administered._revertIfNotAdmin();
    }

    function _revertIfCannotStartEarning(address account_) internal view override(AdminApprovedEarners, WrappedMToken) {
        AdminApprovedEarners._revertIfCannotStartEarning(account_);
    }
}
