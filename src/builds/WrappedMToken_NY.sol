// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IWrappedMToken } from "../interfaces/IWrappedMToken.sol";

import { Initializer as WrappedMTokenInitializer, WrappedMToken } from "../WrappedMToken.sol";

interface IWrappedMToken_NY is IWrappedMToken {}

contract Initializer is WrappedMTokenInitializer {
    function initialize(string memory name_, string memory symbol_, address excessDestination_) external {
        WrappedMTokenInitializer._initialize(name_, symbol_, excessDestination_);
    }
}

/**
 * @title  No earning, all is excess going to some excess destination.
 * @author M^0 Labs
 */
contract WrappedMToken_NY is IWrappedMToken_NY, WrappedMToken {
    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address initializer_
    ) WrappedMToken(name_, symbol_, mToken_, registrar_, initializer_) {}

    function enableEarning() external pure override(IWrappedMToken, WrappedMToken) {
        revert EarningIsDisabled();
    }

    function disableEarning() external pure override(IWrappedMToken, WrappedMToken) {
        revert EarningIsDisabled();
    }

    function _startEarning(address account_, uint128 currentIndex_) internal pure override {
        revert EarningIsDisabled();
    }

    function _stopEarning(address account_, uint128 currentIndex_) internal pure override {
        revert EarningIsDisabled();
    }
}
