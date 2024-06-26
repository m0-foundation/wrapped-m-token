// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { WrappedMToken } from "../../src/WrappedMToken.sol";

contract WrappedMTokenHarness is WrappedMToken {
    constructor(address mToken_) WrappedMToken(mToken_) {}

    function setIsEarningOf(address account_, bool isEarning_) external {
        (, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);
        _setBalanceInfo(account_, isEarning_, index_, rawBalance_);
    }

    function setIndexOf(address account_, uint256 index_) external {
        (bool isEarning_, , uint240 rawBalance_) = _getBalanceInfo(account_);
        _setBalanceInfo(account_, isEarning_, uint128(index_), rawBalance_);
    }

    function setRawBalanceOf(address account_, uint256 rawBalance_) external {
        (bool isEarning_, uint128 index_, ) = _getBalanceInfo(account_);
        _setBalanceInfo(account_, isEarning_, index_, uint240(rawBalance_));
    }

    function setTotalNonEarningSupply(uint256 totalNonEarningSupply_) external {
        totalNonEarningSupply = uint240(totalNonEarningSupply_);
    }

    function setPrincipalOfTotalEarningSupply(uint256 principalOfTotalEarningSupply_) external {
        _principalOfTotalEarningSupply = uint112(principalOfTotalEarningSupply_);
    }

    function setIndexOfTotalEarningSupply(uint256 indexOfTotalEarningSupply_) external {
        _indexOfTotalEarningSupply = uint128(indexOfTotalEarningSupply_);
    }

    function internalBalanceOf(address account_) external view returns (uint256 balance_) {
        (, , balance_) = _getBalanceInfo(account_);
    }

    function principalOfTotalEarningSupply() external view returns (uint256 principalOfTotalEarningSupply_) {
        principalOfTotalEarningSupply_ = _principalOfTotalEarningSupply;
    }

    function indexOfTotalEarningSupply() external view returns (uint256 indexOfTotalEarningSupply_) {
        indexOfTotalEarningSupply_ = _indexOfTotalEarningSupply;
    }
}
