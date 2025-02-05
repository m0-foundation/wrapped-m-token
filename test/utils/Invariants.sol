// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

// import { console2 } from "../../lib/forge-std/src/Test.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

import { IndexingMath } from "../../src/libs/IndexingMath.sol";

import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

library Invariants {
    // Invariant 1: Sum of all accounts' balances is equal to total supply.
    // Invariant 1a: Sum of all non-earning accounts' balances is equal to total non-earning supply.
    // Invariant 1b: Sum of all earning accounts' balances is equal to total earning supply.
    function checkInvariant1(address wrappedMToken_, address[] memory accounts_) internal view returns (bool success_) {
        uint256 totalNonEarningSupply_;
        uint256 totalEarningSupply_;
        uint256 totalSupply_;

        for (uint256 i_; i_ < accounts_.length; ++i_) {
            address account_ = accounts_[i_];
            uint256 balance_ = IWrappedMToken(wrappedMToken_).balanceOf(account_);

            totalSupply_ += balance_;

            if (IWrappedMToken(wrappedMToken_).isEarning(account_)) {
                totalEarningSupply_ += balance_;
            } else {
                totalNonEarningSupply_ += balance_;
            }
        }

        // console2.log("Invariant 1: totalNonEarningSupply_  = %d", totalNonEarningSupply_);
        // console2.log(
        //     "Invariant 1: totalNonEarningSupply() = %d",
        //     IWrappedMToken(wrappedMToken_).totalNonEarningSupply()
        // );

        if (totalNonEarningSupply_ != IWrappedMToken(wrappedMToken_).totalNonEarningSupply()) return false;

        // console2.log("Invariant 1: totalEarningSupply_  = %d", totalEarningSupply_);
        // console2.log("Invariant 1: totalEarningSupply() = %d", IWrappedMToken(wrappedMToken_).totalEarningSupply());

        if (totalEarningSupply_ != IWrappedMToken(wrappedMToken_).totalEarningSupply()) return false;

        // console2.log("Invariant 1: totalSupply_  = %d", totalSupply_);
        // console2.log("Invariant 1: totalSupply() = %d", IWrappedMToken(wrappedMToken_).totalSupply());

        if (totalSupply_ != IWrappedMToken(wrappedMToken_).totalSupply()) return false;

        return true;
    }

    // Invariant 2: Sum of all accounts' accrued yield is less than or equal to total accrued yield.
    function checkInvariant2(address wrappedMToken_, address[] memory accounts_) internal view returns (bool success_) {
        uint256 totalAccruedYield_;

        for (uint256 i_; i_ < accounts_.length; ++i_) {
            totalAccruedYield_ += IWrappedMToken(wrappedMToken_).accruedYieldOf(accounts_[i_]);
        }

        // console2.log("Invariant 2: totalAccruedYield_  = %d", totalAccruedYield_);

        // console2.log("Invariant 2: totalAccruedYield() = %d", IWrappedMToken(wrappedMToken_).totalAccruedYield());

        return IWrappedMToken(wrappedMToken_).totalAccruedYield() >= totalAccruedYield_;
    }

    // Invariant 3: M Balance of wrapper is greater or equal to total supply, accrued yield, and excess.
    function checkInvariant3(address wrappedMToken_, address mToken_) internal view returns (bool success_) {
        // console2.log(
        //     "Invariant 3: M Balance of wrapper                           = %d ",
        //     IERC20(mToken_).balanceOf(wrappedMToken_)
        // );

        // console2.log(
        //     "Invariant 3: totalSupply() + totalAccruedYield() + excess() = %d",
        //     IWrappedMToken(wrappedMToken_).totalSupply() +
        //         IWrappedMToken(wrappedMToken_).totalAccruedYield() +
        //         IWrappedMToken(wrappedMToken_).excess()
        // );

        return
            IERC20(mToken_).balanceOf(wrappedMToken_) >=
            IWrappedMToken(wrappedMToken_).totalSupply() +
                IWrappedMToken(wrappedMToken_).totalAccruedYield() +
                IWrappedMToken(wrappedMToken_).excess();
    }

    // Invariant 4: Sum of all earning accounts' principals is less than or equal to principal of total earning supply.
    function checkInvariant4(address wrappedMToken_, address[] memory accounts_) internal view returns (bool success_) {
        uint256 principalOfTotalEarningSupply_;

        for (uint256 i_; i_ < accounts_.length; ++i_) {
            address account_ = accounts_[i_];

            if (!IWrappedMToken(wrappedMToken_).isEarning(account_)) continue;

            principalOfTotalEarningSupply_ += IndexingMath.getPrincipalAmountRoundedDown(
                uint240(IWrappedMToken(wrappedMToken_).balanceOf(account_)),
                IWrappedMToken(wrappedMToken_).lastIndexOf(account_)
            );
        }

        // console2.log("Invariant 2: principalOfTotalEarningSupply_ = %d", principalOfTotalEarningSupply_);

        // console2.log(
        //     "Invariant 2: principalOfTotalEarningSupply()         = %d",
        //     IWrappedMToken(wrappedMToken_).principalOfTotalEarningSupply()
        // );

        return IWrappedMToken(wrappedMToken_).principalOfTotalEarningSupply() >= principalOfTotalEarningSupply_;
    }
}
