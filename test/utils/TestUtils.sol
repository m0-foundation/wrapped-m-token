// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../../lib/protocol/src/libs/ContinuousIndexingMath.sol";

contract TestUtils is Test {
    /* ============ index ============ */
    function _getContinuousIndexAt(
        uint32 rate_,
        uint128 initialIndex_,
        uint32 elapsedTime_
    ) internal pure returns (uint128) {
        return
            uint128(
                ContinuousIndexingMath.multiplyIndicesUp(
                    initialIndex_,
                    ContinuousIndexingMath.getContinuousIndex(
                        ContinuousIndexingMath.convertFromBasisPoints(rate_),
                        elapsedTime_
                    )
                )
            );
    }

    /* ============ present ============ */
    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return ContinuousIndexingMath.multiplyDown(principalAmount_, index_);
    }
}
