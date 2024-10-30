// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Script, console2 } from "../lib/forge-std/src/Script.sol";

import { DeployBase } from "./DeployBase.sol";

contract DeployUpgradeMainnet is Script, DeployBase {
    error DeployerMismatch(address expected, address actual);

    error DeployerNonceTooHigh();

    error UnexpectedDeployerNonce();

    error CurrentNonceMismatch(uint64 expected, uint64 actual);

    error ResultingMigratorMismatch(address expected, address actual);

    address internal constant _REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;

    // NOTE: Ensure this is the correct Excess Destination mainnet address.
    address internal constant _EXCESS_DESTINATION = 0xd7298f620B0F752Cf41BD818a16C756d9dCAA34f; // Vault

    address internal constant _M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;

    // NOTE: Ensure this is the correct Migration Admin mainnet address.
    address internal constant _WRAPPED_M_MIGRATION_ADMIN = 0x431169728D75bd02f4053435b87D15c8d1FB2C72;

    // NOTE: Ensure this is the correct Migration Admin mainnet address.
    address internal constant _EARNER_MANAGER_MIGRATION_ADMIN = 0x431169728D75bd02f4053435b87D15c8d1FB2C72;

    address internal constant _WRAPPED_M_PROXY = 0x437cc33344a0B27A429f795ff6B469C72698B291; // Mainnet address for the Proxy.

    // NOTE: Ensure this is the correct mainnet deployer to use.
    address internal constant _EXPECTED_DEPLOYER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;

    // NOTE: Ensure this is the correct nonce to use to deploy the Migrator on mainnet.
    uint64 internal constant _DEPLOYER_MIGRATOR_NONCE = 40;

    // NOTE: Ensure this is the correct expected mainnet address for the Migrator.
    address internal constant _EXPECTED_WRAPPED_M_MIGRATOR = address(0);

    function run() external {
        address deployer_ = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        console2.log("Deployer:", deployer_);

        if (deployer_ != _EXPECTED_DEPLOYER) revert DeployerMismatch(_EXPECTED_DEPLOYER, deployer_);

        uint64 currentNonce_ = vm.getNonce(deployer_);

        uint64 startNonce_ = currentNonce_;
        address earnerManagerImplementation_;
        address earnerManagerProxy_;
        address wrappedMTokenImplementation_;
        address wrappedMTokenMigrator_;

        while (true) {
            if (startNonce_ > _DEPLOYER_MIGRATOR_NONCE) revert DeployerNonceTooHigh();

            (
                earnerManagerImplementation_,
                earnerManagerProxy_,
                wrappedMTokenImplementation_,
                wrappedMTokenMigrator_
            ) = mockDeployUpgrade(deployer_, startNonce_);

            if (wrappedMTokenMigrator_ == _EXPECTED_WRAPPED_M_MIGRATOR) break;

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

        (
            earnerManagerImplementation_,
            earnerManagerProxy_,
            wrappedMTokenImplementation_,
            wrappedMTokenMigrator_
        ) = deployUpgrade(
            _M_TOKEN,
            _REGISTRAR,
            _EXCESS_DESTINATION,
            _WRAPPED_M_MIGRATION_ADMIN,
            _EARNER_MANAGER_MIGRATION_ADMIN
        );

        vm.stopBroadcast();

        console2.log("Earner Manager Implementation address:", earnerManagerImplementation_);
        console2.log("Earner Manager Proxy address:", earnerManagerProxy_);
        console2.log("Wrapped M Implementation address:", wrappedMTokenImplementation_);
        console2.log("Migrator address:", wrappedMTokenMigrator_);

        if (wrappedMTokenMigrator_ != _EXPECTED_WRAPPED_M_MIGRATOR) {
            revert ResultingMigratorMismatch(_EXPECTED_WRAPPED_M_MIGRATOR, wrappedMTokenMigrator_);
        }
    }
}
