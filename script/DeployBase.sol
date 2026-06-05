// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ContractHelper } from "../lib/common/src/libs/ContractHelper.sol";
import { Proxy } from "../lib/common/src/Proxy.sol";

import { WrappedMTokenMigratorV1 } from "../src/WrappedMTokenMigratorV1.sol";
import { WrappedMToken } from "../src/WrappedMToken.sol";

contract DeployBase {
    /**
     * @dev   Groups the Wrapped M governance role addresses passed to the Migrator's `initialize`.
     * @param admin                 The address of the Wrapped M admin.
     * @param freezeManager         The address of the Wrapped M freeze manager.
     * @param pauser                The address of the Wrapped M pauser.
     * @param forcedTransferManager The address of the Wrapped M forced transfer manager.
     * @param excessManager         The address of the Wrapped M excess manager.
     */
    struct UpgradeRoles {
        address admin;
        address freezeManager;
        address pauser;
        address forcedTransferManager;
        address excessManager;
    }

    /**
     * @dev    Deploys Wrapped M Token.
     * @param  mToken_                      The address of the M Token contract.
     * @param  registrar_                   The address of the Registrar contract.
     * @param  swapFacility_                The address of the SwapFacility contract.
     * @param  wrappedMMigrationAdmin_      The address of the Wrapped M Migration Admin.
     * @return wrappedMTokenImplementation_ The address of the deployed Wrapped M Token implementation.
     * @return wrappedMTokenProxy_          The address of the deployed Wrapped M Token proxy.
     */
    function deploy(
        address mToken_,
        address registrar_,
        address swapFacility_,
        address wrappedMMigrationAdmin_
    ) public virtual returns (address wrappedMTokenImplementation_, address wrappedMTokenProxy_) {
        wrappedMTokenImplementation_ = address(
            new WrappedMToken(mToken_, registrar_, swapFacility_, wrappedMMigrationAdmin_)
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
     * @param  earners_                     The addresses of the earners to migrate.
     * @param  roles_                        The Wrapped M governance role addresses.
     * @return wrappedMTokenImplementation_ The address of the deployed Wrapped M Token implementation.
     * @return wrappedMTokenMigrator_       The address of the deployed Wrapped M Token Migrator.
     */
    function deployUpgrade(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address swapFacility_,
        address wrappedMMigrationAdmin_,
        address[] memory earners_,
        UpgradeRoles memory roles_
    ) public virtual returns (address wrappedMTokenImplementation_, address wrappedMTokenMigrator_) {
        wrappedMTokenImplementation_ = address(
            new WrappedMToken(mToken_, registrar_, swapFacility_, wrappedMMigrationAdmin_)
        );

        wrappedMTokenMigrator_ = _deployMigrator(wrappedMTokenImplementation_, earners_, excessDestination_, roles_);
    }

    /// @dev Deploys the Wrapped M Token Migrator (split out to avoid stack-too-deep in `deployUpgrade`).
    function _deployMigrator(
        address implementation_,
        address[] memory earners_,
        address excessDestination_,
        UpgradeRoles memory roles_
    ) internal returns (address migrator_) {
        return
            address(
                new WrappedMTokenMigratorV1(
                    implementation_,
                    earners_,
                    roles_.admin,
                    roles_.freezeManager,
                    roles_.pauser,
                    roles_.forcedTransferManager,
                    roles_.excessManager,
                    excessDestination_
                )
            );
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
