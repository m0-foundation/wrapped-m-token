// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IWrappedMToken } from "../interfaces/IWrappedMToken.sol";

import { Initializer as WrappedMTokenInitializer, WrappedMToken } from "../WrappedMToken.sol";

interface IWrappedMToken_SY is IWrappedMToken {
    error InvalidFeeRate();

    function HUNDRED_PERCENT() external pure returns (uint16 hundredPercent);

    function feeRate() external view returns (uint16 feeRate);
}

contract Initializer is WrappedMTokenInitializer {
    function initialize(string memory name_, string memory symbol_, address excessDestination_) external {
        WrappedMTokenInitializer._initialize(name_, symbol_, excessDestination_);
    }
}

/**
 * @title  Yield is split and returned to excess.
 * @author M^0 Labs
 */
contract WrappedMToken_SY is IWrappedMToken_SY, WrappedMToken {
    uint16 public constant HUNDRED_PERCENT = 10_000;

    uint16 public immutable feeRate;

    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address initializer_,
        uint16 feeRate_
    ) WrappedMToken(name_, symbol_, mToken_, registrar_, initializer_) {
        if ((feeRate = feeRate_) > HUNDRED_PERCENT) revert InvalidFeeRate();
    }

    function _afterClaim(address account_, uint240 yield_, uint128 currentIndex_) internal override {
        uint240 fee_ = uint240((uint256(yield_) * feeRate) / HUNDRED_PERCENT);

        _subtractEarningAmount(account_, fee_, currentIndex_);

        emit Transfer(account_, address(0), fee_);

        super._afterClaim(account_, yield_, currentIndex_);
    }

    function _beforeStopEarning(address account_, uint128 currentIndex_) internal override {
        _claim(account_, currentIndex_);

        super._beforeStopEarning(account_, currentIndex_);
    }
}
