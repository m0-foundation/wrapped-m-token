// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

interface IInitializable {
    function initialize(address implementation_, bytes calldata initializationArguments_) external;
}
