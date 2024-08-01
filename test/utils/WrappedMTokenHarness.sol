// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { WrappedMToken } from "../../src/WrappedMToken.sol";

contract WrappedMTokenHarness is WrappedMToken {
    constructor(address mToken_, address migrationAdmin_) WrappedMToken(mToken_, migrationAdmin_) {}

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

    function setPrincipalOfTotalEarningSupply(uint256 principalOfTotalEarningSupply_) external {
        _principalOfTotalEarningSupply = uint112(principalOfTotalEarningSupply_);
    }

    function setLastIndexOfTotalEarningSupply(uint256 indexOfTotalEarningSupply_) external {
        _indexOfTotalEarningSupply = uint128(indexOfTotalEarningSupply_);
    }

    function lastIndexOf(address account_) external view returns (uint128 index_) {
        return _accounts[account_].lastIndex;
    }

    function principalOfTotalEarningSupply() external view returns (uint240 principalOfTotalEarningSupply_) {
        principalOfTotalEarningSupply_ = _principalOfTotalEarningSupply;
    }

    function indexOfTotalEarningSupply() external view returns (uint128 indexOfTotalEarningSupply_) {
        indexOfTotalEarningSupply_ = _indexOfTotalEarningSupply;
    }
}
