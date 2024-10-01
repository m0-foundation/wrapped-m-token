// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

/**
 * @title Morpho Distributor (Dual-Cascade, Cumulative Distribution)
 */
interface IDistributor {
    /* ============ Events ============ */

    /// @notice Emitted when yet unaccounted wM is distributed across vaults.
    event Distributed(uint256 amount);

    /// @notice Emitted when a vault's share of total future distributions is set.
    event VaultSharesSet(address indexed vault, uint256 amount);

    /// @notice Emitted when an account deposits vault shares, increasing it's share of a vault's distribution.
    event Deposited(address indexed vault, address indexed account, uint256 shares);

    /// @notice Emitted when an account withdraws vault shares, decreasing it's share of a vault's distribution.
    event Withdrawn(address indexed vault, address indexed account, uint256 shares);

    /* ============ Custom Errors ============ */

    /// @notice Error emitted when a Morpho vault is detected to not have been deployed by the Morpho Vault Factory.
    error InvalidVault();

    /// @notice Error emitted when transfer of vault shares to an account has failed.
    error TransferFailed();

    /// @notice Error emitted when transfer of vault shares from an account has failed.
    error TransferFromFailed();

    /* ============ Interactive Functions ============ */

    /// @notice Allow `msg.sender` to deposit an amount of Morpho Vault shares to get access to WrappedM yield.
    function deposit(address vault, uint256 amount) external;

    /// @notice Allow `msg.sender` to withdraw an amount of Morpho Vault shares to cease access to WrappedM yield.
    function withdraw(address vault, uint256 amount) external;

    /// @notice Allow anyone to distribute a vaults distributable WrappedM across all accounts.
    function distribute(address vault) external;

    /// @notice Allow `msg.sender` to claim their WrappedM yield for their deposited shares of a Morpho Vault.
    function claim(address vault, address recipient) external returns (uint256 claimed);

    /* ============ View/Pure Functions ============ */

    /// @notice Returns the address of the WrappedM token contract.
    function wrappedMToken() external view returns (address wrappedMToken);

    /// @notice Returns the address of the Morpho Blue contract.
    function morphoBlue() external view returns (address morphoBlue);

    /// @notice Returns the address of the Morpho Vault Factory contract.
    function morphoVaultFactory() external view returns (address morphoVaultFactory);

    /// @notice Returns the WrappedM yield claimable for an account's deposited shares of a Morpho Vault.
    function getClaimable(address vault, address account) external view returns (uint256 claimable);

    /// @notice Returns an account's shares of distribution of a vault's distribution.
    function getShares(address vault, address account) external view returns (uint256 shares);

    /// @notice Returns a vault's shares of distribution.
    function getShares(address vault) external view returns (uint256 shares);

    /// @notice Returns the total shares of all participating accounts of a vault.
    function getTotalShares(address vault) external view returns (uint256 totalShares);

    /// @notice Returns the total shares of all vaults.
    function getTotalShares() external view returns (uint256 totalShares);
}
