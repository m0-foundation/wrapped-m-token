// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { console } from "../../lib/forge-std/src/Test.sol";

import { IndexingMath } from "../../lib/common/src/libs/IndexingMath.sol";

import { TestBase } from "./TestBase.sol";

contract MigrationIntegrationTests is TestBase {
    address[] internal _holders = [
        0x970A7749EcAA4394C8B2Bf5F2471F41FD6b79288,
        0x9c6e67fA86138Ab49359F595BfE4Fb163D0f16cc,
        0xa969cFCd9e583edb8c8B270Dc8CaFB33d6Cf662D,
        0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb,
        0xcAD001c30E96765aC90307669d578219D4fb1DCe,
        0xCF3166181848eEC4Fd3b9046aE7CB582F34d2e6c,
        0xdd82875f0840AAD58a455A70B88eEd9F59ceC7c7,
        0xDeD796De6a14E255487191963dEe436c45995813,
        0xea0C048c728578b1510EBDF9b692E8936D6Fbc90
    ];

    function setUp() public override {
        super.setUp();

        vm.selectFork(mainnetFork);
    }

    function test_initialState() external view {
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_418_521_333405);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_142_615762);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_093_596157);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_146361);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 43_084797);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 29_760_546197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_341_395374);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 33_760983);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 921_119567);

        assertEq(_wrappedMToken.currentIndex(), 1_054471748112);
    }

    function test_index_noMigration() external {
        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_521_001_729306);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_233_405166);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_224_681607);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_449175);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 44_910436);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 31_021_594638);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_398_234537);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 35_191543);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 960_150316);

        assertEq(_wrappedMToken.currentIndex(), 1_099153050162);
    }

    function test_index_migrate_earningNotDisabled() external {
        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 0);
        assertEq(_wrappedMToken.enableMIndex(), IndexingMath.EXP_SCALED_ONE);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_418_521_333405);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_142_615762);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_093_596157);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_146361);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 43_084797);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 29_760_546197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_341_395374);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 33_760983);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 921_119567);

        assertEq(_wrappedMToken.currentIndex(), 1_054471748112);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_521_001_729306);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_233_405166);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_224_681607);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_449175);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 44_910436);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 31_021_594638);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_398_234537);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 35_191543);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 960_150316);

        assertEq(_wrappedMToken.currentIndex(), 1_099153050162);
    }

    function test_index_migrate_earningDisabled_immediatelyReenabled() external {
        _removeFromList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.disableEarning();

        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 1_054471748112);
        assertEq(_wrappedMToken.enableMIndex(), 0);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_418_521_333405);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_142_615762);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_093_596157);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_146361);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 43_084797);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 29_760_546197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_341_395374);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 33_760983);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 921_119567);

        assertEq(_wrappedMToken.currentIndex(), 1_054471748112);

        _addToList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.enableEarning();

        assertEq(_wrappedMToken.disableIndex(), 1_054471748112);
        assertEq(_wrappedMToken.enableMIndex(), 1_054471748112);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_418_521_333405);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_142_615762);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_093_596157);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_146361);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 43_084797);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 29_760_546197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_341_395374);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 33_760983);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 921_119567);

        assertEq(_wrappedMToken.currentIndex(), 1_054471748112);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_521_001_729306);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_233_405166);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_224_681607);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_449175);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 44_910436);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 31_021_594638);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_398_234537);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 35_191543);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 960_150316);

        assertEq(_wrappedMToken.currentIndex(), 1_099153050162);
    }

    function test_index_migrate_earningDisabled_notReenabled() external {
        _removeFromList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.disableEarning();

        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 1_054471748112);
        assertEq(_wrappedMToken.enableMIndex(), 0);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_418_521_333405);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_142_615762);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_093_596157);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_146361);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 43_084797);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 29_760_546197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_341_395374);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 33_760983);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 921_119567);

        assertEq(_wrappedMToken.currentIndex(), 1_054471748112);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_418_521_333405);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_142_615762);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_093_596157);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_146361);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 43_084797);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 29_760_546197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_341_395374);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 33_760983);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 921_119567);

        assertEq(_wrappedMToken.currentIndex(), 1_054471748112);
    }

    function test_index_migrate_earningDisabled_reenabledLater() external {
        _removeFromList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.disableEarning();

        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 1_054471748112);
        assertEq(_wrappedMToken.enableMIndex(), 0);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_418_521_333405);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_142_615762);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_093_596157);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_146361);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 43_084797);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 29_760_546197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_341_395374);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 33_760983);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 921_119567);

        assertEq(_wrappedMToken.currentIndex(), 1_054471748112);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        _addToList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.enableEarning();

        assertEq(_wrappedMToken.disableIndex(), 1_054471748112);
        assertEq(_wrappedMToken.enableMIndex(), 1_099153050162);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_418_521_333405);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_142_615762);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_093_596157);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_146361);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 43_084797);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 29_760_546197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_341_395374);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 33_760983);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 921_119567);

        assertEq(_wrappedMToken.currentIndex(), 1_054471748112);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 2_521_001_729306 - 3); // Rounding error
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 2_233_405166);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 3_224_681607);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 7_449175);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 44_910436);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 31_021_594638);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 1_398_234537);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 35_191543);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 960_150316);

        assertEq(_wrappedMToken.currentIndex(), 1_099153050162 - 1); // Rounding error
    }
}
