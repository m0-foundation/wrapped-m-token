// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { Common } from "./Common.sol";

/**
 * @title Account Funds Distribution
 * @dev   An abstract implementation for distributing across accounts within vaults based on their shares.
 */
abstract contract AccountFundsDistribution {
    mapping(address vault => uint256 totalShares) private _totalShares;
    mapping(address vault => uint256 pointsPerShare) private _pointsPerShares;
    mapping(address vault => uint256 pointsLost) private _pointsLost; // Ignore this for now.

    mapping(address vault => mapping(address account => int256 correction)) private _correctionPoints;
    mapping(address vault => mapping(address account => uint256 shares)) private _shares;

    /// @dev Distributes the `distributable_` across all shares of `vault_`.
    function _distribute(address vault_, uint256 distributable_) internal {
        if (distributable_ == 0) return;

        uint256 totalShares_ = _totalShares[vault_];

        if (totalShares_ == 0) revert Common.ZeroTotalShares();

        uint256 points_ = distributable_ * Common.PRECISION;

        _pointsPerShares[vault_] += points_ / totalShares_;
        _pointsLost[vault_] += points_ % totalShares_; // Ignore this for now.
    }

    /// @dev Increases the participating shares of `account_` for `vault_`, but first distributes `distributable_`.
    function _addShares(address vault_, uint256 distributable_, address account_, uint256 amount_) internal {
        _distribute(vault_, distributable_);

        if (amount_ == 0) return;

        _correctionPoints[vault_][account_] -= Common.toInt256(_pointsPerShares[vault_] * amount_); // _correctForReceipt

        _shares[vault_][account_] += amount_;
        _totalShares[vault_] += amount_;
    }

    /// @dev Decreases the participating shares of `account_` for `vault_`, but first distributes `distributable_`.
    function _removeShares(address vault_, uint256 distributable_, address account_, uint256 amount_) internal {
        _distribute(vault_, distributable_);

        if (amount_ == 0) return;

        _correctionPoints[vault_][account_] += Common.toInt256(_pointsPerShares[vault_] * amount_); // _correctForSend

        _shares[vault_][account_] -= amount_;
        _totalShares[vault_] -= amount_;
    }

    /// @dev Returns the lifetime distributions of `account_` for its participation in `vault_`.
    function _getCumulativeDistribution(
        address vault_,
        address account_
    ) internal view returns (uint256 distributions_) {
        return
            Common.toUint256(
                Common.toInt256(_pointsPerShares[vault_] * _shares[vault_][account_]) +
                    _correctionPoints[vault_][account_]
            ) / Common.PRECISION;
    }

    /// @dev Returns the participating shares of `account_` for `vault_`.
    function _getShares(address vault_, address account_) internal view returns (uint256 shares_) {
        shares_ = _shares[vault_][account_];
    }
}
