// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ContractHelper } from "../lib/common/src/libs/ContractHelper.sol";
import { Proxy } from "../lib/common/src/Proxy.sol";

import { MigratorV1 } from "../src/MigratorV1.sol";
import { WrappedMToken } from "../src/WrappedMToken.sol";

contract DeployBase {
    /**
     * @dev    Deploys Wrapped M Token.
     * @param  mToken_            The address of the M Token contract.
     * @param  registrar_         The address of the Registrar contract.
     * @param  excessDestination_ The address of the excess destination.
     * @param  migrationAdmin_    The address of the Migration Admin.
     * @return implementation_    The address of the deployed Wrapped M Token implementation.
     * @return proxy_             The address of the deployed Wrapped M Token proxy.
     */
    function deploy(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address migrationAdmin_
    ) public virtual returns (address implementation_, address proxy_) {
        // Wrapped M token needs `mToken_`, `registrar_`, `excessDestination_`, and `migrationAdmin_` addresses.
        // Proxy needs `implementation_` addresses.

        implementation_ = address(new WrappedMToken(mToken_, registrar_, excessDestination_, migrationAdmin_));
        proxy_ = address(new Proxy(implementation_));
    }

    /**
     * @dev    Deploys Wrapped M Token components needed to upgrade an existing Wrapped M proxy.
     * @param  mToken_            The address of the M Token contract.
     * @param  registrar_         The address of the Registrar contract.
     * @param  excessDestination_ The address of the excess destination.
     * @param  migrationAdmin_    The address of the Migration Admin.
     * @return implementation_    The address of the deployed Wrapped M Token implementation.
     * @return migrator_          The address of the deployed Migrator.
     */
    function deployUpgrade(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address migrationAdmin_,
        address[] memory earners_
    ) public virtual returns (address implementation_, address migrator_) {
        // Wrapped M token needs `mToken_`, `registrar_`, `excessDestination_`, and `migrationAdmin_` addresses.
        // Migrator needs `implementation_` addresses.

        implementation_ = address(new WrappedMToken(mToken_, registrar_, excessDestination_, migrationAdmin_));
        migrator_ = address(new MigratorV1(implementation_, earners_));
    }

    /**
     * @dev    Mock deploys Wrapped M Token, returning the would-be addresses.
     * @param  deployer_       The address of the deployer.
     * @param  deployerNonce_  The nonce of the deployer.
     * @return implementation_ The address of the would-be Wrapped M Token implementation.
     * @return proxy_          The address of the would-be Wrapped M Token proxy.
     */
    function mockDeploy(
        address deployer_,
        uint256 deployerNonce_
    ) public view virtual returns (address implementation_, address proxy_) {
        // Wrapped M token needs `mToken_`, `registrar_`, `excessDestination_`, and `migrationAdmin_` addresses.
        // Proxy needs `implementation_` addresses.

        implementation_ = ContractHelper.getContractFrom(deployer_, deployerNonce_);
        proxy_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
    }

    /**
     * @dev    Mock deploys Wrapped M Token, returning the would-be addresses.
     * @param  deployer_       The address of the deployer.
     * @param  deployerNonce_  The nonce of the deployer.
     * @return implementation_ The address of the would-be Wrapped M Token implementation.
     * @return migrator_       The address of the would-be Migrator.
     */
    function mockDeployUpgrade(
        address deployer_,
        uint256 deployerNonce_
    ) public view virtual returns (address implementation_, address migrator_) {
        // Wrapped M token needs `mToken_`, `registrar_`, `excessDestination_`, and `migrationAdmin_` addresses.
        // Migrator needs `implementation_` addresses.

        implementation_ = ContractHelper.getContractFrom(deployer_, deployerNonce_);
        migrator_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
    }
}
