// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { ERC20Helper } from "../../../lib/erc20-helper/src/ERC20Helper.sol";

import {
    Id as MarketId,
    IMorphoBlueLIke,
    IMorphoVaultFactoryLike,
    IMorphoVaultLike,
    IWrappedMLike
} from "./Dependencies.sol";

import { IDistributor } from "./interfaces/IDistributor.sol";

import { AccountFundsDistribution } from "./AccountFundsDistribution.sol";
import { VaultFundsDistribution } from "./VaultFundsDistribution.sol";

// TODO: Permit-based deposit.

/**
 * @title Morpho Distributor (Dual-Cascade, Cumulative Distribution)
 * @dev   A contract for distributing Morpho yield across accounts within vaults.
 * @dev   Each distribution cascade is an ERC2222 model relying on tracking per-account "corrections".
 */
contract Distributor is IDistributor, AccountFundsDistribution, VaultFundsDistribution {
    /* ============ Variables ============ */

    uint256 internal constant _MORPHO_POSITION_SLOT = 2;
    uint256 internal constant _MORPHO_MARKET_SLOT = 3;

    /// @inheritdoc IDistributor
    address public immutable wrappedMToken;

    /// @inheritdoc IDistributor
    address public immutable morphoBlue;

    /// @inheritdoc IDistributor
    address public immutable morphoVaultFactory;

    uint256 internal _lastWrappedMBalance;

    mapping(address vault => uint256 lastCumulativeDistribution) internal _lastCumulativeDistributions;
    mapping(address vault => mapping(address account => uint256 claimed)) internal _claims;

    /* ============ Constructor ============ */

    constructor(address wrappedMToken_, address morphoBlue_, address morphoVaultFactory_) {
        wrappedMToken = wrappedMToken_;
        morphoBlue = morphoBlue_;
        morphoVaultFactory = morphoVaultFactory_;
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IDistributor
    function deposit(address vault_, uint256 amount_) external {
        if (!IMorphoVaultFactoryLike(morphoVaultFactory).isMetaMorpho(vault_)) revert InvalidVault();

        emit Deposited(vault_, msg.sender, amount_);

        if (!ERC20Helper.transferFrom(vault_, msg.sender, address(this), amount_)) revert TransferFromFailed();

        _updateShares(vault_, AccountFundsDistribution._getTotalShares(vault_) + amount_);

        // Distribute vault's unaccounted WrappedM across accounts, then add shares for the account within the vault.
        AccountFundsDistribution._addShares(vault_, _updateLastCumulativeDistribution(vault_), msg.sender, amount_);
    }

    /// @inheritdoc IDistributor
    function withdraw(address vault_, uint256 amount_) external {
        emit Withdrawn(vault_, msg.sender, amount_);

        _updateShares(vault_, AccountFundsDistribution._getTotalShares(vault_) - amount_);

        // Distribute vault's unaccounted WrappedM across accounts, then remove shares for the account within the vault.
        AccountFundsDistribution._removeShares(vault_, _updateLastCumulativeDistribution(vault_), msg.sender, amount_);

        if (!ERC20Helper.transfer(vault_, msg.sender, amount_)) revert TransferFailed();
    }

    /// @inheritdoc IDistributor
    function distribute(address vault_) public {
        _updateShares(vault_, AccountFundsDistribution._getTotalShares(vault_));
        AccountFundsDistribution._distribute(vault_, _updateLastCumulativeDistribution(vault_));
    }

    /// @inheritdoc IDistributor
    function claim(address vault_, address recipient_) external returns (uint256 claimed_) {
        distribute(vault_);

        // NOTE: Do not need to check result of transfer as the behavior of WrappedM is known to revert on failure.
        IWrappedMLike(wrappedMToken).transfer(recipient_, claimed_ = _updateClaim(vault_, msg.sender));

        _lastWrappedMBalance = IWrappedMLike(wrappedMToken).balanceOf(address(this));
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IDistributor
    function getClaimable(address vault_, address account_) public view returns (uint256 claimable_) {
        // NOTE: Should/could never be negative.
        return AccountFundsDistribution._getCumulativeDistribution(vault_, account_) - _claims[vault_][account_];
    }

    /// @inheritdoc IDistributor
    function getShares(address vault_, address account_) external view returns (uint256 shares_) {
        return AccountFundsDistribution._getShares(vault_, account_);
    }

    /// @inheritdoc IDistributor
    function getShares(address vault_) external view returns (uint256 shares_) {
        return VaultFundsDistribution._getShares(vault_);
    }

    /// @inheritdoc IDistributor
    function getTotalShares(address vault_) external view returns (uint256 totalShares_) {
        return AccountFundsDistribution._getTotalShares(vault_);
    }

    /// @inheritdoc IDistributor
    function getTotalShares() external view returns (uint256 totalShares_) {
        return VaultFundsDistribution._getTotalShares();
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @notice Updates the shares of a vault, first distribute any new WrappedM across all vaults.
     * @param  vault_ The address of the vault to update the shares of.
     */
    function _updateShares(address vault_, uint256 totalVaultDeposits_) internal {
        uint256 distributable_ = _updateLastWrappedMBalance();
        uint256 vaultAssets_ = _convertToAssets(vault_, totalVaultDeposits_);

        emit Distributed(distributable_);
        emit VaultSharesSet(vault_, vaultAssets_);

        VaultFundsDistribution._setShares(distributable_, vault_, vaultAssets_);
    }

    /// @dev Updates `_lastWrappedMBalance` to current wM balance, returning the increase (which is distributable).
    function _updateLastWrappedMBalance() internal returns (uint256 distributable_) {
        // NOTE: `distributable_` should/could never be negative.
        uint256 wrappedMBalance_ = IWrappedMLike(wrappedMToken).balanceOf(address(this));
        distributable_ = wrappedMBalance_ - _lastWrappedMBalance;
        _lastWrappedMBalance = wrappedMBalance_;
    }

    /// @dev Updates `_lastCumulativeDistributions[vault_]`, returning the increase (which is distributable).
    function _updateLastCumulativeDistribution(address vault_) internal returns (uint256 distributable_) {
        // NOTE: `distributable_` should/could never be negative.
        uint256 cumulativeDistribution_ = VaultFundsDistribution._getCumulativeDistribution(vault_);
        distributable_ = cumulativeDistribution_ - _lastCumulativeDistributions[vault_];
        _lastCumulativeDistributions[vault_] = cumulativeDistribution_;
    }

    /// @dev Updates `_claims[vault_][account_]`, returning the increase (which is claimable).
    function _updateClaim(address vault_, address account_) internal returns (uint256 claimable_) {
        _claims[vault_][account_] += (claimable_ = getClaimable(vault_, account_));
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev Returns the asset value of an amount of shares of `vault_`.
    function _convertToAssets(address vault_, uint256 shares_) internal view returns (uint256 assets_) {
        return (shares_ * _getVaultTotalAssets(vault_)) / IMorphoVaultLike(vault_).totalSupply();
    }

    /// @dev Returns the wM assets `vault_` has as outstanding liquidity in a lending markets.
    function _getVaultAssetsInMarket(address vault_, MarketId id_) internal view returns (uint256) {
        // Fetch exact storage slots from MorphoBlue rather than making 2 calls to read a lot more unnecessary slots.
        // 4 variables are needed, spread across 3 storage slots:
        //   - 3 variables in the Market struct, located in the mapping at storage slot 3.
        //     - See https://github.com/morpho-org/morpho-blue/blob/v1.0.0/src/Morpho.sol#L60
        //     - See https://github.com/morpho-org/morpho-blue/blob/v1.0.0/src/interfaces/IMorpho.sol#L27-L29
        //     - `totalSupplyAssets` in the top half of the 0-offset slot of the Market struct.
        //     - `totalSupplyShares` in the bottom half of the 0-offset slot of the Market struct.
        //     - `totalBorrowAssets` in the top half of the 1-offset slot of the Market struct.
        //   - 1 variable in the Position struct, located in the mapping at storage slot 2.
        //     - See https://github.com/morpho-org/morpho-blue/blob/v1.0.0/src/Morpho.sol#L58
        //     - https://github.com/morpho-org/morpho-blue/blob/v1.0.0/src/interfaces/IMorpho.sol#L17
        //     - `supplyShares` in the 0-offset slot of the Position struct.
        bytes32[] memory slots_ = new bytes32[](3);
        slots_[1] = bytes32(uint256(slots_[0] = keccak256(abi.encode(id_, _MORPHO_MARKET_SLOT))) + 1);
        slots_[2] = keccak256(abi.encode(vault_, keccak256(abi.encode(id_, _MORPHO_POSITION_SLOT))));

        // NOTE: Reuse `slots_` to save gas, instead of creating new location in memory.
        slots_ = IMorphoBlueLIke(morphoBlue).extSloads(slots_);

        // `totalSupplyAssets` is right shifted by 128 bits and cast to uint128 to get the top half of the slot.
        // `totalBorrowAssets` is right shifted by 128 bits and cast to uint128 to get the top half of the slot.
        // `liquidity_` is how much of the supplied assets are sitting in the market, not having yet been borrowed.
        uint128 totalSupplyAssets = uint128(uint256(slots_[0] >> 128));
        uint128 totalBorrowAssets = uint128(uint256(slots_[1] >> 128));
        uint128 liquidity_ = totalSupplyAssets - totalBorrowAssets;

        if (liquidity_ == 0) return 0;

        // `totalSupplyShares` is cast to uint128 to get the bottom half of the slot.
        // `supplyShares` is the amount of shares the vault has in the market.
        uint128 totalSupplyShares = uint128(uint256(slots_[0]));
        uint256 supplyShares = uint256(slots_[2]);

        // Compute the portion of `totalSupplyShares` that the vault's `supplyShares` represent.
        return (liquidity_ * supplyShares) / totalSupplyShares;
    }

    /// @dev Returns all the wM assets `vault_` has as outstanding liquidity in all lending markets.
    function _getVaultTotalAssets(address vault_) internal view returns (uint256 assets_) {
        uint256 marketCount_ = IMorphoVaultLike(vault_).withdrawQueueLength();

        for (uint256 i_; i_ < marketCount_; ++i_) {
            assets_ += _getVaultAssetsInMarket(vault_, IMorphoVaultLike(vault_).withdrawQueue(i_));
        }
    }
}
