// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { Bytes32String } from "../lib/common/src/libs/Bytes32String.sol";
import { IndexingMath } from "../lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";
import { IWrappedMToken } from "./interfaces/IWrappedMToken.sol";

import { Migratable } from "./Migratable.sol";

abstract contract WrappedMTokenStorageLayout {
    /// @custom:storage-location erc7201:m-zero.storage.WrappedMToken
    struct WrappedMTokenStorage {
        bytes32 name;
        bytes32 symbol;
        address excessDestination;
    }

    // keccak256(abi.encode(uint256(keccak256("m-zero.storage.WrappedMToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _WRAPPED_M_TOKEN_STORAGE_LOCATION =
        0xa42bd00c321004a3a311d89d7de22f9a9bce2736d5fa3ef3cd574d80bf6d9993; // TODO: Update this value.

    function _getWrappedMTokenStorage() internal pure returns (WrappedMTokenStorage storage $) {
        assembly {
            $.slot := _WRAPPED_M_TOKEN_STORAGE_LOCATION
        }
    }
}

abstract contract Initializer is WrappedMTokenStorageLayout {
    function _initialize(string memory name_, string memory symbol_, address excessDestination_) internal {
        WrappedMTokenStorage storage $ = _getWrappedMTokenStorage();

        $.name = Bytes32String.toBytes32(name_);
        $.symbol = Bytes32String.toBytes32(symbol_);

        if (($.excessDestination = excessDestination_) == address(0)) revert IWrappedMToken.ZeroExcessDestination();
    }
}

/**
 * @title  ERC20 Token contract for wrapping M into a non-rebasing token with claimable yields.
 * @author M^0 Labs
 */
