// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { IEarnerStatusManager } from "./interfaces/IEarnerStatusManager.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";

/**
 * @title  Earner Status Manager contract for setting and returning earner status for Wrapped M Token accounts.
 * @author M^0 Labs
 */
contract EarnerStatusManager is IEarnerStatusManager {
    /* ============ Variables ============ */

    /// @dev Registrar key holding value of whether the earners list can be ignored or not.
    bytes32 internal constant _EARNERS_LIST_IGNORED = "earners_list_ignored";

    /// @dev Registrar key of earners list.
    bytes32 internal constant _EARNERS_LIST = "earners";

    /// @dev Registrar key of claim recipient admin list.
    bytes32 internal constant _EARNER_STATUS_ADMIN_LIST = "wm_earner_status_admins";

    /// @inheritdoc IEarnerStatusManager
    address public immutable registrar;

    /// @dev Mapping of account to earner status.
    mapping(address account => bool earnerStatus) internal _earnerStatuses;

    /* ============ Modifiers ============ */

    modifier onlyEarnerStatusAdmin() {
        _revertIfNotEarnerStatusAdmin();
        _;
    }

    /* ============ Constructor ============ */

    /**
     * @dev   Constructs the contract.
     * @param registrar_ The address of a Registrar contract.
     */
    constructor(address registrar_) {
        if ((registrar = registrar_) == address(0)) revert ZeroRegistrar();
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IEarnerStatusManager
    function setEarnerStatus(address account_, bool earnerStatus_) external onlyEarnerStatusAdmin {
        _setEarnerStatus(account_, earnerStatus_);
    }

    /// @inheritdoc IEarnerStatusManager
    function setEarnerStatuses(
        address[] calldata accounts_,
        bool[] calldata earnerStatuses_
    ) external onlyEarnerStatusAdmin {
        if (accounts_.length != earnerStatuses_.length) revert ArrayLengthMismatch();

        for (uint256 index_; index_ < accounts_.length; ++index_) {
            _setEarnerStatus(accounts_[index_], earnerStatuses_[index_]);
        }
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IEarnerStatusManager
    function earnerStatusFor(address account_) external view returns (bool earnerStatus_) {
        return isEarnerListIgnored() || isInEarnerList(account_) || _earnerStatuses[account_];
    }

    /// @inheritdoc IEarnerStatusManager
    function isEarnerListIgnored() public view returns (bool isIgnored_) {
        return IRegistrarLike(registrar).get(_EARNERS_LIST_IGNORED) != bytes32(0);
    }

    /// @inheritdoc IEarnerStatusManager
    function isInEarnerList(address account_) public view returns (bool isInList_) {
        return IRegistrarLike(registrar).listContains(_EARNERS_LIST, account_);
    }

    /// @inheritdoc IEarnerStatusManager
    function isEarnerStatusAdmin(address account_) public view returns (bool isAdmin_) {
        return IRegistrarLike(registrar).listContains(_EARNER_STATUS_ADMIN_LIST, account_);
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Sets the earner status for `account` to `earnerStatus_`.
     * @param account_      The account under which yield could generate.
     * @param earnerStatus_ Whether the account is an earner.
     */
    function _setEarnerStatus(address account_, bool earnerStatus_) internal {
        if (account_ == address(0)) revert ZeroAccount();

        emit EarnerStatusSet(msg.sender, account_, _earnerStatuses[account_] = earnerStatus_);
    }

    function _revertIfNotEarnerStatusAdmin() internal view {
        if (!isEarnerStatusAdmin(msg.sender)) revert NotEarnerStatusAdmin();
    }
}
