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

        if (chainId_ == 1 || chainId_ == 8453 || chainId_ == 42161) {
            return
                NetworkConfig({
                    migrationAdmin: 0xf7298F047F92d0Eb21231478Ef6ba9FE1eCD4c73, // MXON Safe
                    excessDestination: 0x235D1149E99f88E6fe8E190FfAeb8d091bcF49eF,
                    admin: 0xf7298F047F92d0Eb21231478Ef6ba9FE1eCD4c73, // MXON Safe
                    freezeManager: 0x4F1cf2449B4D07bD86Fd57709B1695C11D8314F2, // MXON
                    pauser: 0x4F1cf2449B4D07bD86Fd57709B1695C11D8314F2, // MXON
                    forcedTransferManager: 0x4F1cf2449B4D07bD86Fd57709B1695C11D8314F2, // MXON
                    excessManager: 0x235D1149E99f88E6fe8E190FfAeb8d091bcF49eF
                });
        }

        revert UnsupportedChainId(chainId_);
    }
}
