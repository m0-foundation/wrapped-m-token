// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import {ERC20Extended} from "../../lib/common/src/ERC20Extended.sol";

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

import {IMToken} from "../../lib/protocol/src/interfaces/IMToken.sol";

import {MPosition} from "./MPosition.sol";

contract wM is ERC20 {
    struct EarnerBalance {
        uint256 lastIndex;
        uint256 principal;
    }

    address public immutable mToken;
    address public immutable earner;
    address public immutable nonEarner;

    mapping(address earner => EarnerBalance balance) public earningSuppliers;

    error OnlyOnePositionPerEarner(); // for simplicity purposes to start
    error InsufficientBalance(address account, uint256 rawBalance, uint256 amount);

    constructor(address mToken_) ERC20("Wrapped M Token", "wM", 18) {
        mToken = mToken_;
        earner = address(new MPosition(address(this), mToken_)); // on M earner list
        nonEarner = address(new MPosition(address(this), mToken_));
    }

    function wrap(uint256 amount) external {
        if (IMToken(mToken).isEarning(msg.sender)) {
            if (earningSuppliers[msg.sender].principal != 0) revert OnlyOnePositionPerEarner();

            uint256 currentIndex_ = IMToken(mToken).currentIndex();
            earningSuppliers[msg.sender] = EarnerBalance(currentIndex_, amount / currentIndex_);
            IMToken(mToken).transferFrom(msg.sender, earner, amount);
        } else {
            IMToken(mToken).transferFrom(msg.sender, nonEarner, amount);
        }

        _mint(msg.sender, amount); // mint wM tokens
    }

    function unwrap(uint256 amount_) external {
        // if earner or used to be an earner
        if (earningSuppliers[msg.sender].principal != 0) {
            uint256 currentIndex_ = IMToken(mToken).currentIndex();
            EarnerBalance storage earnerBalance_ = earningSuppliers[msg.sender];
            uint256 initialBalance_ = earnerBalance_.principal * earnerBalance_.lastIndex;
            if (amount_ > initialBalance_) revert InsufficientBalance(msg.sender, initialBalance_, amount_);

            uint256 currentBalance_ = earnerBalance_.principal * currentIndex_;
            uint256 mInterest_ = currentBalance_ - initialBalance_;

            // Withdraw interest and required amount
            MPosition(earner).withdraw(amount_ + mInterest_, msg.sender);

            earnerBalance_.principal = (initialBalance_ - amount_) / currentIndex_;
            earnerBalance_.lastIndex = currentIndex_;
        } else {
            // non-earner
            MPosition(nonEarner).withdraw(amount_, msg.sender);
        }

        _burn(msg.sender, amount_); // burn wM tokens
    }
}
