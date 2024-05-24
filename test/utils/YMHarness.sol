// SPDX-License-Identifier: UNTITLED

pragma solidity 0.8.23;

import { YM } from "../../src/YM.sol";

contract YMHarness is YM {
    constructor(address mToken_, address wMToken_, address registrar_) YM(mToken_, wMToken_, registrar_) {}

    function increaseBalanceOf(address account_, uint256 balance_) external {
        _balances[account_].balance += uint240(balance_);
        totalSupply += balance_;
    }
}
