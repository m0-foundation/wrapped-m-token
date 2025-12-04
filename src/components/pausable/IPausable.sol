// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

/**
 * @title Pausable interface.
 * @dev Imported from https://github.com/m0-foundation/m0-evm-m-extensions/blob/7609e5e9151589e2078d91d0d95e1d0fef4278ce/src/components/pausable/IPausable.sol
 * @author M0 Labs
 */
interface IPausable {
    /* ============ Errors ============ */

    /// @notice Emitted if no pauser is set.
    error ZeroPauser();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Pauses the contract.
     * @dev    Can only be called by an account with the PAUSER_ROLE.
     * @dev    When paused, wrap/unwrap and transfer of tokens should be disabled.
     *         Approval should still be enabled to allow users to change their allowances.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract.
     * @dev    Can only be called by an account with the PAUSER_ROLE.
     */
    function unpause() external;

    /* ============ View/Pure Functions ============ */

    /// @notice The role that can pause/unpause the contract.
    function PAUSER_ROLE() external view returns (bytes32);
}
