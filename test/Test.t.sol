// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

import { IWrappedM } from "../src/interfaces/IWrappedM.sol";

import { WrappedM } from "../src/WrappedM.sol";
import { Proxy } from "../src/Proxy.sol";

contract MockM {
    address public ttgRegistrar;

    uint128 public currentIndex;

    mapping(address account => uint256 balance) public balanceOf;

    function transfer(address, uint256) external returns (bool success_) {
        return true;
    }

    function transferFrom(address, address, uint256) external returns (bool success_) {
        return true;
    }

    function setBalanceOf(address account_, uint256 balance_) external {
        balanceOf[account_] = balance_;
    }

    function setCurrentIndex(uint128 currentIndex_) external {
        currentIndex = currentIndex_;
    }

    function setTtgRegistrar(address ttgRegistrar_) external {
        ttgRegistrar = ttgRegistrar_;
    }
}

contract MockRegistrar {
    address public vault;

    mapping(bytes32 key => bytes32 value) public get;

    mapping(bytes32 list => mapping(address account => bool contains)) public listContains;

    function set(bytes32 key_, bytes32 value_) external {
        get[key_] = value_;
    }

    function setListContains(bytes32 list_, address account_, bool contains_) external {
        listContains[list_][account_] = contains_;
    }

    function setVault(address vault_) external {
        vault = vault_;
    }
}

contract WrappedMV2 {
    function foo() external pure returns (uint256) {
        return 1;
    }
}

