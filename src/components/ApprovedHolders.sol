// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IApprovedHolders {
    error NotApprovedHolder(address account);
}

abstract contract ApprovedHoldersLayout {
    /// @custom:storage-location erc7201:m-zero.storage.ApprovedHolders
    struct ApprovedHoldersStorage {
        mapping(address account => bool isApproved) isApprovedHolder;
    }

    // keccak256(abi.encode(uint256(keccak256("m-zero.storage.ApprovedHolders")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _APPROVED_HOLDERS_STORAGE_LOCATION =
        0xd9713610e02dd164e5be09a24564c9315cd2335f0d0ab26fe2e84c68635357ad; // TODO: Update this value.

    function _getApprovedHoldersStorage() internal pure returns (ApprovedHoldersStorage storage $) {
        assembly {
            $.slot := _APPROVED_HOLDERS_STORAGE_LOCATION
        }
    }
}

abstract contract ApprovedHolders is IApprovedHolders, ApprovedHoldersLayout {
    function setIsApprovedHolder(address account_, bool isApproved_) external virtual {
        _beforeSetIsApprovedHolder(account_, isApproved_);

        _getApprovedHoldersStorage().isApprovedHolder[account_] = isApproved_;
    }

    function _revertIfNotApprovedHolder(address account_) internal view {
        if (!_getApprovedHoldersStorage().isApprovedHolder[account_]) revert NotApprovedHolder(account_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeSetIsApprovedHolder(address account_, bool isApproved_) internal virtual {}
}
