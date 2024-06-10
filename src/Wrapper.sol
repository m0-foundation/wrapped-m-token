pragma solidity 0.8.23;

import {IMToken} from "../lib/protocol/src/interfaces/IMToken.sol";
import {WM} from "./WM.sol";

contract Wrapper {
    address public immutable mToken;
    address public immutable wMToken;

    // Excess of M claim fields
    address public immutable excessMOwner;
    // uint256 public claimedExcessM;

    /* ============ Constructor ============ */

    constructor(address mToken_, address wMToken_, address excessMOwner_) {
        mToken = mToken_;
        wMToken = wMToken_;
        excessMOwner = excessMOwner_;
    }

    function wrap(address account_, uint256 amount_) external {
        IMToken(mToken).transfer(address(this), amount_);
        WM(wMToken).mint(account_, amount_);
    }

    function unwrap(address account_, uint256 amount_) external {
        WM(wMToken).burn(msg.sender, amount_);
        IMToken(mToken).transfer(account_, amount_);
    }

    // Just example, excess of M goes somewhere else
    function claimExcess(uint256 amount_) external {
        if (amount_ <= WM(wMToken).excessOfM()) {
            IMToken(mToken).transfer(excessMOwner, amount_);
        }
    }

    function claim(uint256 amount_) external {
        // WMToken(wMToken).claim(msg.sender, amount_);
    }
}
