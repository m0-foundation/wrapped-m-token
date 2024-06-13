// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

interface IWrappedM is IERC20Extended {
    /* ============ Events ============ */

    event Claim(address indexed account, uint256 yield);

    event ExcessClaim(uint256 yield);

    event StartEarning(address indexed account);

    event StopEarning(address indexed account);

    /* ============ Custom Errors ============ */

    error ApprovedEarner();

    error DivisionByZero();

    error NotApprovedEarner();

    error ZeroMToken();

    /* ============ Interactive Functions ============ */

    function claim() external returns (uint240 yield);

    function claimExcess() external returns (uint240 yield);

    function deposit(address destination, uint256 amount) external;

    function startEarning(address account) external;

    function stopEarning(address account) external;

    function withdraw(address destination, uint256 amount) external;

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account) external view returns (uint240 yield);

    function currentMIndex() external view returns (uint128 index);

    function excess() external view returns (uint240 yield);

    function mToken() external view returns (address mToken);

    function principalOfTotalEarningSupply() external view returns (uint112 principal);

    function indexOfTotalEarningSupply() external view returns (uint128 index);

    function totalNonEarningSupply() external view returns (uint240 totalSupply);

    function registrar() external view returns (address registrar);

    function totalAccruedYield() external view returns (uint240 yield);

    function totalEarningSupply() external view returns (uint240 totalSupply);

    function vault() external view returns (address vault);
}
