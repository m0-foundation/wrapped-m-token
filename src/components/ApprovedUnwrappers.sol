// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IApprovedUnwrappers {
    error NotApprovedUnwrapper(address account);
}

abstract contract ApprovedUnwrappersStorageLayout {
    /// @custom:storage-location erc7201:m-zero.storage.ApprovedUnwrappers
    struct ApprovedUnwrappersStorage {
        mapping(address account => bool isApproved) isApprovedUnwrapper;
    }

    // keccak256(abi.encode(uint256(keccak256("m-zero.storage.ApprovedUnwrappers")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _APPROVED_UNWRAPPERS_STORAGE_LOCATION =
        0xe01ee865e5080ad2a381701c74955dc9fb36393383724e72be97772be04b053b; // TODO: Update this value.

    function _getApprovedUnwrappersStorage() internal pure returns (ApprovedUnwrappersStorage storage $) {
        assembly {
            $.slot := _APPROVED_UNWRAPPERS_STORAGE_LOCATION
        }
    }
}

abstract contract ApprovedUnwrappers is IApprovedUnwrappers, ApprovedUnwrappersStorageLayout {
    function setIsApprovedUnwrapper(address account_, bool isApproved_) external virtual {
        _beforeSetIsApprovedUnwrapper(account_, isApproved_);

        _getApprovedUnwrappersStorage().isApprovedUnwrapper[account_] = isApproved_;
    }

    function _revertIfNotApprovedUnwrapper(address account_) internal view {
        if (!_getApprovedUnwrappersStorage().isApprovedUnwrapper[account_]) revert NotApprovedUnwrapper(account_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeSetIsApprovedUnwrapper(address account_, bool isApproved_) internal virtual {}
}
