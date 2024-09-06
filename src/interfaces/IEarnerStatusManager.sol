// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

/**
 * @title  Earner Status Manager interface for setting and returning earner status for Wrapped M Token accounts.
 * @author M^0 Labs
 */
interface IEarnerStatusManager {
    /* ============ Events ============ */

    /**
     * @notice Emitted when the admin index is updated.
     * @param  adminIndex The index of the admin.
     * @param  enabled    Whether the admin is enabled.
     */
    event AdminIndexUpdated(uint256 indexed adminIndex, bool indexed enabled);

    /**
     * @notice Emitted when the status for `account` is set to `status`.
     * @param  adminIndex The admin index the status is set by.
     * @param  account    The account under which yield could generate.
     * @param  status     Whether the account is set an earner according to the admin.
     */
    event StatusSet(uint256 indexed adminIndex, address indexed account, bool indexed status);

    /* ============ Custom Errors ============ */

    /// @notice Emitted when the admin index is already set according to the Registrar.
    error AdminIndexAlreadySet();

    /// @notice Emitted when the lengths of input arrays do not match.
    error ArrayLengthMismatch();

    /// @notice Emitted when caller is not an admin.
    error NotAdmin();

    /// @notice Emitted when an account (whose status is being set) is 0x0.
    error ZeroAccount();

    /// @notice Emitted in constructor if Registrar is 0x0.
    error ZeroRegistrar();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Updates the admin status at an index, according to the Registrar.
     * @param  adminIndex The admin index to update.
     */
    function updateAdminIndex(uint256 adminIndex) external;

    /**
     * @notice Sets the status for `account` to `status`.
     * @param  adminIndex The index of the admin setting the status.
     * @param  account    The account under which yield could generate.
     * @param  status     Whether the account is an earner, according to the admin.
     */
    function setStatus(uint256 adminIndex, address account, bool status) external;

    /**
     * @notice Sets the status for multiple accounts.
     * @param  adminIndex The index of the admin setting the status.
     * @param  accounts   The accounts under which yield could generate.
     * @param  statuses   Whether each account is an earner, respectively, according to the admin.
     */
    function setStatuses(uint256 adminIndex, address[] calldata accounts, bool[] calldata statuses) external;

    /* ============ View/Pure Functions ============ */

    /**
     * @notice Returns the status for `account`.
     * @param  account The account being queried.
     * @return status  Whether the account is an earner.
     */
    function statusFor(address account) external view returns (bool status);

    /**
     * @notice Returns the statuses for multiple accounts.
     * @param  accounts The accounts being queried.
     * @return statuses Whether each account is an earner, respectively.
     */
    function statusesFor(address[] calldata accounts) external view returns (bool[] memory statuses);

    /**
     * @notice Returns whether the list of earners can be ignored (thus making all accounts earners).
     * @return isIgnored Whether the list of earners can be ignored.
     */
    function isListIgnored() external view returns (bool isIgnored);

    /**
     * @notice Returns whether `account` is a Registrar-approved earner.
     * @param  account  The account being queried.
     * @return isInList Whether the account is a Registrar-approved earner.
     */
    function isInList(address account) external view returns (bool isInList);

    /**
     * @notice Returns whether `account` is an earner, according to the admins.
     * @param  account The account being queried.
     * @return status  Whether the account is an earner, according to the admins.
     */
    function getStatusByAdmins(address account) external view returns (bool status);

    /**
     * @notice Returns whether `account` is an earner according to the admin at a given admin index.
     * @param  adminIndex The index of the admin.
     * @param  account    The account being queried.
     * @return status     Whether the account is an earner, according to the admin.
     */
    function getStatusByAdmin(uint256 adminIndex, address account) external view returns (bool status);

    /**
     * @notice Returns the statuses for multiple accounts according to the admin at a given admin index.
     * @param  adminIndex The index of the admin.
     * @param  accounts   The accounts being queried.
     * @return statuses   Whether each account is an earner, according to the admin.
     */
    function getStatusesByAdmin(
        uint256 adminIndex,
        address[] calldata accounts
    ) external view returns (bool[] memory statuses);

    /**
     * @notice Returns the address of the admin at a given admin index.
     * @param  adminIndex The index of the admin.
     * @return admin      The address of the admin.
     */
    function getAdmin(uint256 adminIndex) external view returns (address admin);

    /**
     * @notice Returns whether the admin at a given admin index is enabled.
     * @param  adminIndex The index of the admin.
     * @return enabled    Whether the admin is enabled.
     */
    function isAdminIndexEnabled(uint256 adminIndex) external view returns (bool enabled);

    /// @notice Returns the address of the Registrar.
    function registrar() external view returns (address);
}
