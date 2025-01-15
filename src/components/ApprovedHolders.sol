// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IApprovedHolders {
    error NotApprovedHolder(address account);
}

abstract contract ApprovedHolders is IApprovedHolders {
    mapping(address account => bool isApproved) public isApprovedHolder;

    function setIsApprovedHolder(address account_, bool isApproved_) external virtual {
        _beforeSetIsApprovedHolder(account_, isApproved_);

        isApprovedHolder[account_] = isApproved_;
    }

    function _revertIfNotApprovedHolder(address account_) internal view {
        if (!isApprovedHolder[account_]) revert NotApprovedHolder(account_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeSetIsApprovedHolder(address account_, bool isApproved_) internal virtual {}
}
