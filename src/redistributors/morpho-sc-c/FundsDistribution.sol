// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

/**
 * @title Funds Distribution
 * @dev   An abstract implementation for distributing across accounts based on their shares.
 */
abstract contract FundsDistribution {
    error OutOfBoundsForInt256();
    error OutOfBoundsForUInt256();
    error ZeroTotalShares();

    uint256 internal constant _PRECISION = 2 ** 128;

    uint256 internal _totalShares;
    uint256 internal _pointsPerShare;
    uint256 internal _pointsLost; // Ignore this for now.

    mapping(address account => int256 correction) internal _correctionPoints;
    mapping(address account => uint256 shares) internal _shares;

    /// @dev Distributes the `distributable_` across all shares.
    function _distribute(uint256 amount_) internal {
        if (amount_ == 0) return;

        uint256 totalShares_ = _totalShares;

        if (totalShares_ == 0) revert ZeroTotalShares();

        uint256 points_ = amount_ * _PRECISION;

        _pointsPerShare += points_ / totalShares_;
        _pointsLost += points_ % totalShares_;
    }

    /// @dev Increases the participating shares of `account_`, but first distributes `distributable_`.
    function _addShares(uint256 distributable_, address account_, uint256 amount_) internal {
        _distribute(distributable_);

        if (amount_ == 0) return;

        _correctionPoints[account_] -= _toInt256(_pointsPerShare * amount_); // _correctForReceipt

        _shares[account_] += amount_;
        _totalShares += amount_;
    }

    /// @dev Decreases the participating shares of `account_`, but first distributes `distributable_`.
    function _removeShares(uint256 distributable_, address account_, uint256 amount_) internal {
        _distribute(distributable_);

        if (amount_ == 0) return;

        _correctionPoints[account_] += _toInt256(_pointsPerShare * amount_); // _correctForSend

        _shares[account_] -= amount_;
        _totalShares -= amount_;
    }

    /// @dev Returns the lifetime distributions of `account_`.
    function _getCumulativeDistribution(address account_) internal view returns (uint256 distributions_) {
        return _toUint256(_toInt256(_pointsPerShare * _shares[account_]) + _correctionPoints[account_]) / _PRECISION;
    }

    function _toInt256(uint256 a_) internal pure returns (int256 b_) {
        if (a_ > uint256(type(int256).max)) revert OutOfBoundsForInt256();

        b_ = int256(a_);
    }

    function _toUint256(int256 a_) internal pure returns (uint256 b_) {
        if (a_ < 0) revert OutOfBoundsForUInt256();

        b_ = uint256(a_);
    }
}
