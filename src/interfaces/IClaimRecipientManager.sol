// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

/**
 * @title  Claim Recipient Manager interface for setting an returning claim recipients for Wrapped M Token yield.
 * @author M^0 Labs
 */
interface IClaimRecipientManager {
    /* ============ Events ============ */

    /**
     * @notice Emitted when the claim recipient for `account` is set to `recipient`.
     * @param  admin     The claim recipient admin performing the call.
     * @param  account   The account under which yield will generate.
     * @param  recipient The account that will receive the yield when claims are performed.
     */
    event ClaimRecipientSet(address indexed admin, address indexed account, address indexed recipient);

    /* ============ Custom Errors ============ */

    /// @notice Emitted when the lengths of input arrays do not match.
    error ArrayLengthMismatch();

    /// @notice Emitted when caller is not a claim recipient admin.
    error NotClaimRecipientAdmin();

    /// @notice Emitted in constructor if Registrar is 0x0.
    error ZeroRegistrar();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Sets the claim recipient for `account` to `recipient`.
     * @param  account   The account under which yield will generate.
     * @param  recipient The account that should receive the yield when claims are performed.
     */
    function setClaimRecipient(address account, address recipient) external;

    /**
     * @notice Sets the claim recipient for multiple accounts.
     * @param  accounts    The accounts under which yield will generate.
     * @param  recipients  The accounts that should receive the yield when claims are performed ro each account.
     */
    function setClaimRecipients(address[] calldata accounts, address[] calldata recipients) external;

    /* ============ View/Pure Functions ============ */

    /**
     * @notice Returns the claim recipient for `account`.
     * @param  account   The account being queried.
     * @return recipient The account that should receive the yield when claims are performed.
     */
    function claimRecipientFor(address account) external view returns (address recipient);

    /**
     * @notice Returns the claim recipient override for `account`. Overrides `claimRecipientFor`.
     * @param  account   The account being queried.
     * @return recipient The account that should receive the yield when claims are performed.
     */
    function claimRecipientOverrideFor(address account) external view returns (address recipient);

    /**
     * @notice Returns whether `account` is a Registrar-approved earner.
     * @param  account The account being queried.
     * @return isAdmin True if the account is a Registrar-approved claim recipient admin, false otherwise.
     */
    function isClaimRecipientAdmin(address account) external view returns (bool isAdmin);

    /// @notice Returns the address of the Registrar.
    function registrar() external view returns (address);
}
