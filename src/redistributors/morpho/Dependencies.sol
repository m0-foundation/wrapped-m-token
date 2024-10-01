// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

type Id is bytes32;

interface IMorphoBlueLIke {
    function extSloads(bytes32[] memory slots) external view returns (bytes32[] memory);
}

interface IMorphoVaultFactoryLike {
    function isMetaMorpho(address vault) external view returns (bool isMetaMorpho);
}

interface IMorphoVaultLike {
    function totalSupply() external view returns (uint256 totalSupply);

    function withdrawQueue(uint256 index) external view returns (Id marketId);

    function withdrawQueueLength() external view returns (uint256 length);
}

interface IWrappedMLike {
    function transfer(address recipient, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256 balance);
}
