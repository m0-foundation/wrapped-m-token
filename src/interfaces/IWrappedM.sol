// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { IMigratable } from "./IMigratable.sol";

interface IWrappedM is IMigratable, IERC20Extended {
    /* ============ Events ============ */

    event Claim(address indexed account, uint256 yield);

    event ExcessClaim(uint256 yield);

    event StartedEarning(address indexed account);

    event StoppedEarning(address indexed account);

    /* ============ Custom Errors ============ */

    error ApprovedEarner();

    error NotApprovedEarner();

    error ZeroMToken();

    /* ============ Interactive Functions ============ */

    function wrap(address destination, uint256 amount) external;

    function unwrap(address destination, uint256 amount) external;

    function claimFor(address account) external returns (uint240 yield);

    function claimExcess() external returns (uint240 yield);

    function startEarningFor(address account) external;

    function stopEarningFor(address account) external;

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account) external view returns (uint240 yield);

    function currentIndex() external view returns (uint128 index);

    function excess() external view returns (uint240 yield);

    function mToken() external view returns (address mToken);

    function totalNonEarningSupply() external view returns (uint240 totalSupply);

    function registrar() external view returns (address registrar);

    function totalAccruedYield() external view returns (uint240 yield);

    function totalEarningSupply() external view returns (uint240 totalSupply);

    function vault() external view returns (address vault);
}
