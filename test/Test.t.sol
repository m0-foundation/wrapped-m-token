// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { Test } from "../lib/forge-std/src/Test.sol";

import { WrappedM } from "../src/WrappedM.sol";

contract MockM {
    uint128 public currentIndex;

    mapping (address account => uint256 balance) public balanceOf;

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
    mapping (bytes32 key => bytes32 value) public get;

    mapping (bytes32 list => mapping (address account => bool contains)) public listContains;

    function set(bytes32 key_, bytes32 value_) external {
        get[key_] = value_;
    }

    function setListContains(bytes32 list_, address account_, bool contains_) external {
        listContains[list_][account_] = contains_;
    }
}

contract Tests is Test {
    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _ALLOCATORS_LIST = "wm_allocators";
    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _EARNING_DELEGATE_PREFIX = "earning_delegate";

    address internal _allocator = makeAddr("allocator");

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    MockM internal _mToken;
    MockRegistrar internal _registrar;
    WrappedM internal _wrappedM;

    function setUp() external {
        _mToken = new MockM();
        _mToken.setCurrentIndex(_EXP_SCALED_ONE);

        _registrar = new MockRegistrar();
        _wrappedM = new WrappedM(address(_mToken), address(_registrar));

        _registrar.setListContains(_ALLOCATORS_LIST, _allocator, true);
    }

    function test_story() external {
        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _registrar.setListContains(_EARNERS_LIST, _bob, true);
        _registrar.setListContains(_EARNERS_LIST, _carol, true);
        _registrar.setListContains(_EARNERS_LIST, _dave, true);

        vm.prank(_alice);
        _wrappedM.startEarning();

        vm.prank(_bob);
        _wrappedM.startEarning();

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
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 0);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

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
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 0);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

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
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 100_000000);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 100_000000);

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
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 100_000000);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 100_000000);

        vm.prank(_dave);
        _wrappedM.deposit(_dave, 100_000000);

        _mToken.setBalanceOf(address(_wrappedM), 600_000000);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Contract (Non-Earner)
        assertEq(_wrappedM.balanceOf(address(_wrappedM)), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(address(_wrappedM)), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalSupply(), 500_000000);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 100_000000);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

        vm.prank(_alice);
        uint256 yield_ = _wrappedM.claim();

        assertEq(yield_, 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalSupply(), 600_000000);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 0);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

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

        // Assert Contract (Non-Earner)
        assertEq(_wrappedM.balanceOf(address(_wrappedM)), 100_000000);
        assertEq(_wrappedM.accruedYieldOf(address(_wrappedM)), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalSupply(), 600_000000);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 150_000000);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 150_000000);

        vm.prank(_alice);
        _wrappedM.transfer(_carol, 100_000000);

        // Assert Alice (Earner)
        assertEq(_wrappedM.balanceOf(_alice), 199_999998);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedM.balanceOf(_carol), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Contract (Non-Earner)
        assertEq(_wrappedM.balanceOf(address(_wrappedM)), 250_000000);
        assertEq(_wrappedM.accruedYieldOf(address(_wrappedM)), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 300_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 549_999999);
        assertEq(_wrappedM.totalSupply(), 849_999999);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 50_000001);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

        vm.prank(_dave);
        _wrappedM.transfer(_bob, 50_000000);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 199_999998);
        assertEq(_wrappedM.accruedYieldOf(_bob), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 50_000000);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Contract (Non-Earner)
        assertEq(_wrappedM.balanceOf(address(_wrappedM)), 250_000000);
        assertEq(_wrappedM.accruedYieldOf(address(_wrappedM)), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 500_000001);
        assertEq(_wrappedM.totalSupply(), 900_000001);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 0);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

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

        // Assert Contract (Non-Earner)
        assertEq(_wrappedM.balanceOf(address(_wrappedM)), 250_000000);
        assertEq(_wrappedM.accruedYieldOf(address(_wrappedM)), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000000);
        assertEq(_wrappedM.totalNonEarningSupply(), 500_000001);
        assertEq(_wrappedM.totalSupply(), 900_000001);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 133_333332);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 166_666667);

        vm.prank(_alice);
        _wrappedM.stopEarning();

        // Assert Alice (Non-Earner)
        assertEq(_wrappedM.balanceOf(_alice), 266_666664);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Contract (Non-Earner)
        assertEq(_wrappedM.balanceOf(address(_wrappedM)), 416_666667);
        assertEq(_wrappedM.accruedYieldOf(address(_wrappedM)), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000002);
        assertEq(_wrappedM.totalNonEarningSupply(), 933_333332);
        assertEq(_wrappedM.totalSupply(), 1_133_333334);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 66_666666);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

        vm.prank(_carol);
        _wrappedM.startEarning();

        // Assert Carol (Earner)
        assertEq(_wrappedM.balanceOf(_carol), 200_000000);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000002);
        assertEq(_wrappedM.totalNonEarningSupply(), 733_333332);
        assertEq(_wrappedM.totalSupply(), 1_133_333334);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 66_666666);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

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

        // Assert Contract (Non-Earner)
        assertEq(_wrappedM.balanceOf(address(_wrappedM)), 416_666667);
        assertEq(_wrappedM.accruedYieldOf(address(_wrappedM)), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000002);
        assertEq(_wrappedM.totalNonEarningSupply(), 733_333332);
        assertEq(_wrappedM.totalSupply(), 1_133_333334);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 183_333333);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 183_333333);

        vm.prank(_alice);
        _wrappedM.withdraw(_alice, 266_666664);
        _mToken.setBalanceOf(address(_wrappedM), 1_233_333336);

        // Assert Alice (Non-Earner)
        assertEq(_wrappedM.balanceOf(_alice), 0);
        assertEq(_wrappedM.accruedYieldOf(_alice), 0);

        // Assert Contract (Non-Earner)
        assertEq(_wrappedM.balanceOf(address(_wrappedM)), 600000000);
        assertEq(_wrappedM.accruedYieldOf(address(_wrappedM)), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 400_000002);
        assertEq(_wrappedM.totalNonEarningSupply(), 650000005);
        assertEq(_wrappedM.totalSupply(), 1_050_000007);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 183_333329);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

        vm.prank(_bob);
        _wrappedM.withdraw(_bob, 333_333330);
        _mToken.setBalanceOf(address(_wrappedM), 900_000006);

        // Assert Bob (Earner)
        assertEq(_wrappedM.balanceOf(_bob), 0);
        assertEq(_wrappedM.accruedYieldOf(_bob), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 200_000004);
        assertEq(_wrappedM.totalNonEarningSupply(), 650_000005);
        assertEq(_wrappedM.totalSupply(), 850_000009);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 49_999997);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

        vm.prank(_carol);
        _wrappedM.withdraw(_carol, 250_000000);
        _mToken.setBalanceOf(address(_wrappedM), 650000006);

        // Assert Carol (Earner)
        assertEq(_wrappedM.balanceOf(_carol), 0);
        assertEq(_wrappedM.accruedYieldOf(_carol), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 4);
        assertEq(_wrappedM.totalNonEarningSupply(), 650_000005);
        assertEq(_wrappedM.totalSupply(), 650_000009);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 0);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

        vm.prank(_dave);
        _wrappedM.withdraw(_dave, 50_000000);
        _mToken.setBalanceOf(address(_wrappedM), 600000006);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedM.balanceOf(_dave), 0);
        assertEq(_wrappedM.accruedYieldOf(_dave), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 4);
        assertEq(_wrappedM.totalNonEarningSupply(), 600_000005);
        assertEq(_wrappedM.totalSupply(), 600_000009);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 0);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

        vm.prank(_allocator);
        _wrappedM.allocate(_allocator, 600_000000);

        // Assert Allocator (Non-Earner)
        assertEq(_wrappedM.balanceOf(_allocator), 600_000000);
        assertEq(_wrappedM.accruedYieldOf(_allocator), 0);

        // Assert Contract (Non-Earner)
        assertEq(_wrappedM.balanceOf(address(_wrappedM)), 0);
        assertEq(_wrappedM.accruedYieldOf(address(_wrappedM)), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 4);
        assertEq(_wrappedM.totalNonEarningSupply(), 600_000005);
        assertEq(_wrappedM.totalSupply(), 600_000009);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 0);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);

        vm.prank(_allocator);
        _wrappedM.withdraw(_allocator, 600_000000);
        _mToken.setBalanceOf(address(_wrappedM), 6);

        // Assert Allocator (Non-Earner)
        assertEq(_wrappedM.balanceOf(_allocator), 0);
        assertEq(_wrappedM.accruedYieldOf(_allocator), 0);

        // Assert Globals
        assertEq(_wrappedM.totalEarningSupply(), 4);
        assertEq(_wrappedM.totalNonEarningSupply(), 5);
        assertEq(_wrappedM.totalSupply(), 9);
        assertEq(_wrappedM.accruedYieldOfEarningSupply(), 0);
        assertEq(_wrappedM.accruedYieldOfNonEarningSupply(), 0);
    }
}
