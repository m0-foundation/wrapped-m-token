// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { IMigratable } from "./IMigratable.sol";

/**
 * @title  Wrapped M Token interface extending Extended ERC20.
 * @author M^0 Labs
 */
interface IWrappedMToken is IMigratable, IERC20Extended {
    /* ============ Events ============ */

    /**
     * @notice Emitted when some yield is claim for `account` to `recipient`.
     * @param  account   The account under which yield was generated.
     * @param  recipient The account that received the yield.
     * @param  yield     The amount of yield claimed.
     */
    event Claimed(address indexed account, address indexed recipient, uint256 yield);

    /**
     * @notice Emitted when earning is enabled for the entire wrapper.
     * @param  index The index at the moment earning is enabled.
     */
    event EarningEnabled(uint128 index);

    /**
     * @notice Emitted when earning is disabled for the entire wrapper.
     * @param  index The index at the moment earning is disabled.
     */
    event EarningDisabled(uint128 index);

    /**
     * @notice Emitted when the wrapper's excess M is claimed.
     * @param  excess The amount of excess M claimed.
     */
    event ExcessClaimed(uint256 excess);

    /**
     * @notice Emitted when `account` starts being an wM earner.
     * @param  account The account that started earning.
     */
    event StartedEarning(address indexed account);

    /**
     * @notice Emitted when `account` stops being an wM earner.
     * @param  account The account that stopped earning.
     */
    event StoppedEarning(address indexed account);

    /* ============ Custom Errors ============ */

    /// @notice Emitted when performing an operation that is not allowed when earning is disabled.
    error EarningIsDisabled();

    /// @notice Emitted when performing an operation that is not allowed when earning is enabled.
    error EarningIsEnabled();

    /// @notice Emitted when trying to enable earning after it has been explicitly disabled.
    error EarningCannotBeReenabled();

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

    /// @notice Emitted when the non-governance migrate function is called by a account other than the migration admin.
    error UnauthorizedMigration();

    /// @notice Emitted in constructor if M Token is 0x0.
    error ZeroMToken();

    /// @notice Emitted in constructor if Migration Admin is 0x0.
    error ZeroMigrationAdmin();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Wraps `amount` M from the caller into wM for `recipient`.
     * @param  recipient The account receiving the minted wM.
     * @param  amount    The amount of M deposited and wM minted.
     */
    function wrap(address recipient, uint256 amount) external;

    /**
     * @notice Unwraps `amount` wM from the caller into M for `recipient`.
     * @param  recipient The account receiving the withdrawn M.
     * @param  amount    The amount of wM burned and M withdrawn.
     */
    function unwrap(address recipient, uint256 amount) external;

    /**
     * @notice Claims any claimable yield for `account`.
     * @param  account The account under which yield was generated.
     * @return yield   The amount of yield claimed.
     */
    function claimFor(address account) external returns (uint240 yield);

    /**
     * @notice Claims any excess M of the wrapper.
     * @return excess The amount of excess claimed.
     */
    function claimExcess() external returns (uint240 excess);

    /// @notice Enables earning for the wrapper if allowed by TTG and if it has never been done.
    function enableEarning() external;

    /// @notice Disables earning for the wrapper if disallowed by TTG and if it has never been done.
    function disableEarning() external;

    /**
     * @notice Starts earning for `account` if allowed by TTG.
     * @param  account The account to start earning for.
     */
    function startEarningFor(address account) external;

    /**
     * @notice Stops earning for `account` if disallowed by TTG.
     * @param  account The account to stop earning for.
     */
    function stopEarningFor(address account) external;

    /* ============ Temporary Admin Migration ============ */

    /**
     * @notice Performs an arbitrarily defined migration.
     * @param  migrator The address of a migrator.
     */
    function migrate(address migrator) external;

    /* ============ View/Pure Functions ============ */

    /**
     * @notice Returns the yield accrued for `account`, which is claimable.
     * @param  account The account being queried.
     * @return yield   The amount of yield that is claimable.
     */
    function accruedYieldOf(address account) external view returns (uint240 yield);

    /// @notice The current index of the wrapper's earning mechanism.
    function currentIndex() external view returns (uint128 index);

    /// @notice The current excess M of the wrapper that is not earmarked for account balances or accrued yield.
    function excess() external view returns (uint240 excess);

    /**
     * @notice Returns whether `account` is a wM earner.
     * @param  account   The account being queried.
     * @return isEarning true if the account has started earning.
     */
    function isEarning(address account) external view returns (bool isEarning);

    /// @notice Whether earning is enabled for the entire wrapper.
    function isEarningEnabled() external view returns (bool isEnabled);

    /// @notice Whether earning has been enabled at least once or not.
    function wasEarningEnabled() external view returns (bool wasEnabled);

    /// @notice The account that can bypass TTG and call the `migrate(address migrator)` function.
    function migrationAdmin() external view returns (address migrationAdmin);

    /// @notice The address of the M Token contract.
    function mToken() external view returns (address mToken);

    /// @notice The address of the TTG registrar.
    function registrar() external view returns (address registrar);

    /// @notice The portion of total supply that is not earning yield.
    function totalNonEarningSupply() external view returns (uint240 totalSupply);

    /// @notice The accrued yield of the portion of total supply that is earning yield.
    function totalAccruedYield() external view returns (uint240 yield);

    /// @notice The portion of total supply that is earning yield.
    function totalEarningSupply() external view returns (uint240 totalSupply);

    /// @notice The address of the vault where excess is claimed to.
    function vault() external view returns (address vault);
}
