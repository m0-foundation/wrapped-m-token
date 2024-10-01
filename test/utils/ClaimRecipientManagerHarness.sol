// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ClaimRecipientManager } from "../../src/ClaimRecipientManager.sol";

contract ClaimRecipientManagerHarness is ClaimRecipientManager {
    constructor(address registrar_) ClaimRecipientManager(registrar_) {}

    function setInternalClaimRecipient(address account_, address recipient_) external {
        _claimRecipients[account_] = recipient_;
    }

    function getInternalClaimRecipient(address account_) external view returns (address recipient_) {
        return _claimRecipients[account_];
    }
}
