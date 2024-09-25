// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { ERC20Helper } from "../../../lib/erc20-helper/src/ERC20Helper.sol";

import { IMorphoVaultFactoryLike, IMorphoVaultLike, IWrappedMLike } from "./Dependencies.sol";

import { FundsDistribution } from "./FundsDistribution.sol";

/**
 * @title Morpho Distributor (Single-Cascade, Cumulative Distribution)
 * @dev   A contract for distributing Morpho yield across accounts within vaults.
 * @dev   The distribution cascade is an ERC2222 model relying on tracking per-account "corrections".
 */
contract Distributor is FundsDistribution {
    error InvalidVault();
    error TransferFailed();
    error TransferFromFailed();

    address public immutable wrappedMToken;
    address public immutable morphoBlue;
    address public immutable morphoVaultFactory;

    uint256 internal _lastWrappedMBalance;

    mapping(address vault => mapping(address account => uint256 deposits)) internal _deposits;
    mapping(address account => uint256 claimed) internal _claims;

    constructor(address wrappedMToken_, address morphoBlue_, address morphoVaultFactory_) {
        wrappedMToken = wrappedMToken_;
        morphoBlue = morphoBlue_;
        morphoVaultFactory = morphoVaultFactory_;
    }

    /// @notice Allow `msg.sender` to deposit an amount of Morpho Vault shares to get access to WrappedM yield.
    function deposit(address vault_, uint256 vaultShares_) external {
        _revertIfNotMorphoVault(vault_);

        if (!ERC20Helper.transferFrom(vault_, msg.sender, address(this), vaultShares_)) revert TransferFromFailed();

        _deposits[vault_][msg.sender] += vaultShares_;

        _addShares(_updateLastWrappedMBalance(), msg.sender, vaultShares_);
    }

    /// @notice Allow `msg.sender` to withdraw an amount of Morpho Vault shares to cease access to WrappedM yield.
    function withdraw(address vault_, uint256 vaultShares_) external {
        _revertIfNotMorphoVault(vault_);

        uint256 assets_ = (vaultShares_ * _shares[msg.sender]) / _deposits[vault_][msg.sender];

        _deposits[vault_][msg.sender] -= vaultShares_;

        _removeShares(_updateLastWrappedMBalance(), msg.sender, assets_);

        if (!ERC20Helper.transfer(vault_, msg.sender, vaultShares_)) revert TransferFailed();
    }

    /// @notice Allow anyone to distribute any new WrappedM across all accounts.
    function distribute() public {
        _distribute(_updateLastWrappedMBalance());
    }

    /// @notice Allow `msg.sender` to claim their WrappedM yield for their deposited shares.
    function claim(address recipient_) external returns (uint256 claimed_) {
        distribute();

        IWrappedMLike(wrappedMToken).transfer(recipient_, claimed_ = _updateClaim(msg.sender));

        _lastWrappedMBalance = IWrappedMLike(wrappedMToken).balanceOf(address(this));
    }

    /// @notice Returns the WrappedM yield claimable for an account's deposited shares.
    function getClaimable(address account_) public view returns (uint256 claimable_) {
        // NOTE: Should/could never be negative.
        return _getCumulativeDistribution(account_) - _claims[account_];
    }

    /// @notice Returns an account's deposited shares of a Morpho Vault.
    function getDeposits(address vault_, address account_) external view returns (uint256 shares_) {
        return _deposits[vault_][account_];
    }

    /// @notice Returns an account's shares of distribution.
    function getShares(address account_) external view returns (uint256 shares_) {
        return _shares[account_];
    }

    /// @dev Updates `_lastWrappedMBalance` to current wM balance, returning the increase (which is distributable).
    function _updateLastWrappedMBalance() internal returns (uint256 distributable_) {
        // NOTE: `distributable_` should/could never be negative.
        uint256 wrappedMBalance_ = IWrappedMLike(wrappedMToken).balanceOf(address(this));
        distributable_ = wrappedMBalance_ - _lastWrappedMBalance;
        _lastWrappedMBalance = wrappedMBalance_;
    }

    /// @dev Updates `_claims[account_]`, returning the increase (which is claimable).
    function _updateClaim(address account_) internal returns (uint256 claimable_) {
        _claims[account_] += (claimable_ = getClaimable(account_));
    }

    function _revertIfNotMorphoVault(address vault_) internal view {
        if (!IMorphoVaultFactoryLike(morphoVaultFactory).isMetaMorpho(vault_)) revert InvalidVault();
    }
}
