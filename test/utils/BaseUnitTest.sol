// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IndexingMath } from "../../lib/common/src/libs/IndexingMath.sol";

import { WrappedMTokenHarness } from "../harness/WrappedMTokenHarness.sol";

import { MockM, MockRegistrar, MockSwapFacility } from "../utils/Mocks.sol";

contract BaseUnitTest is Test {
    uint56 internal constant _EXP_SCALED_ONE = IndexingMath.EXP_SCALED_ONE;

    uint56 internal constant _ONE_HUNDRED_PERCENT = 10_000;

    bytes32 internal constant _CLAIM_OVERRIDE_RECIPIENT_KEY_PREFIX = "wm_claim_override_recipient";
    bytes32 internal constant _FREEZE_MANAGER_ROLE = keccak256("FREEZE_MANAGER_ROLE");
    bytes32 internal constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 internal constant _EARNERS_LIST_NAME = "earners";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");

    address internal _admin = makeAddr("admin");
    address internal _excessDestination = makeAddr("excessDestination");
    address internal _freezeManager = makeAddr("freezeManager");
    address internal _migrationAdmin = makeAddr("migrationAdmin");
    address internal _pauser = makeAddr("pauser");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    MockM internal _mToken;
    MockRegistrar internal _registrar;
    MockSwapFacility internal _swapFacility;
    WrappedMTokenHarness internal _wrappedMToken;
}
