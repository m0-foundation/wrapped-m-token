// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IMigratable } from "../../lib/common/src/interfaces/IMigratable.sol";

import { Migratable } from "../../lib/common/src/Migratable.sol";

import { IWrappedMToken } from "../interfaces/IWrappedMToken.sol";

import { WrappedMToken } from "../WrappedMToken.sol";

interface IWrappedMToken_Official is IMigratable, IWrappedMToken {
    error IsApprovedEarner(address account);

    error NotApprovedEarner(address account);

    error UnauthorizedMigration();

    error ZeroMigrationAdmin();

    function migrate(address migrator) external;

    function MIGRATOR_KEY_PREFIX() external pure returns (bytes32 migratorKeyPrefix);

    function migrationAdmin() external view returns (address migrationAdmin);
}

/**
 * @title  Official Wrapped M.
 * @author M^0 Labs
 */
contract WrappedMToken_Official is IWrappedMToken_Official, Migratable, WrappedMToken {
    bytes32 public constant MIGRATOR_KEY_PREFIX = "wm_migrator_vX";

    address public immutable migrationAdmin;

    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address excessDestination_,
        address migrationAdmin_
    ) WrappedMToken(name_, symbol_, mToken_, registrar_, excessDestination_) {
        if ((migrationAdmin = migrationAdmin_) == address(0)) revert ZeroMigrationAdmin();
    }

    function migrate(address migrator_) external {
        if (msg.sender != migrationAdmin) revert UnauthorizedMigration();

        _migrate(migrator_);
    }

    function _getMigrator() internal view override returns (address migrator_) {
        return
            address(
                uint160(
                    // NOTE: A subsequent implementation should use a unique migrator prefix.
                    uint256(_getFromRegistrar(keccak256(abi.encode(MIGRATOR_KEY_PREFIX, address(this)))))
                )
            );
    }

    function _revertIfCannotStartEarning(address account_) internal view override {
        if (!_isRegistrarApprovedEarner(account_)) revert NotApprovedEarner(account_);
    }

    function _revertIfCannotStopEarning(address account_) internal view override {
        if (_isRegistrarApprovedEarner(account_)) revert IsApprovedEarner(account_);
    }
}
