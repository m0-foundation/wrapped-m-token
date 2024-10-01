// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IClaimRecipientManager } from "../../src/interfaces/IClaimRecipientManager.sol";
import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { ClaimRecipientManager } from "../../src/ClaimRecipientManager.sol";
import { WrappedMToken } from "../../src/WrappedMToken.sol";
import { MigratorV1 } from "../../src/MigratorV1.sol";

import { IMTokenLike, IRegistrarLike } from "./vendor/protocol/Interfaces.sol";

contract TestBase is Test {
    IMTokenLike internal constant _mToken = IMTokenLike(0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b);

    address internal constant _minterGateway = 0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E;
    address internal constant _registrar = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;
    address internal constant _vault = 0xd7298f620B0F752Cf41BD818a16C756d9dCAA34f;
    address internal constant _standardGovernor = 0xB024aC5a7c6bC92fbACc8C3387E628a07e1Da016;
    address internal constant _mSource = 0x563AA56D0B627d1A734e04dF5762F5Eea1D56C2f;
    address internal constant _wmSource = 0xfE940BFE535013a52e8e2DF9644f95E3C94fa14B;

    address internal constant _implementationV1 = 0x813B926B1D096e117721bD1Eb017FbA122302DA0;

    IWrappedMToken internal constant _wrappedMToken = IWrappedMToken(0x437cc33344a0B27A429f795ff6B469C72698B291);

    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "wm_migrator_v1";
    bytes32 internal constant _CLAIM_OVERRIDE_RECIPIENT_PREFIX = "wm_claim_override_recipient";

    address internal _migrationAdmin = 0x431169728D75bd02f4053435b87D15c8d1FB2C72;

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");
    address internal _eric = makeAddr("eric");
    address internal _frank = makeAddr("frank");
    address internal _grace = makeAddr("grace");
    address internal _henry = makeAddr("henry");
    address internal _ivan = makeAddr("ivan");
    address internal _judy = makeAddr("judy");

    address[] internal _accounts = [_alice, _bob, _carol, _dave, _eric, _frank, _grace, _henry, _ivan, _judy];

    address internal _implementationV2;
    address internal _migratorV1;

    IClaimRecipientManager internal _claimRecipientManager;

    function _addToList(bytes32 list_, address account_) internal {
        vm.prank(_standardGovernor);
        IRegistrarLike(_registrar).addToList(list_, account_);
    }

    function _removeFomList(bytes32 list_, address account_) internal {
        vm.prank(_standardGovernor);
        IRegistrarLike(_registrar).removeFromList(list_, account_);
    }

    function _giveM(address account_, uint256 amount_) internal {
        vm.prank(_mSource);
        _mToken.transfer(account_, amount_);
    }

    function _giveWM(address account_, uint256 amount_) internal {
        vm.prank(_wmSource);
        _wrappedMToken.transfer(account_, amount_);
    }

    function _giveEth(address account_, uint256 amount_) internal {
        vm.deal(account_, amount_);
    }

    function _wrap(address account_, address recipient_, uint256 amount_) internal {
        vm.prank(account_);
        _mToken.approve(address(_wrappedMToken), amount_);

        vm.prank(account_);
        _wrappedMToken.wrap(recipient_, amount_);
    }

    function _wrap(address account_, address recipient_) internal {
        vm.prank(account_);
        _mToken.approve(address(_wrappedMToken), type(uint256).max);

        vm.prank(account_);
        _wrappedMToken.wrap(recipient_);
    }

    function _unwrap(address account_, address recipient_, uint256 amount_) internal {
        vm.prank(account_);
        _wrappedMToken.unwrap(recipient_, amount_);
    }

    function _unwrap(address account_, address recipient_) internal {
        vm.prank(account_);
        _wrappedMToken.unwrap(recipient_);
    }

    function _transferWM(address sender_, address recipient_, uint256 amount_) internal {
        vm.prank(sender_);
        _wrappedMToken.transfer(recipient_, amount_);
    }

    function _approveWM(address account_, address spender_, uint256 amount_) internal {
        vm.prank(account_);
        _wrappedMToken.approve(spender_, amount_);
    }

    function _set(bytes32 key_, bytes32 value_) internal {
        vm.prank(_standardGovernor);
        IRegistrarLike(_registrar).setKey(key_, value_);
    }

    function _setClaimOverrideRecipient(address account_, address recipient_) internal {
        _set(keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_PREFIX, account_)), bytes32(uint256(uint160(recipient_))));
    }

    function _deployV2Components() internal {
        _claimRecipientManager = IClaimRecipientManager(address(new ClaimRecipientManager(_registrar)));

        _implementationV2 = address(
            new WrappedMToken(address(_mToken), _migrationAdmin, address(_claimRecipientManager))
        );

        _migratorV1 = address(new MigratorV1(_implementationV2));
    }

    function _migrate() internal {
        _set(
            keccak256(abi.encode(_MIGRATOR_V1_PREFIX, address(_wrappedMToken))),
            bytes32(uint256(uint160(_migratorV1)))
        );

        _wrappedMToken.migrate();
    }

    function _migrateFromAdmin() internal {
        vm.prank(_migrationAdmin);
        _wrappedMToken.migrate(_migratorV1);
    }
}
