// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

import {IMToken} from "../../lib/protocol/src/interfaces/IMToken.sol";

import {MPosition} from "./MPosition.sol";

contract wM is ERC20 {
    struct EarnerBalance {
        uint256 lastIndex;
        uint256 principal;
    }

    address public immutable mToken;
    address public immutable earnerPosition;
    address public immutable nonEarnerPosition;

    mapping(address earner => EarnerBalance balance) public earningSuppliers;

    error InsufficientBalance(address account, uint256 rawBalance, uint256 amount);
    error NotEarner();
    error NoEarnerPosition();

    modifier onlyEarner() {
        if (!IMToken(mToken).isEarning(msg.sender)) revert NotEarner();

        _;
    }

    constructor(address mToken_) ERC20("Wrapped M Token", "wM", 18) {
        mToken = mToken_;
        earnerPosition = address(new MPosition(address(this), mToken_)); // on M earner list
        nonEarnerPosition = address(new MPosition(address(this), mToken_));
    }

    function wrapForEarner(uint256 amount) external onlyEarner {
        (uint256 initialBalance_, uint256 interest_, uint256 currentIndex_) = _getEarnerData(msg.sender);

        // Withdraw accrued M interest
        if (interest_ > 0) {
            MPosition(earnerPosition).withdraw(interest_, msg.sender);
        }

        earningSuppliers[msg.sender] = EarnerBalance(currentIndex_, (initialBalance_ + amount) / currentIndex_);

        // Supply M tokens to the earner position that continue to accrue earner rate.
        IMToken(mToken).transferFrom(msg.sender, earnerPosition, amount);

        // Mint wM tokens.
        _mint(msg.sender, amount);
    }

    function wrap(uint256 amount) external {
        // Supply M tokens to the non-earner position.
        IMToken(mToken).transferFrom(msg.sender, nonEarnerPosition, amount);

        // Mint wM tokens.
        _mint(msg.sender, amount);
    }

    function unwrapForEarner(uint256 amount_) external {
        // If earner or used to be an earner
        if (earningSuppliers[msg.sender].principal == 0) revert NoEarnerPosition();

        (uint256 initialBalance_, uint256 interest_, uint256 currentIndex_) = _getEarnerData(msg.sender);

        if (amount_ > initialBalance_) revert InsufficientBalance(msg.sender, initialBalance_, amount_);

        // Withdraw interest and required amount
        MPosition(earnerPosition).withdraw(amount_ + interest_, msg.sender);

        earningSuppliers[msg.sender] = EarnerBalance(currentIndex_, (initialBalance_ - amount_) / currentIndex_);

        _burn(msg.sender, amount_); // burn wM tokens
    }

    function unwrap(uint256 amount_) external {
        // Withdraw M tokens from non-earner position.
        MPosition(nonEarnerPosition).withdraw(amount_, msg.sender);

        _burn(msg.sender, amount_); // burn wM tokens
    }

    function _getEarnerData(address earner) internal view returns (uint256, uint256, uint256) {
        uint256 currentIndex_ = IMToken(mToken).currentIndex();
        EarnerBalance storage earnerBalance_ = earningSuppliers[earner];
        uint256 initialBalance_ = earnerBalance_.principal * earnerBalance_.lastIndex;
        uint256 currentBalance_ = earnerBalance_.principal * currentIndex_;

        return (initialBalance_, currentBalance_ - initialBalance_, currentIndex_);
    }
}
