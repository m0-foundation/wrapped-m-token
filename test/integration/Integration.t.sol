// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { MTokenHarness } from "../utils/MTokenHarness.sol";
import { WrappedMTokenHarness } from "../utils/WrappedMTokenHarness.sol";
import { MockRateModel, MockRegistrar } from "../utils/Mocks.sol";
import { TestUtils } from "../utils/TestUtils.sol";

contract IntegrationTests is TestUtils {
    uint32 internal constant _EARNER_RATE = 5_000; // 5% APY

    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _EARNER_RATE_MODEL = "earner_rate_model";

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");

    address internal _minterGateway = makeAddr("minterGateway");
    address internal _migrationAdmin = makeAddr("migrationAdmin");

    address internal _vault = makeAddr("vault");

    MTokenHarness internal _mToken;
    MockRateModel internal _earnerRateModel;
    MockRegistrar internal _registrar;
    WrappedMTokenHarness internal _wrappedMToken;

    function setUp() external {
        _earnerRateModel = new MockRateModel();
        _earnerRateModel.setRate(_EARNER_RATE);

        _registrar = new MockRegistrar();
        _registrar.set(_EARNER_RATE_MODEL, bytes32(uint256(uint160(address(_earnerRateModel)))));
        _registrar.setVault(_vault);

        _mToken = new MTokenHarness(address(_registrar), _minterGateway);
        _mToken.setLatestIndex(_EXP_SCALED_ONE);

        _wrappedMToken = new WrappedMTokenHarness(address(_mToken), _migrationAdmin);

        _registrar.setListContains(_EARNERS_LIST, address(_wrappedMToken), true);

        _registrar.setListContains(_EARNERS_LIST, _alice, true);
        _registrar.setListContains(_EARNERS_LIST, _bob, true);

        _wrappedMToken.startEarningM();

        _wrappedMToken.startEarningFor(_alice);
        _wrappedMToken.startEarningFor(_bob);
    }

    function test_integration_yieldAccumulation() external {
        uint256 amount_ = 100e6;

        vm.prank(_minterGateway);
        _mToken.mint(_alice, amount_);

        assertEq(_mToken.balanceOf(_alice), amount_);

        _wrap(_mToken, _wrappedMToken, _alice, _alice, amount_);

        // Assert Alice (Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), amount_);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), amount_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), 0);
        assertEq(_wrappedMToken.totalSupply(), amount_);
        assertEq(_wrappedMToken.totalAccruedYield(), 0);
        assertEq(_wrappedMToken.excess(), 0);

        vm.prank(_minterGateway);
        _mToken.mint(_carol, amount_);

        _wrap(_mToken, _wrappedMToken, _carol, _carol, amount_);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), amount_);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        uint256 totalEarningSupply_ = amount_;
        uint256 totalNonEarningSupply_ = amount_;
        uint256 totalSupply_ = amount_ * 2;
        uint256 totalAccruedYield_ = 0;
        uint256 excess_ = 0;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertEq(_wrappedMToken.totalAccruedYield(), totalAccruedYield_);
        assertEq(_wrappedMToken.excess(), excess_);

        // Fast forward 90 days in the future to generate yield
        uint32 timeElapsed_ = 90 days;
        vm.warp(vm.getBlockTimestamp() + timeElapsed_);

        uint128 currentIndex_ = _getContinuousIndexAt(_EARNER_RATE, _EXP_SCALED_ONE, timeElapsed_);
        assertEq(_mToken.currentIndex(), currentIndex_);

        // Assert Alice (Earner)
        uint240 accruedYield_ = _getAccruedYieldOf(_wrappedMToken, _alice, currentIndex_);

        assertEq(_wrappedMToken.balanceOf(_alice), amount_);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), accruedYield_);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), amount_);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        totalAccruedYield_ += accruedYield_; // accrued yield of Alice
        excess_ += accruedYield_; // Carol is not earning so her yield is in excess

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), totalAccruedYield_, 1);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 1);

        vm.prank(_minterGateway);
        _mToken.mint(_bob, amount_);

        _wrap(_mToken, _wrappedMToken, _bob, _bob, amount_);

        // Assert Bob (Earner)
        assertApproxEqAbs(_wrappedMToken.balanceOf(_bob), amount_, 1);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 0);

        // Assert Globals
        totalEarningSupply_ += amount_;
        totalSupply_ += amount_;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), accruedYield_, 1);
        assertApproxEqAbs(_wrappedMToken.excess(), accruedYield_, 1);

        vm.prank(_minterGateway);
        _mToken.mint(_dave, amount_);

        _wrap(_mToken, _wrappedMToken, _dave, _dave, amount_);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), amount_);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        totalNonEarningSupply_ += amount_;
        totalSupply_ += amount_;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), accruedYield_, 1);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 1);

        assertEq(_wrappedMToken.balanceOf(_alice), amount_);

        uint256 yield_ = _wrappedMToken.claimFor(_alice);

        assertEq(yield_, accruedYield_);

        // Assert Alice (Earner)
        uint256 aliceBalance_ = amount_ + accruedYield_;

        assertEq(_wrappedMToken.balanceOf(_alice), aliceBalance_);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Globals
        totalEarningSupply_ += accruedYield_;
        totalSupply_ += accruedYield_;
        totalAccruedYield_ -= accruedYield_;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertEq(_wrappedMToken.totalAccruedYield(), totalAccruedYield_);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 1);

        // Fast forward 180 days in the future to generate yield
        timeElapsed_ = 180 days;
        vm.warp(vm.getBlockTimestamp() + timeElapsed_);

        currentIndex_ = _getContinuousIndexAt(_EARNER_RATE, currentIndex_, timeElapsed_);
        assertApproxEqAbs(_mToken.currentIndex(), currentIndex_, 1);

        // Assert Alice (Earner)
        uint240 accruedYieldOfAlice_ = _getAccruedYieldOf(_wrappedMToken, _alice, currentIndex_);

        assertEq(_wrappedMToken.balanceOf(_alice), aliceBalance_);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), accruedYieldOfAlice_);

        // Assert Bob (Earner)
        uint240 accruedYieldOfBob_ = _getAccruedYieldOf(_wrappedMToken, _bob, currentIndex_);

        assertApproxEqAbs(_wrappedMToken.balanceOf(_bob), amount_, 1);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), accruedYieldOfBob_);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), amount_);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), amount_);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        totalAccruedYield_ += accruedYieldOfAlice_ + accruedYieldOfBob_;

        // Yield of Carol and Dave which deposited at the same time than Alice and Bob respectively but are not earning
        excess_ += accruedYieldOfAlice_ + accruedYieldOfBob_;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), totalAccruedYield_, 1);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 1);
    }

    function test_integration_yieldTransfer() external {
        uint256 amount_ = 100e6;

        vm.prank(_minterGateway);
        _mToken.mint(_alice, amount_);

        _wrap(_mToken, _wrappedMToken, _alice, _alice, amount_);

        vm.prank(_minterGateway);
        _mToken.mint(_carol, amount_);

        _wrap(_mToken, _wrappedMToken, _carol, _carol, amount_);

        // Fast forward 180 days in the future to generate yield
        uint32 timeElapsed_ = 180 days;
        vm.warp(vm.getBlockTimestamp() + timeElapsed_);

        vm.prank(_minterGateway);
        _mToken.mint(_bob, amount_);

        _wrap(_mToken, _wrappedMToken, _bob, _bob, amount_);

        vm.prank(_minterGateway);
        _mToken.mint(_dave, amount_);

        _wrap(_mToken, _wrappedMToken, _dave, _dave, amount_);

        uint128 firstIndex_ = _getContinuousIndexAt(_EARNER_RATE, _EXP_SCALED_ONE, timeElapsed_);
        uint256 accruedYieldOfAlice_ = _getAccruedYieldOf(_wrappedMToken, _alice, firstIndex_);

        vm.prank(_alice);
        _wrappedMToken.transfer(_carol, amount_);

        // Alice has transferred all her tokens and only keeps her accrued yield
        uint256 aliceBalance_ = accruedYieldOfAlice_;

        // Assert Alice (Earner)
        assertApproxEqAbs(_wrappedMToken.balanceOf(_alice), aliceBalance_, 2);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), amount_ * 2);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        uint256 totalEarningSupply_ = aliceBalance_ + amount_;
        uint256 totalNonEarningSupply_ = amount_ * 3;
        uint256 totalSupply_ = totalEarningSupply_ + totalNonEarningSupply_;
        uint256 totalAccruedYield_ = 0; // 0 since Alice has claimed her yield

        // Yield of Carol which deposited at the same time than Alice but is not earning
        uint256 excess_ = accruedYieldOfAlice_;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), totalAccruedYield_, 1);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 2);

        vm.prank(_dave);
        _wrappedMToken.transfer(_bob, amount_ / 2);

        // Assert Bob (Earner)
        uint256 bobBalance_ = amount_ + amount_ / 2;

        assertApproxEqAbs(_wrappedMToken.balanceOf(_bob), bobBalance_, 2);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), amount_ / 2);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        totalEarningSupply_ += amount_ / 2;
        totalNonEarningSupply_ -= amount_ / 2;

        // Assert Globals
        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertEq(_wrappedMToken.totalAccruedYield(), totalAccruedYield_);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 1);

        // Fast forward 180 days in the future to generate yield
        timeElapsed_ = 180 days;
        vm.warp(vm.getBlockTimestamp() + timeElapsed_);

        uint128 secondIndex_ = _getContinuousIndexAt(_EARNER_RATE, firstIndex_, timeElapsed_);
        assertApproxEqAbs(_mToken.currentIndex(), secondIndex_, 1);

        // Assert Alice (Earner)
        accruedYieldOfAlice_ = _getAccruedYieldOf(_wrappedMToken, _alice, secondIndex_);

        assertApproxEqAbs(_wrappedMToken.balanceOf(_alice), aliceBalance_, 2);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), accruedYieldOfAlice_);

        // Assert Bob (Earner)
        uint256 accruedYieldOfBob_ = _getAccruedYieldOf(_wrappedMToken, _bob, secondIndex_);

        assertApproxEqAbs(_wrappedMToken.balanceOf(_bob), bobBalance_, 2);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), accruedYieldOfBob_);

        // Assert Carol (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_carol), amount_ * 2);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), amount_ / 2);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        totalAccruedYield_ += accruedYieldOfAlice_ + accruedYieldOfBob_;
        excess_ =
            _getAccruedYield(uint240(amount_), _EXP_SCALED_ONE, secondIndex_) + // Carol's yield
            _getAccruedYield(uint240(amount_), firstIndex_, secondIndex_) + // Yield of Alice's amount transferred to Carol
            _getAccruedYield(uint240(amount_ / 2), firstIndex_, secondIndex_); // Dave's yield

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), totalAccruedYield_, 1);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 1);
    }

    function test_integration_yieldClaimUnwrap() external {
        uint256 amount_ = 100e6;

        vm.prank(_minterGateway);
        _mToken.mint(_alice, amount_);

        _wrap(_mToken, _wrappedMToken, _alice, _alice, amount_);

        vm.prank(_minterGateway);
        _mToken.mint(_carol, amount_);

        _wrap(_mToken, _wrappedMToken, _carol, _carol, amount_);

        // Fast forward 180 days in the future to generate yield
        uint32 timeElapsed_ = 180 days;
        vm.warp(vm.getBlockTimestamp() + timeElapsed_);

        vm.prank(_minterGateway);
        _mToken.mint(_bob, amount_);

        _wrap(_mToken, _wrappedMToken, _bob, _bob, amount_);

        vm.prank(_minterGateway);
        _mToken.mint(_dave, amount_);

        _wrap(_mToken, _wrappedMToken, _dave, _dave, amount_);

        uint128 firstIndex_ = _getContinuousIndexAt(_EARNER_RATE, _EXP_SCALED_ONE, timeElapsed_);
        assertEq(_mToken.currentIndex(), firstIndex_);

        uint256 accruedYieldOfAlice_ = _getAccruedYieldOf(_wrappedMToken, _alice, firstIndex_);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), accruedYieldOfAlice_);

        // Fast forward 90 days in the future to generate yield
        timeElapsed_ = 90 days;
        vm.warp(vm.getBlockTimestamp() + timeElapsed_);

        uint128 secondIndex_ = _getContinuousIndexAt(_EARNER_RATE, firstIndex_, timeElapsed_);
        assertApproxEqAbs(_mToken.currentIndex(), secondIndex_, 1);

        accruedYieldOfAlice_ = _getAccruedYieldOf(_wrappedMToken, _alice, secondIndex_);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), accruedYieldOfAlice_);

        uint256 accruedYieldOfBob_ = _getAccruedYieldOf(_wrappedMToken, _bob, secondIndex_);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), accruedYieldOfBob_);

        // Stop earning for Alice
        _registrar.setListContains(_EARNERS_LIST, _alice, false);
        _wrappedMToken.stopEarningFor(_alice);

        // Assert Alice (Non-Earner)
        // Yield of Alice is claimed when stopping earning
        assertEq(_wrappedMToken.balanceOf(_alice), amount_ + accruedYieldOfAlice_);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Globals
        uint256 totalEarningSupply_ = amount_; // Only Bob is earning
        uint256 totalNonEarningSupply_ = amount_ * 3 + accruedYieldOfAlice_;
        uint256 totalSupply_ = totalEarningSupply_ + totalNonEarningSupply_;

        // Yield of Carol and Dave which deposited at the same time than Alice and Bob respectively but are not earning
        uint256 excess_ = accruedYieldOfAlice_ + accruedYieldOfBob_;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), accruedYieldOfBob_, 2);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 2);

        _registrar.setListContains(_EARNERS_LIST, _carol, true);
        _wrappedMToken.startEarningFor(_carol);

        // Assert Carol (Earner)
        assertApproxEqAbs(_wrappedMToken.balanceOf(_carol), amount_, 2);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        totalEarningSupply_ += amount_;
        totalNonEarningSupply_ -= amount_;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), accruedYieldOfBob_, 1);
        assertEq(_wrappedMToken.excess(), excess_);

        // Fast forward 180 days in the future to generate yield
        timeElapsed_ = 180 days;
        vm.warp(vm.getBlockTimestamp() + timeElapsed_);

        uint128 thirdIndex_ = _getContinuousIndexAt(_EARNER_RATE, secondIndex_, timeElapsed_);
        assertApproxEqAbs(_mToken.currentIndex(), thirdIndex_, 9);

        // Assert Alice (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_alice), amount_ + accruedYieldOfAlice_);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Bob (Earner)
        accruedYieldOfBob_ = _getAccruedYieldOf(_wrappedMToken, _bob, thirdIndex_);

        assertApproxEqAbs(_wrappedMToken.balanceOf(_bob), amount_, 1);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), accruedYieldOfBob_);

        // Assert Carol (Earner)
        uint256 accruedYieldOfCarol_ = _getAccruedYieldOf(_wrappedMToken, _carol, thirdIndex_);

        assertApproxEqAbs(_wrappedMToken.balanceOf(_carol), amount_, 2);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), accruedYieldOfCarol_);

        // Assert Dave (Non-Earner)
        assertEq(_wrappedMToken.balanceOf(_dave), amount_);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // Assert Globals
        uint256 accruedYieldOfCarolBeforeEarning_ = _getAccruedYield(uint240(amount_), _EXP_SCALED_ONE, secondIndex_);

        excess_ =
            accruedYieldOfCarolBeforeEarning_ +
            _getAccruedYield(uint240(accruedYieldOfCarolBeforeEarning_), secondIndex_, thirdIndex_) + // Carol's yield
            _getAccruedYield(uint240(amount_ + accruedYieldOfAlice_), secondIndex_, thirdIndex_) + // Alice's yield
            _getAccruedYield(uint240(amount_), firstIndex_, thirdIndex_); // Dave's yield

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertEq(_wrappedMToken.totalAccruedYield(), accruedYieldOfBob_ + accruedYieldOfCarol_);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 4);

        uint256 aliceBalance_ = _wrappedMToken.balanceOf(_alice);

        vm.prank(_alice);
        _wrappedMToken.unwrap(_alice, aliceBalance_);

        // Assert Alice (Non-Earner)
        assertEq(_mToken.balanceOf(_alice), aliceBalance_);
        assertEq(_wrappedMToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.accruedYieldOf(_alice), 0);

        // Assert Globals
        totalNonEarningSupply_ -= aliceBalance_;
        totalSupply_ -= aliceBalance_;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertEq(_wrappedMToken.totalAccruedYield(), accruedYieldOfBob_ + accruedYieldOfCarol_);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 4);

        uint256 bobBalance_ = _wrappedMToken.balanceOf(_bob);

        vm.prank(_bob);

        // Accrued yield of Bob is claimed when unwrapping
        _wrappedMToken.unwrap(_bob, bobBalance_ + accruedYieldOfBob_);

        // Assert Bob (Earner)
        assertEq(_mToken.balanceOf(_bob), bobBalance_ + accruedYieldOfBob_);

        assertEq(_wrappedMToken.balanceOf(_bob), 0);
        assertEq(_wrappedMToken.accruedYieldOf(_bob), 0);

        // Assert Globals
        totalEarningSupply_ -= bobBalance_;
        totalSupply_ -= bobBalance_;

        assertEq(_wrappedMToken.totalEarningSupply(), totalEarningSupply_);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertEq(_wrappedMToken.totalSupply(), totalSupply_);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), accruedYieldOfCarol_, 2);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 4);

        uint256 carolBalance_ = _wrappedMToken.balanceOf(_carol);

        vm.prank(_carol);

        // Accrued yield of Carol is claimed when unwrapping
        _wrappedMToken.unwrap(_carol, carolBalance_ + accruedYieldOfCarol_);

        // Assert Carol (Earner)
        assertEq(_mToken.balanceOf(_carol), carolBalance_ + accruedYieldOfCarol_);
        assertEq(_wrappedMToken.balanceOf(_carol), 0);
        assertEq(_wrappedMToken.accruedYieldOf(_carol), 0);

        // Assert Globals
        totalEarningSupply_ -= carolBalance_;
        totalSupply_ -= carolBalance_;

        assertApproxEqAbs(_wrappedMToken.totalEarningSupply(), totalEarningSupply_, 1);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertApproxEqAbs(_wrappedMToken.totalSupply(), totalSupply_, 1);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), 0, 2);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 4);

        uint256 daveBalance_ = _wrappedMToken.balanceOf(_dave);

        vm.prank(_dave);
        _wrappedMToken.unwrap(_dave, daveBalance_);

        // Assert Dave (Non-Earner)
        assertEq(_mToken.balanceOf(_dave), daveBalance_);
        assertEq(_wrappedMToken.balanceOf(_dave), 0);
        assertEq(_wrappedMToken.accruedYieldOf(_dave), 0);

        // // Assert Globals
        totalNonEarningSupply_ -= daveBalance_;
        totalSupply_ -= daveBalance_;

        assertApproxEqAbs(_wrappedMToken.totalEarningSupply(), totalEarningSupply_, 1);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertApproxEqAbs(_wrappedMToken.totalSupply(), totalSupply_, 1);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), 0, 2);
        assertApproxEqAbs(_wrappedMToken.excess(), excess_, 4);

        uint240 excessYield_ = _wrappedMToken.claimExcess();
        assertEq(_mToken.balanceOf(_vault), excessYield_);

        // Assert Globals
        assertApproxEqAbs(_wrappedMToken.totalEarningSupply(), totalEarningSupply_, 1);
        assertEq(_wrappedMToken.totalNonEarningSupply(), totalNonEarningSupply_);
        assertApproxEqAbs(_wrappedMToken.totalSupply(), totalSupply_, 1);
        assertApproxEqAbs(_wrappedMToken.totalAccruedYield(), 0, 2);
        assertEq(_wrappedMToken.excess(), 0);
    }
}
