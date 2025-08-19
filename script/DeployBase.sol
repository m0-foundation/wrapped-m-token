// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ContractHelper } from "../lib/common/src/libs/ContractHelper.sol";
import { Proxy } from "../lib/common/src/Proxy.sol";

import { WrappedMTokenMigratorV1 } from "../src/WrappedMTokenMigratorV1.sol";
import { WrappedMToken } from "../src/WrappedMToken.sol";

contract DeployBase {
    /**
     * @dev    Deploys Wrapped M Token.
     * @param  mToken_                      The address of the M Token contract.
     * @param  registrar_                   The address of the Registrar contract.
     * @param  swapFacility_                The address of the SwapFacility contract.
     * @param  excessDestination_           The address of the excess destination.
     * @param  wrappedMMigrationAdmin_      The address of the Wrapped M Migration Admin.
     * @return wrappedMTokenImplementation_ The address of the deployed Wrapped M Token implementation.
     * @return wrappedMTokenProxy_          The address of the deployed Wrapped M Token proxy.
     */
    function deploy(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address swapFacility_,
        address wrappedMMigrationAdmin_
    ) public virtual returns (address wrappedMTokenImplementation_, address wrappedMTokenProxy_) {
        wrappedMTokenImplementation_ = address(
            new WrappedMToken(mToken_, registrar_, excessDestination_, swapFacility_, wrappedMMigrationAdmin_)
        );

        wrappedMTokenProxy_ = address(new Proxy(wrappedMTokenImplementation_));
    }

    /**
     * @dev    Deploys Wrapped M Token components needed to upgrade an existing Wrapped M proxy.
     * @param  mToken_                      The address of the M Token contract.
     * @param  registrar_                   The address of the Registrar contract.
     * @param  excessDestination_           The address of the excess destination.
     * @param  swapFacility_                The address of the SwapFacility contract.
     * @param  wrappedMMigrationAdmin_      The address of the Wrapped M Migration Admin.
     * @return wrappedMTokenImplementation_ The address of the deployed Wrapped M Token implementation.
     * @return wrappedMTokenMigrator_       The address of the deployed Wrapped M Token Migrator.
     */
    function deployUpgrade(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address swapFacility_,
        address wrappedMMigrationAdmin_,
        address[] memory earners_
    ) public virtual returns (address wrappedMTokenImplementation_, address wrappedMTokenMigrator_) {
        wrappedMTokenImplementation_ = address(
            new WrappedMToken(mToken_, registrar_, excessDestination_, swapFacility_, wrappedMMigrationAdmin_)
        );

        wrappedMTokenMigrator_ = address(new WrappedMTokenMigratorV1(wrappedMTokenImplementation_, earners_));
    }

    /**
     * @dev    Mock deploys Wrapped M Token, returning the would-be addresses.
     * @param  deployer_                    The address of the deployer.
     * @param  deployerNonce_               The nonce of the deployer.
     * @return wrappedMTokenImplementation_ The address of the would-be Wrapped M Token implementation.
     * @return wrappedMTokenProxy_          The address of the would-be Wrapped M Token proxy.
     */
    function mockDeploy(
        address deployer_,
        uint256 deployerNonce_
    ) public view virtual returns (address wrappedMTokenImplementation_, address wrappedMTokenProxy_) {
        wrappedMTokenImplementation_ = ContractHelper.getContractFrom(deployer_, deployerNonce_);
        wrappedMTokenProxy_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
    }

    /**
     * @dev    Mock deploys Wrapped M Token, returning the would-be addresses.
     * @param  deployer_                    The address of the deployer.
     * @param  deployerNonce_               The nonce of the deployer.
     * @return wrappedMTokenImplementation_ The address of the would-be Wrapped M Token implementation.
     * @return wrappedMTokenMigrator_       The address of the deployed Wrapped M Token Migrator.
     */
    function mockDeployUpgrade(
        address deployer_,
        uint256 deployerNonce_
    ) public view virtual returns (address wrappedMTokenImplementation_, address wrappedMTokenMigrator_) {
        wrappedMTokenImplementation_ = ContractHelper.getContractFrom(deployer_, deployerNonce_);
        wrappedMTokenMigrator_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
    }
}
