// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

interface IMTokenLike {
    /* ============ Interactive Functions ============ */

    function transfer(address recipient, uint256 amount) external returns (bool success);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool success);

    /* ============ View/Pure Functions ============ */

    function balanceOf(address account) external view returns (uint256 balance);

    function currentIndex() external view returns (uint128 currentIndex);
}
