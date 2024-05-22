// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import {IMToken} from "../../lib/protocol/src/interfaces/IMToken.sol";

contract MPosition {
    address public immutable wrapper;
    address public immutable mToken;

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != wrapper) revert NotOwner();

        _;
    }

    constructor(address wrapper_, address mToken_) {
        wrapper = wrapper_;
        mToken = mToken_;
    }

    function withdraw(uint256 amount, address receiver) external onlyOwner {
        IMToken(mToken).transfer(receiver, amount);
    }
}
