// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

interface IMTokenLike {
    /* ============ View/Pure Functions ============ */

    function currentIndex() external view returns (uint128);

    function isEarning(address account) external view returns (bool);
}
