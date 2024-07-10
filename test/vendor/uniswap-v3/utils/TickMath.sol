// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

/// @title Math library for computing sqrt prices from ticks and vice versa
/// @notice Computes sqrt price for ticks of size 1.0001, i.e. sqrt(1.0001^tick) as fixed point Q64.96 numbers. Supports
/// prices between 2**-128 and 2**128
/// @dev Contract from Uniswap V3 core
///      https://github.com/Uniswap/v3-core/blob/fc2107bd5709cdee6742d5164c1eb998566bcb75/contracts/libraries/TickMath.sol
library TickMath {
    /// @dev The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = -MIN_TICK;
}
