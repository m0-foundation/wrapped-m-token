// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

interface IYM is IERC20Extended {
    /* ============ Events ============ */

    /**
     * @notice Emitted when YM tokens are distributed to ZERO token holders.
     * @param  liquidator Address of the account that distributed the YM tokens.
     * @param  amount     Amount of underlying M tokens distributed.
     * @param  shares     Amount of YM shares minted.
     */
    event ExcessEarnedMDistributed(address indexed liquidator, uint256 amount, uint256 shares);

    /**
     * @notice Emitted when account stops being a YM earner.
     * @param  account The account that stopped earning.
     */
    event StoppedEarning(address indexed account);

    /* ============ Custom Errors ============ */

    // TODO: merge in a common IERC20Errors.sol file
    /**
     * @notice Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param  sender  Address whose tokens are being transferred.
     * @param  balance Current balance for the interacting account.
     * @param  needed  Minimum amount required to perform a transfer.
     */
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @notice Indicates an error related to the current available earned M tokens that can be distributed.
     * @param  amount    Current amount of earned M tokens.
     * @param  requested Amount of earned M requested.
     */
    error InsufficientExcessEarnedM(uint256 amount, uint256 requested);

    /**
     * @notice Emitted when calling `stopEarning` for an account earning in M token.
     * @param  account Address of the earning account.
     */
    error IsEarning(address account);

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

    /// @notice Emitted if the caller is not the WM token.
    error NotWMToken();

    /// @notice Emitted in constructor if M token is 0x0.
    error ZeroMToken();

    /// @notice Emitted in constructor if TTG Registrar is 0x0.
    error ZeroTTGRegistrar();

    /// @notice Emitted in constructor if WM token is 0x0.
    error ZeroWMToken();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Mint YM tokens to `account`.
     * @dev    MUST only be callable by the WM token.
     * @param  account   The account to mint YM to.
     * @param  amount    The amount of YM to mint.
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice burn YM tokens from `account`.
     * @dev    MUST only be callable by the WM token.
     * @param  account   The account to burn YM from.
     * @param  amount    The amount of YM to burn.
     */
    function burn(address account, uint256 amount) external;

    /**
     * @notice Distributes excess earned M tokens to ZERO token holders.
     * @dev    MUST revert if caller is not the approved liquidator in TTG Registrar.
     * @param  amount Amount of earned M tokens to distribute.
     */
    function distributeExcessEarnedM(uint256 amount) external;

    /// @notice Stops earning for caller.
    function stopEarning() external;

    /**
     * @notice Stops earning for `account`.
     * @dev    MUST revert if `account` is earning in M token.
     * @param  account The account to stop earning for.
     */
    function stopEarning(address account) external;

    /* ============ View/Pure Functions ============ */

    /**
     * @notice Returns the amount of underlying M tokens earned by `account` and held in the WM token.
     * @param  account The account to query the earned M balance of.
     * @return The amount of M tokens earned by `account`.
     */
    function balanceOfEarnedM(address account) external view returns (uint256);

    /// @notice Returns the address of the underlying M token.
    function mToken() external view returns (address);

    /// @notice The address of the TTG Registrar contract.
    function ttgRegistrar() external view returns (address);

    /// @notice Returns the address of the WM token.
    function wMToken() external view returns (address);
}
