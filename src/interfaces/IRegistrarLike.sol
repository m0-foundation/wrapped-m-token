// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IRegistrarLike {
    function get(bytes32 key) external view returns (bytes32 value);

    function listContains(bytes32 list, address account) external view returns (bool);

    function vault() external view returns (address vault);
}
