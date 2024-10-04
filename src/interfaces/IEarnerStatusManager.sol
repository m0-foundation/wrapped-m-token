// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

/**
 * @title  Earner Status Manager interface for setting and returning earner status for Wrapped M Token accounts.
 * @author M^0 Labs
 */
interface IEarnerStatusManager {
    /* ============ Events ============ */

    /**
     * @notice Emitted when the earner status for `account` is set to `earnerStatus`.
     * @param  admin        The earner status admin performing the call.
     * @param  account      The account under which yield could generate.
     * @param  earnerStatus Whether the account is set an earner.
     */
    event EarnerStatusSet(address indexed admin, address indexed account, bool indexed earnerStatus);

    /* ============ Custom Errors ============ */

    /// @notice Emitted when the lengths of input arrays do not match.
    error ArrayLengthMismatch();

    /// @notice Emitted when caller is not a earner status admin.
    error NotEarnerStatusAdmin();

    /// @notice Emitted when an account (whose earner status is being set) is 0x0.
    error ZeroAccount();

    /// @notice Emitted in constructor if Registrar is 0x0.
    error ZeroRegistrar();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Sets the earner status for `account` to `earnerStatus`.
     * @param  account      The account under which yield could generate.
     * @param  earnerStatus Whether the account is an earner.
     */
    function setEarnerStatus(address account, bool earnerStatus) external;

    /**
     * @notice Sets the earner status for multiple accounts.
     * @param  accounts       The accounts under which yield could generate.
     * @param  earnerStatuses Whether each account is an earner, respectively.
     */
    function setEarnerStatuses(address[] calldata accounts, bool[] calldata earnerStatuses) external;

    /* ============ View/Pure Functions ============ */

    /**
     * @notice Returns the earner status for `account`.
     * @param  account      The account being queried.
     * @return earnerStatus Whether the account is an earner.
     */
    function earnerStatusFor(address account) external view returns (bool earnerStatus);

    /**
     * @notice Returns whether the list of earners can be ignored (thus making all accounts earners).
     * @return isIgnored Whether the list of earners can be ignored.
     */
    function isEarnerListIgnored() external view returns (bool isIgnored);

    /**
     * @notice Returns whether `account` is a Registrar-approved earner.
     * @param  account  The account being queried.
     * @return isInList Whether the account is a Registrar-approved earner.
     */
    function isInEarnerList(address account) external view returns (bool isInList);

    /**
     * @notice Returns whether `account` is a Registrar-approved earner status admin.
     * @param  account The account being queried.
     * @return isAdmin True if the account is a Registrar-approved earner status admin, false otherwise.
     */
    function isEarnerStatusAdmin(address account) external view returns (bool isAdmin);

    /// @notice Returns the address of the Registrar.
    function registrar() external view returns (address);
}
