// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IWrappedM } from "./interfaces/IWrappedM.sol";

contract WrappedM is IWrappedM, ERC20Extended {
    /* ============ Variables ============ */

    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    address public immutable mToken;

    uint256 public totalSupply;

    mapping(address account => uint256 balance) public balanceOf;

    /* ============ Modifiers ============ */

    modifier onlyEarner() {
        if (!IMTokenLike(mToken).isEarning(msg.sender)) revert NotEarner();

        _;
    }

    /* ============ Constructor ============ */

    constructor(address mToken_) ERC20Extended("WrappedM by M^0", "wM", 6) {
        mToken = mToken_;
    }

    /* ============ Interactive Functions ============ */

    function deposit(address account_, uint256 amount_) external onlyEarner returns (uint256 shares_) {
        shares_ = _getPrincipalAmountRoundedDown(UIntMath.safe240(amount_), IMTokenLike(mToken).currentIndex());

        emit Transfer(address(0), account_, shares_);

        balanceOf[account_] += shares_;
        totalSupply += shares_;

        IERC20(mToken).transferFrom(msg.sender, address(this), amount_);
    }

    function withdraw(address account_, uint256 shares_) external {
        emit Transfer(account_, address(0), shares_);

        uint256 amount_ = _getPresentAmountRoundedDown(UIntMath.safe112(shares_), IMTokenLike(mToken).currentIndex());

        balanceOf[account_] += shares_;
        totalSupply += shares_;

        IERC20(mToken).transferFrom(address(this), msg.sender, amount_);
    }

    /* ============ View/Pure Functions ============ */

    /* ============ Internal Interactive Functions ============ */

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        emit Transfer(sender_, recipient_, amount_);

        balanceOf[sender_] -= amount_;
        balanceOf[recipient_] += amount_;
    }

    /* ============ Internal View/Pure Functions ============ */

    function _multiplyDown(uint112 x_, uint128 index_) internal pure returns (uint240) {
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

    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return _multiplyDown(principalAmount_, index_);
    }

    function _getPrincipalAmountRoundedDown(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return _divideDown(presentAmount_, index_);
    }
}
