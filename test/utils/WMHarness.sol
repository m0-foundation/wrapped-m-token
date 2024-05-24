// SPDX-License-Identifier: UNTITLED

pragma solidity 0.8.23;

import { WM } from "../../src/WM.sol";

contract WMHarness is WM {
    constructor(address mToken_, address yMToken_, address registrar_) WM(mToken_, yMToken_, registrar_) {}

    function increaseBalanceOf(address account_, uint256 balance_) external {
        _balances[account_] += balance_;
        totalSupply += balance_;
    }
}
