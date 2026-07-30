// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Enum } from "safe-smart-account/common/Enum.sol";

import { Safe } from "../lib/safe-utils/src/Safe.sol";
import { console } from "../lib/forge-std/src/console.sol";
import { Script } from "../lib/forge-std/src/Script.sol";

abstract contract MultiSigBatchBase is Script {
    using Safe for *;

    Safe.Client internal _safeMultiSig;
    address[] internal _targets;
    bytes[] internal _data;

    function _addToBatch(address target_, bytes memory data_) internal {
        _targets.push(target_);
        _data.push(data_);
    }

    /// @dev The Safe's on-chain nonce only advances on execution, so it collides with already queued proposals.
    ///      Set `SAFE_NONCE` to queue behind them instead of conflicting with them.
    function _proposeBatch(address safe_, address sender) internal {
        _safeMultiSig.initialize(safe_);

        uint256 nonce_ = vm.envOr("SAFE_NONCE", _safeMultiSig.getNonce());

        console.log("Safe Nonce:          ", nonce_);

        (address to_, bytes memory data_) = _safeMultiSig.getProposeTransactionsTargetAndData(_targets, _data);

        // NOTE: DelegateCall preserves msg.sender across the batched sub-calls, and must match the signed operation.
        bytes memory signature_ = _safeMultiSig.sign(to_, data_, Enum.Operation.DelegateCall, sender, nonce_, "");

        _safeMultiSig.proposeTransactionsWithSignature(_targets, _data, sender, signature_, nonce_);
    }

    function _simulateBatch(address safe_) internal {
        // NOTE: `isolate` mode runs each top-level call as its own transaction, requiring the Safe to pay for gas.
        vm.deal(safe_, 1 ether);

        vm.startPrank(safe_);

        for (uint256 i = 0; i < _targets.length; i++) {
            (bool success, ) = _targets[i].call(_data[i]);
            require(success, "Simulation failed");
        }

        vm.stopPrank();
    }
}
