// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IApprovedWrappers {
    error NotApprovedWrapper(address account);
}

abstract contract ApprovedWrappersStorageLayout {
    /// @custom:storage-location erc7201:m-zero.storage.ApprovedWrappers
    struct ApprovedWrappersStorage {
        mapping(address account => bool isApproved) isApprovedWrapper;
    }

    // keccak256(abi.encode(uint256(keccak256("m-zero.storage.ApprovedWrappers")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _APPROVED_WRAPPERS_STORAGE_LOCATION =
        0x6f390fc6074c8f8de15071b44536776a87a0ac6d08eaa0aec5c6d3336fe68752; // TODO: Update this value.

    function _getApprovedWrappersStorage() internal pure returns (ApprovedWrappersStorage storage $) {
        assembly {
            $.slot := _APPROVED_WRAPPERS_STORAGE_LOCATION
        }
    }
}

abstract contract ApprovedWrappers is IApprovedWrappers, ApprovedWrappersStorageLayout {
    function setIsApprovedWrapper(address account_, bool isApproved_) external virtual {
        _beforeSetIsApprovedWrapper(account_, isApproved_);

        _getApprovedWrappersStorage().isApprovedWrapper[account_] = isApproved_;
    }

    function _revertIfNotApprovedWrapper(address account_) internal view {
        if (!_getApprovedWrappersStorage().isApprovedWrapper[account_]) revert NotApprovedWrapper(account_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeSetIsApprovedWrapper(address account_, bool isApproved_) internal virtual {}
}
