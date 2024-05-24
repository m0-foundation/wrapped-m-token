// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { IStandardizedYield } from "./IStandardizedYield.sol";

interface IWM is IERC20Extended, IStandardizedYield {
    /* ============ Events ============ */

    /**
     * @notice Emitted when excess earned M tokens are distributed to ZERO token holders.
     * @param  account The account that distributed the excess earned M tokens.
     * @param  amount  The amount of WM tokens distributed.
     */
    event ExcessEarnedMDistributed(address indexed account, uint256 amount);

    /**
     * @notice Emitted when account starts being a WM earner.
     * @param  account The account that started earning.
     */
    event StartedEarning(address indexed account);

    /**
     * @notice Emitted when account stops being a WM earner.
     * @param  account The account that stopped earning.
     */
    event StoppedEarning(address indexed account);

    /* ============ Custom Errors ============ */

    /**
     * @notice Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param  sender  Address whose tokens are being transferred.
     * @param  balance Current balance for the interacting account.
     * @param  needed  Minimum amount required to perform a transfer.
     */
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @notice Emitted when calling `stopEarning` for an account approved as earner by TTG.
     * @param  account Address of the approved account.
     */
    error IsApprovedEarner(address account);

    /**
     * @notice Emitted when calling `startEarning` for an account not approved as earner by TTG.
     * @param  account Address of the unapproved account.
     */
    error NotApprovedEarner(address account);

    /**
     * @notice Emitted when calling `distributeExcessEarnedM` by an account not approved as liquidator by TTG.
     * @param  account Address of the unapproved account.
     */
    error NotApprovedLiquidator(address account);

    /// @notice Emitted in constructor if M token is 0x0.
    error ZeroMToken();

    /// @notice Emitted in constructor if TTG Registrar is 0x0.
    error ZeroTTGRegistrar();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Distributes excess earned M tokens to ZERO token holders.
     * @dev    MUST revert if caller is not the approved liquidator in TTG Registrar.
     * @param  minAmount Minimum amount of M tokens to distribute.
     */
    function distributeExcessEarnedM(uint256 minAmount) external;

    /// @notice Starts earning for caller if allowed by TTG.
    function startEarning() external;

    /// @notice Stops earning for caller.
    function stopEarning() external;

    /**
     * @notice Stops earning for `account`.
     * @dev    MUST revert if `account` is an approved earner in TTG Registrar.
     * @param  account The account to stop earning for.
     */
    function stopEarning(address account) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The M token index at deployment.
    function latestIndex() external view returns (uint128);

    /**
     * @notice Checks if account is an earner.
     * @param  account The account to check.
     * @return True if account is an earner, false otherwise.
     */
    function isEarning(address account) external view returns (bool);

    /// @notice The total amount of M earned by the earning accounts.
    function totalEarnedM() external view returns (uint256);

    /// @notice The address of the TTG Registrar contract.
    function ttgRegistrar() external view returns (address);
}
