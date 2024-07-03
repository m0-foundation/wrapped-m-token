// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../../lib/protocol/src/libs/ContinuousIndexingMath.sol";

import { WrappedMTokenHarness } from "./WrappedMTokenHarness.sol";

import { MTokenHarness } from "./MTokenHarness.sol";

contract TestUtils is Test {
    // bytes32 internal constant MAX_EARNER_RATE = "max_earner_rate";
    //
    // bytes32 internal constant BASE_MINTER_RATE = "base_minter_rate";
    //
    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    // uint16 internal constant ONE = 10_000;

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

    /* ============ penalty ============ */
    // function _getPenaltyPrincipal(
    //     uint240 penaltyBase_,
    //     uint32 penaltyRate_,
    //     uint128 index_
    // ) internal pure returns (uint112) {
    //     return ContinuousIndexingMath.divideUp((penaltyBase_ * penaltyRate_) / ONE, index_);
    // }

    /* ============ principal ============ */
    function _getPrincipalAmountRoundedDown(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return ContinuousIndexingMath.divideDown(presentAmount_, index_);
    }

    // function _getPrincipalAmountRoundedUp(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
    //     return ContinuousIndexingMath.divideUp(presentAmount_, index_);
    // }
    //
    /* ============ present ============ */
    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return ContinuousIndexingMath.multiplyDown(principalAmount_, index_);
    }

    // function _getPresentAmountRoundedUp(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
    //     return ContinuousIndexingMath.multiplyUp(principalAmount_, index_);
    // }
    //

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

    /* ============ signatures ============ */
    // function _makeKey(string memory name_) internal returns (uint256 privateKey_) {
    //     (, privateKey_) = makeAddrAndKey(name_);
    // }
    //
    // function _getCollateralUpdateSignature(
    //     address minterGateway_,
    //     address minter_,
    //     uint256 collateral_,
    //     uint256[] memory retrievalIds_,
    //     bytes32 metadataHash_,
    //     uint256 timestamp_,
    //     uint256 privateKey_
    // ) internal view returns (bytes memory) {
    //     return
    //         _getSignature(
    //             IMinterGateway(minterGateway_).getUpdateCollateralDigest(
    //                 minter_,
    //                 collateral_,
    //                 retrievalIds_,
    //                 metadataHash_,
    //                 timestamp_
    //             ),
    //             privateKey_
    //         );
    // }
    //
    // function _getCollateralUpdateShortSignature(
    //     address minterGateway_,
    //     address minter_,
    //     uint256 collateral_,
    //     uint256[] memory retrievalIds_,
    //     bytes32 metadataHash_,
    //     uint256 timestamp_,
    //     uint256 privateKey_
    // ) internal view returns (bytes memory) {
    //     return
    //         _getShortSignature(
    //             IMinterGateway(minterGateway_).getUpdateCollateralDigest(
    //                 minter_,
    //                 collateral_,
    //                 retrievalIds_,
    //                 metadataHash_,
    //                 timestamp_
    //             ),
    //             privateKey_
    //         );
    // }
    //
    // function _getSignature(bytes32 digest_, uint256 privateKey_) internal pure returns (bytes memory) {
    //     (uint8 v_, bytes32 r_, bytes32 s_) = vm.sign(privateKey_, digest_);
    //
    //     return abi.encodePacked(r_, s_, v_);
    // }
    //
    // function _getShortSignature(bytes32 digest_, uint256 privateKey_) internal pure returns (bytes memory) {
    //     (uint8 v_, bytes32 r_, bytes32 s_) = vm.sign(privateKey_, digest_);
    //
    //     bytes32 vs_ = s_;
    //
    //     if (v_ == 28) {
    //         // then left-most bit of s has to be flipped to 1 to get vs
    //         vs_ = s_ | bytes32(uint256(1) << 255);
    //     }
    //
    //     return abi.encodePacked(r_, vs_);
    // }
}
