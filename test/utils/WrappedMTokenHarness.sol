// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { WrappedMToken } from "../../src/WrappedMToken.sol";

contract WrappedMTokenHarness is WrappedMToken {
    constructor(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address migrationAdmin_
    ) WrappedMToken(mToken_, registrar_, excessDestination_, migrationAdmin_) {}

    function internalWrap(address account_, address recipient_, uint240 amount_) external returns (uint240 wrapped_) {
        return _wrap(account_, recipient_, amount_);
    }

    function internalUnwrap(
        address account_,
        address recipient_,
        uint240 amount_
    ) external returns (uint240 unwrapped_) {
        return _unwrap(account_, recipient_, amount_);
    }

    function setIsEarningOf(address account_, bool isEarning_) external {
        _accounts[account_].isEarning = isEarning_;
    }

    function setLastIndexOf(address account_, uint256 index_) external {
        _accounts[account_].lastIndex = uint128(index_);
    }

    function setAccountOf(address account_, uint256 balance_, uint256 index_) external {
        _accounts[account_] = Account(true, uint240(balance_), uint128(index_));
    }

    function setAccountOf(address account_, uint256 balance_) external {
        _accounts[account_] = Account(false, uint240(balance_), 0);
    }

    function setTotalNonEarningSupply(uint256 totalNonEarningSupply_) external {
        totalNonEarningSupply = uint240(totalNonEarningSupply_);
    }

    function setTotalEarningSupply(uint256 totalEarningSupply_) external {
        totalEarningSupply = uint240(totalEarningSupply_);
    }

    function setPrincipalOfTotalEarningSupply(uint256 principalOfTotalEarningSupply_) external {
        principalOfTotalEarningSupply = uint112(principalOfTotalEarningSupply_);
    }

    function setEnableMIndex(uint256 enableMIndex_) external {
        enableMIndex = uint128(enableMIndex_);
    }

    function setDisableIndex(uint256 disableIndex_) external {
        disableIndex = uint128(disableIndex_);
    }
}
