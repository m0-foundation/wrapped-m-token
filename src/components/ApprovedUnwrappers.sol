// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IApprovedUnwrappers {
    error NotApprovedUnwrapper(address account);
}

abstract contract ApprovedUnwrappers is IApprovedUnwrappers {
    mapping(address account => bool isApproved) public isApprovedUnwrapper;

    function setIsApprovedUnwrapper(address account_, bool isApproved_) external virtual {
        _beforeSetIsApprovedUnwrapper(account_, isApproved_);

        isApprovedUnwrapper[account_] = isApproved_;
    }

    function _revertIfNotApprovedUnwrapper(address account_) internal view {
        if (!isApprovedUnwrapper[account_]) revert NotApprovedUnwrapper(account_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeSetIsApprovedUnwrapper(address account_, bool isApproved_) internal virtual {}
}
