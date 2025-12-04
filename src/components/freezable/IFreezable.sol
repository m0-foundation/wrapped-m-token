// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

/**
 * @title Freezable interface.
 * @dev Imported from https://github.com/m0-foundation/m0-evm-m-extensions/blob/7609e5e9151589e2078d91d0d95e1d0fef4278ce/src/components/freezable/IFreezable.sol
 * @author M0 Labs
 */
interface IFreezable {
    /* ============ Events ============ */

    /**
     * @notice Emitted when an account is frozen.
     * @param account The address of the frozen account.
     * @param timestamp The timestamp at which the account was frozen.
     */
    event Frozen(address indexed account, uint256 timestamp);

    /**
     * @notice Emitted when an account is unfrozen.
     * @param account The address of the unfrozen account.
     * @param timestamp The timestamp at which the account was unfrozen.
     */
    event Unfrozen(address indexed account, uint256 timestamp);

    /* ============ Errors ============ */

    /**
     * @notice Emitted when an account is already frozen.
     * @param account The address of the frozen account.
     */
    error AccountFrozen(address account);

    /**
     * @notice Emitted when an account is not frozen.
     * @param account The address of the account that is not frozen.
     */
    error AccountNotFrozen(address account);

    /// @notice Emitted if no freeze manager is set.
    error ZeroFreezeManager();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Freezes an account.
     * @dev MUST only be callable by the FREEZE_MANAGER_ROLE.
     * @param account The address of the account to freeze.
     */
    function freeze(address account) external;

    /**
     * @notice Freezes multiple accounts.
     * @dev MUST only be callable by the FREEZE_MANAGER_ROLE.
     * @param accounts The list of addresses to freeze.
     */
    function freezeAccounts(address[] calldata accounts) external;

    /**
     * @notice Unfreezes an account.
     * @dev MUST only be callable by the FREEZE_MANAGER_ROLE.
     * @param account The address of the account to unfreeze.
     */
    function unfreeze(address account) external;

    /**
     * @notice Unfreezes multiple accounts.
     * @dev MUST only be callable by the FREEZE_MANAGER_ROLE.
     * @param accounts The list of addresses to unfreeze.
     */
    function unfreezeAccounts(address[] calldata accounts) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can manage the freezelist.
    function FREEZE_MANAGER_ROLE() external view returns (bytes32);

    /**
     * @notice Returns whether an account is frozen or not.
     * @param account The address of the account to check.
     * @return True if the account is frozen, false otherwise.
     */
    function isFrozen(address account) external view returns (bool);
}
