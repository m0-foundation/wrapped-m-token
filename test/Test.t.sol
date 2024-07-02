// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

import { IWrappedMToken } from "../src/interfaces/IWrappedMToken.sol";

import { WrappedMToken } from "../src/WrappedMToken.sol";
import { Proxy } from "../src/Proxy.sol";

import { MockM, MockRegistrar } from "./utils/Mocks.sol";

contract WrappedMTokenV2 {
    function foo() external pure returns (uint256) {
        return 1;
    }
}

contract WrappedMTokenMigratorV1 {
    bytes32 private constant _IMPLEMENTATION_SLOT =
        bytes32(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);

    address public immutable implementationV2;

    constructor(address implementationV2_) {
        implementationV2 = implementationV2_;
    }

    fallback() external virtual {
        bytes32 slot_ = _IMPLEMENTATION_SLOT;
        address implementationV2_ = implementationV2;

        assembly {
            sstore(slot_, implementationV2_)
        }
    }
}

contract Tests is Test {
    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "wm_migrator_v1";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    address internal _migrationAdmin = makeAddr("migrationAdmin");

    address internal _vault = makeAddr("vault");

    MockM internal _mToken;
    MockRegistrar internal _registrar;
    WrappedMToken internal _implementation;
    IWrappedMToken internal _wrappedMToken;

    function setUp() external {
        _registrar = new MockRegistrar();
        _registrar.setVault(_vault);

        _mToken = new MockM();
        _mToken.setCurrentIndex(_EXP_SCALED_ONE);
        _mToken.setTtgRegistrar(address(_registrar));

        _implementation = new WrappedMToken(address(_mToken), _migrationAdmin);

        _wrappedMToken = IWrappedMToken(address(new Proxy(address(_implementation))));
    }

    function test_story() external {
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _registrar.setListContains(_EARNERS_LIST, _bob, true);

        _wrappedMToken.startEarningFor(_alice);

        _wrappedMToken.startEarningFor(_bob);

        vm.prank(_alice);
        _wrappedMToken.wrap(_alice, 100_000000);

        _mToken.setBalanceOf(address(_wrappedMToken), 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), 100_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 100_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalSupply(), 100_000000);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
        assertEq(_wrappedMToken.excess(), 0);

        vm.prank(_carol);
        _wrappedMToken.wrap(_carol, 100_000000);

        _mToken.setBalanceOf(address(_wrappedMToken), 200_000000);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), 100_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 100_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 100_000000);
        assertEq(_wrappedMToken.totalSupply(), 200_000000);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
        assertEq(_wrappedMToken.excess(), 0);

        _mToken.setCurrentIndex(2 * _EXP_SCALED_ONE);
        _mToken.setBalanceOf(address(_wrappedMToken), 400_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), 100_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100_000000);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), 100_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 100_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 100_000000);
        assertEq(_wrappedMToken.totalSupply(), 200_000000);
        assertEq(_wrappedMToken.totalAccruedYield(), 100_000000);
        assertEq(_wrappedMToken.excess(), 100_000000);

        vm.prank(_bob);
        _wrappedMToken.wrap(_bob, 100_000000);

        _mToken.setBalanceOf(address(_wrappedMToken), 500_000000);

        // Assert Bob (Earner)
        assertEq(_wrappedMToken.balanceOf(_bob), 100_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 200_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 100_000000);
        assertEq(_wrappedMToken.totalSupply(), 300_000000);

        assertEq(_wrappedMToken.totalAccruedYield(), 100_000000);
        assertEq(_wrappedMToken.excess(), 100_000000);

        vm.prank(_dave);
        _wrappedMToken.wrap(_dave, 100_000000);

        _mToken.setBalanceOf(address(_wrappedMToken), 600_000000);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), 100_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 200_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 200_000000);
        assertEq(_wrappedMToken.totalSupply(), 400_000000);
        assertEq(_wrappedMToken.totalAccruedYield(), 100_000000);
        assertEq(_wrappedMToken.excess(), 100_000000);

        assertEq(_wrappedMToken.balanceOf(_alice), 100_000000);

        uint256 yield_ = _wrappedMToken.claimFor(_alice);

        assertEq(yield_, 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), 200_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 300_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 200_000000);
        assertEq(_wrappedMToken.totalSupply(), 500_000000);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
        assertEq(_wrappedMToken.excess(), 100_000000);

        _mToken.setCurrentIndex(3 * _EXP_SCALED_ONE);
        _mToken.setBalanceOf(address(_wrappedMToken), 900_000000); // was 600 @ 2.0, so 900 @ 3.0

        // Assert Alice (Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), 200_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 100_000000);

        // Assert Bob (Earner)
        assertEq(_wrappedMToken.balanceOf(_bob), 100_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 50_000000);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), 100_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), 100_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 300_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 200_000000);
        assertEq(_wrappedMToken.totalSupply(), 500_000000);
        assertEq(_wrappedMToken.totalAccruedYield(), 150_000000);
        assertEq(_wrappedMToken.excess(), 250_000000);

        vm.prank(_alice);
        _wrappedMToken.transfer(_carol, 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), 199_999998);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), 200_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 300_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 300_000000);
        assertEq(_wrappedMToken.totalSupply(), 600_000000);
        assertEq(_wrappedMToken.totalAccruedYield(), 50_000001);
        assertEq(_wrappedMToken.excess(), 249_999999);

        vm.prank(_dave);
        _wrappedMToken.transfer(_bob, 50_000000);

        // Assert Bob (Earner)
        assertEq(_wrappedMToken.balanceOf(_bob), 199_999998);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), 50_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 400_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 250_000000);
        assertEq(_wrappedMToken.totalSupply(), 650_000000);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
        assertEq(_wrappedMToken.excess(), 250_000000);

        _mToken.setCurrentIndex(4 * _EXP_SCALED_ONE);
        _mToken.setBalanceOf(address(_wrappedMToken), 1_200_000000); // was 900 @ 3.0, so 1200 @ 4.0

        // Assert Alice (Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), 199_999998);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 66_666666);

        // Assert Bob (Earner)
        assertEq(_wrappedMToken.balanceOf(_bob), 199_999998);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 66_666666);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), 200_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), 50_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 400_000000);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 250_000000);
        assertEq(_wrappedMToken.totalSupply(), 650_000000);
        assertEq(_wrappedMToken.totalAccruedYield(), 133_333332);
        assertEq(_wrappedMToken.excess(), 416_666668);

        _registrar.setListContains(_EARNERS_LIST, _alice, false);

        _wrappedMToken.stopEarningFor(_alice);

        // Assert Alice (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), 266_666664);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 200_000002);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 516_666664);
        assertEq(_wrappedMToken.totalSupply(), 716_666666);
        assertEq(_wrappedMToken.totalAccruedYield(), 66_666666);
        assertEq(_wrappedMToken.excess(), 416_666668);

        _registrar.setListContains(_EARNERS_LIST, _carol, true);

        _wrappedMToken.startEarningFor(_carol);

        // Assert Carol (Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), 200_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 400_000002);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 316_666664);
        assertEq(_wrappedMToken.totalSupply(), 716_666666);
        assertEq(_wrappedMToken.totalAccruedYield(), 66_666666);
        assertEq(_wrappedMToken.excess(), 416_666668);

        _mToken.setCurrentIndex(5 * _EXP_SCALED_ONE);
        _mToken.setBalanceOf(address(_wrappedMToken), 1_500_000000); // was 1200 @ 4.0, so 1500 @ 5.0

        // Assert Alice (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), 266_666664);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Bob (Earner)
        assertEq(_wrappedMToken.balanceOf(_bob), 199_999998);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 133_333332);

        // Assert Carol (Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), 200_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 50_000000);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), 50_000000);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 400_000002);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 316_666664);
        assertEq(_wrappedMToken.totalSupply(), 716_666666);
        assertEq(_wrappedMToken.totalAccruedYield(), 183_333333);
        assertEq(_wrappedMToken.excess(), 600_000001);

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, 266_666664);

        _mToken.setBalanceOf(address(_wrappedMToken), 1_233_333336);

        // Assert Alice (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 400_000002);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 50_000000);
        assertEq(_wrappedMToken.totalSupply(), 450_000002);
        assertEq(_wrappedMToken.totalAccruedYield(), 183_333333);
        assertEq(_wrappedMToken.excess(), 600_000001);

        vm.prank(_bob);
        _wrappedMToken.unwrap(_bob, 333_333330);

        _mToken.setBalanceOf(address(_wrappedMToken), 900_000006);

        // Assert Bob (Earner)
        assertEq(_wrappedMToken.balanceOf(_bob), 0);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 200_000004);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 50_000000);
        assertEq(_wrappedMToken.totalSupply(), 250_000004);
        assertEq(_wrappedMToken.totalAccruedYield(), 50_000001);
        assertEq(_wrappedMToken.excess(), 600_000001);

        vm.prank(_carol);
        _wrappedMToken.unwrap(_carol, 250_000000);

        _mToken.setBalanceOf(address(_wrappedMToken), 650_000006);

        // Assert Carol (Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), 0);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 4);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 50_000000);
        assertEq(_wrappedMToken.totalSupply(), 50_000004);
        assertEq(_wrappedMToken.totalAccruedYield(), 1);
        assertEq(_wrappedMToken.excess(), 600_000001);

        vm.prank(_dave);
        _wrappedMToken.unwrap(_dave, 50_000000);

        _mToken.setBalanceOf(address(_wrappedMToken), 600_000006);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), 0);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 4);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalSupply(), 4);
        assertEq(_wrappedMToken.totalAccruedYield(), 1);
        assertEq(_wrappedMToken.excess(), 600_000001);

        _wrappedMToken.claimExcess();

        _mToken.setBalanceOf(address(_wrappedMToken), 11);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), 4);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalSupply(), 4);
        assertEq(_wrappedMToken.totalAccruedYield(), 1);
        assertEq(_wrappedMToken.excess(), 6);
    }

    function test_migration() external {
        WrappedMTokenV2 implementationV2_ = new WrappedMTokenV2();
        address migrator_ = address(new WrappedMTokenMigratorV1(address(implementationV2_)));

        _registrar.set(
            keccak256(abi.encode(_MIGRATOR_V1_PREFIX, address(_wrappedMToken))),
            bytes32(uint256(uint160(migrator_)))
        );

        vm.expectRevert();
        WrappedMTokenV2(address(_wrappedMToken)).foo();

        _wrappedMToken.migrate();

        assertEq(WrappedMTokenV2(address(_wrappedMToken)).foo(), 1);
    }

    function test_migration_fromAdmin() external {
        WrappedMTokenV2 implementationV2_ = new WrappedMTokenV2();
        address migrator_ = address(new WrappedMTokenMigratorV1(address(implementationV2_)));

        vm.expectRevert();
        WrappedMTokenV2(address(_wrappedMToken)).foo();

        vm.prank(_migrationAdmin);
        _wrappedMToken.migrate(migrator_);

        assertEq(WrappedMTokenV2(address(_wrappedMToken)).foo(), 1);
    }
}
