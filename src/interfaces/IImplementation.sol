// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IImplementation {
    function initializer() external view returns (address initializer_);
}
