// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

interface IWrappedM is IERC20Extended {
    /* ============ Events ============ */

    /* ============ Custom Errors ============ */

    error NotEarner();

    error DivisionByZero();

    /* ============ Interactive Functions ============ */

    function deposit(address account, uint256 amount) external returns (uint256 shares);

    function withdraw(address account, uint256 shares) external;

    /* ============ View/Pure Functions ============ */

    function mToken() external view returns (address);
}
