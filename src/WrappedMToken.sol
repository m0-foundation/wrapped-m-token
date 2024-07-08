// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";
import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IndexingMath } from "./libs/IndexingMath.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";
import { IWrappedMToken } from "./interfaces/IWrappedMToken.sol";

import { Migratable } from "./Migratable.sol";

/**
 * @title  ERC20 Token contract for wrapping M into a non-rebasing token with claimable yields.
 * @author M^0 Labs
 */
contract WrappedMToken is IWrappedMToken, Migratable, ERC20Extended {
    type BalanceInfo is uint256;

    /* ============ Variables ============ */

    /// @dev Registrar key holding value of whether the earners list can be ignored or not.
    bytes32 internal constant _EARNERS_LIST_IGNORED = "earners_list_ignored";

    /// @dev Registrar key of earners list.
    bytes32 internal constant _EARNERS_LIST = "earners";

    /// @dev Registrar key prefix to determine the override recipient of an account's accrued yield.
    bytes32 internal constant _CLAIM_OVERRIDE_RECIPIENT_PREFIX = "wm_claim_override_recipient";

    /// @dev Registrar key prefix to determine the migrator contract.
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "wm_migrator_v1";

    /// @inheritdoc IWrappedMToken
    address public immutable migrationAdmin;

    /// @inheritdoc IWrappedMToken
    address public immutable mToken;

    /// @inheritdoc IWrappedMToken
    address public immutable registrar;

    /// @inheritdoc IWrappedMToken
    address public immutable vault;

    /// @dev The principal and index that make up the non-rebasing totalEarningSupply().
    uint112 internal _principalOfTotalEarningSupply;
    uint128 internal _indexOfTotalEarningSupply;

    /// @inheritdoc IWrappedMToken
    uint240 public totalNonEarningSupply;

    /// @dev Mapping of accounts to their respective `BalanceInfo` custom types.
    mapping(address account => BalanceInfo balance) internal _balances;

    /// @dev Array of indices at which earning was enabled or disabled.
    uint128[] internal _enableDisableEarningIndices;

    /* ============ Constructor ============ */

    /**
     * @dev   Constructs the contract given an M Token address and migration admin.
     *        Note that a proxy will not need to initialize since there are no mutable storage values affected.
     * @param mToken_         The address of an M Token.
     * @param migrationAdmin_ The address of a migration admin.
     */
    constructor(address mToken_, address migrationAdmin_) ERC20Extended("WrappedM by M^0", "wM", 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((migrationAdmin = migrationAdmin_) == address(0)) revert ZeroMigrationAdmin();

        registrar = IMTokenLike(mToken_).ttgRegistrar();
        vault = IRegistrarLike(registrar).vault();
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IWrappedMToken
    function wrap(address recipient_, uint256 amount_) external {
        _wrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function wrap(address recipient_) external {
        _wrap(msg.sender, recipient_, UIntMath.safe240(IMTokenLike(mToken).balanceOf(msg.sender)));
    }

    /// @inheritdoc IWrappedMToken
    function unwrap(address recipient_, uint256 amount_) external {
        _unwrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function unwrap(address recipient_) external {
        _unwrap(msg.sender, recipient_, uint240(balanceWithYieldOf(msg.sender)));
    }

    /// @inheritdoc IWrappedMToken
    function claimFor(address account_) external returns (uint240 yield_) {
        return _claim(account_, currentIndex());
    }

    /// @inheritdoc IWrappedMToken
    function claimExcess() external returns (uint240 excess_) {
        emit ExcessClaimed(excess_ = excess());

        IMTokenLike(mToken).transfer(vault, excess_);
    }

    /// @inheritdoc IWrappedMToken
    function enableEarning() external {
        _revertIfNotApprovedEarner(address(this));

        if (isEarningEnabled()) revert EarningIsEnabled();

        // NOTE: This is a temporary measure to prevent re-enabling earning after it has been disabled.
        //       This line will be removed in the future.
        if (wasEarningEnabled()) revert EarningCannotBeReenabled();

        uint128 currentMIndex_ = _currentMIndex();

        _enableDisableEarningIndices.push(currentMIndex_);

        IMTokenLike(mToken).startEarning();

        emit EarningEnabled(currentMIndex_);
    }

    /// @inheritdoc IWrappedMToken
    function disableEarning() external {
        _revertIfApprovedEarner(address(this));

        if (!isEarningEnabled()) revert EarningIsDisabled();

        uint128 currentMIndex_ = _currentMIndex();

        _enableDisableEarningIndices.push(currentMIndex_);

        IMTokenLike(mToken).stopEarning();

        emit EarningDisabled(currentMIndex_);
    }

    /// @inheritdoc IWrappedMToken
    function startEarningFor(address account_) external {
        _revertIfNotApprovedEarner(account_);

        if (!isEarningEnabled()) revert EarningIsDisabled();

        (bool isEarning_, , , uint240 balance_) = _getBalanceInfo(account_);

        if (isEarning_) return;

        // NOTE: Use `currentIndex()` if/when upgrading to support `startEarningFor` while earning is disabled.
        uint128 currentIndex_ = _currentMIndex();

        _setBalanceInfo(account_, true, currentIndex_, balance_);
        _addTotalEarningSupply(balance_, currentIndex_);

        unchecked {
            totalNonEarningSupply -= balance_;
        }

        emit StartedEarning(account_);
    }

    /// @inheritdoc IWrappedMToken
    function stopEarningFor(address account_) external {
        _revertIfApprovedEarner(account_);

        uint128 currentIndex_ = currentIndex();

        _claim(account_, currentIndex_);

        (bool isEarning_, , , uint240 balance_) = _getBalanceInfo(account_);

        if (!isEarning_) return;

        _setBalanceInfo(account_, false, 0, balance_);
        _subtractTotalEarningSupply(balance_, currentIndex_);

        unchecked {
            totalNonEarningSupply += balance_;
        }

        emit StoppedEarning(account_);
    }

    /* ============ Temporary Admin Migration ============ */

    /**
     * @notice Performs an arbitrary migration by delegate-calling `migrator_`.
     * @param  migrator_ The address of a migrator contract.
     */
    function migrate(address migrator_) external {
        if (msg.sender != migrationAdmin) revert UnauthorizedMigration();

        _migrate(migrator_);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IWrappedMToken
    function accruedYieldOf(address account_) public view returns (uint240 yield_) {
        (bool isEarning_, , uint112 principal_, uint240 balance_) = _getBalanceInfo(account_);

        return isEarning_ ? IndexingMath.getPresentAmountRoundedDown(principal_, currentIndex()) - balance_ : 0;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account_) public view returns (uint256 balance_) {
        (, , , balance_) = _getBalanceInfo(account_);
    }

    /// @inheritdoc IWrappedMToken
    function balanceWithYieldOf(address account_) public view returns (uint256 balance_) {
        return balanceOf(account_) + accruedYieldOf(account_);
    }

    /// @inheritdoc IWrappedMToken
    function claimOverrideRecipientFor(address account_) public view returns (address recipient_) {
        return
            address(
                uint160(
                    uint256(
                        IRegistrarLike(registrar).get(keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_PREFIX, account_)))
                    )
                )
            );
    }

    /// @inheritdoc IWrappedMToken
    function currentIndex() public view returns (uint128 index_) {
        return isEarningEnabled() ? _currentMIndex() : _lastDisableEarningIndex();
    }

    /// @inheritdoc IWrappedMToken
    function isEarning(address account_) external view returns (bool isEarning_) {
        (isEarning_, , , ) = _getBalanceInfo(account_);
    }

    /// @inheritdoc IWrappedMToken
    function isEarningEnabled() public view returns (bool isEnabled_) {
        return _enableDisableEarningIndices.length % 2 == 1;
    }

    /// @inheritdoc IWrappedMToken
    function wasEarningEnabled() public view returns (bool wasEarning_) {
        return _enableDisableEarningIndices.length != 0;
    }

    /// @inheritdoc IWrappedMToken
    function excess() public view returns (uint240 excess_) {
        unchecked {
            uint240 balance_ = uint240(IMTokenLike(mToken).balanceOf(address(this)));
            uint240 earmarked_ = totalNonEarningSupply + _projectedEarningSupply(currentIndex());

            return balance_ > earmarked_ ? balance_ - earmarked_ : 0;
        }
    }

    /// @inheritdoc IWrappedMToken
    function totalAccruedYield() public view returns (uint240 yield_) {
        uint240 projectedEarningSupply_ = _projectedEarningSupply(currentIndex());
        uint240 earningSupply_ = totalEarningSupply();

        unchecked {
            return projectedEarningSupply_ <= earningSupply_ ? 0 : projectedEarningSupply_ - earningSupply_;
        }
    }

    /// @inheritdoc IWrappedMToken
    function totalEarningSupply() public view returns (uint240 totalSupply_) {
        return IndexingMath.getPresentAmountRoundedUp(_principalOfTotalEarningSupply, _indexOfTotalEarningSupply);
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint256 totalSupply_) {
        return totalEarningSupply() + totalNonEarningSupply;
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Mints `amount_` tokens to `recipient_`.
     * @param recipient_ The address whose account balance will be incremented.
     * @param amount_    The present amount of tokens to mint.
     */
    function _mint(address recipient_, uint240 amount_) internal {
        _revertIfInsufficientAmount(amount_);
        _revertIfInvalidRecipient(recipient_);

        (bool isEarning_, , , ) = _getBalanceInfo(recipient_);

        if (isEarning_) {
            uint128 currentIndex_ = currentIndex();

            _claim(recipient_, currentIndex_);

            // NOTE: Additional principal may end up being rounded to 0 and this will not `_revertIfInsufficientAmount`.
            _addEarningAmount(recipient_, amount_, currentIndex_);
        } else {
            _addNonEarningAmount(recipient_, amount_);
        }

        emit Transfer(address(0), recipient_, amount_);
    }

    /**
     * @dev   Burns `amount_` tokens from `account_`.
     * @param account_ The address whose account balance will be decremented.
     * @param amount_  The present amount of tokens to burn.
     */
    function _burn(address account_, uint240 amount_) internal {
        _revertIfInsufficientAmount(amount_);

        (bool isEarning_, , , ) = _getBalanceInfo(account_);

        if (isEarning_) {
            uint128 currentIndex_ = currentIndex();

            _claim(account_, currentIndex_);

            // NOTE: Subtracted principal may end up being rounded to 0 and this will not `_revertIfInsufficientAmount`.
            _subtractEarningAmount(account_, amount_, currentIndex_);
        } else {
            _subtractNonEarningAmount(account_, amount_);
        }

        emit Transfer(account_, address(0), amount_);
    }

    /**
     * @dev   Increments the token balance of `account_` by `amount_`, assuming non-earning status.
     * @param account_ The address whose account balance will be incremented.
     * @param amount_  The present amount of tokens to increment by.
     */
    function _addNonEarningAmount(address account_, uint240 amount_) internal {
        // NOTE: Can be `unchecked` because the max amount of wrappable M is never greater than `type(uint240).max`.
        unchecked {
            (, , , uint240 balance_) = _getBalanceInfo(account_);
            _setBalanceInfo(account_, false, 0, balance_ + amount_);
            totalNonEarningSupply += amount_;
        }
    }

    /**
     * @dev   Decrements the token balance of `account_` by `amount_`, assuming non-earning status.
     * @param account_ The address whose account balance will be decremented.
     * @param amount_  The present amount of tokens to decrement by.
     */
    function _subtractNonEarningAmount(address account_, uint240 amount_) internal {
        unchecked {
            (, , , uint240 balance_) = _getBalanceInfo(account_);

            if (balance_ < amount_) revert InsufficientBalance(account_, balance_, amount_);

            _setBalanceInfo(account_, false, 0, balance_ - amount_);
            totalNonEarningSupply -= amount_;
        }
    }

    /**
     * @dev   Increments the token balance of `account_` by `amount_`, assuming earning status and updated index.
     * @param account_      The address whose account balance will be incremented.
     * @param amount_       The present amount of tokens to increment by.
     * @param currentIndex_ The current index to use to compute the principal amount.
     */
    function _addEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
        // NOTE: Can be `unchecked` because the max amount of wrappable M is never greater than `type(uint240).max`.
        unchecked {
            (, , , uint240 balance_) = _getBalanceInfo(account_);

            _setBalanceInfo(account_, true, currentIndex_, balance_ + amount_);
            _addTotalEarningSupply(amount_, currentIndex_);
        }
    }

    /**
     * @dev   Decrements the token balance of `account_` by `amount_`, assuming earning status and updated index.
     * @param account_      The address whose account balance will be decremented.
     * @param amount_       The present amount of tokens to decrement by.
     * @param currentIndex_ The current index to use to compute the principal amount.
     */
    function _subtractEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
        unchecked {
            (, , , uint240 balance_) = _getBalanceInfo(account_);

            if (balance_ < amount_) revert InsufficientBalance(account_, balance_, amount_);

            _setBalanceInfo(account_, true, currentIndex_, balance_ - amount_);
            _subtractTotalEarningSupply(amount_, currentIndex_);
        }
    }

    /**
     * @dev    Claims accrued yield for `account_` given a `currentIndex_`.
     * @param  account_      The address to claim accrued yield for.
     * @param  currentIndex_ The current index to accrue until.
     * @return yield_        The accrued yield that was claimed.
     */
    function _claim(address account_, uint128 currentIndex_) internal returns (uint240 yield_) {
        (bool isEarner_, uint128 index_, , uint240 startingBalance_) = _getBalanceInfo(account_);

        if (!isEarner_) return 0;

        if (currentIndex_ == index_) return 0;

        _updateIndex(account_, currentIndex_);

        (, , , uint240 endingBalance_) = _getBalanceInfo(account_);

        unchecked {
            if (endingBalance_ <= startingBalance_) return 0;

            yield_ = endingBalance_ - startingBalance_;

            // Update the total earning supply to account for the yield, where the principal has not changed.
            _setTotalEarningSupply(totalEarningSupply() + yield_, _principalOfTotalEarningSupply);
        }

        emit Transfer(address(0), account_, yield_);

        address claimOverrideRecipient_ = claimOverrideRecipientFor(account_);

        // Emit the appropriate `Claimed` and `Transfer` events, depending on the claim override recipient
        if (claimOverrideRecipient_ == address(0)) {
            emit Claimed(account_, account_, yield_);
        } else {
            emit Claimed(account_, claimOverrideRecipient_, yield_);

            // NOTE: Watch out for a long chain of earning claim override recipients.
            _transfer(account_, claimOverrideRecipient_, yield_, currentIndex_);
        }
    }

    /**
     * @dev   Writes the encoded balance information for `account_` in the storage mapping.
     * @param account_   The account whose balance information is being written.
     * @param isEarning_ Whether `account_` is earning or not.
     * @param index_     The index of their last interaction.
     * @param balance_   The present amount of the token balance.
     */
    function _setBalanceInfo(address account_, bool isEarning_, uint128 index_, uint240 balance_) internal {
        // The balance info is encoded as follows:
        //   - The most significant 1 bit is a flag for whether the account is earning or not.
        //   - The next 15 bits are unused/empty.
        //   - If the account is an earner:
        //     - The next 128 bits are the index of the last interaction,
        //     - The next (and least significant) 112 bits are the principal amount.
        //   - If the account is not an earner:
        //     - The 240 least significant bits are simply the present amount.
        _balances[account_] = isEarning_
            ? BalanceInfo.wrap(
                (uint256(1) << 255) |
                    (uint256(index_) << 112) |
                    uint256(IndexingMath.getPrincipalAmountRoundedDown(balance_, index_))
            )
            : BalanceInfo.wrap(uint256(balance_));
    }

    /**
     * @dev   Overwrites the index bits with a new index for `account_`.
     * @param account_ The account whose balance information is being updated.
     * @param index_   The index of their last interaction.
     */
    function _updateIndex(address account_, uint128 index_) internal {
        uint256 unwrapped_ = BalanceInfo.unwrap(_balances[account_]);

        unwrapped_ &= ~(uint256(type(uint128).max) << 112); // Clear the index bits (See `_setBalanceInfo` for layout).

        _balances[account_] = BalanceInfo.wrap(unwrapped_ | (uint256(index_) << 112));
    }

    /**
     * @dev   Transfers `amount_` tokens from `sender_` to `recipient_` given some current index.
     * @param sender_       The sender's address.
     * @param recipient_    The recipient's address.
     * @param amount_       The amount to be transferred.
     * @param currentIndex_ The current index.
     */
    function _transfer(address sender_, address recipient_, uint240 amount_, uint128 currentIndex_) internal {
        _revertIfInvalidRecipient(recipient_);

        // Claims for both the sender and recipient are required before transferring since add an subtract functions
        // assume accounts' balances are up-to-date with the current index.
        _claim(sender_, currentIndex_);
        _claim(recipient_, currentIndex_);

        emit Transfer(sender_, recipient_, amount_);

        // Return early if sender and recipient are the same account.
        if (sender_ == recipient_) return;

        (bool senderIsEarning_, , , uint240 senderBalance_) = _getBalanceInfo(sender_);
        (bool recipientIsEarning_, , , uint240 recipientBalance_) = _getBalanceInfo(recipient_);

        // If the sender and recipient are both earning or both non-earning, update their balances without affecting
        // the total earning and non-earning supply storage variables.
        if (senderIsEarning_ == recipientIsEarning_) {
            if (senderBalance_ < amount_) revert InsufficientBalance(sender_, senderBalance_, amount_);

            // NOTE: `_setBalanceInfo` ignores `index_` passed for non-earners.
            unchecked {
                _setBalanceInfo(sender_, senderIsEarning_, currentIndex_, senderBalance_ - amount_);
                _setBalanceInfo(recipient_, recipientIsEarning_, currentIndex_, recipientBalance_ + amount_);
            }

            return;
        }

        senderIsEarning_
            ? _subtractEarningAmount(sender_, amount_, currentIndex_)
            : _subtractNonEarningAmount(sender_, amount_);

        recipientIsEarning_
            ? _addEarningAmount(recipient_, amount_, currentIndex_)
            : _addNonEarningAmount(recipient_, amount_);
    }

    /**
     * @dev   Internal ERC20 transfer function that needs to be implemented by the inheriting contract.
     * @param sender_    The sender's address.
     * @param recipient_ The recipient's address.
     * @param amount_    The amount to be transferred.
     */
    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        _transfer(sender_, recipient_, UIntMath.safe240(amount_), currentIndex());
    }

    /**
     * @dev   Increments total earning supply by `amount_` tokens.
     * @param amount_       The present amount of tokens to increment total earning supply by.
     * @param currentIndex_ The current index used to compute the principal amount.
     */
    function _addTotalEarningSupply(uint240 amount_, uint128 currentIndex_) internal {
        unchecked {
            uint112 principal_ = IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_);

            // Increment the total earning supply and principal proportionally.
            _setTotalEarningSupply(totalEarningSupply() + amount_, _principalOfTotalEarningSupply + principal_);
        }
    }

    /**
     * @dev   Decrements total earning supply by `amount_` tokens.
     * @param amount_       The present amount of tokens to decrement total earning supply by.
     * @param currentIndex_ The current index used to compute the principal amount.
     */
    function _subtractTotalEarningSupply(uint240 amount_, uint128 currentIndex_) internal {
        unchecked {
            uint112 principal_ = IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_);

            // Decrement the total earning supply and principal proportionally.
            _setTotalEarningSupply(totalEarningSupply() - amount_, _principalOfTotalEarningSupply - principal_);
        }
    }

    /**
     * @dev   Sets the storage variables composing the total earning supply to ensure present and principal amounts.
     * @param amount_    The present amount of total earning supply.
     * @param principal_ The principal amount of total earning supply.
     */
    function _setTotalEarningSupply(uint240 amount_, uint112 principal_) internal {
        _indexOfTotalEarningSupply = (principal_ == 0) ? 0 : IndexingMath.divide240by112Down(amount_, principal_);
        _principalOfTotalEarningSupply = principal_;
    }

    /**
     * @dev   Wraps `amount` M from `account_` into wM for `recipient`.
     * @param account_   The account from which M is deposited.
     * @param recipient_ The account receiving the minted wM.
     * @param amount_    The amount of M deposited and wM minted.
     */
    function _wrap(address account_, address recipient_, uint240 amount_) internal {
        uint256 startingBalance_ = IMTokenLike(mToken).balanceOf(address(this));

        // NOTE: The behavior of `IMTokenLike.transferFrom` is known, so its return can be ignored.
        IMTokenLike(mToken).transferFrom(account_, address(this), amount_);

        // NOTE: When this WrappedMToken contract is earning, any amount of M sent to it is converted to a principal
        //       amount at the MToken contract, which when represented as a present amount, may be a rounding error
        //       amount less than `amount_`. In order to capture the real increase in M, the difference between the
        //       starting and ending M balance is minted as WrappedM.
        _mint(recipient_, UIntMath.safe240(IMTokenLike(mToken).balanceOf(address(this)) - startingBalance_));
    }

    /**
     * @dev   Unwraps `amount` wM from `account_` into M for `recipient`.
     * @param account_   The account from which WM is burned.
     * @param recipient_ The account receiving the withdrawn M.
     * @param amount_    The amount of wM burned and M withdrawn.
     */
    function _unwrap(address account_, address recipient_, uint240 amount_) internal {
        _burn(account_, amount_);

        // NOTE: The behavior of `IMTokenLike.transfer` is known, so its return can be ignored.
        IMTokenLike(mToken).transfer(recipient_, amount_);
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev  Returns the current index of the M Token.
    function _currentMIndex() internal view returns (uint128 index_) {
        return IMTokenLike(mToken).currentIndex();
    }

    /// @dev  Returns the earning index from the last `disableEarning` call.
    function _lastDisableEarningIndex() internal view returns (uint128 index_) {
        return wasEarningEnabled() ? _unsafeAccess(_enableDisableEarningIndices, 1) : 0;
    }

    /**
     * @dev    Reads the decoded balance information for `account_` in the storage mapping.
     * @param  account_   The account whose balance information is being read.
     * @return isEarning_ Whether `account_` is earning or not.
     * @return index_     The index of their last interaction.
     * @return principal_ The principal amount of the token balance.
     * @return balance_   The present amount of the token balance.
     */
    function _getBalanceInfo(
        address account_
    ) internal view returns (bool isEarning_, uint128 index_, uint112 principal_, uint240 balance_) {
        uint256 unwrapped_ = BalanceInfo.unwrap(_balances[account_]);

        // The most significant 1 bit is always a flag for whether the account is earning or not.
        // The next 15 bits are empty.
        isEarning_ = (unwrapped_ >> 255) != 0;

        // For a non-earner, the 240 least significant bits are simply the present balance.
        if (!isEarning_) return (false, uint128(0), uint112(0), uint240(unwrapped_));

        // For an earner, the next 128 bits are the index of the last interaction and the next (and least significant)
        // 112 bits are the principal amount, from which the present balance can then be computed.
        index_ = uint128(unwrapped_ >> 112); // Shift out the 112 principal bits and cast to ignore the flag bit.
        principal_ = uint112(unwrapped_);
        balance_ = IndexingMath.getPresentAmountRoundedDown(principal_, index_);
    }

    /// @dev Returns the address of the contract to use as a migrator, if any.
    function _getMigrator() internal view override returns (address migrator_) {
        return
            address(
                uint160(
                    // NOTE: A subsequent implementation should use a unique migrator prefix.
                    uint256(IRegistrarLike(registrar).get(keccak256(abi.encode(_MIGRATOR_V1_PREFIX, address(this)))))
                )
            );
    }

    /**
     * @dev    Returns whether `account_` is a TTG-approved earner.
     * @param  account_    The account being queried.
     * @return isApproved_ True if the account_ is a TTG-approved earner, false otherwise.
     */
    function _isApprovedEarner(address account_) internal view returns (bool isApproved_) {
        return
            IRegistrarLike(registrar).get(_EARNERS_LIST_IGNORED) != bytes32(0) ||
            IRegistrarLike(registrar).listContains(_EARNERS_LIST, account_);
    }

    function _projectedEarningSupply(uint128 currentIndex_) internal view returns (uint240 supply_) {
        // NOTE: Round up to overestimate the earning supply plus all accrued yield, such that:
        //       `projectedEarningSupply_ >= Sum of all (present earning balances + accrued yield)`.
        return IndexingMath.getPresentAmountRoundedUp(_principalOfTotalEarningSupply, currentIndex_);
    }

    /**
     * @dev   Reverts if `amount_` is equal to 0.
     * @param amount_ Amount of token.
     */
    function _revertIfInsufficientAmount(uint256 amount_) internal pure {
        if (amount_ == 0) revert InsufficientAmount(amount_);
    }

    /**
     * @dev   Reverts if `recipient_` is address(0).
     * @param recipient_ Address of a recipient.
     */
    function _revertIfInvalidRecipient(address recipient_) internal pure {
        if (recipient_ == address(0)) revert InvalidRecipient(recipient_);
    }

    /**
     * @dev   Reverts if `account_` is an approved earner.
     * @param account_ Address of an account.
     */
    function _revertIfApprovedEarner(address account_) internal view {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner();
    }

    /**
     * @dev   Reverts if `account_` is not an approved earner.
     * @param account_ Address of an account.
     */
    function _revertIfNotApprovedEarner(address account_) internal view {
        if (!_isApprovedEarner(account_)) revert NotApprovedEarner();
    }

    /**
     * @dev   Reads the uint128 value at some index of an array of uint128 values whose storage pointer is given,
     *        assuming the index is valid, without wasting gas checking for out-of-bounds errors.
     * @param array_ The storage pointer of an array of uint128 values.
     * @param i_     The index of the array to read.
     */
    function _unsafeAccess(uint128[] storage array_, uint256 i_) internal view returns (uint128 value_) {
        assembly {
            mstore(0, array_.slot)

            value_ := sload(add(keccak256(0, 0x20), div(i_, 2)))

            // Since uint128 values take up either the top half or bottom half of a slot, shift the result accordingly.
            if eq(mod(i_, 2), 1) {
                value_ := shr(128, value_)
            }
        }
    }
}
