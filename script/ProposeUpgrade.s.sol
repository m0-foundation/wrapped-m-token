// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { console2 } from "../lib/forge-std/src/Script.sol";

import { MultiSigBatchBase } from "../lib/common/script/MultiSigBatchBase.sol";

import { IWrappedMToken } from "../src/interfaces/IWrappedMToken.sol";

import { DeployBase } from "./DeployBase.sol";
import { DeployConfig } from "./DeployConfig.sol";
import { EarnersAddresses } from "./EarnersAddresses.sol";

/**
 * @title  Proposes the WrappedMToken v1->v2 upgrade to the migration-admin Safe.
 * @dev    The deployer (a Safe proposer/delegate) deploys the new implementation +
 *         migrator — needing no privileges — then PROPOSES `migrate(migrator)` on the
 *         wM proxy to the current migration-admin Safe via the Safe Transaction Service.
 *         The Safe signers then approve and execute the migration in the Safe UI.
 *
 *         The Safe is read from the proxy's own `migrationAdmin()`, so each chain
 *         self-selects. Use this on the mainnets the upgrade runs on — Base, Arbitrum
 *         and Ethereum — which all have a Safe as that admin. Where it is an EOA
 *         (Sepolia, the rehearsal chain), use `DeployUpgrade` and let the EOA call
 *         `migrate` directly.
 *
 *         Run with `--broadcast --ffi`: `--broadcast` sends the two deployments and
 *         `--ffi` lets safe-utils post the proposal. Running it posts a REAL proposal.
 */
contract ProposeUpgrade is DeployBase, MultiSigBatchBase {
    // Same address on every chain wM is deployed on.
    address internal constant _WRAPPED_M_PROXY = 0x437cc33344a0B27A429f795ff6B469C72698B291;
    address internal constant _M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address internal constant _REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;
    address internal constant _SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;

    function run() external {
        DeployConfig.NetworkConfig memory config_ = DeployConfig.get(block.chainid);

        address deployer_ = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        // The account that must execute `migrate` is the currently deployed contract's
        // migration admin — read it from the proxy so each chain self-selects its Safe.
        address safe_ = IWrappedMToken(_WRAPPED_M_PROXY).migrationAdmin();

        console2.log("Chain ID:", block.chainid);
        console2.log("Deployer (proposer):", deployer_);
        console2.log("Migration-admin Safe:", safe_);
        console2.log("Wrapped M proxy (upgrade target):", _WRAPPED_M_PROXY);

        (address implementation_, address migrator_) = _broadcastUpgrade(deployer_, config_);

        console2.log("Wrapped M Implementation address:", implementation_);
        console2.log("Migrator address:", migrator_);

        // Simulate the migrate against a prank of the Safe first, to catch a bad batch
        // before it reaches the signers, then propose it to the Safe Transaction Service.
        _addToBatch(_WRAPPED_M_PROXY, abi.encodeCall(IWrappedMToken.migrate, (migrator_)));
        _simulateBatch(safe_);
        _proposeBatch(safe_, deployer_);

        console2.log("Proposed migrate(migrator) to the Safe. Sign + execute in the Safe UI.");
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
