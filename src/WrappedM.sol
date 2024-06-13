// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IWrappedM } from "./interfaces/IWrappedM.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";

contract WrappedM is IWrappedM, ERC20Extended {
    type BalanceInfo is uint256;

    /* ============ Variables ============ */

    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _EARNERS_LIST_IGNORED = "earners_list_ignored";
    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _CLAIM_DESTINATION_PREFIX = "claim_destination";

    address public immutable mToken;
    address public immutable registrar;

    uint112 public principalOfTotalEarningSupply;
    uint128 public indexOfTotalEarningSupply;

    uint240 public totalNonEarningSupply;

    mapping(address account => BalanceInfo balance) internal _balances;

    /* ============ Constructor ============ */

    constructor(address mToken_, address registrar_) ERC20Extended("WrappedM by M^0", "wM", 6) {
        mToken = mToken_;
        registrar = registrar_;
        indexOfTotalEarningSupply = currentMIndex();
    }

    /* ============ Interactive Functions ============ */

    function claim() external returns (uint240 yield_) {
        return _claim(msg.sender, currentMIndex());
    }

    function claimExcess() external returns (uint240 yield_) {
        emit ExcessClaim(yield_ = excess());

        IMTokenLike(mToken).transfer(IRegistrarLike(registrar).vault(), yield_);
    }

    function deposit(address destination_, uint256 amount_) external {
        emit Transfer(address(0), destination_, amount_);

        _addAmount(destination_, UIntMath.safe240(amount_));

        IMTokenLike(mToken).transferFrom(msg.sender, address(this), amount_);
    }

    function startEarning(address account_) external {
        if (!_isApprovedEarner(account_)) revert NotApprovedEarner();

        (bool isEarning_, , uint240 rawBalance_) = _getBalanceInfo(account_);

        if (isEarning_) return;

        emit StartEarning(account_);

        uint128 currentIndex_ = currentMIndex();

        _setBalanceInfo(account_, true, currentIndex_, _getPrincipalAmountRoundedDown(rawBalance_, currentIndex_));

        totalNonEarningSupply -= rawBalance_;

        _updateTotalEarningSupply(
            totalEarningSupply() + rawBalance_,
            _getTotalAccruedYield(currentIndex_),
            currentIndex_
        );
    }

    function stopEarning(address account_) external {
        if (_isApprovedEarner(account_)) revert ApprovedEarner();

        (bool isEarning_, , ) = _getBalanceInfo(account_);

        if (!isEarning_) return;

        emit StopEarning(account_);

        uint128 currentIndex_ = currentMIndex();

        _claim(account_, currentIndex_);

        (, uint128 index_, uint256 rawBalance_) = _getBalanceInfo(account_);

        uint240 amount_ = _getPresentAmountRoundedDown(uint112(rawBalance_), index_);

        _setBalanceInfo(account_, false, 0, amount_);
        totalNonEarningSupply += amount_;

        _updateTotalEarningSupply(totalEarningSupply() - amount_, _getTotalAccruedYield(currentIndex_), currentIndex_);
    }

    function withdraw(address destination_, uint256 amount_) external {
        emit Transfer(msg.sender, address(0), amount_);

        _subtractAmount(msg.sender, UIntMath.safe240(amount_));

        IMTokenLike(mToken).transfer(destination_, amount_);
    }

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account_) external view returns (uint240 yield_) {
        (bool isEarning_, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);

        return isEarning_ ? _getAccruedYield(uint112(rawBalance_), index_, currentMIndex()) : 0;
    }

    function balanceOf(address account_) external view returns (uint256 balance_) {
        (bool isEarning_, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);

        return isEarning_ ? _getPresentAmountRoundedDown(uint112(rawBalance_), index_) : rawBalance_;
    }

    function currentMIndex() public view returns (uint128 index_) {
        return IMTokenLike(mToken).currentIndex();
    }

    function excess() public view returns (uint240 yield_) {
        uint240 balance_ = uint240(IMTokenLike(mToken).balanceOf(address(this)));
        uint240 earmarked_ = uint240(totalSupply()) + totalAccruedYield();

        return balance_ > earmarked_ ? balance_ - earmarked_ : 0;
    }

    function totalAccruedYield() public view returns (uint240 yield_) {
        return _getTotalAccruedYield(currentMIndex());
    }

    function totalEarningSupply() public view returns (uint240 totalSupply_) {
        return _getPresentAmountRoundedUp(principalOfTotalEarningSupply, indexOfTotalEarningSupply);
    }

    function totalSupply() public view returns (uint256 totalSupply_) {
        return totalEarningSupply() + totalNonEarningSupply;
    }

    /* ============ Internal Interactive Functions ============ */

    function _addAmount(address recipient_, uint240 amount_) internal {
        (bool isEarning_, , ) = _getBalanceInfo(recipient_);

        if (!isEarning_) return _addNonEarningAmount(recipient_, amount_);

        uint128 currentIndex_ = currentMIndex();

        _claim(recipient_, currentIndex_);
        _addEarningAmount(recipient_, amount_, currentIndex_);
    }

    function _addNonEarningAmount(address recipient_, uint240 amount_) internal {
        (, , uint240 rawBalance_) = _getBalanceInfo(recipient_);
        _setBalanceInfo(recipient_, false, 0, rawBalance_ + amount_);
        totalNonEarningSupply += amount_;
    }

    function _addEarningAmount(address recipient_, uint240 amount_, uint128 currentIndex_) internal {
        (, , uint240 rawBalance_) = _getBalanceInfo(recipient_);

        _setBalanceInfo(
            recipient_,
            true,
            currentIndex_,
            rawBalance_ + _getPrincipalAmountRoundedDown(amount_, currentIndex_)
        );

        _updateTotalEarningSupply(totalEarningSupply() + amount_, _getTotalAccruedYield(currentIndex_), currentIndex_);
    }

    function _claim(address account_, uint128 currentIndex_) internal returns (uint240 yield_) {
        (bool isEarner_, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);

        if (!isEarner_) return 0;

        yield_ = _getAccruedYield(uint112(rawBalance_), index_, currentIndex_);
        _setBalanceInfo(account_, true, currentIndex_, rawBalance_);

        if (yield_ == 0) return 0;

        emit Claim(account_, yield_);
        emit Transfer(address(0), account_, yield_);

        _updateTotalEarningSupply(
            totalEarningSupply() + yield_,
            _getTotalAccruedYield(currentIndex_) - yield_,
            currentIndex_
        );

        address claimOverrideDestination_ = _getClaimOverrideDestination(account_);

        if (claimOverrideDestination_ == address(0)) return yield_;

        // NOTE: Watch out for a long chain of claim override destinations.
        // TODO: Maybe can be optimized since we know `account_` is an earner and already claimed.
        _transfer(account_, claimOverrideDestination_, yield_, currentIndex_);
    }

    function _setBalanceInfo(address account_, bool isEarning_, uint256 index_, uint256 amount_) internal {
        _balances[account_] = isEarning_
            ? BalanceInfo.wrap((1 << 248) | (index_ << 112) | amount_)
            : BalanceInfo.wrap(amount_);
    }

    function _subtractAmount(address account_, uint240 amount_) internal {
        (bool isEarning_, , ) = _getBalanceInfo(account_);

        if (!isEarning_) return _subtractNonEarningAmount(account_, amount_);

        uint128 currentIndex_ = currentMIndex();

        _claim(account_, currentIndex_);
        _subtractEarningAmount(account_, amount_, currentIndex_);
    }

    function _subtractNonEarningAmount(address account_, uint240 amount_) internal {
        (, , uint240 rawBalance_) = _getBalanceInfo(account_);
        _setBalanceInfo(account_, false, 0, rawBalance_ - amount_);
        totalNonEarningSupply -= amount_;
    }

    function _subtractEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
        (, , uint240 rawBalance_) = _getBalanceInfo(account_);

        _setBalanceInfo(
            account_,
            true,
            currentIndex_,
            rawBalance_ - _getPrincipalAmountRoundedUp(amount_, currentIndex_)
        );

        _updateTotalEarningSupply(totalEarningSupply() - amount_, _getTotalAccruedYield(currentIndex_), currentIndex_);
    }

    function _transfer(address sender_, address recipient_, uint240 amount_, uint128 currentIndex_) internal {
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
        _transfer(sender_, recipient_, UIntMath.safe240(amount_), currentMIndex());
    }

    function _updateTotalEarningSupply(
        uint240 totalEarningSupply_,
        uint240 totalAccruedYield_,
        uint128 currentIndex_
    ) internal {
        uint128 accrualIndex_ = _getAccrualIndex(totalAccruedYield_, totalEarningSupply_, currentIndex_);

        principalOfTotalEarningSupply = _getPrincipalAmountRoundedDown(totalEarningSupply_, accrualIndex_);
        indexOfTotalEarningSupply = accrualIndex_;
    }

    /* ============ Internal View/Pure Functions ============ */

    function _divide240By128Down(uint240 x_, uint128 y_) internal pure returns (uint112) {
        if (y_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe112((uint256(x_) * _EXP_SCALED_ONE) / y_);
        }
    }

    function _divide240by240Down(uint240 x_, uint240 y_) internal pure returns (uint128) {
        if (y_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe128((uint256(x_) * _EXP_SCALED_ONE) / y_);
        }
    }

    function _divide240By128Up(uint240 x, uint128 y_) internal pure returns (uint112) {
        if (y_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe112(((uint256(x) * _EXP_SCALED_ONE) + y_ - 1) / y_);
        }
    }

    function _getAccrualIndex(uint240 yield_, uint240 amount_, uint128 currentIndex_) internal pure returns (uint128) {
        return
            yield_ == 0
                ? currentIndex_
                : _multiply128By128Down(currentIndex_, _divide240by240Down(amount_, yield_ + amount_));
    }

    function _getAccruedYield(
        uint112 principalAmount_,
        uint128 index_,
        uint128 currentIndex_
    ) internal pure returns (uint240) {
        return _getPresentAmountRoundedDown(principalAmount_, currentIndex_ - index_);
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

    function _getClaimOverrideDestination(address account_) internal view returns (address) {
        return
            address(
                uint160(
                    uint256(IRegistrarLike(registrar).get(keccak256(abi.encode(_CLAIM_DESTINATION_PREFIX, account_))))
                )
            );
    }

    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return _multiply112By128Down(principalAmount_, index_);
    }

    function _getPresentAmountRoundedUp(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return _multiply112By128Up(principalAmount_, index_);
    }

    function _getPrincipalAmountRoundedDown(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return _divide240By128Down(presentAmount_, index_);
    }

    function _getPrincipalAmountRoundedUp(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return _divide240By128Up(presentAmount_, index_);
    }

    function _getTotalAccruedYield(uint128 currentIndex_) internal view returns (uint240 yield_) {
        return _getPresentAmountRoundedUp(principalOfTotalEarningSupply, currentIndex_ - indexOfTotalEarningSupply);
    }

    function _isApprovedEarner(address account_) internal view returns (bool) {
        return
            IRegistrarLike(registrar).get(_EARNERS_LIST_IGNORED) != bytes32(0) ||
            IRegistrarLike(registrar).listContains(_EARNERS_LIST, account_);
    }

    function _multiply112By128Down(uint112 x_, uint128 y_) internal pure returns (uint240) {
        unchecked {
            return UIntMath.safe240((uint256(x_) * y_) / _EXP_SCALED_ONE);
        }
    }

    function _multiply128By128Down(uint128 x_, uint128 y_) internal pure returns (uint128) {
        unchecked {
            return UIntMath.safe128((uint256(x_) * y_) / _EXP_SCALED_ONE);
        }
    }

    function _multiply112By128Up(uint112 x_, uint128 y_) internal pure returns (uint240) {
        unchecked {
            return UIntMath.safe240(((uint256(x_) * y_) + (_EXP_SCALED_ONE - 1)) / _EXP_SCALED_ONE);
        }
    }
}
