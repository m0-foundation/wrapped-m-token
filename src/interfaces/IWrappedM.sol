// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

interface IWrappedM is IERC20Extended {
    /* ============ Events ============ */

    /* ============ Custom Errors ============ */

    error NotEarner();

    error NotWrappedMYield();

    /* ============ Interactive Functions ============ */

    function deposit(address account, uint256 amount) external returns (uint256 wrappedMYieldTokenId);

    function withdraw(address account, uint256 wrappedMYieldTokenId) external returns (uint256 amount, uint256 yield);

    /* ============ View/Pure Functions ============ */

    function mToken() external view returns (address mToken);

    function wrappedMYield() external view returns (address wrappedMYield);
}