contract WrappedMMigratorV1 {
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
    bytes32 internal constant _CLAIM_DESTINATION_PREFIX = "wm_claim_destination";
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "wm_migrator_v1";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    address internal _vault = makeAddr("vault");

    MockM internal _mToken;
    MockRegistrar internal _registrar;
    WrappedM internal _implementation;
    IWrappedM internal _wrappedM;

    function setUp() external {
        _registrar = new MockRegistrar();
        _registrar.setVault(_vault);

        _mToken = new MockM();
        _mToken.setCurrentIndex(_EXP_SCALED_ONE);
        _mToken.setTtgRegistrar(address(_registrar));

        _implementation = new WrappedM(address(_mToken));

        _wrappedM = IWrappedM(address(new Proxy(address(_implementation))));
    }

    function test_story() external {
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _registrar.setListContains(_EARNERS_LIST, _bob, true);

        _wrappedM.startEarningFor(_alice);

        _wrappedM.startEarningFor(_bob);

        vm.prank(_alice);
        _wrappedM.wrap(_alice, 100_000000);

        _mToken.setBalanceOf(address(_wrappedM), 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 100_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 0);
        assertEq(_wrappedM.totalSupply(), 100_000000);
        assertEq(_wrappedM.totalAccruedYield(), 0);
        assertEq(_wrappedM.excess(), 0);

        vm.prank(_carol);
        _wrappedM.wrap(_carol, 100_000000);

        _mToken.setBalanceOf(address(_wrappedM), 200_000000);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedM.balanceOf(_carol), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 100_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 100_000000);
        assertEq(_wrappedM.totalSupply(), 200_000000);
        assertEq(_wrappedM.totalAccruedYield(), 0);
        assertEq(_wrappedM.excess(), 0);

        _mToken.setCurrentIndex(2 * _EXP_SCALED_ONE);
        _mToken.setBalanceOf(address(_wrappedM), 400_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_alice), 100_000000);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedM.balanceOf(_carol), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 100_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 100_000000);
        assertEq(_wrappedM.totalSupply(), 200_000000);
        assertEq(_wrappedM.totalAccruedYield(), 100_000000);
        assertEq(_wrappedM.excess(), 100_000000);

        vm.prank(_bob);
        _wrappedM.wrap(_bob, 100_000000);

        _mToken.setBalanceOf(address(_wrappedM), 500_000000);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_bob), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 100_000000);
        assertEq(_wrappedM.totalSupply(), 300_000000);

        assertEq(_wrappedM.totalAccruedYield(), 100_000000);
        assertEq(_wrappedM.excess(), 100_000000);

        vm.prank(_dave);
        _wrappedM.wrap(_dave, 100_000000);

        _mToken.setBalanceOf(address(_wrappedM), 600_000000);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalSupply(), 400_000000);
        assertEq(_wrappedM.totalAccruedYield(), 100_000000);
        assertEq(_wrappedM.excess(), 100_000000);

        assertEq(_wrappedM.balanceOf(_alice), 100_000000);

        uint256 yield_ = _wrappedM.claimFor(_alice);

        assertEq(yield_, 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalSupply(), 500_000000);
        assertEq(_wrappedM.totalAccruedYield(), 0);
        assertEq(_wrappedM.excess(), 100_000000);

        _mToken.setCurrentIndex(3 * _EXP_SCALED_ONE);
        _mToken.setBalanceOf(address(_wrappedM), 900_000000); // was 600 @ 2.0, so 900 @ 3.0

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_alice), 100_000000);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_bob), 50_000000);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedM.balanceOf(_carol), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalSupply(), 500_000000);
        assertEq(_wrappedM.totalAccruedYield(), 150_000000);
        assertEq(_wrappedM.excess(), 250_000000);

        vm.prank(_alice);
        _wrappedM.transfer(_carol, 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 199_999998);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedM.balanceOf(_carol), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalSupply(), 600_000000);
        assertEq(_wrappedM.totalAccruedYield(), 50_000001);
        assertEq(_wrappedM.excess(), 249_999999);

        vm.prank(_dave);
        _wrappedM.transfer(_bob, 50_000000);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 199_999998);
        assertEq(_wrappedM.accruedYieldOf(_bob), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 50_000000);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 250_000000);
        assertEq(_wrappedM.totalSupply(), 650_000000);
        assertEq(_wrappedM.totalAccruedYield(), 0);
        assertEq(_wrappedM.excess(), 250_000000);

        _mToken.setCurrentIndex(4 * _EXP_SCALED_ONE);
        _mToken.setBalanceOf(address(_wrappedM), 1_200_000000); // was 900 @ 3.0, so 1200 @ 4.0

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 199_999998);
        assertEq(_wrappedM.accruedYieldOf(_alice), 66_666666);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 199_999998);
        assertEq(_wrappedM.accruedYieldOf(_bob), 66_666666);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedM.balanceOf(_carol), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 50_000000);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 250_000000);
        assertEq(_wrappedM.totalSupply(), 650_000000);
        assertEq(_wrappedM.totalAccruedYield(), 133_333332);
        assertEq(_wrappedM.excess(), 416_666668);

        _registrar.setListContains(_EARNERS_LIST, _alice, false);

        _wrappedM.stopEarningFor(_alice);

        // Assert Alice (Non-Earner)
        assertEq(_wrappedM.balanceOf(_alice), 266_666664);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000002);
        assertEq(_wrappedM.totalNonEarningSupply(), 516_666664);
        assertEq(_wrappedM.totalSupply(), 716_666666);
        assertEq(_wrappedM.totalAccruedYield(), 66_666666);
        assertEq(_wrappedM.excess(), 416_666668);

        _registrar.setListContains(_EARNERS_LIST, _carol, true);

        _wrappedM.startEarningFor(_carol);

        // Assert Carol (Earner)
        assertEq(_wrappedM.balanceOf(_carol), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000002);
        assertEq(_wrappedM.totalNonEarningSupply(), 316_666664);
        assertEq(_wrappedM.totalSupply(), 716_666666);
        assertEq(_wrappedM.totalAccruedYield(), 66_666666);
        assertEq(_wrappedM.excess(), 416_666668);

        _mToken.setCurrentIndex(5 * _EXP_SCALED_ONE);
        _mToken.setBalanceOf(address(_wrappedM), 1_500_000000); // was 1200 @ 4.0, so 1500 @ 5.0

        // Assert Alice (Non-Earner)
        assertEq(_wrappedM.balanceOf(_alice), 266_666664);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 199_999998);
        assertEq(_wrappedM.accruedYieldOf(_bob), 133_333332);

        // Assert Carol (Earner)
        assertEq(_wrappedM.balanceOf(_carol), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 50_000000);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 50_000000);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000002);
        assertEq(_wrappedM.totalNonEarningSupply(), 316_666664);
        assertEq(_wrappedM.totalSupply(), 716_666666);
        assertEq(_wrappedM.totalAccruedYield(), 183_333333);
        assertEq(_wrappedM.excess(), 600_000001);

        vm.prank(_alice);
        _wrappedM.unwrap(_alice, 266_666664);

        _mToken.setBalanceOf(address(_wrappedM), 1_233_333336);

        // Assert Alice (Non-Earner)
        assertEq(_wrappedM.balanceOf(_alice), 0);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000002);
        assertEq(_wrappedM.totalNonEarningSupply(), 50_000000);
        assertEq(_wrappedM.totalSupply(), 450_000002);
        assertEq(_wrappedM.totalAccruedYield(), 183_333333);
        assertEq(_wrappedM.excess(), 600_000001);

        vm.prank(_bob);
        _wrappedM.unwrap(_bob, 333_333330);

        _mToken.setBalanceOf(address(_wrappedM), 900_000006);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 0);
        assertEq(_wrappedM.accruedYieldOf(_bob), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000004);
        assertEq(_wrappedM.totalNonEarningSupply(), 50_000000);
        assertEq(_wrappedM.totalSupply(), 250_000004);
        assertEq(_wrappedM.totalAccruedYield(), 50_000001);
        assertEq(_wrappedM.excess(), 600_000001);

        vm.prank(_carol);
        _wrappedM.unwrap(_carol, 250_000000);

        _mToken.setBalanceOf(address(_wrappedM), 650_000006);

        // Assert Carol (Earner)
        assertEq(_wrappedM.balanceOf(_carol), 0);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 4);
        assertEq(_wrappedM.totalNonEarningSupply(), 50_000000);
        assertEq(_wrappedM.totalSupply(), 50_000004);
        assertEq(_wrappedM.totalAccruedYield(), 1);
        assertEq(_wrappedM.excess(), 600_000001);

        vm.prank(_dave);
        _wrappedM.unwrap(_dave, 50_000000);

        _mToken.setBalanceOf(address(_wrappedM), 600_000006);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 0);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 4);
        assertEq(_wrappedM.totalNonEarningSupply(), 0);
        assertEq(_wrappedM.totalSupply(), 4);
        assertEq(_wrappedM.totalAccruedYield(), 1);
        assertEq(_wrappedM.excess(), 600_000001);

        _wrappedM.claimExcess();

        _mToken.setBalanceOf(address(_wrappedM), 11);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 4);
        assertEq(_wrappedM.totalNonEarningSupply(), 0);
        assertEq(_wrappedM.totalSupply(), 4);
        assertEq(_wrappedM.totalAccruedYield(), 1);
        assertEq(_wrappedM.excess(), 6);
    }

    function test_migration() external {
        WrappedMV2 implementationV2_ = new WrappedMV2();
        address migrator_ = address(new WrappedMMigratorV1(address(implementationV2_)));

        _registrar.set(
            keccak256(abi.encode(_MIGRATOR_V1_PREFIX, address(_wrappedM))),
            bytes32(uint256(uint160(migrator_)))
        );

        vm.expectRevert();
        WrappedMV2(address(_wrappedM)).foo();

        _wrappedM.migrate();

        assertEq(WrappedMV2(address(_wrappedM)).foo(), 1);
    }
}
