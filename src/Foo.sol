// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.25;

contract Foo {
    function getFoo() external pure returns (string memory) {
        return "Foo";
    }
}
