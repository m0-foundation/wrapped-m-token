// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IMorphoVaultFactoryLike {
    function isMetaMorpho(address vault) external view returns (bool isMetaMorpho);
}

interface IMorphoVaultLike {
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function balanceOf(address account) external view returns (uint256 balance);

    function lastTotalAssets() external view returns (uint256 totalAssets);
}

interface IWrappedMLike {
    function transfer(address recipient, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256 balance);
}
