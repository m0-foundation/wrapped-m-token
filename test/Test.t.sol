// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

import { WrappedM } from "../src/WrappedM.sol";

contract MockM {
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

contract Tests is Test {
    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _CLAIM_DESTINATION_PREFIX = "claim_destination";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    address internal _vault = makeAddr("vault");

    MockM internal _mToken;
    MockRegistrar internal _registrar;
    WrappedM internal _wrappedM;

    function setUp() external {
        _mToken = new MockM();
        _mToken.setCurrentIndex(_EXP_SCALED_ONE);

        _registrar = new MockRegistrar();
        _registrar.setVault(_vault);

        _wrappedM = new WrappedM(address(_mToken), address(_registrar));
    }

    function test_story() external {
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _registrar.setListContains(_EARNERS_LIST, _bob, true);

        _wrappedM.startEarning(_alice);

        _wrappedM.startEarning(_bob);

        vm.prank(_alice);
        _wrappedM.deposit(_alice, 100_000000);

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
        _wrappedM.deposit(_carol, 100_000000);

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
        _wrappedM.deposit(_bob, 100_000000);

        _mToken.setBalanceOf(address(_wrappedM), 500_000000);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_bob), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 100_000000);
        assertEq(_wrappedM.totalSupply(), 300_000000);
        assertEq(_wrappedM.totalAccruedYield(), 100_000001);
        assertEq(_wrappedM.excess(), 99_999999);

        vm.prank(_dave);
        _wrappedM.deposit(_dave, 100_000000);

        _mToken.setBalanceOf(address(_wrappedM), 600_000000);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalSupply(), 400_000000);
        assertEq(_wrappedM.totalAccruedYield(), 100_000001);
        assertEq(_wrappedM.excess(), 99_999999);

        vm.prank(_alice);
        uint256 yield_ = _wrappedM.claim();

        assertEq(yield_, 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 299_999999);
        assertEq(_wrappedM.totalNonEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalSupply(), 499_999999);
        assertEq(_wrappedM.totalAccruedYield(), 2);
        assertEq(_wrappedM.excess(), 99_999999);

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
        assertEq(_wrappedM.totalEarningSupply(), 299_999999);
        assertEq(_wrappedM.totalNonEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalSupply(), 499_999999);
        assertEq(_wrappedM.totalAccruedYield(), 150_000002);
        assertEq(_wrappedM.excess(), 249_999999);

        vm.prank(_alice);
        _wrappedM.transfer(_carol, 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 199_999998);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedM.balanceOf(_carol), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 299_999999);
        assertEq(_wrappedM.totalNonEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalSupply(), 599_999999);
        assertEq(_wrappedM.totalAccruedYield(), 50_000003);
        assertEq(_wrappedM.excess(), 249_999998);

        vm.prank(_dave);
        _wrappedM.transfer(_bob, 50_000000);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 199_999998);
        assertEq(_wrappedM.accruedYieldOf(_bob), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 50_000000);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 399_999998);
        assertEq(_wrappedM.totalNonEarningSupply(), 250_000000);
        assertEq(_wrappedM.totalSupply(), 649_999998);
        assertEq(_wrappedM.totalAccruedYield(), 5);
        assertEq(_wrappedM.excess(), 249_999997);

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
        assertEq(_wrappedM.totalEarningSupply(), 399_999998);
        assertEq(_wrappedM.totalNonEarningSupply(), 250_000000);
        assertEq(_wrappedM.totalSupply(), 649_999998);
        assertEq(_wrappedM.totalAccruedYield(), 133_333339);
        assertEq(_wrappedM.excess(), 416_666663);

        _registrar.setListContains(_EARNERS_LIST, _alice, false);

        _wrappedM.stopEarning(_alice);

        // Assert Alice (Non-Earner)
        assertEq(_wrappedM.balanceOf(_alice), 266_666664);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 516_666664);
        assertEq(_wrappedM.totalSupply(), 716_666664);
        assertEq(_wrappedM.totalAccruedYield(), 66_666673);
        assertEq(_wrappedM.excess(), 416_666663);

        _registrar.setListContains(_EARNERS_LIST, _carol, true);

        _wrappedM.startEarning(_carol);

        // Assert Carol (Earner)
        assertEq(_wrappedM.balanceOf(_carol), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 316_666664);
        assertEq(_wrappedM.totalSupply(), 716_666664);
        assertEq(_wrappedM.totalAccruedYield(), 66_666673);
        assertEq(_wrappedM.excess(), 416_666663);

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
        assertEq(_wrappedM.totalEarningSupply(), 400_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 316_666664);
        assertEq(_wrappedM.totalSupply(), 716_666664);
        assertEq(_wrappedM.totalAccruedYield(), 183_333341);
        assertEq(_wrappedM.excess(), 599_999995);

        vm.prank(_alice);
        _wrappedM.withdraw(_alice, 266_666664);

        _mToken.setBalanceOf(address(_wrappedM), 1_233_333336);

        // Assert Alice (Non-Earner)
        assertEq(_wrappedM.balanceOf(_alice), 0);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 50_000000);
        assertEq(_wrappedM.totalSupply(), 450_000000);
        assertEq(_wrappedM.totalAccruedYield(), 183_333341);
        assertEq(_wrappedM.excess(), 599_999995);

        vm.prank(_bob);
        _wrappedM.withdraw(_bob, 333_333330);

        _mToken.setBalanceOf(address(_wrappedM), 900_000006);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 0);
        assertEq(_wrappedM.accruedYieldOf(_bob), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000002);
        assertEq(_wrappedM.totalNonEarningSupply(), 50_000000);
        assertEq(_wrappedM.totalSupply(), 250_000002);
        assertEq(_wrappedM.totalAccruedYield(), 50_000009);
        assertEq(_wrappedM.excess(), 599_999995);

        vm.prank(_carol);
        _wrappedM.withdraw(_carol, 250_000000);

        _mToken.setBalanceOf(address(_wrappedM), 650_000006);

        // Assert Carol (Earner)
        assertEq(_wrappedM.balanceOf(_carol), 0);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 1);
        assertEq(_wrappedM.totalNonEarningSupply(), 50_000000);
        assertEq(_wrappedM.totalSupply(), 50_000001);
        assertEq(_wrappedM.totalAccruedYield(), 10);
        assertEq(_wrappedM.excess(), 599_999995);

        vm.prank(_dave);
        _wrappedM.withdraw(_dave, 50_000000);

        _mToken.setBalanceOf(address(_wrappedM), 600_000006);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 0);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 1);
        assertEq(_wrappedM.totalNonEarningSupply(), 0);
        assertEq(_wrappedM.totalSupply(), 1);
        assertEq(_wrappedM.totalAccruedYield(), 10);
        assertEq(_wrappedM.excess(), 599_999995);

        _wrappedM.claimExcess();

        _mToken.setBalanceOf(address(_wrappedM), 11);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 1);
        assertEq(_wrappedM.totalNonEarningSupply(), 0);
        assertEq(_wrappedM.totalSupply(), 1);
        assertEq(_wrappedM.totalAccruedYield(), 10);
        assertEq(_wrappedM.excess(), 0);
    }
}
