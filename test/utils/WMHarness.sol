// SPDX-License-Identifier: UNTITLED

pragma solidity 0.8.23;

import { WM } from "../../src/WM.sol";

contract WMHarness is WM {
    constructor(address mToken_, address registrar_) WM(mToken_, registrar_) {}

    function increaseBalanceOf(address account_, uint256 balance_) external {
        _balances[account_].balance += uint112(balance_);

        if (_isEarning(account_)) {
            totalEarningSupply += uint112(balance_);
        } else {
            totalNonEarningSupply += uint112(balance_);
        }
    }

    function setIsEarning(address account_, uint128 index_, bool isEarning_) external {
        _balances[account_].index = index_;
        _balances[account_].isEarning = isEarning_;
    }
}
