// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { Common } from "./Common.sol";

/**
 * @title Vault Funds Distribution
 * @dev   An abstract contract for distributing across vaults based on their shares.
 */
abstract contract VaultFundsDistribution {
    uint256 private _totalShares;
    uint256 private _pointsPerShare;
    uint256 private _pointsLost; // Ignore this for now.

    mapping(address vault => int256 correction) private _correctionPoints;
    mapping(address vault => uint256 shares) private _shares;

    /// @dev Distributes the `distributable_` across all shares.
    function _distribute(uint256 distributable_) internal {
        if (distributable_ == 0) return;

        uint256 totalShares_ = _totalShares;

        if (totalShares_ == 0) revert Common.ZeroTotalShares();

        uint256 points_ = distributable_ * Common.PRECISION;

        _pointsPerShare += points_ / totalShares_;
        _pointsLost += points_ % totalShares_; // Ignore this for now.
    }

    /// @dev Increases the participating shares of `vault_`, but first distributes `distributable_`.
    function _addShares(uint256 distributable_, address vault_, uint256 amount_) internal {
        _distribute(distributable_);

        if (amount_ == 0) return;

        _correctionPoints[vault_] -= Common.toInt256(_pointsPerShare * amount_); // _correctForReceipt

        _shares[vault_] += amount_;
        _totalShares += amount_;
    }

    /// @dev Decreases the participating shares of `vault_`, but first distributes `distributable_`.
    function _removeShares(uint256 distributable_, address vault_, uint256 amount_) internal {
        _distribute(distributable_);

        if (amount_ == 0) return;

        _correctionPoints[vault_] += Common.toInt256(_pointsPerShare * amount_); // _correctForSend

        _shares[vault_] -= amount_;
        _totalShares -= amount_;
    }

    /// @dev Returns the lifetime distributions of `vault_`.
    function _getCumulativeDistribution(address vault_) internal view returns (uint256 distributions_) {
        return
            Common.toUint256(Common.toInt256(_pointsPerShare * _shares[vault_]) + _correctionPoints[vault_]) /
            Common.PRECISION;
    }

    /// @dev Returns the participating shares of `vault_`.
    function _getShares(address vault_) internal view returns (uint256 shares_) {
        shares_ = _shares[vault_];
    }
}
