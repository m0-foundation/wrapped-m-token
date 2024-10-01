// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IMorphoVaultFactoryLike {
    function isMetaMorpho(address vault) external view returns (bool isMetaMorpho);
}

interface IMorphoVaultLike {
    function asset() external view returns (address asset);
}

interface IWrappedMLike {
    function transfer(address recipient, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256 balance);
}