abstract contract WrappedMToken is IWrappedMToken, Migratable, WrappedMTokenStorageLayout, ERC20Extended {
    /* ============ Structs ============ */

    /**
     * @dev   Struct to represent an account's balance and yield earning details.
     * @param isEarning         Whether the account is actively earning yield.
     * @param balance           The present amount of tokens held by the account.
     * @param earningPrincipal  The earning principal for the account.
     * @param hasClaimRecipient Whether the account has an explicitly set claim recipient.
     * @param hasEarnerDetails  Whether the account has additional details for earning yield.
     */
    struct Account {
        // First Slot
        bool isEarning;
        uint240 balance;
        // Second slot
        uint112 earningPrincipal;
        bool hasClaimRecipient;
        bool hasEarnerDetails;
    }

    /* ============ Variables ============ */

    /// @inheritdoc IWrappedMToken
    bytes32 public constant EARNERS_LIST_IGNORED_KEY = "earners_list_ignored";

    /// @inheritdoc IWrappedMToken
    bytes32 public constant EARNERS_LIST_NAME = "earners";

    /// @inheritdoc IWrappedMToken
    address public immutable mToken;

    /// @inheritdoc IWrappedMToken
    address public immutable registrar;

    // StatefulERC712.nonces is slot 0
    // ERC3009.authorizationState is slot 1
    // ERC20Extended.allowance is slot 2

    /// @inheritdoc IWrappedMToken
    uint112 public totalEarningPrincipal; // slot 3

    /// @inheritdoc IWrappedMToken
    int144 public roundingError; // slot 3

    /// @inheritdoc IWrappedMToken
    uint240 public totalEarningSupply; // slot 4

    /// @inheritdoc IWrappedMToken
    uint240 public totalNonEarningSupply; // slot 5

    /// @dev Mapping of accounts to their respective `AccountInfo` structs.
    mapping(address account => Account balance) internal _accounts; // slot 6

    /// @inheritdoc IWrappedMToken
    uint128 public enableMIndex; // slot 7

    /// @inheritdoc IWrappedMToken
    uint128 public disableIndex; // slot 7

    /* ============ Modifiers ============ */

    modifier transferHooks(
        address sender_,
        address recipient_,
        uint240 amount_
    ) {
        _beforeTransfer(sender_, recipient_, amount_);

        _;

        _afterTransfer(sender_, recipient_, amount_);
    }

    /* ============ Constructor ============ */

    /**
     * @dev   Constructs the contract given an M Token address and other parameters.
     *        Note that a proxy will not need to initialize since there are no mutable storage values affected.
     * @param name_        The name of the token.
     * @param symbol_      The symbol of the token.
     * @param mToken_      The address of an M Token.
     * @param registrar_   The address of a Registrar.
     * @param initializer_ The address of a proxy Initializer.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address initializer_
    ) Migratable(initializer_) ERC20Extended(name_, symbol_, 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((registrar = registrar_) == address(0)) revert ZeroRegistrar();
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IWrappedMToken
    function wrap(address recipient_, uint256 amount_) external virtual returns (uint240 wrapped_) {
        return _wrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function wrap(address recipient_) external virtual returns (uint240 wrapped_) {
        return _wrap(msg.sender, recipient_, _mBalanceOf(msg.sender));
    }

    /// @inheritdoc IWrappedMToken
    function wrapWithPermit(
        address recipient_,
        uint256 amount_,
        uint256 deadline_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external virtual returns (uint240 wrapped_) {
        IMTokenLike(mToken).permit(msg.sender, address(this), amount_, deadline_, v_, r_, s_);

        return _wrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function wrapWithPermit(
        address recipient_,
        uint256 amount_,
        uint256 deadline_,
        bytes memory signature_
    ) external virtual returns (uint240 wrapped_) {
        IMTokenLike(mToken).permit(msg.sender, address(this), amount_, deadline_, signature_);

        return _wrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function unwrap(address recipient_, uint256 amount_) external virtual returns (uint240 unwrapped_) {
        return _unwrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function unwrap(address recipient_) external virtual returns (uint240 unwrapped_) {
        return _unwrap(msg.sender, recipient_, uint240(balanceOf(msg.sender)));
    }

    /// @inheritdoc IWrappedMToken
    function claimFor(address account_) external virtual returns (uint240 yield_) {
        return _claim(account_, currentIndex());
    }

    /// @inheritdoc IWrappedMToken
    function claimExcess() external virtual returns (uint240 claimed_) {
        int248 excess_ = excess();

        if (excess_ <= 0) revert NoExcess();

        claimed_ = _getSafeTransferableM(address(this), uint240(uint248(excess_)));

        emit ExcessClaimed(claimed_);

        // NOTE: The behavior of `IMTokenLike.transfer` is known, so its return can be ignored.
        IMTokenLike(mToken).transfer(_getWrappedMTokenStorage().excessDestination, claimed_);
    }

    /// @inheritdoc IWrappedMToken
    function enableEarning() external virtual {
        if (!_isRegistrarApprovedEarner(address(this))) revert WrapperIsNotApprovedEarner();

        if (isEarningEnabled()) revert EarningIsEnabled();

        emit EarningEnabled(enableMIndex = _currentMIndex());

        IMTokenLike(mToken).startEarning();
    }

    /// @inheritdoc IWrappedMToken
    function disableEarning() external virtual {
        if (_isRegistrarApprovedEarner(address(this))) revert WrapperIsApprovedEarner();

        if (!isEarningEnabled()) revert EarningIsDisabled();

        emit EarningDisabled(disableIndex = currentIndex());

        delete enableMIndex;

        IMTokenLike(mToken).stopEarning();
    }

    /// @inheritdoc IWrappedMToken
    function startEarningFor(address account_) external virtual {
        _startEarning(account_, currentIndex());
    }

    /// @inheritdoc IWrappedMToken
    function startEarningFor(address[] calldata accounts_) external virtual {
        if (!isEarningEnabled()) revert EarningIsDisabled();

        uint128 currentIndex_ = currentIndex();

        for (uint256 index_; index_ < accounts_.length; ++index_) {
            _startEarning(accounts_[index_], currentIndex_);
        }
    }

    /// @inheritdoc IWrappedMToken
    function stopEarningFor(address account_) external virtual {
        _stopEarning(account_, currentIndex());
    }

    /// @inheritdoc IWrappedMToken
    function stopEarningFor(address[] calldata accounts_) external virtual {
        uint128 currentIndex_ = currentIndex();

        for (uint256 index_; index_ < accounts_.length; ++index_) {
            _stopEarning(accounts_[index_], currentIndex_);
        }
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IWrappedMToken
    function accruedYieldOf(address account_) public view virtual returns (uint240 yield_) {
        Account storage accountInfo_ = _accounts[account_];

        return
            accountInfo_.isEarning
                ? _getAccruedYield(accountInfo_.balance, accountInfo_.earningPrincipal, currentIndex())
                : 0;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account_) public view virtual returns (uint256 balance_) {
        return _accounts[account_].balance;
    }

    /// @inheritdoc IWrappedMToken
    function balanceWithYieldOf(address account_) public view virtual returns (uint256 balance_) {
        unchecked {
            return balanceOf(account_) + accruedYieldOf(account_);
        }
    }

    /// @inheritdoc IWrappedMToken
    function earningPrincipalOf(address account_) public view virtual returns (uint112 earningPrincipal_) {
        return _accounts[account_].earningPrincipal;
    }

    /// @inheritdoc IWrappedMToken
    function currentIndex() public view virtual returns (uint128 index_) {
        uint128 disableIndex_ = disableIndex == 0 ? IndexingMath.EXP_SCALED_ONE : disableIndex;

        return enableMIndex == 0 ? disableIndex_ : (disableIndex_ * _currentMIndex()) / enableMIndex;
    }

    /// @inheritdoc IWrappedMToken
    function isEarning(address account_) public view virtual returns (bool isEarning_) {
        return _accounts[account_].isEarning;
    }

    /// @inheritdoc IWrappedMToken
    function isEarningEnabled() public view virtual returns (bool isEnabled_) {
        return enableMIndex != 0;
    }

    /// @inheritdoc IWrappedMToken
    function excess() public view virtual returns (int248 excess_) {
        unchecked {
            int248 earmarked_ = int248(uint248(totalNonEarningSupply + projectedEarningSupply())) + roundingError;
            int248 balance_ = int248(uint248(_mBalanceOf(address(this))));

            // The entire M balance is excess if the total projected supply (factoring rounding errors) is less than 0.
            return earmarked_ <= 0 ? balance_ : balance_ - earmarked_;
        }
    }

    /// @inheritdoc IWrappedMToken
    function totalAccruedYield() public view virtual returns (uint240 yield_) {
        uint240 projectedEarningSupply_ = projectedEarningSupply();
        uint240 earningSupply_ = totalEarningSupply;

        unchecked {
            return projectedEarningSupply_ <= earningSupply_ ? 0 : projectedEarningSupply_ - earningSupply_;
        }
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual returns (uint256 totalSupply_) {
        unchecked {
            return totalEarningSupply + totalNonEarningSupply;
        }
    }

    /// @inheritdoc IWrappedMToken
    function projectedEarningSupply() public view virtual returns (uint240 supply_) {
        return
            UIntMath.max240(
                IndexingMath.getPresentAmountRoundedUp(totalEarningPrincipal, currentIndex()),
                totalEarningSupply
            );
    }

    /// @inheritdoc IERC20
    function name() external view override(IERC20, ERC20Extended) returns (string memory name_) {
        return Bytes32String.toString(_getWrappedMTokenStorage().name);
    }

    /// @inheritdoc IERC20
    function symbol() external view override(IERC20, ERC20Extended) returns (string memory symbol_) {
        return Bytes32String.toString(_getWrappedMTokenStorage().symbol);
    }

    /// @inheritdoc IWrappedMToken
    function excessDestination() external view returns (address excessDestination_) {
        return _getWrappedMTokenStorage().excessDestination;
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Mints `amount_` tokens to `recipient_`.
     * @param recipient_ The address whose account balance will be incremented.
     * @param amount_    The present amount of tokens to mint.
     */
    function _mint(address recipient_, uint240 amount_) internal virtual {
        _beforeMint(recipient_, amount_);

        _accounts[recipient_].isEarning
            ? _addEarningAmount(recipient_, amount_, currentIndex())
            : _addNonEarningAmount(recipient_, amount_);

        emit Transfer(address(0), recipient_, amount_);

        _afterMint(recipient_, amount_);
    }

    /**
     * @dev   Burns `amount_` tokens from `account_`.
     * @param account_ The address whose account balance will be decremented.
     * @param amount_  The present amount of tokens to burn.
     */
    function _burn(address account_, uint240 amount_) internal virtual {
        _beforeBurn(account_, amount_);

        _accounts[account_].isEarning
            ? _subtractEarningAmount(account_, amount_, currentIndex())
            : _subtractNonEarningAmount(account_, amount_);

        emit Transfer(account_, address(0), amount_);

        _afterBurn(account_, amount_);
    }

    /**
     * @dev   Increments the token balance of `account_` by `amount_`, assuming non-earning status.
     * @param account_ The address whose account balance will be incremented.
     * @param amount_  The present amount of tokens to increment by.
     */
    function _addNonEarningAmount(address account_, uint240 amount_) internal virtual {
        // NOTE: Can be `unchecked` because the max amount of wrappable M is never greater than `type(uint240).max`.
        unchecked {
            _accounts[account_].balance += amount_;
            totalNonEarningSupply += amount_;
        }
    }

    /**
     * @dev   Decrements the token balance of `account_` by `amount_`, assuming non-earning status.
     * @param account_ The address whose account balance will be decremented.
     * @param amount_  The present amount of tokens to decrement by.
     */
    function _subtractNonEarningAmount(address account_, uint240 amount_) internal virtual {
        Account storage accountInfo_ = _accounts[account_];
        uint240 balance_ = accountInfo_.balance;

        if (balance_ < amount_) revert InsufficientBalance(account_, balance_, amount_);

        unchecked {
            accountInfo_.balance = balance_ - amount_;
            totalNonEarningSupply -= amount_;
        }
    }

    /**
     * @dev   Increments the token balance of `account_` by `amount_`, assuming earning status.
     * @param account_      The address whose account balance will be incremented.
     * @param amount_       The present amount of tokens to increment by.
     * @param currentIndex_ The current index to use to compute the principal amount.
     */
    function _addEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal virtual {
        Account storage accountInfo_ = _accounts[account_];
        uint112 principal_ = IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_);

        // NOTE: Can be `unchecked` because the max amount of wrappable M is never greater than `type(uint240).max`.
        unchecked {
            accountInfo_.balance += amount_;
            accountInfo_.earningPrincipal = UIntMath.safe112(uint256(accountInfo_.earningPrincipal) + principal_);
        }

        _addTotalEarningSupply(amount_, principal_);
    }

    /**
     * @dev   Decrements the token balance of `account_` by `amount_`, assuming earning status.
     * @param account_      The address whose account balance will be decremented.
     * @param amount_       The present amount of tokens to decrement by.
     * @param currentIndex_ The current index to use to compute the principal amount.
     */
    function _subtractEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal virtual {
        Account storage accountInfo_ = _accounts[account_];
        uint240 balance_ = accountInfo_.balance;

        if (balance_ < amount_) revert InsufficientBalance(account_, balance_, amount_);

        uint112 earningPrincipal_ = accountInfo_.earningPrincipal;

        // `min112` prevents `earningPrincipal` underflow.
        uint112 principal_ = UIntMath.min112(
            IndexingMath.getPrincipalAmountRoundedUp(amount_, currentIndex_),
            earningPrincipal_
        );

        unchecked {
            accountInfo_.balance = balance_ - amount_;
            accountInfo_.earningPrincipal = earningPrincipal_ - principal_;
        }

        _subtractTotalEarningSupply(amount_, principal_);
    }

    /**
     * @dev    Claims accrued yield for `account_` given a `currentIndex_`.
     * @param  account_      The address to claim accrued yield for.
     * @param  currentIndex_ The current index to accrue until.
     * @return yield_        The accrued yield that was claimed.
     */
    function _claim(address account_, uint128 currentIndex_) internal virtual returns (uint240 yield_) {
        Account storage accountInfo_ = _accounts[account_];

        if (!accountInfo_.isEarning) return 0;

        _beforeClaim(account_, currentIndex_);

        uint240 startingBalance_ = accountInfo_.balance;

        yield_ = _getAccruedYield(startingBalance_, accountInfo_.earningPrincipal, currentIndex_);

        if (yield_ == 0) return 0;

        unchecked {
            // Update balance and total earning supply to account for the yield, but the principals have not changed.
            accountInfo_.balance = startingBalance_ + yield_;
            totalEarningSupply += yield_;
        }

        // Emit the appropriate `Claimed` and `Transfer` events.
        emit Claimed(account_, yield_);
        emit Transfer(address(0), account_, yield_);

        _afterClaim(account_, yield_, currentIndex_);
    }

    /**
     * @dev   Transfers `amount_` tokens from `sender_` to `recipient_` given some current index.
     * @param sender_       The sender's address.
     * @param recipient_    The recipient's address.
     * @param amount_       The amount to be transferred.
     * @param currentIndex_ The current index.
     */
    function _transfer(
        address sender_,
        address recipient_,
        uint240 amount_,
        uint128 currentIndex_
    ) internal virtual transferHooks(sender_, recipient_, amount_) {
        emit Transfer(sender_, recipient_, amount_);

        if (amount_ == 0) return;

        Account storage senderInfo_ = _accounts[sender_];
        Account storage recipientInfo_ = _accounts[recipient_];

        bool senderIsEarner_ = senderInfo_.isEarning;
        bool recipientIsEarner_ = recipientInfo_.isEarning;

        // If sender and earner are different earner states, transfer affects total supplies.
        if (senderIsEarner_ != recipientIsEarner_) {
            senderIsEarner_
                ? _subtractEarningAmount(sender_, amount_, currentIndex_)
                : _subtractNonEarningAmount(sender_, amount_);

            recipientIsEarner_
                ? _addEarningAmount(recipient_, amount_, currentIndex_)
                : _addNonEarningAmount(recipient_, amount_);

            return;
        }

        if (senderInfo_.balance < amount_) revert InsufficientBalance(sender_, senderInfo_.balance, amount_);

        // If sender and recipient are both earners or both non-earners, transfer does not affect total supplies.
        senderIsEarner_
            ? _transferBetweenEarners(senderInfo_, recipientInfo_, amount_, currentIndex_)
            : _transferBetweenNonEarners(senderInfo_, recipientInfo_, amount_);
    }

    /**
     * @dev   Internal ERC20 transfer function that needs to be implemented by the inheriting contract.
     * @param sender_    The sender's address.
     * @param recipient_ The recipient's address.
     * @param amount_    The amount to be transferred.
     */
    function _transfer(address sender_, address recipient_, uint256 amount_) internal virtual override {
        _transfer(sender_, recipient_, UIntMath.safe240(amount_), currentIndex());
    }

    /**
     * @dev   Transfers `amount_` tokens between earners given some current index.
     * @param sender_       The sender's Account storage pointer.
     * @param recipient_    The recipient's Account storage pointer.
     * @param amount_       The amount to be transferred.
     * @param currentIndex_ The current index.
     */
    function _transferBetweenEarners(
        Account storage sender_,
        Account storage recipient_,
        uint240 amount_,
        uint128 currentIndex_
    ) internal {
        uint112 earningPrincipal_ = sender_.earningPrincipal;

        // `min112` prevents `earningPrincipal` underflow.
        uint112 principal_ = UIntMath.min112(
            IndexingMath.getPrincipalAmountRoundedUp(amount_, currentIndex_),
            earningPrincipal_
        );

        // NOTE: Can be `unchecked` because `_transfer` already checked for insufficient sender balance.
        unchecked {
            sender_.balance -= amount_;
            sender_.earningPrincipal = earningPrincipal_ - principal_;

            recipient_.balance += amount_;
            recipient_.earningPrincipal = UIntMath.safe112(uint256(recipient_.earningPrincipal) + principal_);
        }
    }

    /**
     * @dev   Transfers `amount_` tokens between non-earners.
     * @param sender_    The sender's Account storage pointer.
     * @param recipient_ The recipient's Account storage pointer.
     * @param amount_    The amount to be transferred.
     */
    function _transferBetweenNonEarners(Account storage sender_, Account storage recipient_, uint240 amount_) internal {
        // NOTE: Can be `unchecked` because `_transfer` already checked for insufficient sender balance.
        unchecked {
            sender_.balance -= amount_;
            recipient_.balance += amount_;
        }
    }

    /**
     * @dev   Increments total earning supply by `amount_` tokens.
     * @param amount_    The present amount of tokens to increment total earning supply by.
     * @param principal_ The principal amount of tokens to increment total earning principal by.
     */
    function _addTotalEarningSupply(uint240 amount_, uint112 principal_) internal virtual {
        unchecked {
            // Increment the total earning supply and principal proportionally.
            totalEarningSupply += amount_;
            totalEarningPrincipal = UIntMath.safe112(uint256(totalEarningPrincipal) + principal_);
        }
    }

    /**
     * @dev   Decrements total earning supply by `amount_` tokens.
     * @param amount_    The present amount of tokens to decrement total earning supply by.
     * @param principal_ The principal amount of tokens to decrement total earning principal by.
     */
    function _subtractTotalEarningSupply(uint240 amount_, uint112 principal_) internal virtual {
        uint240 totalEarningSupply_ = totalEarningSupply;
        uint112 totalEarningPrincipal_ = totalEarningPrincipal;

        unchecked {
            // `min240` and `min112` prevent `totalEarningSupply` and `totalEarningPrincipal` underflow respectively.
            totalEarningSupply = totalEarningSupply_ - UIntMath.min240(amount_, totalEarningSupply_);
            totalEarningPrincipal = totalEarningPrincipal_ - UIntMath.min112(principal_, totalEarningPrincipal_);
        }
    }

    /**
     * @dev    Wraps `amount` M from `account_` into wM for `recipient`.
     * @param  account_   The account from which M is deposited.
     * @param  recipient_ The account receiving the minted wM.
     * @param  amount_    The amount of M deposited.
     * @return wrapped_   The amount of wM minted.
     */
    function _wrap(address account_, address recipient_, uint240 amount_) internal virtual returns (uint240 wrapped_) {
        _beforeWrap(account_, recipient_, amount_);

        _transferFromM(account_, amount_);
        _mint(recipient_, wrapped_ = amount_);

        _afterWrap(account_, recipient_, amount_);
    }

    /**
     * @dev    Unwraps `amount` wM from `account_` into M for `recipient`.
     * @param  account_   The account from which WM is burned.
     * @param  recipient_ The account receiving the withdrawn M.
     * @param  amount_    The amount of wM burned.
     * @return unwrapped_ The amount of M withdrawn.
     */
    function _unwrap(
        address account_,
        address recipient_,
        uint240 amount_
    ) internal virtual returns (uint240 unwrapped_) {
        _beforeUnwrap(account_, recipient_, amount_);

        _burn(account_, amount_);
        _transferM(recipient_, unwrapped_ = amount_);

        _afterUnwrap(account_, recipient_, amount_);
    }

    /**
     * @dev   Starts earning for `account`.
     * @param account_      The account to start earning for.
     * @param currentIndex_ The current index.
     */
    function _startEarning(address account_, uint128 currentIndex_) internal virtual {
        Account storage accountInfo_ = _accounts[account_];

        if (accountInfo_.isEarning) return;

        _beforeStartEarning(account_, currentIndex_);

        uint240 balance_ = accountInfo_.balance;
        uint112 earningPrincipal_ = IndexingMath.getPrincipalAmountRoundedDown(balance_, currentIndex_);

        accountInfo_.isEarning = true;
        accountInfo_.earningPrincipal = earningPrincipal_;

        _addTotalEarningSupply(balance_, earningPrincipal_);

        unchecked {
            totalNonEarningSupply -= balance_;
        }

        emit StartedEarning(account_);

        _afterStartEarning(account_, currentIndex_);
    }

    /**
     * @dev   Stops earning for `account`.
     * @param account_      The account to stop earning for.
     * @param currentIndex_ The current index.
     */
    function _stopEarning(address account_, uint128 currentIndex_) internal virtual {
        Account storage accountInfo_ = _accounts[account_];

        if (!accountInfo_.isEarning) return;

        _beforeStopEarning(account_, currentIndex_);

        uint240 balance_ = accountInfo_.balance;
        uint112 earningPrincipal_ = accountInfo_.earningPrincipal;

        delete accountInfo_.isEarning;
        delete accountInfo_.earningPrincipal;

        _subtractTotalEarningSupply(balance_, earningPrincipal_);

        unchecked {
            totalNonEarningSupply += balance_;
        }

        emit StoppedEarning(account_);

        _afterStopEarning(account_, currentIndex_);
    }

    /**
     * @dev   Transfer `amount_` M to `recipient_`, tracking this contract's M balance rounding errors.
     * @param recipient_ The account to transfer M to.
     * @param amount_    The amount of M to transfer.
     */
    function _transferM(address recipient_, uint240 amount_) internal virtual {
        uint240 startingBalance_ = _mBalanceOf(address(this));

        // NOTE: The behavior of `IMTokenLike.transfer` is known, so its return can be ignored.
        IMTokenLike(mToken).transfer(recipient_, amount_);

        // NOTE: When this WrappedMToken contract is earning, any amount of M sent from it is converted to a principal
        //       amount at the MToken contract, which when represented as a present amount, may be a rounding error
        //       amount more than `amount_`. In order to capture the real decrease in M, the difference between the
        //       ending and starting M balance is captured.
        uint240 decrease_ = startingBalance_ - _mBalanceOf(address(this));

        // If the M lost is more than the wM burned, then the difference is added to `roundingError`.
        roundingError += int144(int256(uint256(decrease_)) - int256(uint256(amount_)));
    }

    /**
     * @dev   Transfer `amount_` M from `sender_`, tracking this contract's M balance rounding errors.
     * @param sender_ The account to transfer M from.
     * @param amount_ The amount of M to transfer.
     */
    function _transferFromM(address sender_, uint240 amount_) internal virtual {
        uint240 startingBalance_ = _mBalanceOf(address(this));

        // NOTE: The behavior of `IMTokenLike.transferFrom` is known, so its return can be ignored.
        IMTokenLike(mToken).transferFrom(sender_, address(this), _getSafeTransferableM(sender_, amount_));

        // NOTE: When this WrappedMToken contract is earning, any amount of M sent to it is converted to a principal
        //       amount at the MToken contract, which when represented as a present amount, may be a rounding error
        //       amount more/less than `amount_`. In order to capture the real increase in M, the difference between the
        //       starting and ending M balance is captured.
        uint240 increase_ = _mBalanceOf(address(this)) - startingBalance_;

        // If the M gained is more/less than the wM minted, then the difference is subtracted/added to `roundingError`.
        roundingError += int144(int256(uint256(amount_)) - int256(uint256(increase_)));
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev Returns the current index of the M Token.
    function _currentMIndex() internal view virtual returns (uint128 index_) {
        return IMTokenLike(mToken).currentIndex();
    }

    /// @dev Returns whether an account is a Registrar-approved earner.
    function _isRegistrarApprovedEarner(address account_) internal view virtual returns (bool) {
        return
            _getFromRegistrar(EARNERS_LIST_IGNORED_KEY) != bytes32(0) ||
            IRegistrarLike(registrar).listContains(EARNERS_LIST_NAME, account_);
    }

    /**
     * @dev    Compute the yield given an account's balance, earning principal, and the current index.
     * @param  balance_          The token balance of an earning account.
     * @param  earningPrincipal_ The earning principal of the account.
     * @param  currentIndex_     The current index.
     * @return yield_            The yield accrued since the last interaction.
     */
    function _getAccruedYield(
        uint240 balance_,
        uint112 earningPrincipal_,
        uint128 currentIndex_
    ) internal pure virtual returns (uint240 yield_) {
        uint240 balanceWithYield_ = IndexingMath.getPresentAmountRoundedDown(earningPrincipal_, currentIndex_);

        unchecked {
            return (balanceWithYield_ <= balance_) ? 0 : balanceWithYield_ - balance_;
        }
    }

    /**
     * @dev    Retrieve a value from the Registrar.
     * @param  key_   The key to retrieve the value for.
     * @return value_ The value stored in the Registrar.
     */
    function _getFromRegistrar(bytes32 key_) internal view virtual returns (bytes32 value_) {
        return IRegistrarLike(registrar).get(key_);
    }

    /**
     * @dev    Compute the adjusted amount of M that can safely be transferred out given the current index.
     * @param  amount_     Some amount to be transferred out of this contract.
     * @return safeAmount_ The adjusted amount that can safely be transferred out.
     */
    function _getSafeTransferableM(
        address sender_,
        uint240 amount_
    ) internal view virtual returns (uint240 safeAmount_) {
        // If `sender` is not earning, no ned to adjust `amount_`.
        if (!IMTokenLike(mToken).isEarning(sender_)) return amount_;

        uint128 currentIndex_ = _currentMIndex();
        uint112 startingPrincipal_ = uint112(IMTokenLike(mToken).principalBalanceOf(sender_));
        uint240 startingBalance_ = IndexingMath.getPresentAmountRoundedDown(startingPrincipal_, currentIndex_);

        // Adjust `amount_` to ensure it's M balance decrement is limited to `amount_`.
        unchecked {
            uint112 minEndingPrincipal_ = IndexingMath.getPrincipalAmountRoundedUp(
                startingBalance_ - amount_,
                currentIndex_
            );

            return IndexingMath.getPresentAmountRoundedDown(startingPrincipal_ - minEndingPrincipal_, currentIndex_);
        }
    }

    /**
     * @dev    Returns the M Token balance of `account_`.
     * @param  account_ The account being queried.
     * @return balance_ The M Token balance of the account.
     */
    function _mBalanceOf(address account_) internal view virtual returns (uint240 balance_) {
        // NOTE: M Token balance are limited to `uint240`.
        return uint240(IMTokenLike(mToken).balanceOf(account_));
    }

    /**
     * @dev   Reverts if `amount_` is equal to 0.
     * @param amount_ Amount of token.
     */
    function _revertIfInsufficientAmount(uint256 amount_) internal pure {
        if (amount_ == 0) revert InsufficientAmount(amount_);
    }

    /**
     * @dev   Reverts if `account_` is address(0).
     * @param account_ Address of an account.
     */
    function _revertIfInvalidRecipient(address account_) internal pure {
        if (account_ == address(0)) revert InvalidRecipient(account_);
    }

    /* ============ Before/After Hooks ============ */

    function _beforeMint(address recipient_, uint240 amount_) internal virtual {
        _revertIfInsufficientAmount(amount_);
        _revertIfInvalidRecipient(recipient_);
    }

    function _afterMint(address recipient_, uint240 amount_) internal virtual {}

    function _beforeBurn(address account_, uint240 amount_) internal virtual {
        _revertIfInsufficientAmount(amount_);
    }

    function _afterBurn(address account_, uint240 amount_) internal virtual {}

    function _beforeClaim(address account_, uint128 currentIndex_) internal virtual {}

    function _afterClaim(address account_, uint240 yield_, uint128 currentIndex_) internal virtual {}

    function _beforeTransfer(address sender_, address recipient_, uint240 amount_) internal virtual {}

    function _afterTransfer(address sender_, address recipient_, uint240 amount_) internal virtual {}

    function _beforeWrap(address account_, address recipient_, uint240 amount_) internal virtual {}

    function _afterWrap(address account_, address recipient_, uint240 amount_) internal virtual {}

    function _beforeUnwrap(address account_, address recipient_, uint240 amount_) internal virtual {}

    function _afterUnwrap(address account_, address recipient_, uint240 amount_) internal virtual {}

    function _beforeStartEarning(address account_, uint128 currentIndex_) internal virtual {}

    function _afterStartEarning(address account_, uint128 currentIndex_) internal virtual {}

    function _beforeStopEarning(address account_, uint128 currentIndex_) internal virtual {}

    function _afterStopEarning(address account_, uint128 currentIndex_) internal virtual {}
}
