// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContractHelper } from "../lib/common/src/libs/ContractHelper.sol";

import { WrappedMToken } from "../src/WrappedMToken.sol";
import { Proxy } from "../src/Proxy.sol";

contract DeployBase {
    /**
     * @dev    Deploys Wrapped M Token.
     * @param  mToken_         The address the M Token contract.
     * @param  migrationAdmin_ The address the Migration Admin.
     * @return implementation_ The address of the deployed Wrapped M Token implementation.
     * @return proxy_          The address of the deployed Wrapped M Token proxy.
     */
    function deploy(
        address mToken_,
        address migrationAdmin_
    ) public virtual returns (address implementation_, address proxy_) {
        // Wrapped M token needs `mToken_` and `migrationAdmin_` addresses.
        // Proxy needs `implementation_` addresses.

        implementation_ = address(new WrappedMToken(mToken_, migrationAdmin_));
        proxy_ = address(new Proxy(implementation_));
    }

    function _getExpectedWrappedMTokenImplementation(
        address deployer_,
        uint256 deployerNonce_
    ) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_);
    }

    function getExpectedWrappedMTokenImplementation(
        address deployer_,
        uint256 deployerNonce_
    ) public pure virtual returns (address) {
        return _getExpectedWrappedMTokenImplementation(deployer_, deployerNonce_);
    }

    function _getExpectedWrappedMTokenProxy(address deployer_, uint256 deployerNonce_) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
    }

    function getExpectedWrappedMTokenProxy(
        address deployer_,
        uint256 deployerNonce_
    ) public pure virtual returns (address) {
        return _getExpectedWrappedMTokenProxy(deployer_, deployerNonce_);
    }

    function getDeployerNonceAfterProtocolDeployment(uint256 deployerNonce_) public pure virtual returns (uint256) {
        return deployerNonce_ + 2;
    }
}
