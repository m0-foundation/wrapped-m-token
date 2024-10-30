// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ContractHelper } from "../lib/common/src/libs/ContractHelper.sol";

import { SmartMToken } from "../src/SmartMToken.sol";
import { EarnerManager } from "../src/EarnerManager.sol";
import { Proxy } from "../src/Proxy.sol";

contract DeployBase {
    /**
     * @dev    Deploys Smart M Token.
     * @param  mToken_                      The address of the M Token contract.
     * @param  registrar_                   The address of the Registrar contract.
     * @param  excessDestination_           The address of the excess destination.
     * @param  migrationAdmin_              The address of the Migration Admin.
     * @return earnerManagerImplementation_ The address of the deployed Earner Manager implementation.
     * @return earnerManagerProxy_          The address of the deployed Earner Manager proxy.
     * @return smartMTokenImplementation_   The address of the deployed Smart M Token implementation.
     * @return smartMTokenProxy_            The address of the deployed Smart M Token proxy.
     */
    function deploy(
        address mToken_,
        address registrar_,
        address excessDestination_,
        address migrationAdmin_
    )
        public
        virtual
        returns (
            address earnerManagerImplementation_,
            address earnerManagerProxy_,
            address smartMTokenImplementation_,
            address smartMTokenProxy_
        )
    {
        // Earner Manager Proxy constructor needs only known values.
        // Earner Manager Implementation constructor needs `earnerManagerImplementation_`.
        // Smart M Token Implementation constructor needs `earnerManagerProxy_`.
        // Smart M Token Proxy constructor needs `smartMTokenImplementation_`.

        earnerManagerImplementation_ = address(new EarnerManager(registrar_, migrationAdmin_));

        earnerManagerProxy_ = address(new Proxy(earnerManagerImplementation_));

        smartMTokenImplementation_ = address(
            new SmartMToken(mToken_, registrar_, earnerManagerProxy_, excessDestination_, migrationAdmin_)
        );

        smartMTokenProxy_ = address(new Proxy(smartMTokenImplementation_));
    }

    function _getExpectedEarnerManager(address deployer_, uint256 deployerNonce_) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_);
    }

    function getExpectedEarnerManager(address deployer_, uint256 deployerNonce_) public pure virtual returns (address) {
        return _getExpectedEarnerManager(deployer_, deployerNonce_);
    }

    function _getExpectedEarnerManagerProxy(address deployer_, uint256 deployerNonce_) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
    }

    function getExpectedEarnerManagerProxy(
        address deployer_,
        uint256 deployerNonce_
    ) public pure virtual returns (address) {
        return _getExpectedEarnerManagerProxy(deployer_, deployerNonce_);
    }

    function _getExpectedSmartMTokenImplementation(
        address deployer_,
        uint256 deployerNonce_
    ) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_ + 2);
    }

    function getExpectedSmartMTokenImplementation(
        address deployer_,
        uint256 deployerNonce_
    ) public pure virtual returns (address) {
        return _getExpectedSmartMTokenImplementation(deployer_, deployerNonce_);
    }

    function _getExpectedSmartMTokenProxy(address deployer_, uint256 deployerNonce_) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_ + 3);
    }

    function getExpectedSmartMTokenProxy(
        address deployer_,
        uint256 deployerNonce_
    ) public pure virtual returns (address) {
        return _getExpectedSmartMTokenProxy(deployer_, deployerNonce_);
    }

    function getDeployerNonceAfterSmartMTokenDeployment(uint256 deployerNonce_) public pure virtual returns (uint256) {
        return deployerNonce_ + 4;
    }
}
