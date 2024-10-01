// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

library Common {
    error OutOfBoundsForInt256();
    error OutOfBoundsForUInt256();
    error ZeroTotalShares();

    uint256 internal constant PRECISION = 2 ** 128; // TODO: Tune this.

    function toInt256(uint256 a_) internal pure returns (int256 b_) {
        if (a_ > uint256(type(int256).max)) revert OutOfBoundsForInt256();

        b_ = int256(a_);
    }

    function toUint256(int256 a_) internal pure returns (uint256 b_) {
        if (a_ < 0) revert OutOfBoundsForUInt256();

        b_ = uint256(a_);
    }
}
