// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

interface IWrappedM is IERC20Extended {
    /* ============ Errors ============ */

    error ZeroRegistrar();

    error ZeroMToken();

    error NotApprovedEarner();

    error IsApprovedEarner();

    error DivisionByZero();
}
