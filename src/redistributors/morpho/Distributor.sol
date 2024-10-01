// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { ERC20Helper } from "../../../lib/erc20-helper/src/ERC20Helper.sol";

import { IMorphoVaultFactoryLike, IMorphoVaultLike, IWrappedMLike } from "./Dependencies.sol";

import { AccountFundsDistribution } from "./AccountFundsDistribution.sol";
import { VaultFundsDistribution } from "./VaultFundsDistribution.sol";

/**
 * @title Morpho Distributor (Dual-Cascade, Cumulative Distribution)
 * @dev   A contract for distributing Morpho yield across accounts within vaults.
 * @dev   Each distribution cascade is an ERC2222 model relying on tracking per-account "corrections".
 */
contract Distributor is AccountFundsDistribution, VaultFundsDistribution {
    error InvalidVault();
    error TransferFailed();
    error TransferFromFailed();

    address public immutable wrappedMToken;
    address public immutable morphoBlue;
    address public immutable morphoVaultFactory;

    uint256 internal _lastWrappedMBalance;

    mapping(address vault => uint256 lastCumulativeDistribution) internal _lastCumulativeDistributions;
    mapping(address vault => mapping(address account => uint256 claimed)) internal _claims;

    constructor(address wrappedMToken_, address morphoBlue_, address morphoVaultFactory_) {
        wrappedMToken = wrappedMToken_;
        morphoBlue = morphoBlue_;
        morphoVaultFactory = morphoVaultFactory_;
    }

    /// @notice Allow `msg.sender` to deposit an amount of Morpho Vault shares to get access to WrappedM yield.
    function deposit(address vault_, uint256 vaultShares_) external {
        if (!IMorphoVaultFactoryLike(morphoVaultFactory).isMetaMorpho(vault_)) revert InvalidVault();

        if (IMorphoVaultLike(vault_).asset() != wrappedMToken) revert InvalidVault();

        if (!ERC20Helper.transferFrom(vault_, msg.sender, address(this), vaultShares_)) revert TransferFromFailed();

        // Distribute contract's unaccounted WrappedM across vaults, then add shares for the vault.
        VaultFundsDistribution._addShares(_updateLastWrappedMBalance(), vault_, vaultShares_);

        // Distribute vault's unaccounted WrappedM across accounts, then add shares for the account within the vault.
        AccountFundsDistribution._addShares(
            vault_,
            _updateLastCumulativeDistribution(vault_),
            msg.sender,
            vaultShares_
        );
    }

    /// @notice Allow `msg.sender` to withdraw an amount of Morpho Vault shares to cease access to WrappedM yield.
    function withdraw(address vault_, uint256 vaultShares_) external {
        // Distribute contract's unaccounted WrappedM across vaults, then remove shares for the vault.
        VaultFundsDistribution._removeShares(_updateLastWrappedMBalance(), vault_, vaultShares_);

        // Distribute vault's unaccounted WrappedM across accounts, then remove shares for the account within the vault.
        AccountFundsDistribution._removeShares(
            vault_,
            _updateLastCumulativeDistribution(vault_),
            msg.sender,
            vaultShares_
        );

        if (!ERC20Helper.transfer(vault_, msg.sender, vaultShares_)) revert TransferFailed();
    }

    /// @notice Allow anyone to distribute a vaults distributable WrappedM across all accounts.
    function distribute(address vault_) public {
        VaultFundsDistribution._distribute(_updateLastWrappedMBalance());
        AccountFundsDistribution._distribute(vault_, _updateLastCumulativeDistribution(vault_));
    }

    /// @notice Allow `msg.sender` to claim their WrappedM yield for their deposited shares of a Morpho Vault.
    function claim(address vault_, address recipient_) external returns (uint256 claimed_) {
        distribute(vault_);

        IWrappedMLike(wrappedMToken).transfer(recipient_, claimed_ = _updateClaim(vault_, msg.sender));

        _lastWrappedMBalance = IWrappedMLike(wrappedMToken).balanceOf(address(this));
    }

    /// @notice Returns the WrappedM yield claimable for an account's deposited shares of a Morpho Vault.
    function getClaimable(address vault_, address account_) public view returns (uint256 claimable_) {
        // NOTE: Should/can never be negative.
        return AccountFundsDistribution._getCumulativeDistribution(vault_, account_) - _claims[vault_][account_];
    }

    /// @notice Returns an account's deposited shares of a Morpho Vault.
    function getDeposits(address vault_, address account_) external view returns (uint256 shares_) {
        return AccountFundsDistribution._getShares(vault_, account_);
    }

    /// @notice Returns an account's shares of distribution of a vault's distribution.
    function getShares(address vault_, address account_) external view returns (uint256 shares_) {
        return AccountFundsDistribution._getShares(vault_, account_);
    }

    /// @dev Updates `_lastWrappedMBalance` to current wM balance, returning the increase (which is distributable).
    function _updateLastWrappedMBalance() internal returns (uint256 distributable_) {
        // NOTE: `distributable_` should/can never be negative.
        uint256 wrappedMBalance_ = IWrappedMLike(wrappedMToken).balanceOf(address(this));
        distributable_ = wrappedMBalance_ - _lastWrappedMBalance;
        _lastWrappedMBalance = wrappedMBalance_;
    }

    /// @dev Updates `_lastCumulativeDistributions[vault_]`, returning the increase (which is distributable).
    function _updateLastCumulativeDistribution(address vault_) internal returns (uint256 distributable_) {
        // NOTE: `distributable_` should/can never be negative.
        uint256 cumulativeDistribution_ = VaultFundsDistribution._getCumulativeDistribution(vault_);
        distributable_ = cumulativeDistribution_ - _lastCumulativeDistributions[vault_];
        _lastCumulativeDistributions[vault_] = cumulativeDistribution_;
    }

    /// @dev Updates `_claims[vault_][account_]`, returning the increase (which is claimable).
    function _updateClaim(address vault_, address account_) internal returns (uint256 claimable_) {
        _claims[vault_][account_] += (claimable_ = getClaimable(vault_, account_));
    }
}
