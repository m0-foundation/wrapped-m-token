// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { WrappedMToken } from "../../src/WrappedMToken.sol";

contract WrappedMTokenHarness is WrappedMToken {
    constructor(address mToken_, address migrationAdmin_) WrappedMToken(mToken_, migrationAdmin_) {}

    function setIsEarningOf(address account_, bool isEarning_) external {
        (, uint128 index_, , uint240 balance_) = _getBalanceInfo(account_);
        _setBalanceInfo(account_, isEarning_, index_, balance_);
    }

    function setIndexOf(address account_, uint256 index_) external {
        (bool isEarning_, , , uint240 balance_) = _getBalanceInfo(account_);
        _setBalanceInfo(account_, isEarning_, uint128(index_), balance_);
    }

    function setBalanceOf(address account_, uint256 balance_) external {
        (bool isEarning_, uint128 index_, , ) = _getBalanceInfo(account_);
        _setBalanceInfo(account_, isEarning_, index_, uint240(balance_));
    }

    function setAccountOf(address account_, bool isEarning_, uint256 index_, uint256 balance_) external {
        _setBalanceInfo(account_, isEarning_, uint128(index_), uint240(balance_));
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

    function internalBalanceOf(address account_) external view returns (uint240 balance_) {
        (, , , balance_) = _getBalanceInfo(account_);
    }

    function internalIndexOf(address account_) external view returns (uint128 index_) {
        (, index_, , ) = _getBalanceInfo(account_);
    }

    function internalPrincipalOf(address account_) external view returns (uint112 principal_) {
        (, , principal_, ) = _getBalanceInfo(account_);
    }

    function principalOfTotalEarningSupply() external view returns (uint240 principalOfTotalEarningSupply_) {
        principalOfTotalEarningSupply_ = _principalOfTotalEarningSupply;
    }

    function indexOfTotalEarningSupply() external view returns (uint128 indexOfTotalEarningSupply_) {
        indexOfTotalEarningSupply_ = _indexOfTotalEarningSupply;
    }
}
