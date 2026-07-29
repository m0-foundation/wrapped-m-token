// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

/**
 * @title  Per-network configuration for the WrappedMToken v1->v2 upgrade.
 * @author M0 Labs
 * @dev    Only the values that genuinely differ per chain live here (migration admin, excess
 *         destination and the governance roles). Chain-agnostic addresses — the wM proxy, M Token,
 *         Registrar and Swap Facility — are constants in the upgrade scripts. The deployer is not pinned:
 *         the migration admin performs the migration by passing the deployed migrator address to
 *         `WrappedMToken.migrate`, so who deploys the migrator does not matter.
 *
 *         Add a network by adding a `chainId` branch to `get`. An unmapped chain reverts, so the
 *         upgrade can only run where the config has been explicitly decided.
 */
library DeployConfig {
    /// @notice Thrown when no configuration exists for the current chain.
    error UnsupportedChainId(uint256 chainId);

    /**
     * @dev   The per-network upgrade configuration.
     * @param migrationAdmin        The Wrapped M migration admin.
     * @param excessDestination     The destination for excess M.
     * @param admin                 The Wrapped M admin.
     * @param freezeManager         The Wrapped M freeze manager.
     * @param pauser                The Wrapped M pauser.
     * @param forcedTransferManager The Wrapped M forced transfer manager.
     * @param excessManager         The Wrapped M excess manager.
     */
    struct NetworkConfig {
        address migrationAdmin;
        address excessDestination;
        address admin;
        address freezeManager;
        address pauser;
        address forcedTransferManager;
        address excessManager;
    }

    function get(uint256 chainId_) internal pure returns (NetworkConfig memory config_) {
        // Ethereum mainnet.
        // NOTE: Confirm every address below before the upgrade — the roles and deployer are
        //       currently placeholders carried over from the original mainnet script.
        if (chainId_ == 1) {
            return
                NetworkConfig({
                    migrationAdmin: 0x431169728D75bd02f4053435b87D15c8d1FB2C72,
                    excessDestination: 0xd7298f620B0F752Cf41BD818a16C756d9dCAA34f, // Vault
                    admin: 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB,
                    freezeManager: 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB,
                    pauser: 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB,
                    forcedTransferManager: 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB,
                    excessManager: 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB
                });
        }

        if (chainId_ == 11155111) {
            return
                NetworkConfig({
                    migrationAdmin: 0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217,
                    excessDestination: 0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217,
                    admin: 0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217,
                    freezeManager: 0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217,
                    pauser: 0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217,
                    forcedTransferManager: 0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217,
                    excessManager: 0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217
                });
        }

        // NOTE: Add further networks here as their config is decided, e.g.:
        //
        // if (chainId_ == 8453) { // Base
        //     return NetworkConfig({ migrationAdmin: 0x..., excessDestination: 0x...,
        //         admin: 0x..., freezeManager: 0x..., pauser: 0x..., forcedTransferManager: 0x...,
        //         excessManager: 0x... });
        // }

        revert UnsupportedChainId(chainId_);
    }
}
