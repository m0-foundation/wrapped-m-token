// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IEarnerManager } from "../interfaces/IEarnerManager.sol";
import { IWrappedMToken } from "../interfaces/IWrappedMToken.sol";

import { Initializer as WrappedMTokenInitializer, WrappedMToken } from "../WrappedMToken.sol";

interface IWrappedMToken_Official is IWrappedMToken {
    event ClaimRecipientSet(address indexed account, address indexed claimRecipient);

    error IsApprovedEarner(address account);

    error NotApprovedEarner(address account);

    error UnauthorizedMigration();

    error ZeroEarnerManager();

    error ZeroMigrationAdmin();

    function setClaimRecipient(address claimRecipient) external;

    function migrate() external;

    function migrate(address migrator) external;

    function HUNDRED_PERCENT() external pure returns (uint16 hundredPercent);

    function CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX() external pure returns (bytes32 claimOverrideRecipientKeyPrefix);

    function MIGRATOR_KEY_PREFIX() external pure returns (bytes32 migratorKeyPrefix);

    function claimRecipientFor(address account) external view returns (address recipient);

    function earnerManager() external view returns (address earnerManager);

    function migrationAdmin() external view returns (address migrationAdmin);
}

contract Initializer is WrappedMTokenInitializer {
    function initialize(string memory name_, string memory symbol_, address excessDestination_) external {
        WrappedMTokenInitializer._initialize(name_, symbol_, excessDestination_);
    }
}

/**
 * @title  Official Wrapped M.
 * @author M^0 Labs
 */
contract WrappedMToken_Official is IWrappedMToken_Official, WrappedMToken {
    bytes32 public constant CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX = "wm_claim_override_recipient";

    bytes32 public constant MIGRATOR_KEY_PREFIX = "wm_migrator_v3";

    uint16 public constant HUNDRED_PERCENT = 10_000;

    address public immutable earnerManager;

    address public immutable migrationAdmin;

    mapping(address account => address claimRecipient) internal _claimRecipients;

    constructor(
        string memory name_,
        string memory symbol_,
        address mToken_,
        address registrar_,
        address initializer_,
        address earnerManager_,
        address migrationAdmin_
    ) WrappedMToken(name_, symbol_, mToken_, registrar_, initializer_) {
        if ((earnerManager = earnerManager_) == address(0)) revert ZeroEarnerManager();
        if ((migrationAdmin = migrationAdmin_) == address(0)) revert ZeroMigrationAdmin();
    }

    function setClaimRecipient(address claimRecipient_) external {
        _accounts[msg.sender].hasClaimRecipient = (_claimRecipients[msg.sender] = claimRecipient_) != address(0);

        emit ClaimRecipientSet(msg.sender, claimRecipient_);
    }

    function migrate() external {
        _migrate(_getMigrator());
    }

    function migrate(address migrator_) external {
        if (msg.sender != migrationAdmin) revert UnauthorizedMigration();

        _migrate(migrator_);
    }

    function claimRecipientFor(address account_) public view returns (address recipient_) {
        if (_accounts[account_].hasClaimRecipient) return _claimRecipients[account_];

        address claimOverrideRecipient_ = address(
            uint160(uint256(_getFromRegistrar(keccak256(abi.encode(CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX, account_)))))
        );

        return claimOverrideRecipient_ == address(0) ? account_ : claimOverrideRecipient_;
    }

    function _afterClaim(address account_, uint240 yield_, uint128 currentIndex_) internal override {
        address claimRecipient_ = claimRecipientFor(account_);

        if (_accounts[account_].hasEarnerDetails) {
            unchecked {
                yield_ -= _handleEarnerDetails(account_, yield_, currentIndex_);
            }
        }

        if ((claimRecipient_ != account_) && (yield_ != 0)) {
            _transfer(account_, claimRecipient_, yield_, currentIndex_);
        }

        super._afterClaim(account_, yield_, currentIndex_);
    }

    function _beforeStartEarning(address account_, uint128 currentIndex_) internal override {
        (bool isEarner_, , address admin_) = _getEarnerDetails(account_);

        if (!isEarner_) revert NotApprovedEarner(account_);

        _accounts[account_].hasEarnerDetails = admin_ != address(0); // Has earner details if an admin exists.

        super._beforeStartEarning(account_, currentIndex_);
    }

    function _beforeStopEarning(address account_, uint128 currentIndex_) internal override {
        (bool isEarner_, , ) = _getEarnerDetails(account_);

        if (isEarner_) revert IsApprovedEarner(account_);

        _claim(account_, currentIndex_);

        delete _accounts[account_].hasEarnerDetails;

        super._beforeStopEarning(account_, currentIndex_);
    }

    function _handleEarnerDetails(
        address account_,
        uint240 yield_,
        uint128 currentIndex_
    ) internal returns (uint240 fee_) {
        (, uint16 feeRate_, address admin_) = _getEarnerDetails(account_);

        if (admin_ == address(0)) {
            // Prevent transferring to address(0) and remove `hasEarnerDetails` property going forward.
            _accounts[account_].hasEarnerDetails = false;
            return 0;
        }

        if (feeRate_ == 0) return 0;

        feeRate_ = feeRate_ > HUNDRED_PERCENT ? HUNDRED_PERCENT : feeRate_; // Ensure fee rate is capped at 100%.

        unchecked {
            fee_ = (feeRate_ * yield_) / HUNDRED_PERCENT;
        }

        if (fee_ == 0) return 0;

        _transfer(account_, admin_, fee_, currentIndex_);
    }

    function _getEarnerDetails(
        address account_
    ) internal view returns (bool isEarner_, uint16 feeRate_, address admin_) {
        return IEarnerManager(earnerManager).getEarnerDetails(account_);
    }

    function _getMigrator() internal view returns (address migrator_) {
        return
            address(
                uint160(
                    // NOTE: A subsequent implementation should use a unique migrator prefix.
                    uint256(_getFromRegistrar(keccak256(abi.encode(MIGRATOR_KEY_PREFIX, address(this)))))
                )
            );
    }
}
