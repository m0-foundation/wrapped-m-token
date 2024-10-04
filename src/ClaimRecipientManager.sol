// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import { IClaimRecipientManager } from "./interfaces/IClaimRecipientManager.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";

/**
 * @title  Claim Recipient Manager contract for setting and returning claim recipients for Wrapped M Token yield.
 * @author M^0 Labs
 */
contract ClaimRecipientManager is IClaimRecipientManager {
    /* ============ Variables ============ */

    /// @dev Registrar key prefix to determine the override recipient of an account's accrued yield.
    bytes32 internal constant _CLAIM_OVERRIDE_RECIPIENT_PREFIX = "wm_claim_override_recipient";

    /// @dev Registrar key of claim recipient admin list.
    bytes32 internal constant _CLAIM_RECIPIENT_ADMIN_LIST = "wm_claim_recipient_admins";

    /// @inheritdoc IClaimRecipientManager
    address public immutable registrar;

    /// @dev Mapping of account to claim recipient.
    mapping(address account => address recipient) internal _claimRecipients;

    /* ============ Modifiers ============ */

    modifier onlyClaimRecipientAdmin() {
        _revertIfNotClaimRecipientAdmin();
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

    /// @inheritdoc IClaimRecipientManager
    function setClaimRecipient(address account_, address recipient_) external onlyClaimRecipientAdmin {
        _setClaimRecipient(account_, recipient_);
    }

    /// @inheritdoc IClaimRecipientManager
    function setClaimRecipients(
        address[] calldata accounts_,
        address[] calldata recipients_
    ) external onlyClaimRecipientAdmin {
        if (accounts_.length != recipients_.length) revert ArrayLengthMismatch();

        for (uint256 index_; index_ < accounts_.length; ++index_) {
            _setClaimRecipient(accounts_[index_], recipients_[index_]);
        }
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IClaimRecipientManager
    function claimRecipientFor(address account_) external view returns (address recipient_) {
        recipient_ = claimRecipientOverrideFor(account_);

        // `claimRecipientOverrideFor` overrides `claimRecipientFor`.
        return (recipient_ != address(0)) ? recipient_ : _claimRecipients[account_];
    }

    /// @inheritdoc IClaimRecipientManager
    function claimRecipientOverrideFor(address account_) public view returns (address recipient_) {
        return
            address(
                uint160(
                    uint256(
                        IRegistrarLike(registrar).get(keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_PREFIX, account_)))
                    )
                )
            );
    }

    /// @inheritdoc IClaimRecipientManager
    function isClaimRecipientAdmin(address account_) public view returns (bool isAdmin_) {
        return IRegistrarLike(registrar).listContains(_CLAIM_RECIPIENT_ADMIN_LIST, account_);
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Sets the claim recipient for `account` to `recipient`.
     * @param account_   The account under which yield will generate.
     * @param recipient_ The account that should receive the yield when claims are performed.
     */
    function _setClaimRecipient(address account_, address recipient_) internal {
        if (account_ == address(0)) revert ZeroAccount();

        emit ClaimRecipientSet(msg.sender, account_, _claimRecipients[account_] = recipient_);
    }

    function _revertIfNotClaimRecipientAdmin() internal view {
        if (!isClaimRecipientAdmin(msg.sender)) revert NotClaimRecipientAdmin();
    }
}
