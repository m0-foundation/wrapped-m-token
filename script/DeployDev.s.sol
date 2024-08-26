// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Script, console2 } from "../lib/forge-std/src/Script.sol";

import { DeployBase } from "./DeployBase.sol";

contract DeployDev is Script, DeployBase {
    error DeployerMismatch(address expected, address actual);

    error DeployerNonceTooHigh();

    error UnexpectedDeployerNonce();

    error CurrentNonceMismatch(uint64 expected, uint64 actual);

    error ExpectedProxyMismatch(address expected, address actual);

    error ResultingProxyMismatch(address expected, address actual);

    // NOTE: Ensure this is the correct M token testnet address.
    address internal constant _M_TOKEN = 0x0c941AD94Ca4A52EDAeAbF203b61bdd1807CeEC0;

    // NOTE: Ensure this is the correct Migration Admin testnet address.
    address internal constant _MIGRATION_ADMIN = 0x14521ECf225E912Feb2C7827CA79Ea13a744d8d5;

    // NOTE: Ensure this is the correct deployer testnet to use.
    address internal constant _EXPECTED_DEPLOYER = 0x7F299679524722E6D6c65C12069a47e98169ce0A;

    // NOTE: Ensure this is the correct nonce to use to deploy the Proxy on testnet.
    uint64 internal constant _DEPLOYER_PROXY_NONCE = 1;

    // NOTE: Ensure this is the correct expected testnet address for the Proxy.
    address internal constant _EXPECTED_PROXY = 0xa7d883B3578B2f5eE2B1A3A1e6bBf8a29DdA7563;

    function run() external {
        address deployer_ = vm.rememberKey(vm.envUint("DEV_PRIVATE_KEY"));

        console2.log("Deployer:", deployer_);

        if (deployer_ != _EXPECTED_DEPLOYER) revert DeployerMismatch(_EXPECTED_DEPLOYER, deployer_);

        uint64 currentNonce_ = vm.getNonce(deployer_);
        uint64 startNonce_ = _DEPLOYER_PROXY_NONCE - 1;

        if (currentNonce_ > startNonce_) revert DeployerNonceTooHigh();

        address expectedProxy_ = getExpectedWrappedMTokenProxy(deployer_, startNonce_);

        if (expectedProxy_ != _EXPECTED_PROXY) revert ExpectedProxyMismatch(_EXPECTED_PROXY, expectedProxy_);

        vm.startBroadcast(deployer_);

        // Burn nonces until to 1 before `_DEPLOYER_PROXY_NONCE` since implementation is deployed before proxy.
        while (currentNonce_ < startNonce_) {
            payable(deployer_).transfer(0);
            ++currentNonce_;
        }

        if (currentNonce_ != vm.getNonce(deployer_)) revert CurrentNonceMismatch(currentNonce_, vm.getNonce(deployer_));

        if (currentNonce_ != startNonce_) revert UnexpectedDeployerNonce();

        (address implementation_, address proxy_) = deploy(_M_TOKEN, _MIGRATION_ADMIN);

        vm.stopBroadcast();

        console2.log("Wrapped M Implementation address:", implementation_);
        console2.log("Wrapped M Proxy address:", proxy_);

        if (proxy_ != _EXPECTED_PROXY) revert ResultingProxyMismatch(_EXPECTED_PROXY, proxy_);
    }
}
