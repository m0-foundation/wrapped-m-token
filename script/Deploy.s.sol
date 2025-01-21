// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Script, console2 } from "../lib/forge-std/src/Script.sol";

import { DeployBase } from "./DeployBase.sol";

contract DeployProduction is Script, DeployBase {
    error DeployerMismatch(address expected, address actual);

    error DeployerNonceTooHigh();

    error UnexpectedDeployerNonce();

    error CurrentNonceMismatch(uint64 expected, uint64 actual);

    error ExpectedProxyMismatch(address expected, address actual);

    error ResultingProxyMismatch(address expected, address actual);

    function run() external {
        address deployer_ = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        address expectedDeployer_ = vm.envAddress("DEPLOYER");

        uint64 deployerProxyNonce_ = uint64(vm.envUint("DEPLOYER_PROXY_NONCE"));

        address expectedProxy_ = vm.envAddress("EXPECTED_PROXY");

        console2.log("Deployer:", deployer_);

        if (deployer_ != expectedDeployer_) revert DeployerMismatch(expectedDeployer_, deployer_);

        uint64 currentNonce_ = vm.getNonce(deployer_);

        uint64 startNonce_ = currentNonce_;
        address implementation_;
        address proxy_;

        while (true) {
            if (startNonce_ > deployerProxyNonce_) revert DeployerNonceTooHigh();

            (implementation_, proxy_) = mockDeploy(deployer_, startNonce_);

            if (proxy_ == expectedProxy_) break;

            ++startNonce_;
        }

        vm.startBroadcast(deployer_);

        // Burn nonces until to `currentNonce_ == startNonce_`.
        while (currentNonce_ < startNonce_) {
            payable(deployer_).transfer(0);
            ++currentNonce_;
        }

        if (currentNonce_ != vm.getNonce(deployer_)) revert CurrentNonceMismatch(currentNonce_, vm.getNonce(deployer_));

        if (currentNonce_ != startNonce_) revert UnexpectedDeployerNonce();

        (implementation_, proxy_) = deploy(
            vm.envAddress("M_TOKEN"),
            vm.envAddress("REGISTRAR"),
            vm.envAddress("EXCESS_DESTINATION"),
            vm.envAddress("MIGRATION_ADMIN")
        );

        vm.stopBroadcast();

        console2.log("Wrapped M Implementation address:", implementation_);
        console2.log("Wrapped M Proxy address:", proxy_);

        if (proxy_ != expectedProxy_) revert ResultingProxyMismatch(expectedProxy_, proxy_);
    }
}
