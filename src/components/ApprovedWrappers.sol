// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IApprovedWrappers {
    error NotApprovedWrapper(address account);
}

abstract contract ApprovedWrappers is IApprovedWrappers {
    mapping(address account => bool isApproved) public isApprovedWrapper;

    function setIsApprovedWrapper(address account_, bool isApproved_) external virtual {
        _beforeSetIsApprovedWrapper(account_, isApproved_);

        isApprovedWrapper[account_] = isApproved_;
    }

    function _revertIfNotApprovedWrapper(address account_) internal view {
        if (!isApprovedWrapper[account_]) revert NotApprovedWrapper(account_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeSetIsApprovedWrapper(address account_, bool isApproved_) internal virtual {}
}
