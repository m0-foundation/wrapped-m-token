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

    function test_initialState() external view {
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 17_866_898_034674);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 175_872_133591);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 277_153_904106);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_470068);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 910_814580);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 66_300_453613);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 347_033869);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_641_630881);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 60_011_718029);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);
    }

    function test_index_noMigration() external {
        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 18_745_425_119664);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 184_519_881653);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 290_781_743197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_542352);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 955_599930);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 69_560_490365);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 364_097752);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_771_521603);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 62_962_533531);

        assertEq(_wrappedMToken.currentIndex(), 1_073787769981);
    }

    function test_index_migrate_earningNotDisabled() external {
        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 0);
        assertEq(_wrappedMToken.enableMIndex(), IndexingMath.EXP_SCALED_ONE);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 17_866_898_034674);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 175_872_133591);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 277_153_904106);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_470068);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 910_814580);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 66_300_453613);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 347_033869);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_641_630881);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 60_011_718029);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 18_745_425_119664);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 184_519_881653);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 290_781_743197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_542352);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 955_599930);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 69_560_490365);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 364_097752);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_771_521603);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 62_962_533531);

        assertEq(_wrappedMToken.currentIndex(), 1_073787769981);
    }

    function test_index_migrate_earningDisabled_immediatelyReenabled() external {
        _removeFromList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.disableEarning();

        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 1_023463403719);
        assertEq(_wrappedMToken.enableMIndex(), 0);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 17_866_898_034674);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 175_872_133591);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 277_153_904106);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_470068);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 910_814580);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 66_300_453613);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 347_033869);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_641_630881);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 60_011_718029);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        _addToList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.enableEarning();

        assertEq(_wrappedMToken.disableIndex(), 1_023463403719);
        assertEq(_wrappedMToken.enableMIndex(), 1_023463403719);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 17_866_898_034674);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 175_872_133591);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 277_153_904106);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_470068);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 910_814580);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 66_300_453613);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 347_033869);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_641_630881);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 60_011_718029);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 18_745_425_119664 - 35); // Rounding error
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 184_519_881653);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 290_781_743197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_542352);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 955_599930);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 69_560_490365);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 364_097752);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_771_521603);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 62_962_533531);

        assertEq(_wrappedMToken.currentIndex(), 1_073787769981 - 2); // Rounding error
    }

    function test_index_migrate_earningDisabled_notReenabled() external {
        _removeFromList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.disableEarning();

        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 1_023463403719);
        assertEq(_wrappedMToken.enableMIndex(), 0);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 17_866_898_034674);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 175_872_133591);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 277_153_904106);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_470068);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 910_814580);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 66_300_453613);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 347_033869);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_641_630881);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 60_011_718029);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 17_866_898_034674);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 175_872_133591);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 277_153_904106);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_470068);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 910_814580);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 66_300_453613);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 347_033869);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_641_630881);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 60_011_718029);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);
    }

    function test_index_migrate_earningDisabled_reenabledLater() external {
        _removeFromList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.disableEarning();

        _deployV2Components();
        _migrate();

        assertEq(_wrappedMToken.disableIndex(), 1_023463403719);
        assertEq(_wrappedMToken.enableMIndex(), 0);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 17_866_898_034674);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 175_872_133591);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 277_153_904106);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_470068);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 910_814580);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 66_300_453613);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 347_033869);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_641_630881);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 60_011_718029);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        _addToList(_EARNERS_LIST_NAME, address(_wrappedMToken));

        _wrappedMToken.enableEarning();

        assertEq(_wrappedMToken.disableIndex(), 1_023463403719);
        assertEq(_wrappedMToken.enableMIndex(), 1_073787769979);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 17_866_898_034674);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 175_872_133591);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 277_153_904106);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_470068);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 910_814580);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 66_300_453613);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 347_033869);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_641_630881);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 60_011_718029);

        assertEq(_wrappedMToken.currentIndex(), 1_023463403719);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[0]), 18_745_425_119664 - 35); // Rounding error
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[1]), 184_519_881653);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[2]), 290_781_743197);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[3]), 1_542352);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[4]), 955_599930);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[5]), 69_560_490365);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[6]), 364_097752);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[7]), 2_771_521603);
        assertEq(_wrappedMToken.balanceWithYieldOf(_holders[8]), 62_962_533531);

        assertEq(_wrappedMToken.currentIndex(), 1_073787769981 - 2); // Rounding error
    }
}
