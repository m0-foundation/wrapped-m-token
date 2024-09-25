// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

/**
 * @title Funds Distribution
 * @dev   An abstract implementation for distributing across accounts based on their shares.
 */
abstract contract FundsDistribution {
    error ZeroTotalShares();

    uint256 internal constant _PRECISION = 2 ** 128;

    uint256 internal _totalShares; // T = 0
    uint256 internal _pointsPerShare; // S = 0
    uint256 internal _pointsLost; // Ignore this for now.

    mapping(address account => uint256 index) internal _pointsPerShares; // S0 = {}
    mapping(address account => uint256 shares) internal _shares; // stake = {}

    /// @dev Distributes the `distributable_` across all shares.
    function _distribute(uint256 amount_) internal {
        if (amount_ == 0) return;

        uint256 totalShares_ = _totalShares;

        if (totalShares_ == 0) revert ZeroTotalShares();

        uint256 points_ = amount_ * _PRECISION;

        _pointsPerShare += points_ / totalShares_; // S = S + r / T
        _pointsLost += points_ % totalShares_;
    }

    /// @dev Increases the participating shares of `account_`, but first distributes `distributable_` then harvests.
    function _addShares(
        uint256 distributable_,
        address account_,
        uint256 amount_
    ) internal returns (uint256 harvested_) {
        _distribute(distributable_);

        if (amount_ == 0) return 0;

        harvested_ = _harvest(account_);

        _shares[account_] += amount_;
        _totalShares += amount_; // T = T + amount
    }

    /// @dev Decreases the participating shares of `account_`, but first distributes `distributable_` then harvests.
    function _removeShares(
        uint256 distributable_,
        address account_,
        uint256 amount_
    ) internal returns (uint256 harvested_) {
        _distribute(distributable_);

        if (amount_ == 0) return 0;

        harvested_ = _harvest(account_);

        _shares[account_] -= amount_;
        _totalShares -= amount_; // T = T - amount
    }

    /// @dev Harvests the pending distribution for `account_`.
    function _harvest(address account_) internal returns (uint256 harvested_) {
        harvested_ = _getDistribution(account_);
        _pointsPerShares[account_] = _pointsPerShare; // S0[address] = S
    }

    /// @dev Returns the pending distribution of `account_`.
    function _getDistribution(address account_) internal view returns (uint256 reward_) {
        return (_shares[account_] * (_pointsPerShare - _pointsPerShares[account_])) / _PRECISION; // stake[address] * (S - S0[address])
    }
}
