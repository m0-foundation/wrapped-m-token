// SPDX-License-Identifier: UNTITLED

pragma solidity 0.8.23;

import { WM } from "../../src/WM.sol";

contract WMHarness is WM {
    constructor(address mToken, address registrar) WM(mToken, registrar) {}

    function setIsEarning(address account_, bool isEarning_) external {
        _balances[account_].isEarning = isEarning_;
    }

    function setLatestIndex(address account_, uint128 latestIndex_) external {
        _balances[account_].latestIndex = latestIndex_;
    }

    function setBalance(address account_, uint256 balance_) external {
        _balances[account_].balance = balance_;
    }
}
