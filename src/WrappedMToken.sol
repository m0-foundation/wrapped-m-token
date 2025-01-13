// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IndexingMath } from "../lib/common/src/libs/IndexingMath.sol";
import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";
import { Migratable } from "../lib/common/src/Migratable.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";
import { IWrappedMToken } from "./interfaces/IWrappedMToken.sol";

/*

██╗    ██╗██████╗  █████╗ ██████╗ ██████╗ ███████╗██████╗     ███╗   ███╗    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗
██║    ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗    ████╗ ████║    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║
██║ █╗ ██║██████╔╝███████║██████╔╝██████╔╝█████╗  ██║  ██║    ██╔████╔██║       ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║
██║███╗██║██╔══██╗██╔══██║██╔═══╝ ██╔═══╝ ██╔══╝  ██║  ██║    ██║╚██╔╝██║       ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║
╚███╔███╔╝██║  ██║██║  ██║██║     ██║     ███████╗██████╔╝    ██║ ╚═╝ ██║       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║
 ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝     ╚══════╝╚═════╝     ╚═╝     ╚═╝       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝

*/

/**
 * @title  ERC20 Token contract for wrapping M into a non-rebasing token with claimable yields.
 * @author M^0 Labs
 */
contract WrappedMToken is IWrappedMToken, Migratable, ERC20Extended {
    /* ============ Structs ============ */

    /**
     * @dev   Struct to represent an account's balance and yield earning details.
     * @param isEarning         Whether the account is actively earning yield.
     * @param balance           The present amount of tokens held by the account.
     * @param earningPrincipal  The earning principal for the account.
     * @param hasClaimRecipient Whether the account has an explicitly set claim recipient.
     */
    struct Account {
        // First Slot
        bool isEarning;
        uint240 balance;
        // Second slot
        uint112 earningPrincipal;
        bool hasClaimRecipient;
    }

    /* ============ Variables ============ */

    /// @inheritdoc IWrappedMToken
    bytes32 public constant EARNERS_LIST_IGNORED_KEY = "earners_list_ignored";

    /// @inheritdoc IWrappedMToken
    bytes32 public constant EARNERS_LIST_NAME = "earners";

    /// @inheritdoc IWrappedMToken
    bytes32 public constant CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX = "wm_claim_override_recipient";

    /// @inheritdoc IWrappedMToken
    bytes32 public constant MIGRATOR_KEY_PREFIX = "wm_migrator_v2";

    /// @inheritdoc IWrappedMToken
    address public immutable migrationAdmin;

    /// @inheritdoc IWrappedMToken
    address public immutable mToken;

    /// @inheritdoc IWrappedMToken
    address public immutable registrar;

    /// @inheritdoc IWrappedMToken
    address public immutable excessDestination;

    /// @inheritdoc IWrappedMToken
    uint112 public totalEarningPrincipal;

    /// @inheritdoc IWrappedMToken
    int144 public roundingError;

    /// @inheritdoc IWrappedMToken
    uint240 public totalEarningSupply;

    /// @inheritdoc IWrappedMToken
    uint240 public totalNonEarningSupply;

    /// @dev Mapping of accounts to their respective `AccountInfo` structs.
    mapping(address account => Account balance) internal _accounts;

    /// @dev Array of indices at which earning was enabled or disabled.
    uint128[] internal _enableDisableEarningIndices;

    mapping(address account => address claimRecipient) internal _claimRecipients;

    /* ============ Constructor ============ */

    /**
     * @dev   Constructs the contract given an M Token address and migration admin.
     *        Note that a proxy will not need to initialize since there are no mutable storage values affected.
     * @param mToken_            The address of an M Token.
     * @param registrar_         The address of a Registrar.
     * @param excessDestination_ The address of an excess destination.
     * @param migrationAdmin_    The address of a migration admin.
     */
    constructor(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address migrationAdmin_
    ) ERC20Extended("M (Wrapped) by M^0", "wM", 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((registrar = registrar_) == address(0)) revert ZeroRegistrar();
        if ((excessDestination = excessDestination_) == address(0)) revert ZeroExcessDestination();
        if ((migrationAdmin = migrationAdmin_) == address(0)) revert ZeroMigrationAdmin();
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IWrappedMToken
    function wrap(address recipient_, uint256 amount_) external returns (uint240 wrapped_) {
        return _wrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function wrap(address recipient_) external returns (uint240 wrapped_) {
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
    ) external returns (uint240 wrapped_) {
        IMTokenLike(mToken).permit(msg.sender, address(this), amount_, deadline_, v_, r_, s_);

        return _wrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function wrapWithPermit(
        address recipient_,
        uint256 amount_,
        uint256 deadline_,
        bytes memory signature_
    ) external returns (uint240 wrapped_) {
        IMTokenLike(mToken).permit(msg.sender, address(this), amount_, deadline_, signature_);

        return _wrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function unwrap(address recipient_, uint256 amount_) external returns (uint240 unwrapped_) {
        return _unwrap(msg.sender, recipient_, UIntMath.safe240(amount_));
    }

    /// @inheritdoc IWrappedMToken
    function unwrap(address recipient_) external returns (uint240 unwrapped_) {
        return _unwrap(msg.sender, recipient_, uint240(balanceOf(msg.sender)));
    }

    /// @inheritdoc IWrappedMToken
    function claimFor(address account_) external returns (uint240 yield_) {
        return _claim(account_, currentIndex());
    }

    /// @inheritdoc IWrappedMToken
    function claimExcess() external returns (uint240 claimed_) {
        int248 excess_ = excess();

        if (excess_ <= 0) revert NoExcess();

        claimed_ = _getSafeTransferableM(address(this), uint240(uint248(excess_)));

        emit ExcessClaimed(claimed_);

        // NOTE: The behavior of `IMTokenLike.transfer` is known, so its return can be ignored.
        IMTokenLike(mToken).transfer(excessDestination, claimed_);
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
        if (!isEarningEnabled()) revert EarningIsDisabled();

        // NOTE: Use `currentIndex()` if/when upgrading to support `startEarningFor` while earning is disabled.
        _startEarningFor(account_, _currentMIndex());
    }

    /// @inheritdoc IWrappedMToken
    function stopEarningFor(address account_) external {
        _stopEarningFor(account_, currentIndex());
    }

    /// @inheritdoc IWrappedMToken
    function setClaimRecipient(address claimRecipient_) external {
        _accounts[msg.sender].hasClaimRecipient = (_claimRecipients[msg.sender] = claimRecipient_) != address(0);

        emit ClaimRecipientSet(msg.sender, claimRecipient_);
    }

    /* ============ Temporary Admin Migration ============ */

    /// @inheritdoc IWrappedMToken
    function migrate(address migrator_) external {
        if (msg.sender != migrationAdmin) revert UnauthorizedMigration();

        _migrate(migrator_);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IWrappedMToken
    function accruedYieldOf(address account_) public view returns (uint240 yield_) {
        Account storage accountInfo_ = _accounts[account_];

        return
            accountInfo_.isEarning
                ? _getAccruedYield(accountInfo_.balance, accountInfo_.earningPrincipal, currentIndex())
                : 0;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account_) public view returns (uint256 balance_) {
        return _accounts[account_].balance;
    }

    /// @inheritdoc IWrappedMToken
    function balanceWithYieldOf(address account_) external view returns (uint256 balance_) {
        unchecked {
            return balanceOf(account_) + accruedYieldOf(account_);
        }
    }

    /// @inheritdoc IWrappedMToken
    function earningPrincipalOf(address account_) external view returns (uint112 earningPrincipal_) {
        return _accounts[account_].earningPrincipal;
    }

    /// @inheritdoc IWrappedMToken
    function claimRecipientFor(address account_) public view returns (address recipient_) {
        if (_accounts[account_].hasClaimRecipient) return _claimRecipients[account_];

        address claimOverrideRecipient_ = address(
            uint160(uint256(_getFromRegistrar(keccak256(abi.encode(CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, account_)))))
        );

        return claimOverrideRecipient_ == address(0) ? account_ : claimOverrideRecipient_;
    }

    /// @inheritdoc IWrappedMToken
    function currentIndex() public view returns (uint128 index_) {
        if (isEarningEnabled()) return _currentMIndex();

        return UIntMath.max128(IndexingMath.EXP_SCALED_ONE, _lastDisableEarningIndex());
    }

    /// @inheritdoc IWrappedMToken
    function isEarning(address account_) external view returns (bool isEarning_) {
        return _accounts[account_].isEarning;
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
    function excess() public view returns (int248 excess_) {
        unchecked {
            int248 earmarked_ = int248(uint248(totalNonEarningSupply + projectedEarningSupply())) + roundingError;
            int248 balance_ = int248(uint248(_mBalanceOf(address(this))));

            return earmarked_ <= 0 ? balance_ : balance_ - earmarked_;
        }
    }

    /// @inheritdoc IWrappedMToken
    function totalAccruedYield() external view returns (uint240 yield_) {
        uint240 projectedEarningSupply_ = projectedEarningSupply();
        uint240 earningSupply_ = totalEarningSupply;

        unchecked {
            return projectedEarningSupply_ <= earningSupply_ ? 0 : projectedEarningSupply_ - earningSupply_;
        }
    }

    /// @inheritdoc IERC20
    function totalSupply() external view returns (uint256 totalSupply_) {
        unchecked {
            return totalEarningSupply + totalNonEarningSupply;
        }
    }

    /// @inheritdoc IWrappedMToken
    function projectedEarningSupply() public view returns (uint240 supply_) {
        return
            UIntMath.max240(
                IndexingMath.getPresentAmountRoundedUp(totalEarningPrincipal, currentIndex()),
                totalEarningSupply
            );
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

        if (_accounts[recipient_].isEarning) {
            // NOTE: Additional principal may end up being rounded to 0 and this will not `_revertIfInsufficientAmount`.
            _addEarningAmount(recipient_, amount_, currentIndex());
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

        if (_accounts[account_].isEarning) {
            // NOTE: Subtracted principal may end up being rounded to 0 and this will not `_revertIfInsufficientAmount`.
            _subtractEarningAmount(account_, amount_, currentIndex());
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
            _accounts[account_].balance += amount_;
            totalNonEarningSupply += amount_;
        }
    }

    /**
     * @dev   Decrements the token balance of `account_` by `amount_`, assuming non-earning status.
     * @param account_ The address whose account balance will be decremented.
     * @param amount_  The present amount of tokens to decrement by.
     */
    function _subtractNonEarningAmount(address account_, uint240 amount_) internal {
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
    function _addEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
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
    function _subtractEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
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
    function _claim(address account_, uint128 currentIndex_) internal returns (uint240 yield_) {
        Account storage accountInfo_ = _accounts[account_];

        if (!accountInfo_.isEarning) return 0;

        uint240 startingBalance_ = accountInfo_.balance;

        yield_ = _getAccruedYield(startingBalance_, accountInfo_.earningPrincipal, currentIndex_);

        if (yield_ == 0) return 0;

        unchecked {
            // Update balance and total earning supply to account for the yield, but the principals have not changed.
            accountInfo_.balance = startingBalance_ + yield_;
            totalEarningSupply += yield_;
        }

        address claimRecipient_ = claimRecipientFor(account_);

        // Emit the appropriate `Claimed` and `Transfer` events, depending on the claim override recipient
        emit Claimed(account_, claimRecipient_, yield_);
        emit Transfer(address(0), account_, yield_);

        if (claimRecipient_ != account_) {
            // NOTE: Watch out for a long chain of earning claim override recipients.
            _transfer(account_, claimRecipient_, yield_, currentIndex_);
        }
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

        emit Transfer(sender_, recipient_, amount_);

        if (amount_ == 0) return;

        Account storage senderInfo_ = _accounts[sender_];
        Account storage recipientInfo_ = _accounts[recipient_];

        bool senderIsEarner_ = senderInfo_.isEarning;
        bool recipientIsEarner_ = recipientInfo_.isEarning;

        if (senderIsEarner_ != recipientIsEarner_) {
            senderIsEarner_
                ? _subtractEarningAmount(sender_, amount_, currentIndex_)
                : _subtractNonEarningAmount(sender_, amount_);

            recipientIsEarner_
                ? _addEarningAmount(recipient_, amount_, currentIndex_)
                : _addNonEarningAmount(recipient_, amount_);

            return;
        }

        uint240 senderBalance_ = senderInfo_.balance;

        if (senderBalance_ < amount_) revert InsufficientBalance(sender_, senderBalance_, amount_);

        if (!senderIsEarner_) {
            unchecked {
                senderInfo_.balance = senderBalance_ - amount_;
                recipientInfo_.balance += amount_;
            }

            return;
        }

        uint112 earningPrincipal_ = senderInfo_.earningPrincipal;

        // `min112` prevents `earningPrincipal` underflow.
        uint112 principal_ = UIntMath.min112(
            IndexingMath.getPrincipalAmountRoundedUp(amount_, currentIndex_),
            earningPrincipal_
        );

        unchecked {
            senderInfo_.balance = senderBalance_ - amount_;
            senderInfo_.earningPrincipal = earningPrincipal_ - principal_;

            recipientInfo_.balance += amount_;
            recipientInfo_.earningPrincipal = UIntMath.safe112(uint256(recipientInfo_.earningPrincipal) + principal_);
        }
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
     * @param amount_    The present amount of tokens to increment total earning supply by.
     * @param principal_ The principal amount of tokens to increment total earning principal by.
     */
    function _addTotalEarningSupply(uint240 amount_, uint112 principal_) internal {
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
    function _subtractTotalEarningSupply(uint240 amount_, uint112 principal_) internal {
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
    function _wrap(address account_, address recipient_, uint240 amount_) internal returns (uint240 wrapped_) {
        _transferFromM(account_, amount_);
        _mint(recipient_, wrapped_ = amount_);
    }

    /**
     * @dev    Unwraps `amount` wM from `account_` into M for `recipient`.
     * @param  account_   The account from which WM is burned.
     * @param  recipient_ The account receiving the withdrawn M.
     * @param  amount_    The amount of wM burned.
     * @return unwrapped_ The amount of M withdrawn.
     */
    function _unwrap(address account_, address recipient_, uint240 amount_) internal returns (uint240 unwrapped_) {
        _burn(account_, amount_);
        _transferM(recipient_, unwrapped_ = amount_);
    }

    /**
     * @dev   Starts earning for `account` if allowed by the Registrar.
     * @param account_      The account to start earning for.
     * @param currentIndex_ The current index.
     */
    function _startEarningFor(address account_, uint128 currentIndex_) internal {
        _revertIfNotApprovedEarner(account_);

        Account storage accountInfo_ = _accounts[account_];

        if (accountInfo_.isEarning) return;

        uint240 balance_ = accountInfo_.balance;
        uint112 earningPrincipal_ = IndexingMath.getPrincipalAmountRoundedDown(balance_, currentIndex_);

        accountInfo_.isEarning = true;
        accountInfo_.earningPrincipal = earningPrincipal_;

        _addTotalEarningSupply(balance_, earningPrincipal_);

        unchecked {
            totalNonEarningSupply -= balance_;
        }

        emit StartedEarning(account_);
    }

    /**
     * @dev   Stops earning for `account` if disallowed by the Registrar.
     * @param account_      The account to stop earning for.
     * @param currentIndex_ The current index.
     */
    function _stopEarningFor(address account_, uint128 currentIndex_) internal {
        _revertIfApprovedEarner(account_);

        _claim(account_, currentIndex_);

        Account storage accountInfo_ = _accounts[account_];

        if (!accountInfo_.isEarning) return;

        uint240 balance_ = accountInfo_.balance;
        uint112 earningPrincipal_ = accountInfo_.earningPrincipal;

        delete accountInfo_.isEarning;
        delete accountInfo_.earningPrincipal;

        _subtractTotalEarningSupply(balance_, earningPrincipal_);

        unchecked {
            totalNonEarningSupply += balance_;
        }

        emit StoppedEarning(account_);
    }

    /**
     * @dev   Transfer `amount_` M to `recipient_`, tracking this contract's M balance rounding errors.
     * @param recipient_ The account to transfer M to.
     * @param amount_    The amount of M to transfer.
     */
    function _transferM(address recipient_, uint240 amount_) internal {
        uint240 startingBalance_ = _mBalanceOf(address(this));

        // NOTE: The behavior of `IMTokenLike.transfer` is known, so its return can be ignored.
        IMTokenLike(mToken).transfer(recipient_, amount_);

        // NOTE: When this WrappedMToken contract is earning, any amount of M sent from it is converted to a principal
        //       amount at the MToken contract, which when represented as a present amount, may be a rounding error
        //       amount more than `amount_`. In order to capture the real decrease in M, the difference between the
        //       ending and starting M balance is returned.
        uint240 decrease_ = startingBalance_ - _mBalanceOf(address(this));

        // If the M lost is more than the wM burned, then the difference is added to `roundingError`.
        roundingError += int144(int256(uint256(decrease_)) - int256(uint256(amount_)));
    }

    /**
     * @dev   Transfer `amount_` M from `sender_`, tracking this contract's M balance rounding errors.
     * @param sender_ The account to transfer M from.
     * @param amount_ The amount of M to transfer.
     */
    function _transferFromM(address sender_, uint240 amount_) internal {
        uint240 startingBalance_ = _mBalanceOf(address(this));

        // NOTE: The behavior of `IMTokenLike.transferFrom` is known, so its return can be ignored.
        IMTokenLike(mToken).transferFrom(sender_, address(this), _getSafeTransferableM(sender_, amount_));

        // NOTE: When this WrappedMToken contract is earning, any amount of M sent to it is converted to a principal
        //       amount at the MToken contract, which when represented as a present amount, may be a rounding error
        //       amount less than `amount_`. In order to capture the real increase in M, the difference between the
        //       starting and ending M balance is minted as WrappedM token.
        uint240 increase_ = _mBalanceOf(address(this)) - startingBalance_;

        // If the M gained is less than the wM minted, then the difference is added to `roundingError`.
        roundingError += int144(int256(uint256(amount_)) - int256(uint256(increase_)));
    }

    /* ============ Internal View/Pure Functions ============ */

    /// @dev Returns the current index of the M Token.
    function _currentMIndex() internal view returns (uint128 index_) {
        return IMTokenLike(mToken).currentIndex();
    }

    /// @dev Returns the earning index from the last `disableEarning` call.
    function _lastDisableEarningIndex() internal view returns (uint128 index_) {
        return wasEarningEnabled() ? _unsafeAccess(_enableDisableEarningIndices, 1) : 0;
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
    ) internal pure returns (uint240 yield_) {
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
    function _getFromRegistrar(bytes32 key_) internal view returns (bytes32 value_) {
        return IRegistrarLike(registrar).get(key_);
    }

    /**
     * @dev    Compute the adjusted amount of M that can safely be transferred out given the current index.
     * @param  amount_     Some amount to be transferred out of this contract.
     * @return safeAmount_ The adjusted amount that can safely be transferred out.
     */
    function _getSafeTransferableM(address sender_, uint240 amount_) internal view returns (uint240 safeAmount_) {
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

    /// @dev Returns the address of the contract to use as a migrator, if any.
    function _getMigrator() internal view override returns (address migrator_) {
        return
            address(
                uint160(
                    // NOTE: A subsequent implementation should use a unique migrator prefix.
                    uint256(_getFromRegistrar(keccak256(abi.encode(MIGRATOR_KEY_PREFIX, address(this)))))
                )
            );
    }

    /**
     * @dev    Returns whether `account_` is a Registrar-approved earner.
     * @param  account_    The account being queried.
     * @return isApproved_ True if the account_ is a Registrar-approved earner, false otherwise.
     */
    function _isApprovedEarner(address account_) internal view returns (bool isApproved_) {
        return
            _getFromRegistrar(EARNERS_LIST_IGNORED_KEY) != bytes32(0) ||
            IRegistrarLike(registrar).listContains(EARNERS_LIST_NAME, account_);
    }

    /**
     * @dev    Returns the M Token balance of `account_`.
     * @param  account_ The account being queried.
     * @return balance_ The M Token balance of the account.
     */
    function _mBalanceOf(address account_) internal view returns (uint240 balance_) {
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

    /**
     * @dev   Reverts if `account_` is an approved earner.
     * @param account_ Address of an account.
     */
    function _revertIfApprovedEarner(address account_) internal view {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner(account_);
    }

    /**
     * @dev   Reverts if `account_` is not an approved earner.
     * @param account_ Address of an account.
     */
    function _revertIfNotApprovedEarner(address account_) internal view {
        if (!_isApprovedEarner(account_)) revert NotApprovedEarner(account_);
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
