// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

// import { console2 } from "../../lib/forge-std/src/Test.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

library Invariants {
    // Invariant 1: Sum of all accounts' balances is less than or equal to total supply.
    // Invariant 1a: Sum of all non-earning accounts' balances is less than or equal to total non-earning supply.
    // Invariant 1b: Sum of all earning accounts' balances is less than or equal to total earning supply.
    function checkInvariant1(address wrappedMToken_, address[] memory accounts_) internal view returns (bool success_) {
        uint256 totalNonEarningSupply_;
        uint256 totalEarningSupply_;
        uint256 totalSupply_;

        for (uint256 index_; index_ < accounts_.length; ++index_) {
            uint256 balance_ = IWrappedMToken(wrappedMToken_).balanceOf(accounts_[index_]);

            totalSupply_ += balance_;

            if (IWrappedMToken(wrappedMToken_).isEarning(accounts_[index_])) {
                totalEarningSupply_ += balance_;
            } else {
                totalNonEarningSupply_ += balance_;
            }
        }

        // console2.log("Invariant 1: totalNonEarningSupply_  = %d ", totalNonEarningSupply_);
        // console2.log(
        //     "Invariant 1: totalNonEarningSupply() = %d",
        //     IWrappedMToken(wrappedMToken_).totalNonEarningSupply()
        // );

        if (totalNonEarningSupply_ > IWrappedMToken(wrappedMToken_).totalNonEarningSupply()) return false;

        // console2.log("Invariant 1: totalEarningSupply_  = %d ", totalEarningSupply_);
        // console2.log("Invariant 1: totalEarningSupply() = %d", IWrappedMToken(wrappedMToken_).totalEarningSupply());

        if (totalEarningSupply_ > IWrappedMToken(wrappedMToken_).totalEarningSupply()) return false;

        // console2.log("Invariant 1: totalSupply_  = %d ", totalSupply_);
        // console2.log("Invariant 1: totalSupply() = %d", IWrappedMToken(wrappedMToken_).totalSupply());

        if (totalSupply_ > IWrappedMToken(wrappedMToken_).totalSupply()) return false;

        return true;
    }

    // Invariant 2: Sum of all earning accounts' balance and accrued yield is less than or equal to total earning supply and
    //              total accrued yield.
    function checkInvariant2(address wrappedMToken_, address[] memory accounts_) internal view returns (bool success_) {
        uint256 totalSupplyAndAccruedYield_;

        for (uint256 index_; index_ < accounts_.length; ++index_) {
            if (!IWrappedMToken(wrappedMToken_).isEarning(accounts_[index_])) continue;

            totalSupplyAndAccruedYield_ +=
                IWrappedMToken(wrappedMToken_).balanceOf(accounts_[index_]) +
                IWrappedMToken(wrappedMToken_).accruedYieldOf(accounts_[index_]);
        }

        // console2.log("Invariant 2: totalSupplyAndAccruedYield_                = %d ", totalSupplyAndAccruedYield_);

        // console2.log(
        //     "Invariant 2: totalEarningSupply() + totalAccruedYield() = %d",
        //     IWrappedMToken(wrappedMToken_).totalEarningSupply() + IWrappedMToken(wrappedMToken_).totalAccruedYield()
        // );

        return
            IWrappedMToken(wrappedMToken_).totalEarningSupply() + IWrappedMToken(wrappedMToken_).totalAccruedYield() >=
            totalSupplyAndAccruedYield_;
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
}
