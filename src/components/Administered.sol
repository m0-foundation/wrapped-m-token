// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IAdministered {
    error ZeroAdmin();

    error NotAdmin();

    event AdminSet(address indexed admin);

    event PendingAdminSet(address indexed pendingAdmin);
}

abstract contract Administered is IAdministered {
    address public admin;
    address public pendingAdmin;

    constructor(address admin_) {
        if (admin_ == address(0)) revert ZeroAdmin();

        emit AdminSet(admin = admin_);
    }

    function setPendingAdmin(address pendingAdmin_) external {
        _revertIfNotAdmin();

        emit PendingAdminSet(pendingAdmin = pendingAdmin_);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotAdmin();

        emit AdminSet(admin = pendingAdmin);

        delete pendingAdmin;
    }

    function _revertIfNotAdmin() internal view virtual {
        if (msg.sender != admin) revert NotAdmin();
    }
}
