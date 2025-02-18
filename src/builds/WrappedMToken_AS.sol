// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IWrappedMToken } from "../interfaces/IWrappedMToken.sol";

import { WrappedMToken } from "../WrappedMToken.sol";
import { Initializer as WrappedMTokenInitializer, WrappedMToken } from "../WrappedMToken.sol";

import { IAdministered, Initializer as AdministeredInitializer, Administered } from "../components/Administered.sol";

interface IWrappedMToken_AS is IAdministered, IWrappedMToken {
    function seize(address account_, address recipient_) external;
}

contract Initializer is AdministeredInitializer, WrappedMTokenInitializer {
    function initialize(
        string memory name_,
        string memory symbol_,
        address excessDestination_,
        address admin_
    ) external {
        WrappedMTokenInitializer._initialize(name_, symbol_, excessDestination_);
        AdministeredInitializer._initialize(admin_);
    }
}

/**
 * @title  Admin-controlled seizes.
 * @author M^0 Labs
 */
contract WrappedMToken_AS is IWrappedMToken_AS, Administered, WrappedMToken {
    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address initializer_
    ) WrappedMToken(name_, symbol_, mToken_, registrar_, initializer_) {}

    function seize(address account_, address recipient_) external {
        _revertIfNotAdmin();

        uint128 currentIndex_ = currentIndex();

        _claim(account_, currentIndex_);

        _transfer(account_, recipient_, uint240(balanceOf(account_)), currentIndex_);
    }
}
