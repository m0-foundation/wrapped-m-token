// SPDX-License-Identifier: GPL-3.0

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

    address public immutable mToken;
    address public immutable registrar;
    address public immutable vault;

    uint112 internal _principalOfTotalEarningSupply;
    uint128 internal _indexOfTotalEarningSupply;

    uint240 public totalNonEarningSupply;

    mapping(address account => BalanceInfo balance) internal _balances;

    /* ============ Constructor ============ */

    constructor(address mToken_) ERC20Extended("WrappedM by M^0", "wM", 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();

        registrar = IMTokenLike(mToken_).ttgRegistrar();
        vault = IRegistrarLike(registrar).vault();
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

    function startEarningFor(address account_) external {
        if (!_isApprovedEarner(account_)) revert NotApprovedEarner();

        (bool isEarning_, , uint240 rawBalance_) = _getBalanceInfo(account_);

        if (isEarning_) return;

        emit StartedEarning(account_);

        uint128 currentIndex_ = currentIndex();
        uint112 principalAmount_ = IndexingMath.getPrincipalAmountRoundedDown(rawBalance_, currentIndex_);

        _setBalanceInfo(account_, true, currentIndex_, principalAmount_);

        unchecked {
            totalNonEarningSupply -= rawBalance_;
        }

        _addTotalEarningSupply(rawBalance_, currentIndex_);
    }

    function stopEarningFor(address account_) external {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner();

        (bool isEarning_, , ) = _getBalanceInfo(account_);

        if (!isEarning_) return;

        emit StoppedEarning(account_);

        uint128 currentIndex_ = currentIndex();

        _claim(account_, currentIndex_);

        (, uint128 index_, uint256 rawBalance_) = _getBalanceInfo(account_);

        uint240 amount_ = IndexingMath.getPresentAmountRoundedDown(uint112(rawBalance_), index_);

        _setBalanceInfo(account_, false, 0, amount_);

        unchecked {
            totalNonEarningSupply += amount_;
        }

        _subtractTotalEarningSupply(amount_, currentIndex_);
    }

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account_) external view returns (uint240 yield_) {
        (bool isEarning_, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);

        return isEarning_ ? _getAccruedYield(uint112(rawBalance_), index_, currentIndex()) : 0;
    }

    function balanceOf(address account_) external view returns (uint256 balance_) {
        (bool isEarning_, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);

        return isEarning_ ? IndexingMath.getPresentAmountRoundedDown(uint112(rawBalance_), index_) : rawBalance_;
    }

    function currentIndex() public view returns (uint128 index_) {
        return IMTokenLike(mToken).currentIndex();
    }

    function isEarning(address account_) external view returns (bool isEarning_) {
        (isEarning_, , ) = _getBalanceInfo(account_);
    }

    function excess() public view returns (uint240 yield_) {
        uint240 balance_ = uint240(IMTokenLike(mToken).balanceOf(address(this)));
        uint240 earmarked_ = uint240(totalSupply()) + totalAccruedYield();

        unchecked {
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

        (bool isEarning_, , ) = _getBalanceInfo(recipient_);

        if (!isEarning_) return _addNonEarningAmount(recipient_, amount_);

        uint128 currentIndex_ = currentIndex();

        _claim(recipient_, currentIndex_);

        // TODO: Technically, might want to `_revertIfInsufficientAmount` if earning principal is 0.
        _addEarningAmount(recipient_, amount_, currentIndex_);
    }

    function _burn(address account_, uint240 amount_) internal {
        _revertIfInsufficientAmount(amount_);

        emit Transfer(msg.sender, address(0), amount_);

        (bool isEarning_, , ) = _getBalanceInfo(account_);

        if (!isEarning_) return _subtractNonEarningAmount(account_, amount_);

        uint128 currentIndex_ = currentIndex();

        _claim(account_, currentIndex_);

        // TODO: Technically, might want to `_revertIfInsufficientAmount` if earning principal is 0.
        _subtractEarningAmount(account_, amount_, currentIndex_);
    }

    function _addNonEarningAmount(address recipient_, uint240 amount_) internal {
        (, , uint240 rawBalance_) = _getBalanceInfo(recipient_);

        unchecked {
            _setBalanceInfo(recipient_, false, 0, rawBalance_ + amount_);
            totalNonEarningSupply += amount_;
        }
    }

    function _subtractNonEarningAmount(address account_, uint240 amount_) internal {
        (, , uint240 rawBalance_) = _getBalanceInfo(account_);

        if (rawBalance_ < amount_) revert InsufficientBalance(account_, rawBalance_, amount_);

        unchecked {
            _setBalanceInfo(account_, false, 0, rawBalance_ - amount_);
            totalNonEarningSupply -= amount_;
        }
    }

    function _addEarningAmount(address recipient_, uint240 amount_, uint128 currentIndex_) internal {
        (, , uint240 rawBalance_) = _getBalanceInfo(recipient_);

        uint112 principalAmount_ = IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_);

        unchecked {
            _setBalanceInfo(recipient_, true, currentIndex_, rawBalance_ + principalAmount_);
        }

        _addTotalEarningSupply(amount_, currentIndex_);
    }

    function _subtractEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
        (, , uint240 rawBalance_) = _getBalanceInfo(account_);

        uint112 principalAmount_ = IndexingMath.getPrincipalAmountRoundedUp(amount_, currentIndex_);

        if (rawBalance_ < principalAmount_) revert InsufficientBalance(account_, rawBalance_, principalAmount_);

        unchecked {
            _setBalanceInfo(account_, true, currentIndex_, rawBalance_ - principalAmount_);
            _subtractTotalEarningSupply(amount_, currentIndex_);
        }
    }

    function _claim(address account_, uint128 currentIndex_) internal returns (uint240 yield_) {
        (bool isEarner_, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);

        if (!isEarner_) return 0;

        yield_ = _getAccruedYield(uint112(rawBalance_), index_, currentIndex_);
        _setBalanceInfo(account_, true, currentIndex_, rawBalance_);

        if (yield_ == 0) return 0;

        unchecked {
            _setTotalEarningSupply(totalEarningSupply() + yield_, _principalOfTotalEarningSupply);
        }

        address claimOverrideRecipient_ = _getClaimOverrideRecipient(account_);

        if (claimOverrideRecipient_ == address(0)) {
            emit Claimed(account_, account_, yield_);
            emit Transfer(address(0), account_, yield_);
        } else {
            emit Claimed(account_, claimOverrideRecipient_, yield_);

            // NOTE: Watch out for a long chain of claim override recipients.
            // TODO: Maybe can be optimized since we know `account_` is an earner and already claimed.
            _transfer(account_, claimOverrideRecipient_, yield_, currentIndex_);
        }
    }

    function _setBalanceInfo(address account_, bool isEarning_, uint128 index_, uint240 amount_) internal {
        _balances[account_] = isEarning_
            ? BalanceInfo.wrap((uint256(1) << 248) | (uint256(index_) << 112) | uint256(amount_))
            : BalanceInfo.wrap(uint256(amount_));
    }

    function _transfer(address sender_, address recipient_, uint240 amount_, uint128 currentIndex_) internal {
        _revertIfInvalidRecipient(recipient_);

        _claim(sender_, currentIndex_);
        _claim(recipient_, currentIndex_);

        emit Transfer(sender_, recipient_, amount_);

        (bool senderIsEarning_, , ) = _getBalanceInfo(sender_);
        (bool recipientIsEarning_, , ) = _getBalanceInfo(recipient_);

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
        uint112 principalAmount_ = IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_);

        unchecked {
            _setTotalEarningSupply(totalEarningSupply() + amount_, _principalOfTotalEarningSupply + principalAmount_);
        }
    }

    function _subtractTotalEarningSupply(uint240 amount_, uint128 currentIndex_) internal {
        // TODO: Consider `getPrincipalAmountRoundedUp` .
        uint112 principalAmount_ = IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_);

        unchecked {
            _setTotalEarningSupply(totalEarningSupply() - amount_, _principalOfTotalEarningSupply - principalAmount_);
        }
    }

    function _setTotalEarningSupply(uint240 amount_, uint112 principalAmount_) internal {
        _indexOfTotalEarningSupply = principalAmount_ == 0
            ? 0
            : IndexingMath.divide240by112Down(amount_, principalAmount_);

        _principalOfTotalEarningSupply = principalAmount_;
    }

    /* ============ Internal View/Pure Functions ============ */

    function _getAccruedYield(
        uint112 principalAmount_,
        uint128 index_,
        uint128 currentIndex_
    ) internal pure returns (uint240) {
        unchecked {
            return
                currentIndex_ <= index_
                    ? 0
                    : IndexingMath.getPresentAmountRoundedDown(principalAmount_, currentIndex_ - index_);
        }
    }

    function _getBalanceInfo(
        address account_
    ) internal view returns (bool isEarning_, uint128 index_, uint240 rawBalance_) {
        uint256 unwrapped_ = BalanceInfo.unwrap(_balances[account_]);

        return
            (unwrapped_ >> 248) != 0
                ? (true, uint128((unwrapped_ << 8) >> 120), uint112(unwrapped_))
                : (false, uint128(0), uint240(unwrapped_));
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
        uint240 totalProjectedSupply_ = IndexingMath.getPresentAmountRoundedUp(
            _principalOfTotalEarningSupply,
            currentIndex_
        );

        uint240 totalEarningSupply_ = totalEarningSupply();

        unchecked {
            return totalProjectedSupply_ <= totalEarningSupply_ ? 0 : totalProjectedSupply_ - totalEarningSupply_;
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
}
