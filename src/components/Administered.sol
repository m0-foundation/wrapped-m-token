// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IAdministered {
    error ZeroAdmin();

    error NotAdmin();

    event AdminSet(address indexed admin);

    event PendingAdminSet(address indexed pendingAdmin);
}

abstract contract AdministeredStorageLayout {
    /// @custom:storage-location erc7201:m-zero.storage.Administered
    struct AdministeredStorage {
        address admin;
        address pendingAdmin;
    }

    // keccak256(abi.encode(uint256(keccak256("m-zero.storage.Administered")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _ADMINISTERED_STORAGE_LOCATION =
        0xfbb0f8c22dd690c1ef4345fb8f26e7d0f7a0e52285488e9412842ee7f05b1d99; // TODO: Update this value.

    function _getAdministeredStorage() internal pure returns (AdministeredStorage storage $) {
        assembly {
            $.slot := _ADMINISTERED_STORAGE_LOCATION
        }
    }
}

abstract contract Initializer is AdministeredStorageLayout {
    function _initialize(address admin_) internal {
        if ((_getAdministeredStorage().admin = admin_) == address(0)) revert IAdministered.ZeroAdmin();

        emit IAdministered.AdminSet(admin_);
    }
}

abstract contract Administered is IAdministered, AdministeredStorageLayout {
    function setPendingAdmin(address pendingAdmin_) external {
        _revertIfNotAdmin();

        emit PendingAdminSet(_getAdministeredStorage().pendingAdmin = pendingAdmin_);
    }

    function acceptAdmin() external {
        AdministeredStorage storage $ = _getAdministeredStorage();

        address pendingAdmin_ = $.pendingAdmin;

        if (msg.sender != pendingAdmin_) revert NotAdmin();

        emit AdminSet($.admin = pendingAdmin_);

        delete $.pendingAdmin;
    }

    function _revertIfNotAdmin() internal view virtual {
        if (msg.sender != _getAdministeredStorage().admin) revert NotAdmin();
    }
}
