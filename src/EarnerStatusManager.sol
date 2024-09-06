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
    bytes32 internal constant _LIST_IGNORED = "earners_list_ignored";

    /// @dev Registrar key of earners list.
    bytes32 internal constant _LIST = "earners";

    /// @dev Registrar key prefix to determine the account at an earner status admin index.
    bytes32 internal constant _ADMIN_PREFIX = "wm_earner_status_admin_prefix";

    /// @inheritdoc IEarnerStatusManager
    address public immutable registrar;

    /// @dev Mapping of account to earner status.
    mapping(address account => uint256 status) internal _statuses;

    /// @dev Mask of admins enabled.
    uint256 internal _adminsBitMask;

    /* ============ Modifiers ============ */

    modifier onlyAdmin(uint256 adminIndex_) {
        _revertIfNotAdmin(adminIndex_);
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
    function updateAdminIndex(uint256 adminIndex_) external {
        bool enabled_ = getAdmin(adminIndex_) != address(0);
        uint256 adminsBitMask_ = _adminsBitMask;

        uint256 newAdminsBitMask_ = enabled_
            ? adminsBitMask_ | _getAdminBitMask(adminIndex_) // Set bit at index.
            : adminsBitMask_ & ~_getAdminBitMask(adminIndex_); // Clear bit at index.

        if (newAdminsBitMask_ == adminsBitMask_) revert AdminIndexAlreadySet();

        _adminsBitMask = newAdminsBitMask_;

        emit AdminIndexUpdated(adminIndex_, enabled_);
    }

    /// @inheritdoc IEarnerStatusManager
    function setStatus(uint256 adminIndex_, address account_, bool status_) external onlyAdmin(adminIndex_) {
        _setStatus(adminIndex_, account_, status_);
    }

    /// @inheritdoc IEarnerStatusManager
    function setStatuses(
        uint256 adminIndex_,
        address[] calldata accounts_,
        bool[] calldata statuses_
    ) external onlyAdmin(adminIndex_) {
        if (accounts_.length != statuses_.length) revert ArrayLengthMismatch();

        for (uint256 index_; index_ < accounts_.length; ++index_) {
            _setStatus(adminIndex_, accounts_[index_], statuses_[index_]);
        }
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IEarnerStatusManager
    function statusFor(address account_) external view returns (bool status_) {
        return isListIgnored() || isInList(account_) || getStatusByAdmins(account_);
    }

    /// @inheritdoc IEarnerStatusManager
    function statusesFor(address[] calldata accounts_) external view returns (bool[] memory statuses_) {
        statuses_ = new bool[](accounts_.length);

        bool isListIgnored_ = isListIgnored();

        // NOTE: Don't bother loading this from storage if `isListIgnored_` is true.
        uint256 adminsBitMask_ = isListIgnored_ ? 0 : _adminsBitMask;

        for (uint256 index_; index_ < accounts_.length; ++index_) {
            address account_ = accounts_[index_];

            statuses_[index_] = isListIgnored_ || isInList(account_) || _getStatusByAdmins(account_, adminsBitMask_);
        }
    }

    /// @inheritdoc IEarnerStatusManager
    function isListIgnored() public view returns (bool isIgnored_) {
        return IRegistrarLike(registrar).get(_LIST_IGNORED) != bytes32(0);
    }

    /// @inheritdoc IEarnerStatusManager
    function isInList(address account_) public view returns (bool isInList_) {
        return IRegistrarLike(registrar).listContains(_LIST, account_);
    }

    /// @inheritdoc IEarnerStatusManager
    function getStatusByAdmins(address account_) public view returns (bool status_) {
        return _getStatusByAdmins(account_, _adminsBitMask);
    }

    /// @inheritdoc IEarnerStatusManager
    function getStatusByAdmin(uint256 adminIndex_, address account_) public view returns (bool status_) {
        return (_statuses[account_] & _getAdminBitMask(adminIndex_)) != 0;
    }

    /// @inheritdoc IEarnerStatusManager
    function getStatusesByAdmin(
        uint256 adminIndex_,
        address[] calldata accounts_
    ) external view returns (bool[] memory statuses_) {
        statuses_ = new bool[](accounts_.length);

        for (uint256 index_; index_ < accounts_.length; ++index_) {
            statuses_[index_] = getStatusByAdmin(adminIndex_, accounts_[index_]);
        }
    }

    /// @inheritdoc IEarnerStatusManager
    function getAdmin(uint256 adminIndex_) public view returns (address admin_) {
        return
            address(uint160(uint256(IRegistrarLike(registrar).get(keccak256(abi.encode(_ADMIN_PREFIX, adminIndex_))))));
    }

    /// @inheritdoc IEarnerStatusManager
    function isAdminIndexEnabled(uint256 adminIndex_) public view returns (bool enabled_) {
        return (_adminsBitMask & _getAdminBitMask(adminIndex_)) != 0;
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Sets the earner status `adminIndex_` bit for `account` to `status_`.
     * @param adminIndex_ The index of the admin.
     * @param account_    The account under which yield could generate.
     * @param status_     Whether the account is an earner, according to the admin defined by the admin index.
     */
    function _setStatus(uint256 adminIndex_, address account_, bool status_) internal {
        if (account_ == address(0)) revert ZeroAccount();

        if (status_) {
            _statuses[account_] |= _getAdminBitMask(adminIndex_); // Set bit at index.
        } else {
            _statuses[account_] &= ~_getAdminBitMask(adminIndex_); // Clear bit at index.
        }

        emit StatusSet(adminIndex_, account_, status_);
    }

    /**
     * @dev   Reverts if the sender is not an admin.
     * @param adminIndex_ The index of the admin.
     */
    function _revertIfNotAdmin(uint256 adminIndex_) internal view {
        if (msg.sender != getAdmin(adminIndex_)) revert NotAdmin();
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev    Returns the admin bit mask for a given admin index.
     * @param  adminIndex_ The index of the admin.
     * @return adminMask_  The bit mask.
     */
    function _getAdminBitMask(uint256 adminIndex_) internal pure returns (uint256 adminMask_) {
        return 1 << (adminIndex_ - 1);
    }

    /**
     * @dev   Returns the earner status for an account given an admins bit mask.
     * @param account_       The account being queried.
     * @param adminsBitMask_ The bit mask of admins.
     */
    function _getStatusByAdmins(address account_, uint256 adminsBitMask_) internal view returns (bool status_) {
        return (_statuses[account_] & adminsBitMask_) != 0;
    }
}
