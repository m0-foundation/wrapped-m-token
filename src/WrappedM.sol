// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IWrappedMYield } from "./interfaces/IWrappedMYield.sol";
import { IWrappedM } from "./interfaces/IWrappedM.sol";

contract WrappedM is IWrappedM, ERC20Extended {
    /* ============ Variables ============ */

    address public immutable mToken;
    address public immutable wrappedMYield;

    uint256 public totalSupply;

    mapping(address account => uint256 balance) public balanceOf;

    /* ============ Modifiers ============ */

    modifier onlyEarner() {
        if (!IMTokenLike(mToken).isEarning(msg.sender)) revert NotEarner();

        _;
    }

    modifier onlyWrappedMYield() {
        if (msg.sender != wrappedMYield) revert NotWrappedMYield();

        _;
    }

    /* ============ Constructor ============ */

    constructor(address mToken_, address mYield_) ERC20Extended("Wrapped M by M^0", "wM", 6) {
        mToken = mToken_;
        wrappedMYield = mYield_;
    }

    /* ============ Interactive Functions ============ */

    function deposit(address account_, uint256 amount_) external onlyEarner returns (uint256 wrappedMYieldTokenId_) {
        emit Transfer(address(0), account_, amount_);

        balanceOf[account_] += amount_;
        totalSupply += amount_;

        wrappedMYieldTokenId_ = IWrappedMYield(wrappedMYield).mint(account_, amount_);

        IMTokenLike(mToken).transferFrom(msg.sender, address(this), amount_);
    }

    function withdraw(
        address account_,
        uint256 wrappedMYieldTokenId_
    ) external returns (uint256 amount_, uint256 yield_) {
        ( amount_, yield_ ) = IWrappedMYield(wrappedMYield).burn(msg.sender, wrappedMYieldTokenId_);

        emit Transfer(account_, address(0), amount_);

        balanceOf[account_] -= amount_;
        totalSupply -= amount_;

        IMTokenLike(mToken).transfer(account_, amount_ + yield_);
    }

    /* ============ View/Pure Functions ============ */

    /* ============ Internal Interactive Functions ============ */

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        emit Transfer(sender_, recipient_, amount_);

        balanceOf[sender_] -= amount_;
        balanceOf[recipient_] += amount_;
    }

    /* ============ Internal View/Pure Functions ============ */
}
