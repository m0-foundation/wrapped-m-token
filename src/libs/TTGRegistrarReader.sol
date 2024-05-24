// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { ITTGRegistrar } from "../../../lib/protocol/src/interfaces/ITTGRegistrar.sol";

/**
 * @title  Library to read TTG (Two Token Governance) Registrar contract parameters.
 * @author M^0 Labs
 */
library TTGRegistrarReader {
    /* ============ Variables ============ */

    /// @notice The name of parameter in TTG that defines the earner rate model contract.
    bytes32 internal constant EARNER_RATE_MODEL = "earner_rate_model";

    /// @notice The parameter name in TTG that defines the earners list.
    bytes32 internal constant EARNERS_LIST = "earners";

    /// @notice The parameter name in TTG that defines whether to ignore the earners list or not.
    bytes32 internal constant EARNERS_LIST_IGNORED = "earners_list_ignored";

    /// @notice The parameter name in TTG that defines the M wrapper liquidator address.
    bytes32 internal constant M_WRAPPER_LIQUIDATOR = "m_wrapper_liquidator";

    /* ============ Internal View/Pure Functions ============ */

    /// @notice Checks if the given earner is approved.
    function isApprovedEarner(address registrar_, address earner_) internal view returns (bool) {
        return _contains(registrar_, EARNERS_LIST, earner_);
    }

    /// @notice Checks if the given account is approved to liquidate excess earned M.
    function isApprovedLiquidator(address registrar_, address account_) internal view returns (bool) {
        return toAddress(_get(registrar_, M_WRAPPER_LIQUIDATOR)) == account_;
    }

    /// @notice Checks if the `earners_list_ignored` exists.
    function isEarnersListIgnored(address registrar_) internal view returns (bool) {
        return _get(registrar_, EARNERS_LIST_IGNORED) != bytes32(0);
    }

    /// @notice Converts given bytes32 to address.
    function toAddress(bytes32 input_) internal pure returns (address) {
        return address(uint160(uint256(input_)));
    }

    /// @notice Checks if the given list contains the given account.
    function _contains(address registrar_, bytes32 listName_, address account_) private view returns (bool) {
        return ITTGRegistrar(registrar_).listContains(listName_, account_);
    }

    /// @notice Gets the value of the given key.
    function _get(address registrar_, bytes32 key_) private view returns (bytes32) {
        return ITTGRegistrar(registrar_).get(key_);
    }
}
