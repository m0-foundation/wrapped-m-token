// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../../lib/protocol/src/libs/ContinuousIndexingMath.sol";

import { IndexingMath } from "../../src/libs/IndexingMath.sol";

import { WrappedMTokenHarness } from "./WrappedMTokenHarness.sol";
import { MTokenHarness } from "./MTokenHarness.sol";

contract TestUtils is Test {
    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    /* ============ wrap ============ */
    function _wrap(
        MTokenHarness mToken_,
        WrappedMTokenHarness wrappedMToken_,
        address account_,
        address recipient_,
        uint256 amount_
    ) internal {
        vm.prank(account_);
        mToken_.approve(address(wrappedMToken_), amount_);

        vm.prank(account_);
        wrappedMToken_.wrap(recipient_, amount_);
    }

    /* ============ accrued yield ============ */
    function _getAccruedYieldOf(
        WrappedMTokenHarness wrappedMToken_,
        address account_,
        uint128 currentIndex_
    ) internal view returns (uint240) {
        (, , uint112 principal_, uint240 balance_) = wrappedMToken_.internalBalanceInfo(account_);
        return _getPresentAmountRoundedDown(principal_, currentIndex_) - balance_;
    }

    function _getAccruedYield(
        uint240 startingPresentAmount_,
        uint128 startingIndex_,
        uint128 currentIndex_
    ) internal pure returns (uint240) {
        uint112 startingPrincipal_ = _getPrincipalAmountRoundedDown(startingPresentAmount_, startingIndex_);
        return _getPresentAmountRoundedDown(startingPrincipal_, currentIndex_) - startingPresentAmount_;
    }

    /* ============ index ============ */
    function _getContinuousIndexAt(
        uint32 minterRate_,
        uint128 initialIndex_,
        uint32 elapsedTime_
    ) internal pure returns (uint128) {
        return
            uint128(
                ContinuousIndexingMath.multiplyIndicesUp(
                    initialIndex_,
                    ContinuousIndexingMath.getContinuousIndex(
                        ContinuousIndexingMath.convertFromBasisPoints(minterRate_),
                        elapsedTime_
                    )
                )
            );
    }

    /* ============ principal ============ */
    function _getPrincipalAmountRoundedDown(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return IndexingMath.divide240By128Down(presentAmount_, index_);
    }

    /* ============ present ============ */
    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return IndexingMath.multiply112By128Down(principalAmount_, index_);
    }
}
