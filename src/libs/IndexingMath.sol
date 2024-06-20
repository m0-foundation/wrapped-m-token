// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

library IndexingMath {
    /* ============ Variables ============ */

    uint56 internal constant EXP_SCALED_ONE = 1e12;

    /* ============ Custom Errors ============ */

    error DivisionByZero();

    /* ============ Internal View/Pure Functions ============ */

    function divide240By128Down(uint240 x_, uint128 y_) internal pure returns (uint112) {
        if (y_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe112((uint256(x_) * EXP_SCALED_ONE) / y_);
        }
    }

    function divide240by112Down(uint240 x_, uint112 y_) internal pure returns (uint128) {
        if (y_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe128((uint256(x_) * EXP_SCALED_ONE) / y_);
        }
    }

    function divide240By128Up(uint240 x, uint128 y_) internal pure returns (uint112) {
        if (y_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe112(((uint256(x) * EXP_SCALED_ONE) + y_ - 1) / y_);
        }
    }

    function multiply112By128Down(uint112 x_, uint128 y_) internal pure returns (uint240) {
        unchecked {
            return UIntMath.safe240((uint256(x_) * y_) / EXP_SCALED_ONE);
        }
    }

    function multiply128By128Down(uint128 x_, uint128 y_) internal pure returns (uint128) {
        unchecked {
            return UIntMath.safe128((uint256(x_) * y_) / EXP_SCALED_ONE);
        }
    }

    function multiply112By128Up(uint112 x_, uint128 y_) internal pure returns (uint240) {
        unchecked {
            return UIntMath.safe240(((uint256(x_) * y_) + (EXP_SCALED_ONE - 1)) / EXP_SCALED_ONE);
        }
    }

    function getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return multiply112By128Down(principalAmount_, index_);
    }

    function getPresentAmountRoundedUp(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return multiply112By128Up(principalAmount_, index_);
    }

    function getPrincipalAmountRoundedDown(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return divide240By128Down(presentAmount_, index_);
    }

    function getPrincipalAmountRoundedUp(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return divide240By128Up(presentAmount_, index_);
    }
}
