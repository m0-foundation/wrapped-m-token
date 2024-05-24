// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContractHelper } from "../../lib/common/src/ContractHelper.sol";

import { WMHarness } from "./WMHarness.sol";
import { YMHarness } from "./YMHarness.sol";

contract DeployBase {
    /**
     * @dev    Deploys WM and YM.
     * @param  deployer_        The address of the account deploying the contracts.
     * @param  deployerNonce_   The current nonce of the deployer.
     * @param  mToken_           The address of the M token.
     * @param  ttgRegistrar_    The address of the TTG Registrar.
     */
    function deploy(
        address deployer_,
        uint256 deployerNonce_,
        address mToken_,
        address ttgRegistrar_
    ) public virtual returns (WMHarness wMToken_, YMHarness yMToken_) {
        // YM token needs `mToken_` and WM token needs `yMToken_`.
        wMToken_ = new WMHarness(mToken_, _getExpectedYMToken(deployer_, deployerNonce_), ttgRegistrar_);
        yMToken_ = new YMHarness(mToken_, address(wMToken_), ttgRegistrar_);
    }

    function getExpectedWMToken(address deployer_, uint256 deployerNonce_) public pure virtual returns (address) {
        return _getExpectedWMToken(deployer_, deployerNonce_);
    }

    function getExpectedYMToken(address deployer_, uint256 deployerNonce_) public pure virtual returns (address) {
        return _getExpectedYMToken(deployer_, deployerNonce_);
    }

    function _getExpectedWMToken(address deployer_, uint256 deployerNonce_) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_);
    }

    function _getExpectedYMToken(address deployer_, uint256 deployerNonce_) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
    }
}
