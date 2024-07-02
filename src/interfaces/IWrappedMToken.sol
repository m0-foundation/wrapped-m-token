// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { IMigratable } from "./IMigratable.sol";

interface IWrappedMToken is IMigratable, IERC20Extended {
    /* ============ Events ============ */

    event Claimed(address indexed account, address indexed recipient, uint256 yield);

    event ExcessClaimed(uint256 yield);

    /**
     * @notice Emitted when account starts being an wM earner.
     * @param  account The account that started earning.
     */
    event StartedEarning(address indexed account);

    /**
     * @notice Emitted when account stops being an wM earner.
     * @param  account The account that stopped earning.
     */
    event StoppedEarning(address indexed account);

    /* ============ Custom Errors ============ */

    /// @notice Emitted when calling `stopEarning` for an account approved as earner by TTG.
    error IsApprovedEarner();

    /**
     * @notice Emitted when there is insufficient balance to decrement from `account`.
     * @param  account The account with insufficient balance.
     * @param  balance The balance of the account.
     * @param  amount  The amount to decrement.
     */
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    /// @notice Emitted when calling `startEarning` for an account not approved as earner by TTG.
    error NotApprovedEarner();

    /// @notice Emitted when calling `startEarningM` after wrapper was already in earning state once.
    error OnlyEarningOnce();

    /// @notice Emitted when method is called when Wrapped M is not in earning state.
    error NotInEarningState();

    /// @notice Emitted in constructor if M Token is 0x0.
    error ZeroMToken();

    /* ============ Interactive Functions ============ */

    function wrap(address recipient, uint256 amount) external;

    function unwrap(address recipient, uint256 amount) external;

    function claimFor(address account) external returns (uint240 yield);

    function claimExcess() external returns (uint240 yield);

    function startEarningM() external;

    function stopEarningM() external;

    function startEarningFor(address account) external;

    function stopEarningFor(address account) external;

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account) external view returns (uint240 yield);

    function currentIndex() external view returns (uint128 index);

    function isEarning(address account) external view returns (bool isEarning);

    function excess() external view returns (uint240 yield);

    function mToken() external view returns (address mToken);

    function totalNonEarningSupply() external view returns (uint240 totalSupply);

    function registrar() external view returns (address registrar);

    function totalAccruedYield() external view returns (uint240 yield);

    function totalEarningSupply() external view returns (uint240 totalSupply);

    function vault() external view returns (address vault);
}
