// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IWrappedMToken } from "../interfaces/IWrappedMToken.sol";

import { Initializer as WrappedMTokenInitializer, WrappedMToken } from "../WrappedMToken.sol";

interface IWrappedMToken_V is IWrappedMToken {}

contract Initializer is WrappedMTokenInitializer {
    function initialize(string memory name_, string memory symbol_, address excessDestination_) external {
        WrappedMTokenInitializer._initialize(name_, symbol_, excessDestination_);
    }
}

/**
 * @title  Vanilla, no permissions.
 * @author M^0 Labs
 */
contract WrappedMToken_V is IWrappedMToken_V, WrappedMToken {
    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address initializer_
    ) WrappedMToken(name_, symbol_, mToken_, registrar_, initializer_) {}

    function _beforeStopEarning(address account_, uint128 currentIndex_) internal override {
        _claim(account_, currentIndex_);

        super._beforeStopEarning(account_, currentIndex_);
    }
}
