// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IApprovedEarners {
    error ApprovedEarner(address account);

    error NotApprovedEarner(address account);
}

abstract contract ApprovedEarners is IApprovedEarners {
    mapping(address account => bool isApproved) public isApprovedEarner;

    function setIsApprovedEarner(address account_, bool isApproved_) external virtual {
        _beforeSetIsApprovedEarner(account_, isApproved_);

        isApprovedEarner[account_] = isApproved_;
    }

    function _revertIfApprovedEarner(address account_) internal view {
        if (isApprovedEarner[account_]) revert ApprovedEarner(account_);
    }

    function _revertIfNotApprovedEarner(address account_) internal view {
        if (!isApprovedEarner[account_]) revert NotApprovedEarner(account_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeSetIsApprovedEarner(address account_, bool isApproved_) internal virtual {}
}
