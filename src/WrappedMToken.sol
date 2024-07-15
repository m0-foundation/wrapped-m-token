// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IndexingMath } from "./libs/IndexingMath.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IWrappedMToken } from "./interfaces/IWrappedMToken.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";

import { Migratable } from "./Migratable.sol";

contract WrappedMToken is IWrappedMToken, Migratable, ERC20Extended {
    type BalanceInfo is uint256;

    /* ============ Variables ============ */

    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _EARNERS_LIST_IGNORED = "earners_list_ignored";
    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _CLAIM_OVERRIDE_RECIPIENT_PREFIX = "wm_claim_override_recipient";
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "wm_migrator_v1";

    address public immutable migrationAdmin;
    address public immutable mToken;
    address public immutable registrar;
    address public immutable vault;

    uint112 internal _principalOfTotalEarningSupply;
    uint128 internal _indexOfTotalEarningSupply;

    uint240 public totalNonEarningSupply;

    mapping(address account => BalanceInfo balance) internal _balances;

    uint128[] internal _enableDisableEarningIndices;

    /* ============ Constructor ============ */

    constructor(address mToken_, address migrationAdmin_) ERC20Extended("WrappedM by M^0", "wM", 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();

        registrar = IMTokenLike(mToken_).ttgRegistrar();
        vault = IRegistrarLike(registrar).vault();

        if ((migrationAdmin = migrationAdmin_) == address(0)) revert ZeroMigrationAdmin();
    }

    /* ============ Interactive Functions ============ */

    function wrap(address recipient_, uint256 amount_) external {
        _mint(recipient_, UIntMath.safe240(amount_));

        IMTokenLike(mToken).transferFrom(msg.sender, address(this), amount_);
    }

    function unwrap(address recipient_, uint256 amount_) external {
        _burn(msg.sender, UIntMath.safe240(amount_));

        IMTokenLike(mToken).transfer(recipient_, amount_);
    }

    function claimFor(address account_) external returns (uint240 yield_) {
        return _claim(account_, currentIndex());
    }

    function claimExcess() external returns (uint240 yield_) {
        emit ExcessClaimed(yield_ = excess());

        IMTokenLike(mToken).transfer(vault, yield_);
    }

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

    function disableEarning() external {
        _revertIfApprovedEarner(address(this));

        if (!isEarningEnabled()) revert EarningIsDisabled();

        uint128 currentMIndex_ = _currentMIndex();

        _enableDisableEarningIndices.push(currentMIndex_);

        IMTokenLike(mToken).stopEarning();

        emit EarningDisabled(currentMIndex_);
    }

    function startEarningFor(address account_) external {
        _revertIfNotApprovedEarner(account_);

        if (!isEarningEnabled()) revert EarningIsDisabled();

        (bool isEarning_, , , uint240 balance_) = _getBalanceInfo(account_);

        if (isEarning_) return;

        emit StartedEarning(account_);

        uint128 currentIndex_ = currentIndex();

        _setBalanceInfo(account_, true, currentIndex_, balance_);
        _addTotalEarningSupply(balance_, currentIndex_);

        unchecked {
            totalNonEarningSupply -= balance_;
        }
    }

    function stopEarningFor(address account_) external {
        _revertIfApprovedEarner(account_);

        uint128 currentIndex_ = currentIndex();

        _claim(account_, currentIndex_);

        (bool isEarning_, , , uint240 balance_) = _getBalanceInfo(account_);

        if (!isEarning_) return;

        emit StoppedEarning(account_);

        _setBalanceInfo(account_, false, 0, balance_);
        _subtractTotalEarningSupply(balance_, currentIndex_);

        unchecked {
            totalNonEarningSupply += balance_;
        }
    }

    /* ============ Temporary Admin Migration ============ */

    function migrate(address migrator_) external {
        if (msg.sender != migrationAdmin) revert UnauthorizedMigration();

        _migrate(migrator_);
    }

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account_) external view returns (uint240 yield_) {
        (bool isEarning_, , uint112 principal_, uint240 balance_) = _getBalanceInfo(account_);

        if (!isEarning_) return 0;

        uint128 currentIndex_ = currentIndex();

        // NOTE: Since `_claim` computes the balance including yield, updates the account by recomputing an account
        //       principal at the current index, then fetches the balance again in order to be maximally conservative,
        //       This function needs to match the math in order to provide a consistent view of the accrued yield.
        uint240 balanceIncludingAccruedYield_ = IndexingMath.getPresentAmountRoundedDown(
            IndexingMath.getPrincipalAmountRoundedDown(
                IndexingMath.getPresentAmountRoundedDown(principal_, currentIndex_),
                currentIndex_
            ),
            currentIndex_
        );

        return balanceIncludingAccruedYield_ > balance_ ? balanceIncludingAccruedYield_ - balance_ : 0;
    }

    function balanceOf(address account_) external view returns (uint256 balance_) {
        (, , , balance_) = _getBalanceInfo(account_);
    }

    function currentIndex() public view returns (uint128 index_) {
        return isEarningEnabled() ? _currentMIndex() : _lastDisableEarningIndex();
    }

    function isEarning(address account_) external view returns (bool isEarning_) {
        (isEarning_, , , ) = _getBalanceInfo(account_);
    }

    function isEarningEnabled() public view returns (bool isEnabled_) {
        return _enableDisableEarningIndices.length % 2 == 1;
    }

    function wasEarningEnabled() public view returns (bool wasEarning_) {
        return _enableDisableEarningIndices.length != 0;
    }

    function excess() public view returns (uint240 yield_) {
        unchecked {
            uint240 balance_ = uint240(IMTokenLike(mToken).balanceOf(address(this)));
            uint240 earmarked_ = uint240(totalSupply()) + totalAccruedYield();
            return balance_ > earmarked_ ? balance_ - earmarked_ : 0;
        }
    }

    function totalAccruedYield() public view returns (uint240 yield_) {
        return _getTotalAccruedYield(currentIndex());
    }

    function totalEarningSupply() public view returns (uint240 totalSupply_) {
        return IndexingMath.getPresentAmountRoundedUp(_principalOfTotalEarningSupply, _indexOfTotalEarningSupply);
    }

    function totalSupply() public view returns (uint256 totalSupply_) {
        return totalEarningSupply() + totalNonEarningSupply;
    }

    /* ============ Internal Interactive Functions ============ */

    function _mint(address recipient_, uint240 amount_) internal {
        _revertIfInsufficientAmount(amount_);
        _revertIfInvalidRecipient(recipient_);

        emit Transfer(address(0), recipient_, amount_);

        (bool isEarning_, , , ) = _getBalanceInfo(recipient_);

        if (!isEarning_) return _addNonEarningAmount(recipient_, amount_);

        uint128 currentIndex_ = currentIndex();

        _claim(recipient_, currentIndex_);

        // NOTE: Additional principal may end up being rounded to 0 and this will not `_revertIfInsufficientAmount`.
        _addEarningAmount(recipient_, amount_, currentIndex_);
    }

    function _burn(address account_, uint240 amount_) internal {
        _revertIfInsufficientAmount(amount_);

        emit Transfer(msg.sender, address(0), amount_);

        (bool isEarning_, , , ) = _getBalanceInfo(account_);

        if (!isEarning_) return _subtractNonEarningAmount(account_, amount_);

        uint128 currentIndex_ = currentIndex();

        _claim(account_, currentIndex_);

        // NOTE: Subtracted principal may end up being rounded to 0 and this will not `_revertIfInsufficientAmount`.
        _subtractEarningAmount(account_, amount_, currentIndex_);
    }

    function _addNonEarningAmount(address account_, uint240 amount_) internal {
        unchecked {
            (, , , uint240 balance_) = _getBalanceInfo(account_);
            _setBalanceInfo(account_, false, 0, balance_ + amount_);
            totalNonEarningSupply += amount_;
        }
    }

    function _subtractNonEarningAmount(address account_, uint240 amount_) internal {
        unchecked {
            (, , , uint240 balance_) = _getBalanceInfo(account_);

            if (balance_ < amount_) revert InsufficientBalance(account_, balance_, amount_);

            _setBalanceInfo(account_, false, 0, balance_ - amount_);
            totalNonEarningSupply -= amount_;
        }
    }

    function _addEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
        unchecked {
            (, , , uint240 balance_) = _getBalanceInfo(account_);

            _setBalanceInfo(account_, true, currentIndex_, balance_ + amount_);
            _addTotalEarningSupply(amount_, currentIndex_);
        }
    }

    function _subtractEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
        unchecked {
            (, , , uint240 balance_) = _getBalanceInfo(account_);

            if (balance_ < amount_) revert InsufficientBalance(account_, balance_, amount_);

            _setBalanceInfo(account_, true, currentIndex_, balance_ - amount_);
            _subtractTotalEarningSupply(amount_, currentIndex_);
        }
    }

    function _claim(address account_, uint128 currentIndex_) internal returns (uint240 yield_) {
        (bool isEarner_, uint128 index_, uint112 principal_, uint240 startingBalance_) = _getBalanceInfo(account_);

        if (!isEarner_) return 0;

        if (currentIndex_ == index_) return 0;

        _setBalanceInfo(
            account_,
            true,
            currentIndex_,
            IndexingMath.getPresentAmountRoundedDown(principal_, currentIndex_)
        );

        // NOTE: Need to get `endingBalance_` from `_getBalanceInfo` since the true balance is the result of rounding
        //       down while dividing to a principal amount in `_setBalanceInfo` and then rounding down while multiplying
        //       to a present amount in `_getBalanceInfo`.
        (, , , uint240 endingBalance_) = _getBalanceInfo(account_);

        unchecked {
            if (endingBalance_ <= startingBalance_) return 0;

            yield_ = endingBalance_ - startingBalance_;

            _setTotalEarningSupply(totalEarningSupply() + yield_, _principalOfTotalEarningSupply);
        }

        emit Transfer(address(0), account_, yield_);

        address claimOverrideRecipient_ = _getClaimOverrideRecipient(account_);

        if (claimOverrideRecipient_ == address(0)) {
            emit Claimed(account_, account_, yield_);
        } else {
            emit Claimed(account_, claimOverrideRecipient_, yield_);

            // NOTE: Watch out for a long chain of earning claim override recipients.
            _transfer(account_, claimOverrideRecipient_, yield_, currentIndex_);
        }
    }

    function _setBalanceInfo(address account_, bool isEarning_, uint128 index_, uint240 amount_) internal {
        _balances[account_] = isEarning_
            ? BalanceInfo.wrap(
                (uint256(1) << 248) |
                    (uint256(index_) << 112) |
                    uint256(IndexingMath.getPrincipalAmountRoundedDown(amount_, index_))
            )
            : BalanceInfo.wrap(uint256(amount_));
    }

    function _transfer(address sender_, address recipient_, uint240 amount_, uint128 currentIndex_) internal {
        _revertIfInvalidRecipient(recipient_);

        _claim(sender_, currentIndex_);
        _claim(recipient_, currentIndex_);

        emit Transfer(sender_, recipient_, amount_);

        (bool senderIsEarning_, , , uint240 senderBalance_) = _getBalanceInfo(sender_);
        (bool recipientIsEarning_, , , uint240 recipientBalance_) = _getBalanceInfo(recipient_);

        if (senderBalance_ < amount_) revert InsufficientBalance(sender_, senderBalance_, amount_);

        if (senderIsEarning_ == recipientIsEarning_) {
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

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        _transfer(sender_, recipient_, UIntMath.safe240(amount_), currentIndex());
    }

    function _addTotalEarningSupply(uint240 amount_, uint128 currentIndex_) internal {
        unchecked {
            uint112 principal_ = IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_);
            _setTotalEarningSupply(totalEarningSupply() + amount_, _principalOfTotalEarningSupply + principal_);
        }
    }

    function _subtractTotalEarningSupply(uint240 amount_, uint128 currentIndex_) internal {
        unchecked {
            uint112 principal_ = IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_);
            _setTotalEarningSupply(totalEarningSupply() - amount_, _principalOfTotalEarningSupply - principal_);
        }
    }

    function _setTotalEarningSupply(uint240 amount_, uint112 principal_) internal {
        _indexOfTotalEarningSupply = (principal_ == 0) ? 0 : IndexingMath.divide240by112Down(amount_, principal_);
        _principalOfTotalEarningSupply = principal_;
    }

    /* ============ Internal View/Pure Functions ============ */

    function _currentMIndex() internal view returns (uint128 index_) {
        return IMTokenLike(mToken).currentIndex();
    }

    function _lastDisableEarningIndex() internal view returns (uint128 index_) {
        return wasEarningEnabled() ? _unsafeAccess(_enableDisableEarningIndices, 1) : 0;
    }

    function _getBalanceInfo(
        address account_
    ) internal view returns (bool isEarning_, uint128 index_, uint112 principal_, uint240 balance_) {
        uint256 unwrapped_ = BalanceInfo.unwrap(_balances[account_]);

        isEarning_ = (unwrapped_ >> 248) != 0;

        if (!isEarning_) return (isEarning_, uint128(0), uint112(0), uint240(unwrapped_));

        index_ = uint128((unwrapped_ << 8) >> 120);
        principal_ = uint112(unwrapped_);
        balance_ = IndexingMath.getPresentAmountRoundedDown(principal_, index_);
    }

    function _getClaimOverrideRecipient(address account_) internal view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        IRegistrarLike(registrar).get(keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_PREFIX, account_)))
                    )
                )
            );
    }

    function _getMigrator() internal view override returns (address migrator_) {
        return
            address(
                uint160(
                    uint256(IRegistrarLike(registrar).get(keccak256(abi.encode(_MIGRATOR_V1_PREFIX, address(this)))))
                )
            );
    }

    function _getTotalAccruedYield(uint128 currentIndex_) internal view returns (uint240 yield_) {
        uint240 projectedEarningSupply_ = IndexingMath.getPresentAmountRoundedUp(
            _principalOfTotalEarningSupply,
            currentIndex_
        );

        uint240 earningSupply_ = totalEarningSupply();

        unchecked {
            return projectedEarningSupply_ <= earningSupply_ ? 0 : projectedEarningSupply_ - earningSupply_;
        }
    }

    function _isApprovedEarner(address account_) internal view returns (bool) {
        return
            IRegistrarLike(registrar).get(_EARNERS_LIST_IGNORED) != bytes32(0) ||
            IRegistrarLike(registrar).listContains(_EARNERS_LIST, account_);
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

    function _revertIfApprovedEarner(address account_) internal view {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner();
    }

    function _revertIfNotApprovedEarner(address account_) internal view {
        if (!_isApprovedEarner(account_)) revert NotApprovedEarner();
    }

    function _unsafeAccess(uint128[] storage indexes_, uint256 i_) internal view returns (uint128 index_) {
        assembly {
            mstore(0, indexes_.slot)

            index_ := sload(add(keccak256(0, 0x20), div(i_, 2)))

            if eq(mod(i_, 2), 1) {
                index_ := shr(128, index_)
            }
        }
    }
}
