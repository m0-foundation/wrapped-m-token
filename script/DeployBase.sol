// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ContractHelper } from "../lib/common/src/libs/ContractHelper.sol";
import { Proxy } from "../lib/common/src/Proxy.sol";

import { EarnerManager } from "../src/EarnerManager.sol";
import { WrappedMTokenMigratorV1 } from "../src/WrappedMTokenMigratorV1.sol";
import { WrappedMToken } from "../src/WrappedMToken.sol";

contract DeployBase {
    /**
     * @dev    Deploys Wrapped M Token.
     * @param  mToken_                      The address of the M Token contract.
     * @param  registrar_                   The address of the Registrar contract.
     * @param  excessDestination_           The address of the excess destination.
     * @param  wrappedMMigrationAdmin_      The address of the Wrapped M Migration Admin.
     * @param  earnerManagerMigrationAdmin_ The address of the Earner Manager Migration Admin.
     * @return earnerManagerImplementation_ The address of the deployed Earner Manager implementation.
     * @return earnerManagerProxy_          The address of the deployed Earner Manager proxy.
     * @return wrappedMTokenImplementation_ The address of the deployed Wrapped M Token implementation.
     * @return wrappedMTokenProxy_          The address of the deployed Wrapped M Token proxy.
     */
    function deploy(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address wrappedMMigrationAdmin_,
        address earnerManagerMigrationAdmin_
    )
        public
        virtual
        returns (
            address earnerManagerImplementation_,
            address earnerManagerProxy_,
            address wrappedMTokenImplementation_,
            address wrappedMTokenProxy_
        )
    {
        // Earner Manager Implementation constructor needs only known values.
        // Earner Manager Proxy constructor needs `earnerManagerImplementation_`.
        // Wrapped M Token Implementation constructor needs `earnerManagerProxy_`.
        // Wrapped M Token Proxy constructor needs `wrappedMTokenImplementation_`.

        earnerManagerImplementation_ = address(new EarnerManager(registrar_));

        earnerManagerProxy_ = address(new Proxy(earnerManagerImplementation_));

        wrappedMTokenImplementation_ = address(
            new WrappedMToken(mToken_, registrar_, earnerManagerProxy_, excessDestination_)
        );

        wrappedMTokenProxy_ = address(new Proxy(wrappedMTokenImplementation_));

        EarnerManager(earnerManagerProxy_).initialize(earnerManagerMigrationAdmin_);
        WrappedMToken(wrappedMTokenProxy_).initialize(wrappedMMigrationAdmin_);
    }

    /**
     * @dev    Deploys Wrapped M Token components needed to upgrade an existing Wrapped M proxy.
     * @param  mToken_                      The address of the M Token contract.
     * @param  registrar_                   The address of the Registrar contract.
     * @param  excessDestination_           The address of the excess destination.
     * @param  wrappedMMigrationAdmin_      The address of the Wrapped M Migration Admin.
     * @param  earnerManagerMigrationAdmin_ The address of the Earner Manager Migration Admin.
     * @return earnerManagerImplementation_ The address of the deployed Earner Manager implementation.
     * @return earnerManagerProxy_          The address of the deployed Earner Manager proxy.
     * @return wrappedMTokenImplementation_ The address of the deployed Wrapped M Token implementation.
     * @return wrappedMTokenMigrator_       The address of the deployed Wrapped M Token Migrator.
     */
    function deployUpgrade(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address wrappedMMigrationAdmin_,
        address earnerManagerMigrationAdmin_,
        address[] memory earners_
    )
        public
        virtual
        returns (
            address earnerManagerImplementation_,
            address earnerManagerProxy_,
            address wrappedMTokenImplementation_,
            address wrappedMTokenMigrator_
        )
    {
        // Earner Manager Implementation constructor needs only known values.
        // Earner Manager Proxy constructor needs `earnerManagerImplementation_`.
        // Wrapped M Token Implementation constructor needs `earnerManagerProxy_`.
        // Migrator needs `wrappedMTokenImplementation_` addresses.

        earnerManagerImplementation_ = address(new EarnerManager(registrar_));

        earnerManagerProxy_ = address(new Proxy(earnerManagerImplementation_));

        wrappedMTokenImplementation_ = address(
            new WrappedMToken(mToken_, registrar_, earnerManagerProxy_, excessDestination_)
        );

        wrappedMTokenMigrator_ = address(
            new WrappedMTokenMigratorV1(wrappedMTokenImplementation_, earners_, wrappedMMigrationAdmin_)
        );

        EarnerManager(earnerManagerProxy_).initialize(earnerManagerMigrationAdmin_);
    }

    /**
     * @dev    Mock deploys Wrapped M Token, returning the would-be addresses.
     * @param  deployer_                    The address of the deployer.
     * @param  deployerNonce_               The nonce of the deployer.
     * @return earnerManagerImplementation_ The address of the would-be Earner Manager implementation.
     * @return earnerManagerProxy_          The address of the would-be Earner Manager proxy.
     * @return wrappedMTokenImplementation_ The address of the would-be Wrapped M Token implementation.
     * @return wrappedMTokenProxy_          The address of the would-be Wrapped M Token proxy.
     */
    function mockDeploy(
        address deployer_,
        uint256 deployerNonce_
    )
        public
        view
        virtual
        returns (
            address earnerManagerImplementation_,
            address earnerManagerProxy_,
            address wrappedMTokenImplementation_,
            address wrappedMTokenProxy_
        )
    {
        // Earner Manager Implementation constructor needs only known values.
        // Earner Manager Proxy constructor needs `earnerManagerImplementation_`.
        // Wrapped M Token Implementation constructor needs `earnerManagerProxy_`.
        // Wrapped M Token Proxy constructor needs `wrappedMTokenImplementation_`.

        earnerManagerImplementation_ = ContractHelper.getContractFrom(deployer_, deployerNonce_);
        earnerManagerProxy_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
        wrappedMTokenImplementation_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 2);
        wrappedMTokenProxy_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 3);
    }

    /**
     * @dev    Mock deploys Wrapped M Token, returning the would-be addresses.
     * @param  deployer_                    The address of the deployer.
     * @param  deployerNonce_               The nonce of the deployer.
     * @return earnerManagerImplementation_ The address of the would-be Earner Manager implementation.
     * @return earnerManagerProxy_          The address of the would-be Earner Manager proxy.
     * @return wrappedMTokenImplementation_ The address of the would-be Wrapped M Token implementation.
     * @return wrappedMTokenMigrator_       The address of the deployed Wrapped M Token Migrator.
     */
    function mockDeployUpgrade(
        address deployer_,
        uint256 deployerNonce_
    )
        public
        view
        virtual
        returns (
            address earnerManagerImplementation_,
            address earnerManagerProxy_,
            address wrappedMTokenImplementation_,
            address wrappedMTokenMigrator_
        )
    {
        // Earner Manager Implementation constructor needs only known values.
        // Earner Manager Proxy constructor needs `earnerManagerImplementation_`.
        // Wrapped M Token Implementation constructor needs `earnerManagerProxy_`.
        // Migrator needs `wrappedMTokenImplementation_` addresses.

        earnerManagerImplementation_ = ContractHelper.getContractFrom(deployer_, deployerNonce_);
        earnerManagerProxy_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
        wrappedMTokenImplementation_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 2);
        wrappedMTokenMigrator_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 3);
    }
}
