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
        _accounts[account_].earningState = isEarning_ ? EarningState.PRINCIPAL_BASED : EarningState.NOT_EARNING;
    }

    function setEarningPrincipalOf(address account_, uint256 earningPrincipal_) external {
        _accounts[account_].earningPrincipal = uint112(earningPrincipal_);
    }

    function setAccountOf(address account_, uint256 balance_, uint256 earningPrincipal_) external {
        _accounts[account_] = Account(EarningState.PRINCIPAL_BASED, uint240(balance_), uint112(earningPrincipal_));
    }

    function setAccountOf(address account_, uint256 balance_) external {
        _accounts[account_] = Account(EarningState.NOT_EARNING, uint240(balance_), 0);
    }

    function setTotalNonEarningSupply(uint256 totalNonEarningSupply_) external {
        totalNonEarningSupply = uint240(totalNonEarningSupply_);
    }

    function setTotalEarningSupply(uint256 totalEarningSupply_) external {
        totalEarningSupply = uint240(totalEarningSupply_);
    }

    function setTotalEarningPrincipal(uint256 totalEarningPrincipal_) external {
        totalEarningPrincipal = uint112(totalEarningPrincipal_);
    }

    function setEnableMIndex(uint256 enableMIndex_) external {
        enableMIndex = uint128(enableMIndex_);
    }

    function setDisableIndex(uint256 disableIndex_) external {
        disableIndex = uint128(disableIndex_);
    }

    function getAccountOf(
        address account_
    ) external view returns (bool isEarning_, uint240 balance_, uint112 earningPrincipal_) {
        Account storage account = _accounts[account_];
        return (account.earningState == EarningState.PRINCIPAL_BASED, account.balance, account.earningPrincipal);
    }
}
