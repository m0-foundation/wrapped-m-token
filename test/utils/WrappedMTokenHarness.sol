// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { WrappedMToken } from "../../src/WrappedMToken.sol";

contract WrappedMTokenHarness is WrappedMToken {
    constructor(
        address mToken_,
        address registrar_,
        address earnerManager_,
        address excessDestination_,
        address migrationAdmin_
    ) WrappedMToken(mToken_, registrar_, earnerManager_, excessDestination_, migrationAdmin_) {}

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

    function setEarningPrincipalOf(address account_, uint256 earningPrincipal_) external {
        _accounts[account_].earningPrincipal = uint112(earningPrincipal_);
    }

    function setAccountOf(
        address account_,
        uint256 balance_,
        uint256 earningPrincipal_,
        bool hasClaimRecipient_,
        bool hasEarnerDetails_
    ) external {
        _accounts[account_] = Account(
            true,
            uint240(balance_),
            uint112(earningPrincipal_),
            hasClaimRecipient_,
            hasEarnerDetails_
        );
    }

    function setAccountOf(address account_, uint256 balance_) external {
        _accounts[account_] = Account(false, uint240(balance_), 0, false, false);
    }

    function setInternalClaimRecipient(address account_, address claimRecipient_) external {
        _claimRecipients[account_] = claimRecipient_;
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

    function setRoundingError(int256 roundingError_) external {
        roundingError = int144(roundingError_);
    }

    function setHasEarnerDetails(address account_, bool hasEarnerDetails_) external {
        _accounts[account_].hasEarnerDetails = hasEarnerDetails_;
    }

    function getAccountOf(
        address account_
    )
        external
        view
        returns (
            bool isEarning_,
            uint240 balance_,
            uint112 earningPrincipal_,
            bool hasClaimRecipient_,
            bool hasEarnerDetails_
        )
    {
        Account storage account = _accounts[account_];
        return (
            account.isEarning,
            account.balance,
            account.earningPrincipal,
            account.hasClaimRecipient,
            account.hasEarnerDetails
        );
    }

    function getInternalClaimRecipientOf(address account_) external view returns (address claimRecipient_) {
        return _claimRecipients[account_];
    }
}
