// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IAdminApprovedEarners {
    error NotApprovedEarner(address account);
}

abstract contract AdminApprovedEarners is IAdminApprovedEarners {
    mapping(address account => bool isApproved) public isApprovedEarner;

    function setIsApprovedEarner(address account_, bool isApproved_) external {
        _revertIfNotAdmin();
        isApprovedEarner[account_] = isApproved_;
    }

    function _revertIfNotAdmin() internal virtual;

    function _revertIfCannotStartEarning(address account_) internal view virtual {
        if (!isApprovedEarner[account_]) revert NotApprovedEarner(account_);
    }
}
