// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IWrappedM } from "./interfaces/IWrappedM.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";

contract WrappedM is IWrappedM, ERC20Extended {
    type Balance is uint256;

    /* ============ Variables ============ */

    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _CLAIM_DESTINATION_PREFIX = "claim_destination";

    address public immutable mToken;
    address public immutable registrar;

    uint112 public principalOfTotalEarningSupply;
    uint128 public indexOfTotalEarningSupply;

    uint240 public totalNonEarningSupply;

    mapping(address account => Balance balance) internal _balances;

    /* ============ Modifiers ============ */

    /* ============ Constructor ============ */

    constructor(address mToken_, address registrar_) ERC20Extended("WrappedM by M^0", "wM", 6) {
        mToken = mToken_;
        registrar = registrar_;
        indexOfTotalEarningSupply = currentMIndex();
    }

    /* ============ Interactive Functions ============ */

    function claim() external returns (uint256 yield_) {
        return _claim(msg.sender);
    }

    function claimExcess() external returns (uint256 yield_) {
        IMTokenLike(mToken).transfer(IRegistrarLike(registrar).vault(), yield_ = excess());
    }

    function deposit(address destination_, uint256 amount_) external {
        IMTokenLike(mToken).transferFrom(msg.sender, address(this), amount_);
        _addAmount(destination_, UIntMath.safe240(amount_));
    }

    function withdraw(address destination_, uint256 amount_) external {
        IMTokenLike(mToken).transfer(destination_, amount_);
        _subtractAmount(msg.sender, UIntMath.safe240(amount_));
    }

    function startEarning(address account_) external {
        if (!_isApprovedEarner(account_)) revert NotApprovedEarner();

        _startEarning(account_);
    }

    function stopEarning(address account_) external {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner();

        _stopEarning(account_);
    }

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account_) external view returns (uint256 yield_) {
        return _accruedYield(_balances[account_]);
    }

    function totalAccruedYield() public view returns (uint256 yield_) {
        return _getPresentAmountRoundedUp(principalOfTotalEarningSupply, currentMIndex() - indexOfTotalEarningSupply);
    }

    function excess() public view returns (uint256 yield_) {
        uint256 balance_ = IMTokenLike(mToken).balanceOf(address(this));
        uint256 earmarked_ = totalSupply() + totalAccruedYield();

        return balance_ > earmarked_ ? balance_ - earmarked_ : 0;
    }

    function balanceOf(address account) external view returns (uint256 balance_) {
        (bool isEarning_, uint128 index_, uint256 rawBalance_) = _unwrap(_balances[account]);

        return isEarning_ ? _getPresentAmountRoundedDown(uint112(rawBalance_), index_) : rawBalance_;
    }

    function totalEarningSupply() public view returns (uint256 totalSupply_) {
        return _getPresentAmountRoundedUp(principalOfTotalEarningSupply, indexOfTotalEarningSupply);
    }

    function totalSupply() public view returns (uint256 totalSupply_) {
        return totalEarningSupply() + totalNonEarningSupply;
    }

    function currentMIndex() public view returns (uint128 index_) {
        return IMTokenLike(mToken).currentIndex();
    }

    /* ============ Internal Interactive Functions ============ */

    function _claim(address account_) internal returns (uint240 yield_) {
        (bool isEarner_, uint128 index_, uint256 rawBalance_) = _unwrap(_balances[account_]);

        if (!isEarner_) return 0;

        yield_ = _accruedYield(uint112(rawBalance_), index_);
        _balances[account_] = _wrap(true, currentMIndex(), rawBalance_);

        _updateTotalEarningSupply(uint240(totalEarningSupply() + yield_), uint240(totalAccruedYield() - yield_));

        address claimOverrideDestination_ = _getClaimOverrideDestination(account_);

        if (claimOverrideDestination_ != address(0)) {
            // NOTE: Watch out for a long chain of delegations.
            // TODO: Maybe can be optimized since we know `account_` is an earner and already claimed.
            _transfer(account_, claimOverrideDestination_, yield_);
        }
    }

    function _subtractAmount(address account_, uint240 amount_) internal {
        (bool isEarning_, , ) = _unwrap(_balances[account_]);

        if (isEarning_) {
            _claim(account_);
            _subtractEarningAmount(account_, amount_);
        } else {
            _subtractNonEarningAmount(account_, amount_);
        }
    }

    function _subtractNonEarningAmount(address account_, uint240 amount_) internal {
        (, , uint256 rawBalance_) = _unwrap(_balances[account_]);
        _balances[account_] = _wrap(false, 0, rawBalance_ - amount_);
        totalNonEarningSupply -= amount_;
    }

    function _subtractEarningAmount(address account_, uint240 amount_) internal {
        (, , uint256 rawBalance_) = _unwrap(_balances[account_]);

        _balances[account_] = _wrap(
            true,
            currentMIndex(),
            rawBalance_ - _getPrincipalAmountRoundedUp(amount_, currentMIndex())
        );

        _updateTotalEarningSupply(uint240(totalEarningSupply() - amount_));
    }

    function _addAmount(address recipient_, uint240 amount_) internal {
        (bool isEarning_, , ) = _unwrap(_balances[recipient_]);

        if (isEarning_) {
            _claim(recipient_);
            _addEarningAmount(recipient_, amount_);
        } else {
            _addNonEarningAmount(recipient_, amount_);
        }
    }

    function _addNonEarningAmount(address recipient_, uint240 amount_) internal {
        (, , uint256 rawBalance_) = _unwrap(_balances[recipient_]);
        _balances[recipient_] = _wrap(false, 0, rawBalance_ + amount_);
        totalNonEarningSupply += amount_;
    }

    function _addEarningAmount(address recipient_, uint240 amount_) internal {
        (, , uint256 rawBalance_) = _unwrap(_balances[recipient_]);

        _balances[recipient_] = _wrap(
            true,
            currentMIndex(),
            rawBalance_ + _getPrincipalAmountRoundedDown(amount_, currentMIndex())
        );

        _updateTotalEarningSupply(uint240(totalEarningSupply() + amount_));
    }

    function _startEarning(address account_) internal {
        (bool isEarning_, , uint256 rawBalance_) = _unwrap(_balances[account_]);

        if (isEarning_) return;

        _balances[account_] = _wrap(
            true,
            currentMIndex(),
            _getPrincipalAmountRoundedDown(uint240(rawBalance_), currentMIndex())
        );

        totalNonEarningSupply -= uint240(rawBalance_);

        _updateTotalEarningSupply(uint240(totalEarningSupply() + rawBalance_));
    }

    function _stopEarning(address account_) internal {
        (bool isEarning_, , ) = _unwrap(_balances[account_]);

        if (!isEarning_) return;

        _claim(account_);

        (, uint128 index_, uint256 rawBalance_) = _unwrap(_balances[account_]);

        uint240 amount_ = _getPresentAmountRoundedDown(uint112(rawBalance_), index_);

        _balances[account_] = _wrap(false, 0, amount_);
        totalNonEarningSupply += amount_;

        _updateTotalEarningSupply(uint240(totalEarningSupply() - amount_));
    }

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        _claim(sender_);
        _claim(recipient_);

        uint240 safeAmount_ = UIntMath.safe240(amount_);
        (bool senderIsEarning_, , ) = _unwrap(_balances[sender_]);
        (bool recipientIsEarning_, , ) = _unwrap(_balances[recipient_]);

        if (senderIsEarning_) {
            _subtractEarningAmount(sender_, safeAmount_);
        } else {
            _subtractNonEarningAmount(sender_, safeAmount_);
        }

        if (recipientIsEarning_) {
            _addEarningAmount(recipient_, safeAmount_);
        } else {
            _addNonEarningAmount(recipient_, safeAmount_);
        }
    }

    function _updateTotalEarningSupply(uint240 totalEarningSupply_) internal {
        _updateTotalEarningSupply(totalEarningSupply_, uint240(totalAccruedYield()));
    }

    function _updateTotalEarningSupply(uint240 totalEarningSupply_, uint240 accruedYieldOfEarningSupply_) internal {
        uint128 accrualIndex_ = _accrualIndex(accruedYieldOfEarningSupply_, totalEarningSupply_);

        principalOfTotalEarningSupply = _getPrincipalAmountRoundedDown(totalEarningSupply_, accrualIndex_);
        indexOfTotalEarningSupply = accrualIndex_;
    }

    /* ============ Internal View/Pure Functions ============ */

    function _accruedYield(Balance balance_) internal view returns (uint240) {
        (bool isEarning_, uint128 index_, uint256 rawBalance_) = _unwrap(balance_);

        return isEarning_ ? _accruedYield(uint112(rawBalance_), index_) : 0;
    }

    function _accruedYield(uint112 principalAmount_, uint128 index_) internal view returns (uint240) {
        return _getPresentAmountRoundedDown(principalAmount_, currentMIndex() - index_);
    }

    function _accrualIndex(uint240 yield_, uint240 amount_) internal view returns (uint128) {
        return
            yield_ == 0
                ? currentMIndex()
                : _multiply128By128Down(currentMIndex(), _divide240by240Down(amount_, yield_ + amount_));
    }

    function _isApprovedEarner(address account_) internal view returns (bool) {
        // TODO: Toggle boolean and/or separate list?
        return IRegistrarLike(registrar).listContains(_EARNERS_LIST, account_);
    }

    function _getClaimOverrideDestination(address account_) internal view returns (address) {
        return
            address(
                uint160(
                    uint256(IRegistrarLike(registrar).get(keccak256(abi.encode(_CLAIM_DESTINATION_PREFIX, account_))))
                )
            );
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

    function _wrap(bool isEarning_, uint256 index_, uint256 amount_) internal pure returns (Balance balance_) {
        return isEarning_ ? Balance.wrap((1 << 248) | (index_ << 112) | amount_) : Balance.wrap(amount_);
    }

    function _unwrap(Balance balance_) internal pure returns (bool isEarning_, uint128 index_, uint256 rawBalance_) {
        uint256 unwrapped_ = Balance.unwrap(balance_);

        return
            (unwrapped_ >> 248) != 0
                ? (true, uint128((unwrapped_ << 8) >> 120), (unwrapped_ << 144) >> 144)
                : (false, 0, unwrapped_);
    }
}
