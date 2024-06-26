// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

contract MockM {
    address public ttgRegistrar;

    uint128 public currentIndex;

    mapping(address account => uint256 balance) public balanceOf;

    function transfer(address, uint256) external returns (bool success_) {
        return true;
    }

    function transferFrom(address, address, uint256) external returns (bool success_) {
        return true;
    }

    function setBalanceOf(address account_, uint256 balance_) external {
        balanceOf[account_] = balance_;
    }

    function setCurrentIndex(uint128 currentIndex_) external {
        currentIndex = currentIndex_;
    }

    function setTtgRegistrar(address ttgRegistrar_) external {
        ttgRegistrar = ttgRegistrar_;
    }
}

contract MockRegistrar {
    address public vault;

    mapping(bytes32 key => bytes32 value) public get;

    mapping(bytes32 list => mapping(address account => bool contains)) public listContains;

    function set(bytes32 key_, bytes32 value_) external {
        get[key_] = value_;
    }

    function setListContains(bytes32 list_, address account_, bool contains_) external {
        listContains[list_][account_] = contains_;
    }

    function setVault(address vault_) external {
        vault = vault_;
    }
}
