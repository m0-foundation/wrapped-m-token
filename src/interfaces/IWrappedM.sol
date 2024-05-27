// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

interface IWrappedM is IERC20Extended {
    /* ============ Events ============ */

    event Claim(address indexed account, uint256 yield);

    event StartEarning(address indexed account);

    event StopEarning(address indexed account);

    /* ============ Custom Errors ============ */

    error NotApprovedEarner();

    error IsApprovedEarner();

    error DivisionByZero();

    error NotEarning();

    error NotAllocator();

    error NotEarningDelegate();

    /* ============ Interactive Functions ============ */

    function deposit(address destination, uint256 amount) external;

    function withdraw(address destination, uint256 amount) external;

    /* ============ View/Pure Functions ============ */

    function mToken() external view returns (address);
}
