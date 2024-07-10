// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

interface IMTokenLike {
    /* ============ Interactive Functions ============ */

    function mint(address account, uint256 amount) external;

    function transfer(address recipient, uint256 amount) external returns (bool success);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool success);

    function startEarning() external;

    function stopEarning() external;

    function updateIndex() external returns (uint128);

    /* ============ View/Pure Functions ============ */

    function isEarning(address account) external view returns (bool earning);

    function balanceOf(address account) external view returns (uint256 balance);

    function currentIndex() external view returns (uint128 currentIndex);

    function ttgRegistrar() external view returns (address ttgRegistrar);
}
