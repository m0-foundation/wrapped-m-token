// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

interface IProxied {
    event Migrate(address indexed migrator, address indexed oldImplementation, address indexed newImplementation);

    error ZeroMigrator();

    function migrate() external;

    function implementation() external view returns (address implementation);
}
