// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Script, console2 } from "../lib/forge-std/src/Script.sol";

import { DeployBase } from "./DeployBase.sol";
import { DeployConfig } from "./DeployConfig.sol";
import { EarnersAddresses } from "./EarnersAddresses.sol";

/**
 * @title  Deploys the WrappedMToken v1->v2 upgrade.
 * @dev    This is the EOA-admin path, kept for Sepolia — the rehearsal chain, whose
 *         `migrationAdmin` is an EOA, so there is no Safe to propose to. The mainnets the
 *         upgrade runs on (Base, Arbitrum, Ethereum) all have a Safe admin and use
 *         `ProposeUpgrade` instead, which deploys AND queues `migrate` in one run.
 *
 *         Chain-agnostic addresses are constants below; per-network values come from DeployConfig;
 *         earners from EarnersAddresses. The deployer needs no privileges: it only deploys the
 *         implementation + migrator, then the migration admin calls `migrate(migrator)` on the
 *         proxy with the logged migrator address.
 */
contract DeployUpgrade is Script, DeployBase {
    // Same address on every chain wM is deployed on.
    address internal constant _WRAPPED_M_PROXY = 0x437cc33344a0B27A429f795ff6B469C72698B291;
    address internal constant _M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address internal constant _REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;
    address internal constant _SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;

    function run() external {
        DeployConfig.NetworkConfig memory config_ = DeployConfig.get(block.chainid);

        address deployer_ = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        console2.log("Chain ID:", block.chainid);
        console2.log("Deployer:", deployer_);
        console2.log("Wrapped M proxy (upgrade target):", _WRAPPED_M_PROXY);

        (address implementation_, address migrator_) = _broadcastUpgrade(deployer_, config_);

        console2.log("Wrapped M Implementation address:", implementation_);
        console2.log("Migrator address:", migrator_);

        // NOTE: The migration admin completes the upgrade by calling `migrate(migrator)` on the wM
        //       proxy with the migrator address logged above; the deployer here needs no privileges.
    }

    /// @dev Isolates the many-argument `deployUpgrade` call in its own frame to avoid stack-too-deep.
    function _broadcastUpgrade(
        address deployer_,
        DeployConfig.NetworkConfig memory config_
    ) internal returns (address implementation_, address migrator_) {
        address[] memory earners_ = EarnersAddresses.getEarners(block.chainid);

        vm.startBroadcast(deployer_);

        (implementation_, migrator_) = deployUpgrade(
            _M_TOKEN,
            _REGISTRAR,
            config_.excessDestination,
            _SWAP_FACILITY,
            config_.migrationAdmin,
            earners_,
            UpgradeRoles({
                admin: config_.admin,
                freezeManager: config_.freezeManager,
                pauser: config_.pauser,
                forcedTransferManager: config_.forcedTransferManager,
                excessManager: config_.excessManager
            })
        );

        vm.stopBroadcast();
    }
}
