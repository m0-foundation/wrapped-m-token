// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IApprovedEarners {
    error ApprovedEarner(address account);

    error NotApprovedEarner(address account);
}

abstract contract ApprovedEarnersStorageLayout {
    /// @custom:storage-location erc7201:m-zero.storage.ApprovedEarners
    struct ApprovedEarnersStorage {
        mapping(address account => bool isApproved) isApprovedEarner;
    }

    // keccak256(abi.encode(uint256(keccak256("m-zero.storage.ApprovedEarners")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _APPROVED_EARNERS_STORAGE_LOCATION =
        0x04c33fe29ed4a0f4ad2559d47c6677697dbc19677af98b959aa8bd5d1c9bde67; // TODO: Update this value.

    function _getApprovedEarnersStorage() internal pure returns (ApprovedEarnersStorage storage $) {
        assembly {
            $.slot := _APPROVED_EARNERS_STORAGE_LOCATION
        }
    }
}

abstract contract ApprovedEarners is IApprovedEarners, ApprovedEarnersStorageLayout {
    function setIsApprovedEarner(address account_, bool isApproved_) external virtual {
        _beforeSetIsApprovedEarner(account_, isApproved_);

        _getApprovedEarnersStorage().isApprovedEarner[account_] = isApproved_;
    }

    function _revertIfApprovedEarner(address account_) internal view {
        if (_getApprovedEarnersStorage().isApprovedEarner[account_]) revert ApprovedEarner(account_);
    }

    function _revertIfNotApprovedEarner(address account_) internal view {
        if (!_getApprovedEarnersStorage().isApprovedEarner[account_]) revert NotApprovedEarner(account_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeSetIsApprovedEarner(address account_, bool isApproved_) internal virtual {}
}
