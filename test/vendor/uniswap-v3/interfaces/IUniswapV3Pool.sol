// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

/// @title The interface for a Uniswap V3 Pool
/// @notice A Uniswap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
/// @dev Contract from Uniswap V3 core
///      https://github.com/Uniswap/v3-core/blob/4024732be626f4b4299a4314150d5c5471d59ed9/contracts/interfaces/IUniswapV3Pool.sol
interface IUniswapV3Pool {
    /// @notice Sets the initial price for the pool
    /// @dev Price is represented as a sqrt(amountToken1/amountToken0) Q64.96 value
    /// @param sqrtPriceX96 the initial sqrt price of the pool as a Q64.96
    function initialize(uint160 sqrtPriceX96) external;
}
