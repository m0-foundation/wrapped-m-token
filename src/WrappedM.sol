// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IWrappedM } from "./interfaces/IWrappedM.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";

// TODO: Allow willing accounts to block the activate of claim delegates for this account.

contract WrappedM is IWrappedM, ERC20Extended {
    type Balance is uint256;

    /* ============ Variables ============ */

    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _ALLOCATORS_LIST = "wm_allocators";
    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _EARNING_DELEGATE_PREFIX = "earning_delegate";

    address public immutable mToken;
    address public immutable registrar;

    uint240 public totalEarningSupply;

    uint112 public principalOfTotalNonEarningSupply;
    uint128 public indexOfNonEarningSupply;

    mapping(address account => Balance balance) internal _balances;

    mapping(address account => address claimDelegate) public claimDelegateOf;

    /* ============ Modifiers ============ */

    /* ============ Constructor ============ */

    constructor(address mToken_, address registrar_) ERC20Extended("WrappedM by M^0", "wM", 6) {
        mToken = mToken_;
        registrar = registrar_;

        indexOfNonEarningSupply = currentMIndex();
    }

    /* ============ Interactive Functions ============ */

    function activateClaimDelegate(address account_) external {
        claimDelegateOf[account_] = _getEaringDelegate(account_);
    }

    function claim() external returns (uint256 yield_) {
        ( bool isEarning_, , ) = _unwrap(_balances[msg.sender]);

        if (!isEarning_) revert NotEarning();

        return _claimForEarner(msg.sender, currentMIndex());
    }

    // TODO: Should anyone be allowed to do this? No harm, but legal implications?
    function claimForTotalNonEarningSupply() external returns (uint256 yield_) {
        return _claimForTotalNonEarningSupply(currentMIndex());
    }

    function deposit(address destination_, uint256 amount_) external {
        IMTokenLike(mToken).transferFrom(msg.sender, address(this), amount_);

        _mint(destination_, UIntMath.safe240(amount_));
    }

    function withdraw(address destination_, uint256 amount_) external {
        IMTokenLike(mToken).transfer(destination_, amount_);

        _burn(msg.sender, UIntMath.safe240(amount_));
    }

    // TODO: Could be replace with a transferFrom override, but transferFrom is not virtual.
    function allocate(address recipient_, uint256 amount_) external {
        if (!_isApprovedAllocator(msg.sender)) revert NotAllocator();

        _transfer(address(this), recipient_, amount_);
    }

    function startEarning() external {
        if (!_isApprovedEarner(msg.sender)) revert NotApprovedEarner();

        _startEarning(msg.sender);
    }

    function startEarning(address account_) external {
        if (_getEaringDelegate(account_) != msg.sender) revert NotEarningDelegate();

        if (!_isApprovedEarner(account_)) revert NotApprovedEarner();

        _startEarning(account_);
    }

    function stopEarning() external {
        _stopEarning(msg.sender);
    }

    function stopEarning(address account_) external {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner();

        _stopEarning(account_);
    }

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account_) public view returns (uint256 yield_) {
        return _accruedYield(_balances[account_], currentMIndex());
    }

    function accruedYieldOfEarningSupply() public view returns (uint256 yield_) {
        uint256 mBalance_ = IMTokenLike(mToken).balanceOf(address(this));
        uint256 earMarked = totalSupply() + accruedYieldOfNonEarningSupply();

        return mBalance_ <= earMarked ? 0 : mBalance_ - earMarked;
    }

    function accruedYieldOfNonEarningSupply() public view returns (uint256 yield_) {
        return _accruedYield(principalOfTotalNonEarningSupply, indexOfNonEarningSupply, currentMIndex());
    }

    function balanceOf(address account) external view returns (uint256 balance_) {
        ( bool isEarning_, uint128 index_, uint256 rawBalance_ ) = _unwrap(_balances[account]);

        return isEarning_ ? _getPresentAmountRoundedDown(uint112(rawBalance_), index_) : rawBalance_;
    }

    function totalNonEarningSupply() public view returns (uint256 totalSupply_) {
        return _getPresentAmountRoundedDown(principalOfTotalNonEarningSupply, indexOfNonEarningSupply);
    }

    function totalSupply() public view returns (uint256 totalSupply_) {
        return totalEarningSupply + totalNonEarningSupply();
    }

    function currentMIndex() public view returns (uint128 index_) {
        return IMTokenLike(mToken).currentIndex();
    }

    /* ============ Internal Interactive Functions ============ */

    function _claimForEarner(address account_, uint128 currentIndex_) internal returns (uint240 yield_) {
        ( , uint128 index_, uint256 rawBalance_) = _unwrap(_balances[account_]);

        if (index_ == currentIndex_) return 0;

        yield_ = _accruedYield(uint112(rawBalance_), index_, currentIndex_);

        _balances[account_] = _wrap(true, currentIndex_, rawBalance_);

        if (yield_ != 0) {
            emit Claim(account_, yield_);
            emit Transfer(address(0), account_, yield_);

            totalEarningSupply += yield_;
        }

        address claimDelegate_ = claimDelegateOf[account_];

        if (claimDelegate_ != address(0) && claimDelegate_ != account_) {
            // NOTE: Watch out for a long chain of delegations.
            // TODO: Maybe can be optimized since we know `account_` is an earner and already claimed.
            _transfer(account_, claimDelegate_, yield_);
        }
    }

    function _claimForTotalNonEarningSupply(uint128 currentIndex_) internal returns (uint240 yield_) {
        yield_ = _accruedYield(principalOfTotalNonEarningSupply, indexOfNonEarningSupply, currentIndex_);

        if (yield_ != 0) {
            emit Claim(address(this), yield_);
            emit Transfer(address(0), address(this), yield_);
        }

        ( , , uint256 rawBalance_ ) = _unwrap(_balances[address(this)]);

        _balances[address(this)] = _wrap(false, 0, rawBalance_ + yield_);
        indexOfNonEarningSupply = currentIndex_;
    }

    function _burn(address account_, uint240 amount_) internal {
        ( bool isEarning_, , ) = _unwrap(_balances[account_]);

        uint128 currentIndex_ = currentMIndex();

        if (isEarning_) {
            _claimForEarner(account_, currentIndex_);
            _burnEarningAmount(account_, amount_, currentIndex_);
        } else {
            _claimForTotalNonEarningSupply(currentIndex_);
            _burnNonEarningAmount(account_, amount_, currentIndex_);
        }

        emit Transfer(account_, address(0), amount_);
    }

    /// @dev Should only be called if indexOfNonEarningSupply is currentIndex_.
    function _burnNonEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
        ( , , uint256 rawBalance_ ) = _unwrap(_balances[account_]);

        _balances[account_] = _wrap(false, 0, rawBalance_ - amount_);
        principalOfTotalNonEarningSupply -= _getPrincipalAmountRoundedDown(amount_, currentIndex_);
    }

    /// @dev Should only be called if _balances[account_].index is currentIndex_.
    function _burnEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
        ( , , uint256 rawBalance_ ) = _unwrap(_balances[account_]);

        _balances[account_] = _wrap(
            true,
            currentIndex_,
            rawBalance_ - _getPrincipalAmountRoundedUp(amount_, currentIndex_)
        );

        totalEarningSupply -= amount_;
    }

    function _mint(address recipient_, uint240 amount_) internal {
        ( bool isEarning_, , ) = _unwrap(_balances[recipient_]);

        uint128 currentIndex_ = currentMIndex();

        if (isEarning_) {
            _claimForEarner(recipient_, currentIndex_);
            _mintEarningAmount(recipient_, amount_, currentIndex_);
        } else {
            _claimForTotalNonEarningSupply(currentIndex_);
            _mintNonEarningAmount(recipient_, amount_, currentIndex_);
        }

        emit Transfer(address(0), recipient_, amount_);
    }

    /// @dev Should only be called if indexOfNonEarningSupply is currentIndex_.
    function _mintNonEarningAmount(address recipient_, uint240 amount_, uint128 currentIndex_) internal {
        ( , , uint256 rawBalance_ ) = _unwrap(_balances[recipient_]);

        _balances[recipient_] = _wrap(false, 0, rawBalance_ + amount_);
        principalOfTotalNonEarningSupply += _getPrincipalAmountRoundedDown(amount_, currentIndex_);
    }

    /// @dev Should only be called if _balances[recipient_].index is currentIndex_.
    function _mintEarningAmount(address recipient_, uint240 amount_, uint128 currentIndex_) internal {
        ( , , uint256 rawBalance_ ) = _unwrap(_balances[recipient_]);

        uint112 principalAmount_ = _getPrincipalAmountRoundedDown(amount_, currentIndex_);

        _balances[recipient_] = _wrap(true, currentIndex_, rawBalance_ + principalAmount_);

        totalEarningSupply += amount_;
    }

    function _startEarning(address account_) internal {
        ( bool isEarning_, , uint256 rawBalance_) = _unwrap(_balances[account_]);

        if (isEarning_) return;

        emit StartEarning(account_);

        uint128 currentIndex_ = currentMIndex();

        _claimForTotalNonEarningSupply(currentIndex_);

        uint112 principalAmount_ = _getPrincipalAmountRoundedDown(uint240(rawBalance_), currentIndex_);

        _balances[account_] = _wrap(true, currentIndex_, principalAmount_);

        principalOfTotalNonEarningSupply -= principalAmount_;
        totalEarningSupply += uint240(rawBalance_);
    }

    function _stopEarning(address account_) internal {
        ( bool isEarning_, , ) = _unwrap(_balances[account_]);

        if (!isEarning_) return;

        uint128 currentIndex_ = currentMIndex();

        _claimForEarner(account_, currentIndex_);
        _claimForTotalNonEarningSupply(currentIndex_);

        emit StopEarning(account_);

        ( , uint128 index_, uint256 rawBalance_) = _unwrap(_balances[account_]);

        uint240 amount_ = _getPresentAmountRoundedDown(uint112(rawBalance_), index_);

        _balances[account_] = _wrap(false, 0, amount_);

        totalEarningSupply -= amount_;
        principalOfTotalNonEarningSupply += uint112(rawBalance_);
    }

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        emit Transfer(sender_, recipient_, amount_);

        uint240 safeAmount_ = UIntMath.safe240(amount_);

        ( bool senderIsEarning_, , uint256 senderRawBalance_ ) = _unwrap(_balances[sender_]);
        ( bool recipientIsEarning_, , uint256 recipientRawBalance_ ) = _unwrap(_balances[recipient_]);

        if (!senderIsEarning_ && !recipientIsEarning_) {
            _balances[sender_] = _wrap(false, 0, senderRawBalance_ - safeAmount_);
            _balances[recipient_] = _wrap(false, 0, recipientRawBalance_ + safeAmount_);

            return;
        }

        uint128 currentIndex_ = currentMIndex();

        if (senderIsEarning_ && recipientIsEarning_) {
            _claimForEarner(sender_, currentIndex_);
            _claimForEarner(recipient_, currentIndex_);

            ( , , senderRawBalance_ ) = _unwrap(_balances[sender_]);
            ( , , recipientRawBalance_ ) = _unwrap(_balances[recipient_]);

            uint112 principalAmount_ = _getPrincipalAmountRoundedDown(safeAmount_, currentIndex_);

            _balances[sender_] = _wrap(true, currentIndex_, senderRawBalance_ - principalAmount_);
            _balances[recipient_] = _wrap(true, currentIndex_, recipientRawBalance_ + principalAmount_);
        } else if (senderIsEarning_) {
            _claimForEarner(sender_, currentIndex_);
            _claimForTotalNonEarningSupply(currentIndex_);
            _burnEarningAmount(sender_, safeAmount_, currentIndex_);
            _mintNonEarningAmount(recipient_, safeAmount_, currentIndex_);
        } else {
            _claimForEarner(recipient_, currentIndex_);
            _claimForTotalNonEarningSupply(currentIndex_);
            _burnNonEarningAmount(sender_, safeAmount_, currentIndex_);
            _mintEarningAmount(recipient_, safeAmount_, currentIndex_);
        }
    }

    /* ============ Internal View/Pure Functions ============ */

    function _accruedYield(Balance balance_, uint128 currentIndex_) internal pure returns (uint240 yield_) {
        ( bool isEarning_, uint128 index_, uint256 rawBalance_) = _unwrap(balance_);

        return isEarning_ ? _accruedYield(uint112(rawBalance_), index_, currentIndex_) : 0;
    }

    function _accruedYield(
        uint112 principalAmount_,
        uint128 index_,
        uint128 currentIndex_
    ) internal pure returns (uint240 yield_) {
        // TODO: Compare with `_getPresentAmountRoundedDown(principalAmount_, currentIndex_) - _getPresentAmountRoundedDown(principalAmount_, index_)`
        return _getPresentAmountRoundedDown(principalAmount_, currentIndex_ - index_);
    }

    function _isApprovedEarner(address account_) internal view returns (bool isApproved_) {
        // TODO: Toggle boolean?
        // TODO: Separate list?
        return (account_ != address(this)) && IRegistrarLike(registrar).listContains(_EARNERS_LIST, account_);
    }

    function _isApprovedAllocator(address account_) internal view returns (bool isApproved_) {
        return IRegistrarLike(registrar).listContains(_ALLOCATORS_LIST, account_);
    }

    function _getEaringDelegate(address account_) internal view returns (address earningDelegate_) {
        return
            address(
                uint160(
                    uint256(
                        IRegistrarLike(registrar).get(keccak256(abi.encode(_EARNING_DELEGATE_PREFIX, account_)))
                    )
                )
            );
    }

    function _multiplyDown(uint112 x_, uint128 index_) internal pure returns (uint240 z) {
        unchecked {
            return uint240((uint256(x_) * index_) / _EXP_SCALED_ONE);
        }
    }

    function _divideDown(uint240 x_, uint128 index_) internal pure returns (uint112 z) {
        if (index_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe112((uint256(x_) * _EXP_SCALED_ONE) / index_);
        }
    }

    function _divideUp(uint240 x, uint128 index) internal pure returns (uint112 z) {
        if (index == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe112(((uint256(x) * _EXP_SCALED_ONE) + index - 1) / index);
        }
    }

    function _getPresentAmountRoundedDown(
        uint112 principalAmount_,
        uint128 index_
    ) internal pure returns (uint240 presentAmount_) {
        return _multiplyDown(principalAmount_, index_);
    }

    function _getPrincipalAmountRoundedDown(
        uint240 presentAmount_,
        uint128 index_
    ) internal pure returns (uint112 principalAmount_) {
        return _divideDown(presentAmount_, index_);
    }

    function _getPrincipalAmountRoundedUp(
        uint240 presentAmount_,
        uint128 index_
    ) internal pure returns (uint112 principalAmount_) {
        return _divideUp(presentAmount_, index_);
    }

    function _unwrap(Balance balance_) internal pure returns (bool isEarning_, uint128 index_, uint256 rawBalance_) {
        uint256 unwrapped_ = Balance.unwrap(balance_);

        isEarning_ = (unwrapped_ >> 248) != 0;

        if (isEarning_) {
            index_ = uint128((unwrapped_ << 8) >> 120);

            if (index_ == 0) {
                index_ = _EXP_SCALED_ONE;
            }

            rawBalance_ = (unwrapped_ << 144) >> 144;
        } else {
            index_ = 0;
            rawBalance_ = (unwrapped_ << 8) >> 8;
        }
    }

    function _wrap( bool isEarning_, uint256 index_, uint256 amount_) internal pure returns (Balance balance_) {
        return isEarning_ ? Balance.wrap(1 << 248 | index_ << 112 | amount_) : Balance.wrap(amount_);
    }
}
